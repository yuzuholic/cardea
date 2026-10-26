"""Recommenders-compatible constants, splitters, and metrics.

Mirrors the public API of ``recommenders.utils.constants``,
``recommenders.datasets.python_splitters`` and
``recommenders.evaluation.python_evaluation`` from
https://github.com/recommenders-team/recommenders (MIT).

The upstream package pins ``numpy<2`` / ``pandas<3`` and cannot be installed
into this project's ``.venv`` (Python 3.13, numpy 2.5, pandas 3.0). These are
independent implementations of the same documented definitions, with matching
names, signatures and column conventions, so that switching to the real package
later is an import change and nothing more.

Metric definitions follow:
  - Precision@k / Recall@k / MAP@k : Spark MLlib RankingMetrics conventions
  - nDCG@k                        : normalised DCG, binary relevance, log_e
  - novelty / diversity /
    serendipity / coverage        : Castells et al. ECIR 2011;
                                    Zhang et al. WSDM 2012;
                                    Shani & Gunawardana 2010
"""

from __future__ import annotations

import numpy as np
import pandas as pd

# --------------------------------------------------------------------------
# recommenders.utils.constants
# --------------------------------------------------------------------------
DEFAULT_USER_COL = "userID"
DEFAULT_ITEM_COL = "itemID"
DEFAULT_RATING_COL = "rating"
DEFAULT_LABEL_COL = "label"
DEFAULT_TITLE_COL = "title"
DEFAULT_GENRE_COL = "genre"
DEFAULT_RELEVANCE_COL = "relevance"
DEFAULT_TIMESTAMP_COL = "timestamp"
DEFAULT_PREDICTION_COL = "prediction"
DEFAULT_SIMILARITY_COL = "sim"
DEFAULT_ITEM_FEATURES_COL = "features"

DEFAULT_HEADER = (
    DEFAULT_USER_COL,
    DEFAULT_ITEM_COL,
    DEFAULT_RATING_COL,
    DEFAULT_TIMESTAMP_COL,
)

COL_DICT = {
    "col_user": DEFAULT_USER_COL,
    "col_item": DEFAULT_ITEM_COL,
    "col_rating": DEFAULT_RATING_COL,
    "col_prediction": DEFAULT_PREDICTION_COL,
}

DEFAULT_K = 10
DEFAULT_THRESHOLD = 10
SEED = 42


# --------------------------------------------------------------------------
# recommenders.datasets.python_splitters
# --------------------------------------------------------------------------
def min_rating_filter_pandas(
    data,
    min_rating=1,
    filter_by="user",
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
):
    """Drop users (or items) with fewer than ``min_rating`` interactions."""
    if filter_by not in ("user", "item"):
        raise ValueError("filter_by should be either 'user' or 'item'.")
    if min_rating < 1:
        raise ValueError("min_rating should be an integer >= 1.")
    key = col_user if filter_by == "user" else col_item
    if min_rating <= 1:
        return data
    counts = data.groupby(key)[key].transform("size")
    return data[counts >= min_rating]


def _process_ratio(ratio):
    if isinstance(ratio, float):
        if ratio <= 0 or ratio >= 1:
            raise ValueError("ratio must be in (0, 1)")
        return False, ratio
    if isinstance(ratio, (list, tuple)):
        if any(r <= 0 for r in ratio):
            raise ValueError("all ratios must be positive")
        total = sum(ratio)
        return True, [r / total for r in ratio]
    raise TypeError("ratio must be a float or a list of floats")


def python_random_split(data, ratio=0.75, seed=SEED):
    """Random split. Returns a list of DataFrames."""
    multi, ratio = _process_ratio(ratio)
    ratios = ratio if multi else [ratio, 1 - ratio]
    shuffled = data.sample(frac=1.0, random_state=seed).reset_index(drop=True)
    bounds = [0, *(np.cumsum(ratios) * len(shuffled)).round().astype(int)[:-1], len(shuffled)]
    return [
        shuffled.iloc[lo:hi].reset_index(drop=True)
        for lo, hi in zip(bounds[:-1], bounds[1:])
    ]


