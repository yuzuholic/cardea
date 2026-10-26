---
name: recsys
description: Build, evaluate, and iterate on recommendation algorithms for the recc-poc title catalog, following the conventions of the Recommenders project (recommenders-team/recommenders). Use this when the task involves recommending titles, similar-title/"more like this" lists, ranking or scoring a catalog, candidate generation, item-to-item similarity, collaborative filtering, content-based filtering, cold-start, embeddings for retrieval, or offline evaluation with ranking metrics (MAP, nDCG, precision@k, recall@k, novelty, diversity, coverage, serendipity). Also use when choosing which recommendation algorithm fits the data currently available, or when designing the interaction logging needed before collaborative filtering becomes possible.
---

# Recommendation systems for recc-poc

This skill grounds recommendation work in this repo in the practices of
[recommenders-team/recommenders](https://github.com/recommenders-team/recommenders)
(Linux Foundation AI & Data) — its column conventions, its splitters, its metric
definitions, and its algorithm ladder — while staying honest about what this
repo's data can actually support today.

**Terminology:** in anything user-facing, the domain noun is **title** (or
*series*), never *manga*. `manga` is one value of the `type` column alongside
`manhwa`, `manhua`, `novel`, `oel`, `other`. This is a hard rule.

---

## 1. Read this before writing any code

Five facts about `data/series.sqlite` that determine everything. All verified
against the live database.

1. **There are no users and no interactions.** One table, `series`, 557,313
   rows, 146 columns — a pure item catalog. Every classic collaborative
   filtering algorithm (ALS, SAR, BPR, NCF, LightGCN, BiVAE) needs a
   `(user, item, rating)` triple and therefore **cannot be trained here yet**.
   Anyone who reaches for "let's do collaborative filtering" has misread the
   data. See §3 for what is actually possible, and `references/roadmap.md`
   for how to earn the right to use CF.

2. **45% of rows are duplicates.** `state` is `active` (302,894), `merged`
   (254,416), or `deleted` (3). Merged rows are alternate editions folded into a
   canonical row via `merged_with`. **Always filter `WHERE state = 'active'`.**
   Skipping this inflates every count, poisons similarity with near-identical
   documents, and makes evaluation meaningless.

3. **`popularity_global_current` is a rank, not a score.** `1` is the most
   popular title; the range runs 1..300,818 over active rows (99.3% populated).
   Lower is better. Never average it, never feed it raw to a model as a
   feature — invert or log-transform it first.

4. **`tags_v2` is the strongest content signal and it is weighted.** 97.1% of
   active rows have it. Each entry is a JSON object with `name`, `weight`
   (`defining` > `core` > `recurrent` > `incidental` > `unweighted`), `level`
   (2–6 in a `name_path` hierarchy), `is_genre`, and `is_spoiler`. Mean 22.4
   tags per title, ~2,400 distinct names. The flat `tags` column is the same
   information with the weights thrown away and only 58% coverage — prefer
   `tags_v2`.

5. **`relationships_v2` gives you free ground truth.** 100% populated (often
   `[]`); ~30% of active titles have at least one edge. Each edge has
   `to_series_id` and `relation_type` (`sequel`, `prequel`, `side_story`,
   `spin_off`, `main`, `source`, `alternative`, `adaptation`, `parody`,
   `cameo`, …). This is a franchise graph, and it is the only relevance label
   available before real users exist. Its limits are real — see §5.

`references/catalog-schema.md` has the full field guide, including which of the
146 columns are usable, which are dead (`genres_v2`, `popularity`,
`relationships` — all 0% populated), and how each JSON column is shaped.

---

## 2. Column conventions — use the Recommenders names

The Recommenders package hard-codes a schema in
`recommenders/utils/constants.py`. Match it exactly and every splitter, metric,
and model in that ecosystem works on your frames without adapters:

```python
DEFAULT_USER_COL       = "userID"
DEFAULT_ITEM_COL       = "itemID"
DEFAULT_RATING_COL     = "rating"
DEFAULT_PREDICTION_COL = "prediction"
DEFAULT_TIMESTAMP_COL  = "timestamp"
DEFAULT_K              = 10
SEED                   = 42
```

**In this repo's item-to-item mode there is no user, so `userID` holds the seed
title's id** and `itemID` holds the recommended title's id. This is deliberate:
ranking metrics are defined per grouping key, and "per seed" is structurally
identical to "per user". When real interaction logs arrive, `userID` starts
holding actual user ids and none of the evaluation code changes.

A recommendation output frame is always:

| userID (seed) | itemID (recommended) | prediction (score) |
|---|---|---|

A ground-truth frame is always:

| userID (seed) | itemID (relevant) | rating (relevance) |
|---|---|---|

---

## 3. The algorithm ladder

Pick the rung matching the data you have *today*, not the one you wish you had.
Rungs 0–2 are available now; 3+ unlock as interaction logging lands.

| Rung | Requires | Approach | Recommenders reference |
|---|---|---|---|
| **0** | catalog only | Popularity / rating priors. The baseline every other model must beat. | `examples/02_model_collaborative_filtering/baseline_deep_dive.ipynb` |
| **1** | catalog only | **Content-based:** TF-IDF over weighted tags + cosine. This is the workhorse here. | `recommenders/models/tfidf/tfidf_utils.py` (`TfidfRecommender`) |
| **2** | catalog only | Relationship-graph expansion, content-reranked; hybrid blend of 0+1+2. | — (repo-specific) |
| **3** | implicit interactions (views, reads, adds) | **SAR** — item co-occurrence with time decay. Cheap, explainable, strong first CF model. | `recommenders/models/sar/sar_singlenode.py` |
| **4** | more interactions | **BPR** / **BiVAE** (Cornac), **LightGCN**, **NCF** — learned embeddings for implicit feedback. | `examples/02_model_collaborative_filtering/` |
| **5** | interactions + user/item features at scale | **LightGBM**, **Wide & Deep**, **xDeepFM** — ranking with side features. | `examples/02_model_content_based_filtering/` |

**Do not skip rungs.** A tuned popularity baseline beats an untuned neural model
on most catalogs, and if you can't beat rung 0 you have a data problem, not a
model problem.

`references/algorithms.md` has the selection criteria, exact constructor
signatures, and the empirical hyperparameters the Recommenders benchmark uses.

---

## 4. Workflow

Mirrors the five tasks the Recommenders repo organises its examples around
(prepare → model → evaluate → tune → operationalize).

### Phase 1 — Prepare
```bash
.venv/Scripts/python.exe .claude/skills/recsys/scripts/catalog.py --build
```
Reads `data/series.sqlite`, filters to `state = 'active'`, parses the JSON
columns, and writes two Parquet artifacts to `data/`:
- `items.parquet` — one row per active title with normalized fields
- `relations.parquet` — the ground-truth edge list from `relationships_v2`

Both are cached; re-run with `--force` to rebuild. Full catalog build takes a
few minutes; pass `--limit N` while iterating.

### Phase 2 — Model
```bash
.venv/Scripts/python.exe .claude/skills/recsys/scripts/baselines.py --demo 3397
```
Three recommenders sharing a `fit()` / `recommend_k_items()` interface modelled
on `SARSingleNode`:
- `PopularityRecommender` — rung 0
- `TagContentRecommender` — rung 1, TF-IDF over weight-scaled tags
- `RelationshipRecommender` — rung 2, franchise-graph expansion

Import them rather than reimplementing; add new models by subclassing
`BaseRecommender` in that file so the benchmark picks them up for free.

### Phase 3 — Evaluate
```bash
.venv/Scripts/python.exe .claude/skills/recsys/scripts/benchmark.py --n-seeds 2000
```
Scores every registered model against the relationship ground truth and prints a
comparison table using the Recommenders metric definitions (MAP@k, nDCG@k,
precision@k, recall@k) plus the beyond-accuracy metrics that matter more than
people expect (catalog coverage, novelty, diversity).

Never report a single number. A model that wins on precision while recommending
the same 200 titles to everyone has lost. See `references/evaluation.md`.

**Known-good reference numbers** — full catalog (302,894 titles), 600 seeds,
k=10, seed=42. If a change moves these substantially, understand why before
moving on:

| model | MAP@10 | nDCG@10 | Recall@10 | coverage | med. pop. rank |
|---|---|---|---|---|---|
| popularity | 0.005 | 0.009 | 0.023 | 0.0000 | 6 |
| tag-content | 0.072 | 0.084 | 0.106 | 0.0148 | 150,275 |

`tag-content` beats popularity by ~15× on MAP while recommending from deep in
the tail — that ratio, not the absolute number, is the signal. Absolute values
are low because the candidate pool is 302k and the ground truth averages 1.4
relevant items per seed.

### Phase 4 — Tune
Sweep with `metrics.py`'s splitters holding the protocol fixed. Change one thing
at a time; log the config alongside the metric row.

### Phase 5 — Operationalize
`requirements.txt` already carries FastAPI + uvicorn, and the frontend is
Vite/React. Serve precomputed top-k lists from Parquet or SQLite rather than
scoring at request time — 302k items means a full similarity scan is not a
per-request operation. See `references/roadmap.md`.

---

## 5. Evaluation honesty

The relationship graph is a **proxy** label. It answers "can this model recover
the franchise structure?" — not "will a reader enjoy this?". Treat it as a
smoke test with three known biases:

- It rewards recommending sequels and spin-offs, which a real product may
  deliberately want to *suppress* from a "more like this" rail.
- Coverage is thin: only ~30% of active titles have any edge, and those skew
  popular. Metrics computed over that subset overstate performance on the tail.
- `parody` is the single most common relation type (~18k of ~50k edges sampled)
  and is mostly doujinshi noise. `scripts/catalog.py` excludes it from ground
  truth by default; `--include-weak` puts it back.

Offline ranking metrics also do not measure novelty, diversity, or business
outcome. Recommenders ships `novelty`, `diversity`, `serendipity`,
`catalog_coverage`, and `distributional_coverage` for exactly this reason, and
`scripts/metrics.py` implements the same definitions. Report them together.

---

## 6. Environment constraint — read before `pip install recommenders`

**The `recommenders` package cannot be installed into this project's `.venv`.**
It pins `numpy<2.0.0` and `pandas>2.0.0,<3.0.0`; this venv runs Python 3.13 with
numpy 2.5.2 and pandas 3.0.5. Installing it will downgrade the stack and break
the existing FastAPI/Jupyter setup.

Two supported paths:

1. **Recommended — mirror the API, skip the dependency.**
   `scripts/metrics.py` implements the Recommenders splitters and metrics with
   matching names, signatures, and column conventions, on the modern stack. When
   you later want the real package, the import line is the only change.

2. **Separate environment for notebook exploration.** If you want to run the
   upstream notebooks or train ALS/BPR/BiVAE/LightGCN, create an isolated
   Python 3.11 env — never reuse `.venv`:
   ```bash
   uv venv .venv-reco --python 3.11
   .venv-reco/Scripts/python.exe -m pip install recommenders
   ```
   Feed it the Parquet artifacts from Phase 1 so both environments share data
   without sharing dependencies.

---

## 7. Reference files

Read on demand — do not load all of these up front.

| File | Read it when |
|---|---|
| `references/catalog-schema.md` | Choosing features, parsing a JSON column, or checking coverage of a field |
| `references/algorithms.md` | Choosing a model, or needing exact constructor/API signatures from Recommenders |
| `references/evaluation.md` | Choosing metrics, setting up a split, or interpreting a result |
| `references/roadmap.md` | Designing interaction logging, or planning the path from cold-start to CF |

## 8. Scripts

| Script | Purpose |
|---|---|
| `scripts/catalog.py` | sqlite → normalized Parquet; ground-truth edge list |
| `scripts/metrics.py` | Recommenders-compatible constants, splitters, and metrics |
| `scripts/baselines.py` | Rung 0/1/2 recommenders with a shared `fit`/`recommend_k_items` API |
| `scripts/benchmark.py` | Trains every registered model and prints the comparison table |
| `scripts/test_metrics.py` | Validates every metric against hand-computed values — run it after touching `metrics.py` |

They run from anywhere:
`.venv/Scripts/python.exe .claude/skills/recsys/scripts/<script>.py`

---

## 9. Rules

- Filter `state = 'active'` in every query that touches `series`. No exceptions.
- Use the Recommenders column names. Do not invent `item_id` / `score` variants.
- Seed every split and model with `SEED = 42`; report the seed with results.
- Always include a popularity baseline in any comparison table.
- Report accuracy metrics *and* coverage/novelty together, never accuracy alone.
- Say "title", never "manga", in anything a user will read.
- State the evaluation protocol (k, seed count, ground-truth relation types)
  next to any metric — a bare "nDCG 0.34" is not a result.
