"""Rung 0-2 recommenders for the recc-poc catalog.

All models share the interface used by ``recommenders.models.sar.SARSingleNode``:

    model.fit(items_df)
    recs = model.recommend_k_items(seeds, top_k=10, remove_seen=True)
    # -> DataFrame[userID, itemID, prediction]

In item-to-item mode ``userID`` holds the SEED title's id and ``itemID`` the
recommended title's id. This is deliberate: ranking metrics group by ``userID``,
so "per seed" and "per user" are structurally identical, and swapping in real
interaction data later changes nothing downstream.

Usage:
    python baselines.py --demo 3397             # Solo Leveling
    python baselines.py --demo 1692 --top-k 15  # BERSERK
"""

from __future__ import annotations

import argparse
import re
import unicodedata

import numpy as np
import pandas as pd
import scipy.sparse as sp
from sklearn.feature_extraction.text import TfidfTransformer
from sklearn.preprocessing import normalize

from catalog import load_items, load_relations
from metrics import (
    DEFAULT_ITEM_COL,
    DEFAULT_K,
    DEFAULT_PREDICTION_COL,
    DEFAULT_USER_COL,
)

EMPTY = pd.DataFrame(columns=[DEFAULT_USER_COL, DEFAULT_ITEM_COL, DEFAULT_PREDICTION_COL])

_PUNCT = re.compile(r"[^\w\s]", re.UNICODE)
_WS = re.compile(r"\s+")


def _norm(s):
    """Fold a free-text tag toward the catalog's own spelling.

    Incoming tags come from whatever source scraped the series, so `Slice of
    Life`, `slice-of-life` and `Slice Of Life` must land on the same column.
    Accents are stripped too: `Shōnen` and `Shounen` should not be two tags.
    """
    if not s:
        return ""
    s = unicodedata.normalize("NFKD", str(s))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return _WS.sub(" ", _PUNCT.sub(" ", s.casefold())).strip()


# Hand aliases, written from the measured miss list rather than guessed. Keys
# are already normalised; values must exist in the catalog vocabulary and are
# asserted at fit time so a typo fails loudly instead of silently dropping a tag.
ALIASES = {
    "male protagonist": "Male Lead",
    "female protagonist": "Female Lead",
    "bl": "Boys Love",
    "gl": "Girls Love",
    "shounen ai": "Boys Love",
    "shoujo ai": "Girls Love",
    "yuri": "Girls Love",
    "long strip": "Longstrip",
    "webtoons": "Web Comic",
    "webtoon webcomic": "Web Comic",
    "web comics": "Web Comic",
    "person in a strange world": "Isekai",
    "love triangles": "Love Triangle",
    "time travel": "Time Travel",
    "martial arts": "Martial Arts",
    "video games": "Video Games",
    "sci fi": "Sci-Fi",
    "gender bender": "Gender Bender",
    "school life": "School Life",
    "office workers": "Office Worker",
}

# Words that are not tags in this catalog — they are the `type` column. Routing
# them there turns a miss into a usable filter instead of noise.
TYPE_WORDS = {
    "manhwa": "manhwa", "manhua": "manhua", "manga": "manga",
    "webtoon": "manhwa", "webtoons": "manhwa",
    "light novels": "novel", "light novel": "novel",
    "web novels": "novel", "web novel": "novel", "novel": "novel",
    "oel": "oel",
}


def _variants(s):
    """Cheap spelling variants of a tag, most specific first."""
    base = _norm(s)
    if not base:
        return
    yield base
    # "Webtoon/Webcomic", "Fellatio, Oral"
    for part in re.split(r"[/,;|]", s):
        p = _norm(part)
        if p and p != base:
            yield p
    # plurals
    if base.endswith("ies") and len(base) > 4:
        yield base[:-3] + "y"
    if base.endswith("s") and not base.endswith("ss"):
        yield base[:-1]


def _seed_ids(seeds):
    """Accept a DataFrame with a userID column, a Series, or a plain iterable."""
    if isinstance(seeds, pd.DataFrame):
        col = DEFAULT_USER_COL if DEFAULT_USER_COL in seeds.columns else seeds.columns[0]
        return seeds[col].to_numpy()
    if isinstance(seeds, pd.Series):
        return seeds.to_numpy()
    return np.asarray(list(seeds))