def _stratify(
    data,
    ratio=0.75,
    min_rating=1,
    filter_by="user",
    is_random=True,
    seed=SEED,
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    col_timestamp=DEFAULT_TIMESTAMP_COL,
):
    if filter_by not in ("user", "item"):
        raise ValueError("filter_by should be either 'user' or 'item'.")
    for col in (col_user, col_item):
        if col not in data.columns:
            raise ValueError(f"Schema of data not valid. Missing {col}")
    if not is_random and col_timestamp not in data.columns:
        raise ValueError("Schema of data not valid. Missing Timestamp Col")

    multi, ratio = _process_ratio(ratio)
    ratios = ratio if multi else [ratio, 1 - ratio]
    split_col = col_user if filter_by == "user" else col_item

    data = min_rating_filter_pandas(
        data, min_rating=min_rating, filter_by=filter_by,
        col_user=col_user, col_item=col_item,
    ).copy()

    if is_random:
        rng = np.random.default_rng(seed)
        data["_order"] = rng.random(len(data))
    else:
        data["_order"] = data[col_timestamp]

    data = data.sort_values([split_col, "_order"])
    groups = data.groupby(split_col)
    data["_count"] = groups[split_col].transform("size")
    data["_rank"] = groups.cumcount() + 1

    splits, prev = [], None
    for threshold in np.cumsum(ratios):
        cond = data["_rank"] <= (threshold * data["_count"]).round()
        if prev is not None:
            cond &= data["_rank"] > (prev * data["_count"]).round()
        splits.append(data[cond].drop(columns=["_order", "_rank", "_count"]))
        prev = threshold
    return splits


def python_stratified_split(
    data,
    ratio=0.75,
    min_rating=1,
    filter_by="user",
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    seed=SEED,
):
    """Per-user (or per-item) proportional random split."""
    return _stratify(
        data, ratio=ratio, min_rating=min_rating, filter_by=filter_by,
        is_random=True, seed=seed, col_user=col_user, col_item=col_item,
    )


def python_chrono_split(
    data,
    ratio=0.75,
    min_rating=1,
    filter_by="user",
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    col_timestamp=DEFAULT_TIMESTAMP_COL,
):
    """Per-user (or per-item) chronological split. Use once timestamps exist."""
    return _stratify(
        data, ratio=ratio, min_rating=min_rating, filter_by=filter_by,
        is_random=False, col_user=col_user, col_item=col_item,
        col_timestamp=col_timestamp,
    )


# --------------------------------------------------------------------------
# recommenders.evaluation.python_evaluation — ranking metrics
# --------------------------------------------------------------------------
def get_top_k_items(
    dataframe, col_user=DEFAULT_USER_COL, col_rating=DEFAULT_RATING_COL, k=DEFAULT_K
):
    """Top-k rows per user, with a 1-based ``rank`` column."""
    top = (
        dataframe.sort_values([col_user, col_rating], ascending=[True, False])
        .groupby(col_user, as_index=False)
        .head(k if k is not None else len(dataframe))
        .copy()
    )
    top["rank"] = top.groupby(col_user).cumcount() + 1
    return top.reset_index(drop=True)


def _merge_ranking_true_pred(
    rating_true,
    rating_pred,
    col_user,
    col_item,
    col_prediction,
    relevancy_method="top_k",
    k=DEFAULT_K,
    threshold=DEFAULT_THRESHOLD,
):
    """Join truth and predictions on the users common to both.

    Returns (df_hit, df_hit_count, n_users) where df_hit carries the model rank
    of each hit and df_hit_count the per-user hit / relevant counts.
    """
    common = set(rating_true[col_user].unique()) & set(rating_pred[col_user].unique())
    n_users = len(common)
    if n_users == 0:
        empty = pd.DataFrame(columns=[col_user, col_item, "rank"])
        return empty, pd.DataFrame(columns=[col_user, "hit", "actual"]), 0

    true = rating_true[rating_true[col_user].isin(common)]
    pred = rating_pred[rating_pred[col_user].isin(common)]

    if relevancy_method == "top_k":
        top = get_top_k_items(pred, col_user=col_user, col_rating=col_prediction, k=k)
    elif relevancy_method == "by_threshold":
        sel = pred[pred[col_prediction] >= threshold]
        top = get_top_k_items(sel, col_user=col_user, col_rating=col_prediction, k=None)
    elif relevancy_method is None:
        top = get_top_k_items(pred, col_user=col_user, col_rating=col_prediction, k=None)
    else:
        raise NotImplementedError(f"Unknown relevancy_method: {relevancy_method}")

    df_hit = top.merge(true[[col_user, col_item]], on=[col_user, col_item])[
        [col_user, col_item, "rank"]
    ]

    hits = df_hit.groupby(col_user, as_index=False).size().rename(columns={"size": "hit"})
    actual = (
        true.groupby(col_user, as_index=False)[col_item]
        .nunique()
        .rename(columns={col_item: "actual"})
    )
    df_hit_count = actual.merge(hits, on=col_user, how="left").fillna({"hit": 0})
    return df_hit, df_hit_count, n_users


def precision_at_k(
    rating_true,
    rating_pred,
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    col_prediction=DEFAULT_PREDICTION_COL,
    relevancy_method="top_k",
    k=DEFAULT_K,
    threshold=DEFAULT_THRESHOLD,
    **_,
):
    """Precision@k, averaged over users. Denominator is k (Spark convention)."""
    _, hc, n_users = _merge_ranking_true_pred(
        rating_true, rating_pred, col_user, col_item, col_prediction,
        relevancy_method, k, threshold,
    )
    if n_users == 0:
        return 0.0
    return float((hc["hit"] / k).sum() / n_users)


