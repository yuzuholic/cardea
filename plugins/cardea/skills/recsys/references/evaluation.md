# Evaluation

Metric definitions here match `recommenders/evaluation/python_evaluation.py`.
`scripts/metrics.py` implements the same functions with the same signatures on
this project's stack.

---

## Choose metrics by task, not by habit

| Task | Metrics | Why |
|---|---|---|
| **Top-k ranking** (what this repo does) | MAP@k, nDCG@k, precision@k, recall@k | Measure whether relevant items appear, and how high |
| Rating prediction | RMSE, MAE, R², explained variance | Only meaningful with explicit 1–5 style ratings |
| Binary relevance / CTR | AUC, logloss | Needs calibrated probabilities |
| **Beyond accuracy** (always report) | novelty, diversity, serendipity, catalog coverage, distributional coverage | Accuracy alone rewards recommending the same popular head to everyone |

This catalog has no explicit user ratings, so **rating metrics do not apply**.
Reporting RMSE on a top-k list is a category error — you would be measuring
prediction error on a set the model itself chose.

---

## Ranking metrics

All take `(rating_true, rating_pred)` and share the signature:

```python
metric(rating_true, rating_pred,
       col_user="userID", col_item="itemID",
       col_rating="rating", col_prediction="prediction",
       relevancy_method="top_k", k=10, threshold=10)
```

`relevancy_method` is `top_k` (take the model's top k), `by_threshold`
(everything scoring above `threshold`), or `None` (use the frame as given).
`top_k` is what you want.

### precision@k
Of the k recommended, what fraction were relevant. Punishes padding a list with
filler. Note the Recommenders/Spark convention: the denominator is `k`, not the
number of items actually returned — a model returning 3 items instead of 10
cannot score above 0.3.

### recall@k
Of all relevant items, what fraction appeared in the top k. Structurally capped
when a seed has more relevant items than `k` — with `k=10` and 25 franchise
relatives, the ceiling is 0.4. Report the distribution of ground-truth set sizes
alongside recall or the number is uninterpretable.

### nDCG@k
Discounted cumulative gain, normalised by the ideal ordering. **The primary
metric for this repo** — it is the only one that cares where in the list a hit
landed. Additional parameters:

- `score_type`: `binary` (default; relevance 1 for any hit), `raw`, `exp`
- `discfun_type`: `loge` (default) or `log2`

Use `binary` here — the relationship graph has no graded relevance.

### MAP@k
Mean average precision. Rewards getting several relevant items high in the list.
Sensitive to list order throughout, not just at the cut. Values are much smaller
than precision — MAP 0.13 is a strong result, not a weak one.

### r_precision_at_k
Precision at R, where R is that seed's number of relevant items. Self-normalises
for seeds with different ground-truth set sizes, which makes it a better
headline than recall@k when set sizes vary as much as they do here.

---

## Beyond-accuracy metrics

These take `(train_df, reco_df)` — historical interactions and the
recommendation output — not ground truth.

### catalog_coverage(train_df, reco_df)
`distinct items recommended / distinct items in train`. The single most
diagnostic number for a recommender. A content model scoring well on nDCG while
covering 2% of the catalog has memorised the head. On a 302k-title catalog,
double-digit coverage is a genuinely good result.

### distributional_coverage(train_df, reco_df)
Shannon entropy of the recommendation frequency distribution. Catches the case
where coverage looks fine but a handful of items take almost all the impressions.

### novelty(train_df, reco_df)
Mean `-log2(item interaction share)` over recommended items (Castells et al.,
ECIR 2011). Higher = more long-tail. Popularity baselines score near zero by
construction; use it to check a model is not just popularity in disguise.

### diversity(train_df, reco_df, item_feature_df=None, item_sim_measure=...)
`1 - mean intra-list cosine similarity`. `item_sim_measure` is
`item_cooccurrence_count` (default) or `item_feature_vector` (requires
`item_feature_df` with a `features` vector column — for this catalog, the TF-IDF
tag vectors). Per-user variant: `user_diversity`.

### serendipity(train_df, reco_df, ...)
Relevant *and* unexpected — mean `(1 - similarity to the user's history) ×
relevance`. Needs a `col_relevance` column in `reco_df`. The metric that best
captures what a discovery product is actually for, and the hardest to move.

---

## Splitting

From `recommenders/datasets/python_splitters.py`:

```python
python_random_split(data, ratio=0.75, seed=42)

python_stratified_split(data, ratio=0.75, min_rating=1, filter_by="user",
                        col_user="userID", col_item="itemID", seed=42)

python_chrono_split(data, ratio=0.75, min_rating=1, filter_by="user",
                    col_user="userID", col_item="itemID",
                    col_timestamp="timestamp")

numpy_stratified_split(X, ratio=0.75, seed=42)   # for affinity matrices
```

Choosing:

- **`python_stratified_split`** — the default for top-k ranking. Every user/seed
  appears in both splits, so ranking metrics are computable for all of them. A
  plain random split strands users entirely in test, where they are unscoreable.
- **`python_chrono_split`** — once timestamps exist, this is the honest one. It
  predicts the future from the past, which is what production does. Expect
  metrics to drop versus a random split; that drop is the measurement error the
  random split was hiding.
- **`ratio`** accepts a list (`[0.7, 0.15, 0.15]`) for train/valid/test.
- **`min_rating` + `filter_by`** prune users or items below an interaction count
  before splitting. Standard practice is `min_rating=5`; report it, because it
  materially changes the difficulty of the task.

`numpy_stratified_split` exists because the usual row-wise split does not work
for unsupervised affinity matrices — it cuts a per-user *proportion* of rated
items so both matrices keep every user.

---

## Protocol for this repo (item-to-item, relationship labels)

1. Take active titles with ≥1 strong-relation edge as the seed pool.
2. `userID` = seed id, `itemID` = related id, `rating` = 1.
3. Ground truth is the full symmetrized strong-relation edge set per seed. There
   is no train/test split of the *labels* here — the content model never saw
   them. `RelationshipRecommender` is the exception and must be reported
   separately, since it trains on the evaluation signal.
4. Exclude the seed itself from its own recommendations.
5. `k = 10` unless there is a reason; state it.
6. Sample 2,000+ seeds for iteration speed; run the full pool before concluding
   anything. Report the seed count with the numbers.

Fix the protocol before you compare models. Changing `k`, the relation-type
filter, or the seed pool between runs invalidates comparison, and it is the
single most common way offline evaluation goes wrong.

---

## Reading a result

- **Accuracy up, coverage down** — the model drifted toward the popular head.
  Usually a regression even when the headline metric improved.
- **Precision high, recall low** — the model is conservative. Fine for a "more
  like this" rail; bad for a discovery feed.
- **Beats the popularity baseline by little** — the personalisation is not
  earning its complexity. Ship the baseline.
- **Loses to the popularity baseline** — a bug, a leak, or a label problem.
  Investigate before tuning.

Offline metrics rank candidates for online testing. They do not predict business
outcome, and a model that wins offline can lose in an A/B test — usually because
offline data was collected under the old model's own recommendations. When
online metrics exist (CTR, conversion, retention), they are the ground truth and
these become a regression check.