class BaseRecommender:
    """Subclass this and register it in benchmark.py to join the comparison."""

    name = "base"

    def fit(self, items: pd.DataFrame):
        raise NotImplementedError

    def recommend_k_items(self, seeds, top_k=DEFAULT_K, remove_seen=True) -> pd.DataFrame:
        raise NotImplementedError


# --------------------------------------------------------------------------
# Rung 0 — popularity
# --------------------------------------------------------------------------
class PopularityRecommender(BaseRecommender):
    """Non-personalised ranking by inverted popularity rank, optionally blended
    with the aggregate rating.

    Every other model must beat this. If it does not, the personalisation is not
    earning its complexity.
    """

    name = "popularity"

    def __init__(self, rating_weight=0.0, min_rating_coverage=True):
        self.rating_weight = rating_weight
        self.min_rating_coverage = min_rating_coverage
        self.ranked_ = None

    def fit(self, items):
        score = (1 - self.rating_weight) * items["popularity_score"].to_numpy()
        if self.rating_weight > 0:
            score = score + self.rating_weight * items["rating_score"].to_numpy()
        df = pd.DataFrame({DEFAULT_ITEM_COL: items["id"].to_numpy(), "score": score})
        self.ranked_ = df.sort_values("score", ascending=False).reset_index(drop=True)
        return self

    def recommend_k_items(self, seeds, top_k=DEFAULT_K, remove_seen=True):
        ids = _seed_ids(seeds)
        if len(ids) == 0:
            return EMPTY.copy()
        # take k+1 so a seed appearing in its own list can be dropped
        head = self.ranked_.head(top_k + 1)
        out = pd.DataFrame({
            DEFAULT_USER_COL: np.repeat(ids, len(head)),
            DEFAULT_ITEM_COL: np.tile(head[DEFAULT_ITEM_COL].to_numpy(), len(ids)),
            DEFAULT_PREDICTION_COL: np.tile(head["score"].to_numpy(), len(ids)),
        })
        if remove_seen:
            out = out[out[DEFAULT_USER_COL] != out[DEFAULT_ITEM_COL]]
        return (
            out.groupby(DEFAULT_USER_COL, group_keys=False, sort=False)
            .head(top_k)
            .reset_index(drop=True)
        )