def recall_at_k(
    rating_true,
    rating_pred,
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    col_prediction=DEFAULT_PREDICTION_COL,
    relevancy_method="top_k",
    k=DEFAULT_K,
    threshold=DEFAULT_THRESHOLD,
    **_,
):
    """Recall@k, averaged over users."""
    _, hc, n_users = _merge_ranking_true_pred(
        rating_true, rating_pred, col_user, col_item, col_prediction,
        relevancy_method, k, threshold,
    )
    if n_users == 0:
        return 0.0
    return float((hc["hit"] / hc["actual"]).sum() / n_users)


def r_precision_at_k(
    rating_true,
    rating_pred,
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    col_prediction=DEFAULT_PREDICTION_COL,
    relevancy_method="top_k",
    k=DEFAULT_K,
    threshold=DEFAULT_THRESHOLD,
    **_,
):
    """Precision at R, where R is each user's number of relevant items."""
    df_hit, hc, n_users = _merge_ranking_true_pred(
        rating_true, rating_pred, col_user, col_item, col_prediction,
        relevancy_method, k, threshold,
    )
    if n_users == 0:
        return 0.0
    # keep only hits ranked within that user's own R
    hit_r = df_hit.merge(hc[[col_user, "actual"]], on=col_user)
    hit_r = hit_r[hit_r["rank"] <= hit_r["actual"]]
    counts = hit_r.groupby(col_user, as_index=False).size().rename(columns={"size": "hit"})
    merged = hc[[col_user, "actual"]].merge(counts, on=col_user, how="left").fillna({"hit": 0})
    return float((merged["hit"] / merged["actual"]).sum() / n_users)


def ndcg_at_k(
    rating_true,
    rating_pred,
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    col_rating=DEFAULT_RATING_COL,
    col_prediction=DEFAULT_PREDICTION_COL,
    relevancy_method="top_k",
    k=DEFAULT_K,
    threshold=DEFAULT_THRESHOLD,
    score_type="binary",
    discfun_type="loge",
    **_,
):
    """Normalised DCG@k, averaged over users.

    ``score_type='binary'`` gives every hit relevance 1 — the right choice when
    ground truth carries no graded relevance.
    """
    if score_type != "binary":
        raise NotImplementedError("only score_type='binary' is implemented")
    disc = (lambda r: np.log(r + 1)) if discfun_type == "loge" else (lambda r: np.log2(r + 1))

    df_hit, hc, n_users = _merge_ranking_true_pred(
        rating_true, rating_pred, col_user, col_item, col_prediction,
        relevancy_method, k, threshold,
    )
    if n_users == 0:
        return 0.0

    dcg = df_hit.assign(gain=1.0 / disc(df_hit["rank"]))
    dcg = dcg.groupby(col_user, as_index=False)["gain"].sum().rename(columns={"gain": "dcg"})

    ideal_len = np.minimum(hc["actual"].to_numpy(), k)
    idcg = np.array([np.sum(1.0 / disc(np.arange(1, n + 1))) for n in ideal_len])
    ideal = pd.DataFrame({col_user: hc[col_user].to_numpy(), "idcg": idcg})

    merged = ideal.merge(dcg, on=col_user, how="left").fillna({"dcg": 0.0})
    return float((merged["dcg"] / merged["idcg"]).sum() / n_users)


def map_at_k(
    rating_true,
    rating_pred,
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    col_prediction=DEFAULT_PREDICTION_COL,
    relevancy_method="top_k",
    k=DEFAULT_K,
    threshold=DEFAULT_THRESHOLD,
    **_,
):
    """Mean Average Precision@k (Spark MLlib convention: divide by min(R, k))."""
    df_hit, hc, n_users = _merge_ranking_true_pred(
        rating_true, rating_pred, col_user, col_item, col_prediction,
        relevancy_method, k, threshold,
    )
    if n_users == 0 or df_hit.empty:
        return 0.0

    df = df_hit.sort_values([col_user, "rank"]).copy()
    df["hit_order"] = df.groupby(col_user).cumcount() + 1
    df["prec"] = df["hit_order"] / df["rank"]
    sum_prec = df.groupby(col_user, as_index=False)["prec"].sum()

    merged = hc.merge(sum_prec, on=col_user, how="left").fillna({"prec": 0.0})
    denom = np.minimum(merged["actual"].to_numpy(), k)
    return float((merged["prec"].to_numpy() / denom).sum() / n_users)


