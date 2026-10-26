"""Offline benchmark for recc-poc recommenders.

Evaluates every registered model against the relationship ground truth using the
Recommenders metric definitions, and prints accuracy alongside coverage and
novelty. Reporting accuracy alone is how you ship a model that recommends the
same 200 popular titles to everyone.

Usage:
    python benchmark.py                          # 2000 seeds, k=10
    python benchmark.py --n-seeds 5000 --top-k 20
    python benchmark.py --models popularity,tag-content
    python benchmark.py --safe-only              # content_rating == 'safe'

Protocol (fix it before comparing anything):
  * seeds  = active titles with >= 1 strong-relation edge, sampled with SEED=42
  * truth  = the full symmetrized strong-relation edge set for each seed
  * k      = --top-k
  * the seed is always excluded from its own recommendations
"""

from __future__ import annotations

import argparse
import time

import numpy as np
import pandas as pd

from baselines import (
    HybridRecommender,
    PopularityRecommender,
    RelationshipRecommender,
    TagContentRecommender,
)
from catalog import load_items, load_relations
from metrics import (
    DEFAULT_ITEM_COL,
    DEFAULT_USER_COL,
    SEED,
    catalog_coverage,
    distributional_coverage,
    map_at_k,
    ndcg_at_k,
    novelty,
    precision_at_k,
    r_precision_at_k,
    recall_at_k,
)


def build_models(items, relations):
    """Registry. Add a model here and it joins every comparison."""
    pop = PopularityRecommender()
    tag = TagContentRecommender()
    rel = RelationshipRecommender(relations=relations)
    hybrid = HybridRecommender([(rel, 1.0), (tag, 0.6), (pop, 0.2)])
    return {
        "popularity": pop,
        "tag-content": tag,
        "relationship": rel,
        "hybrid": hybrid,
    }


# Models that train on the same edges used as ground truth. Their scores are an
# oracle reference line, not a comparable result.
LEAKY = {"relationship", "hybrid"}


def build_reference(items):
    """Pseudo-interaction distribution standing in for a real log.

    Novelty and coverage are defined against how often each item is *interacted
    with*. There is no interaction log yet, and one row per item makes every
    item equally novel. Popularity rank is the best available proxy, so weight
    each item by its inverted rank and treat that as expected demand. Replace
    this with the real log the moment one exists.
    """
    weight = items["popularity_score"].to_numpy(dtype=float)
    weight = np.where(np.isfinite(weight) & (weight > 0), weight, 0.0)
    return pd.DataFrame({
        DEFAULT_USER_COL: 0,
        DEFAULT_ITEM_COL: items["id"].to_numpy(),
        "weight": weight,
    })


def evaluate(model, truth, seeds, items, top_k, train_ref, pop_rank):
    t0 = time.perf_counter()
    recs = model.recommend_k_items(seeds, top_k=top_k, remove_seen=True)
    elapsed = time.perf_counter() - t0

    if recs.empty:
        return {"model": model.name, "seeds_served": 0}

    ranks = recs[DEFAULT_ITEM_COL].map(pop_rank).dropna()

    return {
        "model": model.name,
        "MAP@k": map_at_k(truth, recs, k=top_k),
        "nDCG@k": ndcg_at_k(truth, recs, k=top_k),
        "Prec@k": precision_at_k(truth, recs, k=top_k),
        "Recall@k": recall_at_k(truth, recs, k=top_k),
        "R-prec": r_precision_at_k(truth, recs, k=top_k),
        "coverage": catalog_coverage(train_ref, recs),
        "dist-cov": distributional_coverage(train_ref, recs),
        "novelty": novelty(train_ref, recs, col_weight="weight"),
        "med-pop-rank": float(ranks.median()) if len(ranks) else float("nan"),
        "seeds_served": recs[DEFAULT_USER_COL].nunique(),
        "sec": elapsed,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--n-seeds", type=int, default=2000)
    ap.add_argument("--top-k", type=int, default=10)
    ap.add_argument("--models", type=str, default=None,
                    help="comma-separated subset of the registry")
    ap.add_argument("--safe-only", action="store_true",
                    help="restrict the catalog to content_rating == 'safe'")
    ap.add_argument("--seed", type=int, default=SEED)
    args = ap.parse_args()

    items = load_items()
    relations = load_relations()

    if args.safe_only:
        items = items[items["content_rating"] == "safe"].reset_index(drop=True)
        keep = set(items["id"].astype(int))
        relations = relations[
            relations[DEFAULT_USER_COL].isin(keep) & relations[DEFAULT_ITEM_COL].isin(keep)
        ]

    # seed pool: titles that have ground truth AND exist in the item table
    known = set(items["id"].astype(int))
    relations = relations[relations[DEFAULT_USER_COL].isin(known)]
    pool = relations[DEFAULT_USER_COL].unique()
    rng = np.random.default_rng(args.seed)
    chosen = rng.choice(pool, size=min(args.n_seeds, len(pool)), replace=False)
    seeds = pd.DataFrame({DEFAULT_USER_COL: chosen})
    truth = relations[relations[DEFAULT_USER_COL].isin(set(chosen))]

    sizes = truth.groupby(DEFAULT_USER_COL).size()
    print(f"catalog     {len(items):,} active titles")
    print(f"seed pool   {len(pool):,} titles with ground truth; sampled {len(chosen):,}")
    print(f"truth       {len(truth):,} pairs | per seed: mean={sizes.mean():.1f} "
          f"median={sizes.median():.0f} max={sizes.max()}")
    print(f"protocol    k={args.top_k} seed={args.seed} "
          f"{'safe-only' if args.safe_only else 'all content ratings'}\n")

    registry = build_models(items, relations)
    wanted = args.models.split(",") if args.models else list(registry)

    train_ref = build_reference(items)
    pop_rank = dict(zip(items["id"], pd.to_numeric(
        items["popularity_global_current"], errors="coerce")))

    rows = []
    for name in wanted:
        if name not in registry:
            raise SystemExit(f"unknown model {name!r}; choose from {list(registry)}")
        model = registry[name]
        print(f"fitting {name} ...", end=" ", flush=True)
        t0 = time.perf_counter()
        model.fit(items)
        print(f"{time.perf_counter() - t0:.1f}s")
        rows.append(evaluate(model, truth, seeds, items, args.top_k, train_ref, pop_rank))

    table = pd.DataFrame(rows).set_index("model")
    for col in table.columns:
        if col not in ("seeds_served", "med-pop-rank"):
            table[col] = table[col].astype(float).round(4)

    print("\n" + "=" * 100)
    print(table.to_string())
    print("=" * 100)

    leaky = [n for n in wanted if n in LEAKY]
    if leaky:
        print(f"\nNOTE: {', '.join(leaky)} train on the relationship edges used as "
              f"ground truth.\n      Their scores are an oracle reference line, not a "
              f"comparable result.")
    print("\nRead coverage next to accuracy: a model that wins on nDCG while covering"
          "\na fraction of a percent of the catalog has memorised the popular head.")


if __name__ == "__main__":
    main()