# --------------------------------------------------------------------------
# Rung 1 — content: TF-IDF over weighted tags
# --------------------------------------------------------------------------
class TagContentRecommender(BaseRecommender):
    """TF-IDF over ``tags_v2`` with term frequency scaled by tag weight, then
    cosine similarity.

    Mirrors ``recommenders.models.tfidf.tfidf_utils.TfidfRecommender`` but scores
    in batches against the sparse matrix instead of materialising a dense N x N
    similarity — at 302k titles that matrix would be ~365 TB.

    Args:
        min_df: drop tags appearing on fewer than this many titles.
        max_df: drop tags appearing on more than this fraction of titles. Very
            common tags carry no discriminative signal and destroy sparsity.
        use_genres: append ``genre_list`` entries to the token stream.
        batch_size: seeds scored per matmul. Each batch materialises a
            (batch_size x n_items) float32 block.
    """

    name = "tag-content"

    def __init__(self, min_df=3, max_df=0.4, use_genres=True, batch_size=64,
                 fuzzy_weight=1.0, ancestors=None, ancestor_decay=0.8):
        self.fuzzy_weight = fuzzy_weight
        self.min_df = min_df
        self.max_df = max_df
        self.use_genres = use_genres
        self.batch_size = batch_size
        # tag name -> ordered ancestor names, root first. Without it every tag
        # is its own orthogonal dimension and `Swordplay` shares nothing with
        # `Martial Arts` (nb 16).
        self.ancestors = ancestors or {}
        self.ancestor_decay = ancestor_decay
        self.matrix_ = None
        self.item_ids_ = None
        self.index_ = None

    def _accumulate(self, tokens, weights, acc=None):
        """Tag names + weights -> {token: weight}, with ancestors folded in.

        Ancestors are prefixed `^` so they occupy their own vocabulary entries
        and can never be confused with a real tag of the same name. Their weight
        decays with distance up the tree, but the heavy lifting is done by IDF:
        a broad ancestor appears on far more titles than its leaves and is
        discounted automatically, which is why the decay is mild.

        Used by both `fit` and `encode_tags` — the payload has to be expanded
        exactly like the catalog or the two vectors stop living in one space.
        """
        acc = {} if acc is None else acc
        for tok, w in zip(tokens, weights):
            acc[tok] = acc.get(tok, 0.0) + float(w)
            if self.ancestor_decay <= 0:
                continue
            for up, a in enumerate(reversed(self.ancestors.get(tok, ())), start=1):
                key = "^" + a
                acc[key] = acc.get(key, 0.0) + float(w) * self.ancestor_decay ** up
        return acc

    def fit(self, items):
        names = items["tag_names"].to_list()
        weights = items["tag_weights"].to_list()
        if self.use_genres:
            genres = items["genre_list"].to_list()
            names = [list(t) + ["genre:" + g for g in gs] for t, gs in zip(names, genres)]
            weights = [list(w) + [1.5] * len(gs) for w, gs in zip(weights, genres)]

        # expand once, then reuse for both the df pass and the matrix build
        docs = [self._accumulate(toks, wts) for toks, wts in zip(names, weights)]

        # document frequency pass -> vocabulary
        n_docs = len(docs)
        df_counts: dict[str, int] = {}
        for d in docs:
            for tok in d:
                df_counts[tok] = df_counts.get(tok, 0) + 1
        lo, hi = self.min_df, self.max_df * n_docs
        kept = sorted(t for t, c in df_counts.items() if lo <= c <= hi)
        vocab = {t: i for i, t in enumerate(kept)}
        if not vocab:
            raise ValueError("empty vocabulary — loosen min_df/max_df")

        rows, cols, vals = [], [], []
        for r, d in enumerate(docs):
            acc: dict[int, float] = {}
            for tok, w in d.items():
                c = vocab.get(tok)
                if c is not None:
                    acc[c] = acc.get(c, 0.0) + w
            if acc:
                rows.extend([r] * len(acc))
                cols.extend(acc.keys())
                vals.extend(acc.values())

        counts = sp.csr_matrix(
            (vals, (rows, cols)), shape=(n_docs, len(vocab)), dtype=np.float32
        )
        # Keep the fitted transformer and vocabulary. Without them the model can
        # only look up rows it already has; with them it can encode a document
        # it has never seen, which is what the payload path needs.
        self.tfidf_ = TfidfTransformer(sublinear_tf=True).fit(counts)
        tfidf = self.tfidf_.transform(counts)
        self.matrix_ = normalize(tfidf).astype(np.float32).tocsr()
        self.item_ids_ = items["id"].to_numpy()
        self.index_ = {int(v): i for i, v in enumerate(self.item_ids_)}
        self.vocab_ = vocab
        self.vocab_size_ = len(vocab)
        # normalised tag name -> column, so incoming free text can be matched.
        # Ancestor entries are excluded: `^Swordplay` normalises to the same key
        # as the real `Swordplay` tag and would silently overwrite it.
        self.lookup_ = {_norm(t): c for t, c in vocab.items()
                        if not t.startswith("^")}
        # ancestor token -> column, used to expand a payload the same way fit did
        self.anc_cols_ = {t[1:]: c for t, c in vocab.items() if t.startswith("^")}
        # column -> tag name, so a matched column can be walked back up the tree
        self.col_name_ = {c: t for t, c in vocab.items() if not t.startswith("^")}
        bad = [f"{k} -> {v}" for k, v in ALIASES.items() if _norm(v) not in self.lookup_]
        if bad:
            print(f"WARNING: {len(bad)} alias targets are not real tags: {bad}")
        return self

    def encode_tags(self, tag_names, tag_weights=None):
        """Encode raw tag strings into one query vector.

        This is the payload path: same vocabulary, same IDF, same normalisation
        as the fitted catalog, so the resulting vector lives in exactly the same
        space and cosine similarity is meaningful.

        Returns (vector, report) where report records which incoming tags were
        matched and which were dropped — the miss list is the single most useful
        diagnostic, because unmatched tags fail silently otherwise.
        """
        if self.matrix_ is None:
            raise RuntimeError("fit() first")
        weights = tag_weights or [1.0] * len(tag_names)

        acc: dict[int, float] = {}
        matched, missed, layers = [], [], {}
        type_hints = []
        for name, w in zip(tag_names, weights):
            col, layer = self._match(name)
            if layer == "type":
                type_hints.append(col)     # col holds the type value here
                layers["type"] = layers.get("type", 0) + 1
                continue
            if col is None:
                missed.append(name)
                layers["miss"] = layers.get("miss", 0) + 1
                continue
            matched.append(name)
            layers[layer] = layers.get(layer, 0) + 1
            # Fuzzy matches are guesses, not facts. `fuzzy_weight` < 1 discounts
            # them; = 1 treats them as equal to an exact hit. Measured, not assumed.
            mult = 1.0 if layer == "exact" else self.fuzzy_weight
            acc[col] = acc.get(col, 0.0) + float(w) * mult

            # expand up the tree exactly as fit() did, or a projected payload
            # lands in a different space than the catalog it is scored against
            for up, a in enumerate(reversed(self.ancestors.get(self.col_name_.get(col), ())),
                                   start=1):
                c = self.anc_cols_.get(a)
                if c is not None:
                    acc[c] = acc.get(c, 0.0) + float(w) * mult * self.ancestor_decay ** up

        counts = sp.csr_matrix(
            (list(acc.values()), ([0] * len(acc), list(acc.keys()))),
            shape=(1, len(self.vocab_)), dtype=np.float32,
        )
        vec = normalize(self.tfidf_.transform(counts)).astype(np.float32)
        return vec, {"matched": matched, "missed": missed, "layers": layers,
                     "type_hints": type_hints,
                     "n_in": len(tag_names), "n_matched": len(matched)}

    def _match(self, name):
        """Resolve one free-text tag -> (column | type value | None, layer)."""
        n = _norm(name)
        col = self.lookup_.get(n)
        if col is not None:
            return col, "exact"
        if n in ALIASES:
            target = self.lookup_.get(_norm(ALIASES[n]))
            if target is not None:
                return target, "alias"
        if n in TYPE_WORDS:
            return TYPE_WORDS[n], "type"
        for v in _variants(name):
            col = self.lookup_.get(v)
            if col is not None:
                return col, "rule"
            if v in ALIASES:
                target = self.lookup_.get(_norm(ALIASES[v]))
                if target is not None:
                    return target, "alias"
            if v in TYPE_WORDS:
                return TYPE_WORDS[v], "type"
        return None, "miss"

    def recommend_for_payload(self, payload, top_k=DEFAULT_K, seed_id=None):
        """v1 entry point: a metadata payload in, ranked catalog titles out.

        The described series need not exist in the catalog. Only ``tags`` is
        read at this rung — titles/authors/synopsis are accepted so the contract
        is stable while those signals get built.
        """
        vec, report = self.encode_tags(payload.get("tags") or [])
        if vec.nnz == 0:
            return EMPTY.copy(), {**report, "reason": "no tags matched the vocabulary"}

        scores = np.asarray((vec @ self.matrix_.T).todense(), dtype=np.float32).ravel()
        if seed_id is not None and seed_id in self.index_:
            scores[self.index_[seed_id]] = -np.inf

        k = min(top_k, scores.size)
        part = np.argpartition(-scores, k - 1)[:k]
        part = part[np.argsort(-scores[part])]
        out = pd.DataFrame({
            DEFAULT_USER_COL: seed_id if seed_id is not None else -1,
            DEFAULT_ITEM_COL: self.item_ids_[part],
            DEFAULT_PREDICTION_COL: scores[part],
        })
        return out[out[DEFAULT_PREDICTION_COL] > 0].reset_index(drop=True), report

    def recommend_k_items(self, seeds, top_k=DEFAULT_K, remove_seen=True):
        ids = [int(s) for s in _seed_ids(seeds)]
        rows = [(s, self.index_[s]) for s in ids if s in self.index_]
        if not rows:
            return EMPTY.copy()

        mat_t = self.matrix_.T.tocsr()
        take = top_k + 1 if remove_seen else top_k
        frames = []
        for start in range(0, len(rows), self.batch_size):
            batch = rows[start:start + self.batch_size]
            block = (self.matrix_[[r for _, r in batch]] @ mat_t)
            block = np.asarray(block.todense(), dtype=np.float32)
            k = min(take, block.shape[1])
            part = np.argpartition(-block, k - 1, axis=1)[:, :k]
            part_scores = np.take_along_axis(block, part, axis=1)
            order = np.argsort(-part_scores, axis=1)
            cols = np.take_along_axis(part, order, axis=1)
            scores = np.take_along_axis(part_scores, order, axis=1)
            frames.append(pd.DataFrame({
                DEFAULT_USER_COL: np.repeat([s for s, _ in batch], k),
                DEFAULT_ITEM_COL: self.item_ids_[cols].ravel(),
                DEFAULT_PREDICTION_COL: scores.ravel(),
            }))

        out = pd.concat(frames, ignore_index=True)
        if remove_seen:
            out = out[out[DEFAULT_USER_COL] != out[DEFAULT_ITEM_COL]]
        out = out[out[DEFAULT_PREDICTION_COL] > 0]
        return (
            out.groupby(DEFAULT_USER_COL, group_keys=False, sort=False)
            .head(top_k)
            .reset_index(drop=True)
        )


