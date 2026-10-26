"""Build normalized Parquet artifacts from ``data/series.sqlite``.

Outputs (into ``data/``):
    items.parquet      one row per ACTIVE title, JSON columns parsed
    relations.parquet   symmetrized ground-truth edge list [userID, itemID, rating]

Usage:
    python catalog.py --build              # build both, skip if cached
    python catalog.py --build --force
    python catalog.py --build --limit 20000    # fast iteration
    python catalog.py --build --include-weak   # keep parody/cameo/other edges
    python catalog.py --info                   # summarise the cached artifacts

Only ``state = 'active'`` rows are read: the other 45% of the table is merged
duplicates and would poison both similarity and evaluation.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[4]
DB_PATH = REPO / "data" / "series.sqlite"
ITEMS_PATH = REPO / "data" / "items.parquet"
RELATIONS_PATH = REPO / "data" / "relations.parquet"

# tags_v2 weight -> term-frequency multiplier
TAG_WEIGHTS = {
    "defining": 3.0,
    "core": 2.0,
    "recurrent": 1.5,
    "incidental": 1.0,
    "unweighted": 1.0,
}

# relation_type buckets. `parody` (the most common type) and `cameo` are
# overwhelmingly doujinshi noise and make poor relevance labels.
STRONG_RELATIONS = {
    "sequel", "prequel", "side_story", "spin_off", "main", "source",
    "alternative", "adaptation", "parent", "contains", "series",
    "compilation", "remake", "summary", "character_focus",
}
WEAK_RELATIONS = {"parody", "cameo", "other", "crossover"}

SELECT_COLS = [
    "id", "title", "type", "year", "status", "content_rating",
    "tags_v2", "tags", "genres", "authors", "artists", "description",
    "rating", "popularity_global_current", "popularity_type_current",
    "total_chapters", "has_anime", "relationships_v2",
]


def _loads(raw):
    if not raw:
        return []
    try:
        val = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return []
    return val if isinstance(val, list) else []


def _parse_tags(raw_v2, raw_flat):
    """-> (list[str] names, list[float] weights). Falls back to flat `tags`."""
    entries = _loads(raw_v2)
    if entries:
        names, weights = [], []
        for t in entries:
            name = t.get("name")
            if not name:
                continue
            names.append(name)
            weights.append(TAG_WEIGHTS.get(t.get("weight"), 1.0))
        if names:
            return names, weights
    flat = [t for t in _loads(raw_flat) if isinstance(t, str)]
    return flat, [1.0] * len(flat)


def _parse_relations(raw, include_weak=False):
    """-> list[(to_series_id, relation_type)] for the kept relation types."""
    keep = STRONG_RELATIONS | WEAK_RELATIONS if include_weak else STRONG_RELATIONS
    out = []
    for r in _loads(raw):
        if not isinstance(r, dict):
            continue
        target, rtype = r.get("to_series_id"), r.get("relation_type")
        if target is None or rtype not in keep:
            continue
        out.append((int(target), rtype))
    return out


def build(limit=None, include_weak=False, chunksize=25_000):
    if not DB_PATH.exists():
        sys.exit(f"missing {DB_PATH} — decompress series.sqlite.zst first")

    query = f"SELECT {', '.join(SELECT_COLS)} FROM series WHERE state = 'active'"
    if limit:
        query += f" LIMIT {int(limit)}"

    conn = sqlite3.connect(DB_PATH)
    item_chunks, edge_rows = [], []
    n_read = 0

    for chunk in pd.read_sql_query(query, conn, chunksize=chunksize):
        n_read += len(chunk)
        print(f"  ... {n_read:,} rows", end="\r", flush=True)

        parsed = [_parse_tags(a, b) for a, b in zip(chunk["tags_v2"], chunk["tags"])]
        chunk["tag_names"] = [p[0] for p in parsed]
        chunk["tag_weights"] = [p[1] for p in parsed]
        chunk["genre_list"] = [
            [g for g in _loads(v) if isinstance(g, str)] for v in chunk["genres"]
        ]
        chunk["author_list"] = [
            [a for a in _loads(v) if isinstance(a, str)] for v in chunk["authors"]
        ]

        for sid, raw in zip(chunk["id"], chunk["relationships_v2"]):
            for target, rtype in _parse_relations(raw, include_weak):
                edge_rows.append((int(sid), target, rtype))

        item_chunks.append(
            chunk.drop(columns=["tags_v2", "tags", "genres", "authors",
                                "relationships_v2"])
        )

    conn.close()
    print()

    items = pd.concat(item_chunks, ignore_index=True)
    items["n_tags"] = items["tag_names"].str.len()

    # popularity_global_current is a RANK (1 = most popular). Invert it into a
    # bounded score so it can be blended or used as a feature.
    rank = pd.to_numeric(items["popularity_global_current"], errors="coerce")
    items["popularity_score"] = np.where(
        rank.notna(), 1.0 / np.log1p(rank.fillna(1e9)), 0.0
    )
    items["rating_score"] = pd.to_numeric(items["rating"], errors="coerce").fillna(0.0) / 100.0

    ITEMS_PATH.parent.mkdir(parents=True, exist_ok=True)
    items.to_parquet(ITEMS_PATH, index=False)

    # --- ground truth: symmetrize, drop self-loops and dangling targets -----
    edges = pd.DataFrame(edge_rows, columns=["userID", "itemID", "relation_type"])
    if not edges.empty:
        valid = set(items["id"].astype(int))
        edges = edges[edges["itemID"].isin(valid) & edges["userID"].isin(valid)]
        mirrored = edges.rename(columns={"userID": "itemID", "itemID": "userID"})
        edges = pd.concat([edges, mirrored[edges.columns]], ignore_index=True)
        edges = edges[edges["userID"] != edges["itemID"]]
        edges = edges.drop_duplicates(subset=["userID", "itemID"])
    edges["rating"] = 1.0
    edges.to_parquet(RELATIONS_PATH, index=False)

    print(f"wrote {ITEMS_PATH}      {len(items):,} titles")
    print(f"wrote {RELATIONS_PATH}  {len(edges):,} edges over "
          f"{edges['userID'].nunique():,} seeds")
    return items, edges


def load_items():
    if not ITEMS_PATH.exists():
        sys.exit(f"missing {ITEMS_PATH} — run: python catalog.py --build")
    return pd.read_parquet(ITEMS_PATH)


def load_relations():
    if not RELATIONS_PATH.exists():
        sys.exit(f"missing {RELATIONS_PATH} — run: python catalog.py --build")
    return pd.read_parquet(RELATIONS_PATH)


def info():
    items, rel = load_items(), load_relations()
    print(f"items.parquet      {len(items):,} active titles, {len(items.columns)} cols")
    print(f"  with tags        {(items['n_tags'] > 0).sum():,}")
    print(f"  types            {items['type'].value_counts().to_dict()}")
    print(f"  content_rating   {items['content_rating'].value_counts().to_dict()}")
    print(f"relations.parquet  {len(rel):,} edges, {rel['userID'].nunique():,} seeds")
    print(f"  relation types   {rel['relation_type'].value_counts().head(10).to_dict()}")
    sizes = rel.groupby("userID").size()
    print(f"  edges per seed   mean={sizes.mean():.1f} median={sizes.median():.0f} "
          f"p90={sizes.quantile(0.9):.0f} max={sizes.max()}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--info", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--limit", type=int, default=None,
                    help="dev subset. NOTE: LIMIT without ORDER BY returns rows "
                         "in rowid order, which skews toward low ids (popular, "
                         "well-populated titles). Never benchmark on it.")
    ap.add_argument("--include-weak", action="store_true",
                    help="keep parody/cameo/other edges in ground truth")
    args = ap.parse_args()

    if args.build:
        if ITEMS_PATH.exists() and RELATIONS_PATH.exists() and not args.force:
            print("artifacts already exist; use --force to rebuild")
        else:
            build(limit=args.limit, include_weak=args.include_weak)
    if args.info or not args.build:
        info()


if __name__ == "__main__":
    main()