# --------------------------------------------------------------------------
# recommenders.evaluation.python_evaluation — beyond-accuracy metrics
# --------------------------------------------------------------------------
def catalog_coverage(
    train_df, reco_df, col_user=DEFAULT_USER_COL, col_item=DEFAULT_ITEM_COL
):
    """Distinct items recommended / distinct items available."""
    n_train = train_df[col_item].nunique()
    if n_train == 0:
        return 0.0
    return float(reco_df[col_item].nunique() / n_train)


def distributional_coverage(
    train_df, reco_df, col_user=DEFAULT_USER_COL, col_item=DEFAULT_ITEM_COL
):
    """Shannon entropy of the recommendation frequency distribution."""
    counts = reco_df.groupby(col_item).size().to_numpy(dtype=float)
    if counts.size == 0:
        return 0.0
    p = counts / counts.sum()
    return float(-np.sum(p * np.log2(p)))


def historical_item_novelty(
    train_df,
    reco_df=None,
    col_user=DEFAULT_USER_COL,
    col_item=DEFAULT_ITEM_COL,
    col_weight=None,
):
    """Per-item novelty: ``-log2(item interactions / total interactions)``.

    ``col_weight`` is an extension over the upstream signature. With no
    interaction log, one row per item makes every item equally novel and the
    metric degenerates to ``log2(n_items)``. Passing a weight column (e.g. a
    popularity-derived pseudo-interaction count) restores a meaningful spread.
    """
    if col_weight is None:
        counts = (
            train_df.groupby(col_item, as_index=False).size().rename(columns={"size": "count"})
        )
    else:
        counts = (
            train_df.groupby(col_item, as_index=False)[col_weight]
            .sum()
            .rename(columns={col_weight: "count"})
        )
    total = counts["count"].sum()
    if total <= 0:
        counts["item_novelty"] = 0.0
    else:
        share = (counts["count"] / total).clip(lower=1e-12)
        counts["item_novelty"] = -np.log2(share)
    return counts[[col_item, "item_novelty"]].sort_values(col_item).reset_index(drop=True)


def novelty(train_df, reco_df, col_user=DEFAULT_USER_COL, col_item=DEFAULT_ITEM_COL,
            col_weight=None):
    """Mean novelty of the recommended items (Castells et al., ECIR 2011).

    Higher = more long-tail. A popularity baseline scores near the floor by
    construction, which makes this the check for "is my model just popularity
    wearing a hat?".
    """
    item_nov = historical_item_novelty(train_df, reco_df, col_user, col_item, col_weight)
    reco_counts = reco_df.groupby(col_item, as_index=False).size().rename(columns={"size": "count"})
    merged = reco_counts.merge(item_nov, on=col_item)
    if len(reco_df) == 0 or merged.empty:
        return 0.0
    return float((merged["count"] * merged["item_novelty"]).sum() / len(reco_df))


def intra_list_similarity(reco_df, feature_matrix, item_index,
                          col_user=DEFAULT_USER_COL, col_item=DEFAULT_ITEM_COL):
    """Mean pairwise cosine similarity within each recommendation list.

    Args:
        feature_matrix: L2-normalised (n_items x n_features) sparse/dense matrix.
        item_index: dict mapping item id -> row position in ``feature_matrix``.
    """
    sims = []
    for _, grp in reco_df.groupby(col_user):
        rows = [item_index[i] for i in grp[col_item] if i in item_index]
        if len(rows) < 2:
            continue
        sub = feature_matrix[rows]
        gram = (sub @ sub.T)
        gram = gram.toarray() if hasattr(gram, "toarray") else np.asarray(gram)
        n = gram.shape[0]
        off = (gram.sum() - np.trace(gram)) / (n * (n - 1))
        sims.append(off)
    return float(np.mean(sims)) if sims else 0.0


def diversity(reco_df, feature_matrix, item_index,
              col_user=DEFAULT_USER_COL, col_item=DEFAULT_ITEM_COL):
    """1 - mean intra-list similarity (Zhang et al., WSDM 2012)."""
    return 1.0 - intra_list_similarity(
        reco_df, feature_matrix, item_index, col_user=col_user, col_item=col_item
    )


def ranking_metrics_python(rating_true, rating_pred, k=DEFAULT_K, **col_dict):
    """The four headline ranking metrics, as a dict. Mirrors benchmark_utils."""
    cols = {**COL_DICT, **col_dict}
    cols.pop("col_rating", None)
    return {
        "MAP@k": map_at_k(rating_true, rating_pred, k=k, **cols),
        "nDCG@k": ndcg_at_k(rating_true, rating_pred, k=k, **cols),
        "Precision@k": precision_at_k(rating_true, rating_pred, k=k, **cols),
        "Recall@k": recall_at_k(rating_true, rating_pred, k=k, **cols),
    }