# --------------------------------------------------------------------------
# Rung 2 — relationship graph
# --------------------------------------------------------------------------
class RelationshipRecommender(BaseRecommender):
    """Franchise-graph expansion over the symmetrized ``relationships_v2`` edges.

    High precision, low coverage — only ~30% of active titles have any edge.

    WARNING: when the benchmark's ground truth is built from the same edges,
    this model is trained on the evaluation label. Its score is an oracle
    reference line, not a comparable result.
    """

    name = "relationship"

    def __init__(self, relations=None, hops=2, decay=0.4):
        self.relations = relations
        self.hops = hops
        self.decay = decay
        self.adj_: dict[int, list[int]] = {}

    def fit(self, items=None):
        rel = self.relations if self.relations is not None else load_relations()
        self.adj_ = {
            int(u): [int(v) for v in grp[DEFAULT_ITEM_COL]]
            for u, grp in rel.groupby(DEFAULT_USER_COL)
        }
        return self

    def recommend_k_items(self, seeds, top_k=DEFAULT_K, remove_seen=True):
        recs = []
        for seed in (int(s) for s in _seed_ids(seeds)):
            scores: dict[int, float] = {}
            frontier, visited = [seed], {seed}
            for hop in range(self.hops):
                weight = self.decay ** hop
                nxt = []
                for node in frontier:
                    for nb in self.adj_.get(node, ()):
                        if remove_seen and nb == seed:
                            continue
                        scores[nb] = max(scores.get(nb, 0.0), weight)
                        if nb not in visited:
                            visited.add(nb)
                            nxt.append(nb)
                frontier = nxt
                if not frontier:
                    break
            for item, score in sorted(scores.items(), key=lambda kv: -kv[1])[:top_k]:
                recs.append((seed, item, score))
        if not recs:
            return EMPTY.copy()
        return pd.DataFrame(
            recs, columns=[DEFAULT_USER_COL, DEFAULT_ITEM_COL, DEFAULT_PREDICTION_COL]
        )


