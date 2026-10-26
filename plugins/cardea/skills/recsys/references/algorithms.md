# Algorithm selection and Recommenders APIs

The [Recommenders](https://github.com/recommenders-team/recommenders) project
ships ~30 algorithms. This file covers how to pick one, and the exact API for
the ones that matter here. Signatures are taken from the upstream source at the
current `main`.

---

## Picking an algorithm

Answer these in order. The first "no" tells you where you are on the ladder.

1. **Do you have logged user→item interactions?** No → rungs 0–2 only.
2. **Are they explicit ratings or implicit events?** Implicit (views, reads,
   adds) is what a reader app produces. Explicit rating prediction (RMSE/MAE) is
   the wrong objective for implicit data — optimise ranking instead.
3. **How many interactions?** Under ~100k → SAR or BPR. Millions → LightGCN,
   BiVAE, or Spark ALS.
4. **Do you need cold-start coverage?** Pure CF cannot recommend a title nobody
   has touched. You will always need the content model as a fallback — keep it.
5. **Do you have side features you want the model to use?** → LightGBM,
   Wide & Deep, xDeepFM.

Two structural properties, from the Recommenders taxonomy:

- **Collaborative filtering** learns from the interaction matrix alone.
  Strong when dense, useless on cold items.
- **Content-based filtering** learns from item/user attributes. Handles
  cold-start, but ceilings out — it can only recommend things that *look*
  similar, never things that are *liked together*.

Every mature system is a hybrid. Start content-based here because that is the
only thing the data supports; keep it as the cold-start arm forever.

---

## Rung 0–2: available today

Implemented in `scripts/baselines.py`. All expose the Recommenders-style
interface:

```python
model.fit(items_df)
recs = model.recommend_k_items(seeds_df, top_k=10, remove_seen=True)
# -> DataFrame[userID, itemID, prediction]
```

### PopularityRecommender (rung 0)

Ranks by `1 / log1p(popularity_global_current)`, optionally blended with
`rating`. Non-personalised; identical list for every seed. Its job is to be the
number every other model must beat, and to expose how much of your "good"
precision is just popularity bias.

### TagContentRecommender (rung 1)

TF-IDF over `tags_v2` with term frequency scaled by tag weight
(`defining` 3.0, `core` 2.0, `recurrent` 1.5, `incidental`/`unweighted` 1.0),
cosine similarity, top-k per seed. This mirrors
`recommenders.models.tfidf.tfidf_utils.TfidfRecommender`, adapted to a weighted
token stream instead of raw text.

Upstream API, for reference:

```python
from recommenders.models.tfidf.tfidf_utils import TfidfRecommender

rec = TfidfRecommender(id_col="itemID", tokenization_method="none")
df_clean = rec.clean_dataframe(df, cols_to_clean=["description", "tags"],
                               new_col_name="cleaned_text")
tf, vectors = rec.tokenize_text(df_clean, text_col="cleaned_text",
                                ngram_range=(1, 3), min_df=0.0)
rec.fit(tf, vectors)
top_k = rec.recommend_top_k_items(df_clean, k=10)
```

`tokenization_method` is one of `none`, `nltk`, `bert`, `scibert`. The BERT
options pull in `transformers` — unnecessary for tag tokens, which are already
clean categorical terms.

Note the upstream implementation materialises a dense N×N similarity matrix via
`linear_kernel`. At 302k active titles that is ~365 TB. `scripts/baselines.py`
scores in batches against the sparse matrix instead. **Never call
`recommend_top_k_items` on the full catalog.**

### RelationshipRecommender (rung 2)

Expands the symmetrized `relationships_v2` graph, optionally to 2 hops with a
decay factor. High precision, terrible coverage — it can only speak about the
~30% of titles that have edges. Useful as a hybrid component and as an upper
bound on what the graph label can explain, but be aware it is trained on the
same signal used to evaluate it, so its benchmark score is not comparable to the
others. Treat it as an oracle reference line, not a competitor.

### Hybrid

Score-level blending after per-model min-max normalisation is the pragmatic
default:

```python
score = w_pop * pop_norm + w_tag * tag_norm + w_rel * rel_norm
```

Fit the weights on a held-out seed set. A cascade (graph first, content to fill
to k, popularity to backfill) is often better than a linear blend because it
preserves the precision of the graph arm.

---

## Rung 3: SAR — the first real CF model

`recommenders/models/sar/sar_singlenode.py`. Item-to-item co-occurrence with
time decay. No training loop, no GPU, explainable, and competitive — in the
upstream MovieLens-100k benchmark it scores MAP 0.111 / nDCG@10 0.382, beating
NCF and losing only to BiVAE and BPR.

```python
from recommenders.models.sar import SAR   # alias for SARSingleNode

model = SAR(
    col_user="userID",
    col_item="itemID",
    col_rating="rating",
    col_timestamp="timestamp",
    similarity_type="jaccard",   # cooccurrence | cosine | inclusion index |
                                 # jaccard | lift | mutual information |
                                 # lexicographers mutual information
    time_decay_coefficient=30,   # days until a rating decays by half
    timedecay_formula=True,
    threshold=1,                 # drop co-occurrences below this count
    normalize=True,
)
model.fit(train)                                   # train has no duplicates
top_k = model.recommend_k_items(test, top_k=10, remove_seen=True)
```

Other useful methods:

| method | use |
|---|---|
| `get_item_based_topk(items, top_k)` | **cold-start**: recommend from a seed item set for a user the model never saw |
| `get_popularity_based_topk(top_k)` | built-in rung-0 fallback |
| `get_topk_most_similar_users(user, top_k)` | user-user neighbourhoods |
| `predict(test)` | scores for the given pairs only (rating metrics) |
| `score(test, remove_seen)` | raw score matrix |

**`similarity_type` is the main tuning knob**, and the choice is a product
decision, not just an accuracy one — from the upstream docstrings:

- `cooccurrence` — favours predictability; popular items dominate
- `lift` — favours discoverability/serendipity; surfaces niche items loved by a
  small group
- `jaccard` — the compromise, and the sensible default

`get_item_based_topk` is the reason SAR is the right rung-3 choice here: it
works for anonymous sessions from day one, using the session's items as the
seed set, without retraining.

---

## Rung 4: learned embeddings

### BPR (Cornac) — best accuracy/effort ratio for implicit feedback

```python
from recommenders.models.cornac.bpr import BPR
from recommenders.models.cornac.cornac_utils import predict_ranking
import cornac

train_set = cornac.data.Dataset.from_uir(
    train.drop("timestamp", axis=1).itertuples(index=False), seed=42
)
model = BPR(k=200, max_iter=200, learning_rate=0.01, lambda_reg=1e-3,
            seed=42, verbose=False)
model.fit(train_set)
all_preds = predict_ranking(model, train, usercol="userID", itemcol="itemID",
                            predcol="prediction", remove_seen=True)
```

Benchmark (MovieLens-100k): MAP 0.132, nDCG@10 0.442.

### BiVAE (Cornac) — best accuracy in the upstream benchmark

```python
model = cornac.models.BiVAECF(
    k=100, encoder_structure=[200], act_fn="tanh", likelihood="pois",
    n_epochs=500, batch_size=1024, learning_rate=0.001, seed=42, use_gpu=True,
)
model.fit(train_set)
preds = predict_ranking(model, train, remove_seen=True)
```

MAP 0.146, nDCG@10 0.475. Needs a GPU to be practical.

### LightGCN — graph convolution over the interaction bipartite graph

```python
from recommenders.models.deeprec.DataModel.ImplicitCF import ImplicitCF
from recommenders.models.deeprec.models.graphrec.lightgcn import LightGCN

data = ImplicitCF(train=train, test=test, col_user="userID", col_item="itemID",
                  col_rating="rating", seed=42)
model = LightGCN(n_users=data.n_users, n_items=data.n_items,
                 norm_adj=data.get_norm_adj_mat(), embed_size=64, n_layers=3,
                 seed=42)
model.fit(data, epochs=20, learning_rate=0.005, batch_size=1024, decay=1e-4,
          eval_epoch=5, top_k=10, metrics=["recall", "ndcg", "precision", "map"])
top_k = model.recommend_k_items(test, top_k=10, remove_seen=True)
```

Architecture args go on the constructor, training args on `fit`.
MAP 0.089, nDCG@10 0.420.

### NCF

```python
from recommenders.models.ncf.ncf_singlenode import NCF
from recommenders.models.ncf.dataset import Dataset as NCFDataset

data = NCFDataset(train_file="train.csv", col_user="userID", col_item="itemID",
                  col_rating="rating", seed=42)
model = NCF(n_users=data.n_users, n_items=data.n_items, model_type="NeuMF",
            n_factors=4, layer_sizes=[16, 8, 4], n_epochs=15, batch_size=1024,
            learning_rate=1e-3, verbose=10)
model.fit(data)
preds = model.predict(user_list, item_list, is_list=True)
```

Note `NCFDataset` reads from a **CSV file path**, not a DataFrame.
MAP 0.108, nDCG@10 0.396.

### Multinomial VAE / Standard VAE / RBM

Operate on a dense user×item affinity matrix built with
`recommenders.datasets.sparse.AffinityMatrix`, split with
`numpy_stratified_split`. At 302k items a dense matrix is impractical without
first restricting to a head-of-catalog subset.

---

## Rung 5: feature-aware ranking

- **LightGBM** (`recommenders/models/lightgbm/lightgbm_utils.py`) — gradient
  boosting over engineered features. Fast, CPU-friendly, and the most likely
  next step here because this catalog is feature-rich and interaction-poor.
- **Wide & Deep** (`recommenders/models/wide_deep/wide_deep_utils.py`) —
  memorisation (wide, crossed categorical) + generalisation (deep embeddings).
- **xDeepFM** (`recommenders/models/deeprec/models/xDeepFM.py`) — explicit
  high-order feature interactions; expects libffm-format input, for which
  `recommenders.datasets.pandas_df_utils.LibffmConverter` exists.

---

## Sequential models (worth knowing about for a reader app)

Reading is inherently sequential — chapter order, series order, session order.
Recommenders ships SASRec, SSEPT, GRU, Caser, NextItNet, A2SVD, SLi-Rec, and SUM
under `recommenders/models/sasrec/` and
`recommenders/models/deeprec/models/sequential/`. These need session-ordered
event logs, which makes them a rung-4+ option once logging exists — but it is
worth designing the event schema now so the option stays open. See
`references/roadmap.md`.

---

## Upstream benchmark reference (MovieLens-100k, k=10, 15 epochs)

Useful for calibrating expectations — these are the numbers a competent
implementation reaches on a dense, well-studied dataset. Do not expect to match
them on a sparse catalog with proxy labels.

| Algorithm | MAP | nDCG@k | Precision@k | Recall@k |
|---|---|---|---|---|
| BiVAE | 0.146 | 0.475 | 0.412 | 0.219 |
| BPR | 0.132 | 0.442 | 0.388 | 0.213 |
| SAR | 0.111 | 0.382 | 0.331 | 0.176 |
| NCF | 0.108 | 0.396 | 0.347 | 0.181 |
| LightGCN | 0.089 | 0.420 | 0.380 | 0.144 |
| EmbDotBias | 0.019 | 0.118 | 0.104 | 0.042 |
| SVD | 0.013 | 0.096 | 0.091 | 0.033 |
| ALS | 0.005 | 0.044 | 0.048 | 0.018 |

The spread between the top and bottom is ~30×. Model choice matters more than
hyperparameter tuning within a model — get the family right first.
