# From cold-start catalog to a real recommender

This repo has 302,894 active titles and zero interactions. Everything below is
about closing that gap deliberately rather than discovering six months later
that the logs are unusable.

---

## The event schema, decided now

The single highest-leverage decision available today. Collaborative filtering
needs `(user, item, signal, time)`; sequential models need session ordering;
counterfactual evaluation needs to know what was *shown*, not just what was
clicked. All three are cheap to log now and impossible to reconstruct later.

```
interactions
  user_id       TEXT      stable across sessions (anonymous id is fine)
  series_id     INTEGER   -> series.id, canonical (state='active') only
  event_type    TEXT      view | open | read_chapter | finish | add_to_library
                          | rate | dismiss | hide
  value         REAL      chapters read, seconds, rating — event-dependent
  session_id    TEXT      groups events into a session
  position      INTEGER   rank within the session, for sequential models
  source        TEXT      search | browse | rail:similar | rail:trending | direct
  ts            INTEGER   unix seconds
```

Four things people leave out and regret:

- **`source`** — without it you cannot separate "the user liked this" from "we
  put it first". Every recommender trained on its own output has a feedback loop;
  `source` is what lets you detect and correct for it.
- **`position`** — enables sequential models (SASRec, GRU4Rec, SLi-Rec) and
  position-bias correction.
- **Negative signals** (`dismiss`, `hide`) — implicit feedback is
  positive-only by default, which forces models to sample negatives at random.
  Explicit negatives are worth many times their volume.
- **Impressions** — what was shown but not clicked. A separate, higher-volume
  table; sample it if cost is a concern, but log something.

Canonicalise `series_id` through `merged_with` at write time. Interactions
scattered across merged duplicates silently split each item's signal.

---

## Turning events into a training frame

Recommenders algorithms want `(userID, itemID, rating, timestamp)`. For implicit
feedback, `rating` is a confidence weight you construct:

```python
WEIGHTS = {
    "view": 0.5, "open": 1.0, "read_chapter": 2.0,
    "finish": 5.0, "add_to_library": 4.0, "rate": 5.0, "dismiss": -2.0,
}
interactions["rating"] = interactions["event_type"].map(WEIGHTS)
train = (interactions.groupby(["userID", "itemID"], as_index=False)
                     .agg(rating=("rating", "sum"),
                          timestamp=("ts", "max")))
```

Then apply the standard hygiene:

- **Deduplicate.** `SAR.fit` explicitly requires no duplicate `(user, item)`
  rows; several other models silently sum them.
- **Filter sparse users/items** with `min_rating=5, filter_by="user"` on the
  splitter. Users with 1–2 events add noise and cannot be evaluated.
- **Cap runaway weights.** One user reading 400 chapters should not dominate the
  co-occurrence matrix; `log1p` or clip.
- **Decay old signal.** SAR does this natively via
  `timedecay_formula=True, time_decay_coefficient=30`. Elsewhere, apply
  `recommenders.utils.python_utils.exponential_decay(value, max_val, half_life)`.

---

## Thresholds — when each rung unlocks

Rough, and dataset-dependent, but the shape is reliable:

| Interactions | Users | What becomes viable |
|---|---|---|
| 0 | 0 | Content + popularity only (**today**) |
| ~10k | ~1k | SAR item-to-item; co-occurrence is noisy but real |
| ~100k | ~10k | BPR, SAR with confidence; first genuine personalisation |
| ~1M | ~100k | BiVAE, LightGCN, NCF; sequential models |
| ~10M+ | ~1M | Spark ALS, two-tower retrieval + learned reranking |

Before the ~10k mark, effort is better spent on the content model, on logging
quality, and on the cold-start path — not on CF.

---

## Serving

At 302k items, scoring the full catalog per request is not viable. The standard
two-stage architecture:

**Candidate generation** (~hundreds of candidates, must be fast)
- Precomputed top-k content-similar lists per title, stored in SQLite or Parquet
- Franchise-graph neighbours
- Trending / popular by `type` and `content_rating`
- Once CF exists: ANN lookup over item embeddings

**Ranking** (~hundreds → 10, can afford to be smart)
- Blend candidate-source scores
- Apply hard filters: `content_rating`, `type`, already-read, dismissed
- Apply diversity constraints — cap titles per author, per franchise, per genre

The hard filters belong in the serving layer, never learned by the model.
A model that has to learn "don't show pornographic titles to this account" will
get it wrong some fraction of the time; a `WHERE` clause will not.

### Precompute

```python
# offline, batched: for each active title, store its top 50 similar
# -> data/similar_titles.parquet  [seed_id, rank, item_id, score]
```

302k × 50 rows is ~15M — a few hundred MB in Parquet, or a SQLite table with an
index on `seed_id` and sub-millisecond lookups. Rebuild nightly. Serve from
FastAPI (already in `requirements.txt`); the API does a keyed read and a filter,
no linear algebra at request time.

---

## Getting to A/B testing

Offline metrics rank candidates for online testing; they do not settle
anything. When traffic exists:

- Split on **user**, never on request, or the same person sees both variants.
- Watch guardrails as well as the target metric: catalog coverage, long-tail
  impression share, and complaint/hide rate. A variant that lifts CTR by
  concentrating every impression on 200 titles has damaged the product.
- Run long enough to see returning users. Novelty effects decay over days.
- Keep the popularity baseline as a permanent control arm.

The Recommenders glossary defines the standard online metrics — CTR, conversion
rate, AOV, ARPU, MAU — if you need the business-side vocabulary.

---

## Recommended sequence

1. **Now** — build the Parquet cache; ship the content + popularity hybrid;
   precompute similar-title lists; establish the offline benchmark.
2. **With the first UI** — land the event schema above, including impressions
   and `source`. Log before you need it.
3. **At ~10k interactions** — train SAR, compare against the content model on
   the same protocol, and start the hybrid cascade (CF where it has signal,
   content everywhere else).
4. **At ~100k** — BPR or BiVAE; introduce a proper time-based split; begin A/B
   testing.
5. **Later** — sequential models over reading sessions, learned reranking with
   the catalog's rich side features (rung 5), embedding-based retrieval.

Steps 1 and 2 are the ones that matter. Everything after is standard work that
becomes possible only if the logging is right.