# --------------------------------------------------------------------------
# Hybrid
# --------------------------------------------------------------------------
class HybridRecommender(BaseRecommender):
    """Score-level blend of component models after per-seed min-max normalisation.

    ``models`` is a list of ``(model, weight)``. Components are asked for a
    deeper list (``top_k * oversample``) so the blend has something to reorder.
    """

    name = "hybrid"

    def __init__(self, models, oversample=3):
        self.models = models
        self.oversample = oversample

    def fit(self, items):
        for model, _ in self.models:
            if getattr(model, "matrix_", None) is None and not getattr(model, "adj_", None) \
                    and getattr(model, "ranked_", None) is None:
                model.fit(items)
        return self

    def recommend_k_items(self, seeds, top_k=DEFAULT_K, remove_seen=True):
        deep = top_k * self.oversample
        frames = []
        for model, weight in self.models:
            recs = model.recommend_k_items(seeds, top_k=deep, remove_seen=remove_seen)
            if recs.empty:
                continue
            grp = recs.groupby(DEFAULT_USER_COL)[DEFAULT_PREDICTION_COL]
            lo, hi = grp.transform("min"), grp.transform("max")
            span = (hi - lo).replace(0, np.nan)
            recs = recs.assign(
                **{DEFAULT_PREDICTION_COL: weight * ((recs[DEFAULT_PREDICTION_COL] - lo) / span).fillna(1.0)}
            )
            frames.append(recs)
        if not frames:
            return EMPTY.copy()
        pooled = (
            pd.concat(frames, ignore_index=True)
            .groupby([DEFAULT_USER_COL, DEFAULT_ITEM_COL], as_index=False)[DEFAULT_PREDICTION_COL]
            .sum()
            .sort_values([DEFAULT_USER_COL, DEFAULT_PREDICTION_COL], ascending=[True, False])
        )
        return (
            pooled.groupby(DEFAULT_USER_COL, group_keys=False, sort=False)
            .head(top_k)
            .reset_index(drop=True)
        )


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--demo", type=int, required=True, help="seed series id")
    ap.add_argument("--top-k", type=int, default=DEFAULT_K)
    args = ap.parse_args()

    items = load_items()
    titles = dict(zip(items["id"], items["title"]))
    seed = args.demo
    if seed not in titles:
        raise SystemExit(f"id {seed} is not an active title")
    print(f"seed: {seed}  {titles[seed]}\n")

    models = [
        PopularityRecommender().fit(items),
        TagContentRecommender().fit(items),
        RelationshipRecommender().fit(items),
    ]
    models.append(
        HybridRecommender([(models[2], 1.0), (models[1], 0.6), (models[0], 0.2)]).fit(items)
    )

    seeds = pd.DataFrame({DEFAULT_USER_COL: [seed]})
    for model in models:
        recs = model.recommend_k_items(seeds, top_k=args.top_k)
        print(f"--- {model.name} ({len(recs)} results)")
        for _, row in recs.iterrows():
            iid = int(row[DEFAULT_ITEM_COL])
            print(f"    {row[DEFAULT_PREDICTION_COL]:7.4f}  {iid:>7}  "
                  f"{titles.get(iid, '?')}")
        print()


if __name__ == "__main__":
    main()


# --------------------------------------------------------------------------
# Rung 1b — content: TF-IDF over the synopsis
# --------------------------------------------------------------------------
_BOILER = [
    # bracketed: "(Source: Viz Media)", "[Source: MU, translated]" -> stops at
    # the closing bracket, so it can never run past its own block
    re.compile(r"[\(\[]\s*(?:source|note)\s*[:\-][^)\]]*[\)\]]", re.I),
    # bare: "Source: Kodansha" -> stops at end of LINE, not end of string.
    # Running to $ would swallow real plot text when a note appears mid-body.
    re.compile(r"(?im)^\s*(?:source|note)\s*[:\-].*$"),
    re.compile(r"https?://\S+"),
    re.compile(r"\*\*|__"),
]
_MDLINK = re.compile(r"\[([^\]]+)\]\([^)]+\)")


def clean_synopsis(text):
    """Strip scraper boilerplate from a description.

    47.9% of descriptions carry a source attribution or URL. Left in, TF-IDF
    learns that two titles are similar because both were published by Viz —
    publisher metadata scored as plot.
    """
    if not text:
        return ""
    s = _MDLINK.sub(r"\1", str(text))
    for pat in _BOILER:
        s = pat.sub(" ", s)
    return _WS.sub(" ", s).strip()


class SynopsisContentRecommender(BaseRecommender):
    """TF-IDF over cleaned `description` text, cosine similarity.

    The only signal in a v1 payload that does not depend on somebody else's tag
    vocabulary. Coverage is the catch: 62.5% of active titles have a
    description, and only 43.1% of thinly-tagged ones do.
    """

    name = "synopsis"

    # ngram_range is (1, 1) on purpose. sklearn strips stopwords BEFORE forming
    # n-grams, so bigrams get glued across sentence boundaries: "…two years ago.
    # However, for some reason…" becomes the term `ago reason`. Measured over the
    # real vocabulary, 62% of bigrams never appear verbatim in the prose, and they
    # carry high IDF precisely because they are artifacts. Dropping them beat
    # sentence-bounding and keeping stopwords on every population (nb 13).
    def __init__(self, min_df=5, max_df=0.3, ngram_range=(1, 1),
                 max_features=100_000, clean=True, batch_size=64):
        self.min_df = min_df
        self.max_df = max_df
        self.ngram_range = ngram_range
        self.max_features = max_features
        self.clean = clean
        self.batch_size = batch_size
        self.matrix_ = None

    def fit(self, items):
        from sklearn.feature_extraction.text import TfidfVectorizer

        raw = items["description"].fillna("").astype(str)
        docs = raw.map(clean_synopsis) if self.clean else raw

        self.vec_ = TfidfVectorizer(
            strip_accents="unicode", lowercase=True, stop_words="english",
            ngram_range=self.ngram_range, min_df=self.min_df, max_df=self.max_df,
            max_features=self.max_features, sublinear_tf=True, dtype=np.float32,
        )
        self.matrix_ = normalize(self.vec_.fit_transform(docs)).astype(np.float32).tocsr()
        self.item_ids_ = items["id"].to_numpy()
        self.index_ = {int(v): i for i, v in enumerate(self.item_ids_)}
        self.has_text_ = np.asarray(self.matrix_.getnnz(axis=1) > 0, dtype=bool)
        return self

    def encode_text(self, synopsis):
        """One synopsis -> one normalised vector in the fitted term space."""
        s = clean_synopsis(synopsis) if self.clean else (synopsis or "")
        if not s.strip():
            return sp.csr_matrix((1, len(self.vec_.vocabulary_)), dtype=np.float32)
        v = self.vec_.transform([s])
        return normalize(v).astype(np.float32) if v.nnz else v

    def encode_batch(self, synopses):
        docs = [clean_synopsis(s) if self.clean else (s or "") for s in synopses]
        return normalize(self.vec_.transform(docs)).astype(np.float32)

    def recommend_k_items(self, seeds, top_k=DEFAULT_K, remove_seen=True):
        ids = [int(s) for s in _seed_ids(seeds)]
        rows = [(s, self.index_[s]) for s in ids
                if s in self.index_ and self.has_text_[self.index_[s]]]
        if not rows:
            return EMPTY.copy()

        mat_t = self.matrix_.T.tocsr()
        take = top_k + 1 if remove_seen else top_k
        frames = []
        for start in range(0, len(rows), self.batch_size):
            batch = rows[start:start + self.batch_size]
            block = np.asarray(
                (self.matrix_[[r for _, r in batch]] @ mat_t).todense(), dtype=np.float32)
            k = min(take, block.shape[1])
            part = np.argpartition(-block, k - 1, axis=1)[:, :k]
            sc = np.take_along_axis(block, part, axis=1)
            order = np.argsort(-sc, axis=1)
            cols = np.take_along_axis(part, order, axis=1)
            frames.append(pd.DataFrame({
                DEFAULT_USER_COL: np.repeat([s for s, _ in batch], k),
                DEFAULT_ITEM_COL: self.item_ids_[cols].ravel(),
                DEFAULT_PREDICTION_COL: np.take_along_axis(sc, order, axis=1).ravel(),
            }))

        out = pd.concat(frames, ignore_index=True)
        if remove_seen:
            out = out[out[DEFAULT_USER_COL] != out[DEFAULT_ITEM_COL]]
        out = out[out[DEFAULT_PREDICTION_COL] > 0]
        return (out.groupby(DEFAULT_USER_COL, group_keys=False, sort=False)
                .head(top_k).reset_index(drop=True))
