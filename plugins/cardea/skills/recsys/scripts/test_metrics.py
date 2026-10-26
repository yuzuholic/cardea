"""Validate metrics.py against hand-computed values.

Every expectation below is derived by hand in the comments, not from a previous
run of this code — that is the point. If you change a metric definition, this is
what tells you whether you changed it correctly.

    python test_metrics.py
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from metrics import (  # noqa: E402
    precision_at_k, recall_at_k, ndcg_at_k, map_at_k, r_precision_at_k,
    catalog_coverage, distributional_coverage, novelty,
    python_stratified_split, python_chrono_split, python_random_split,
    get_top_k_items,
)

# user 1: relevant = {A, B, C}; recommended (in order) = A, X, B, Y, Z
# user 2: relevant = {D};       recommended (in order) = W, D, V, U, T
truth = pd.DataFrame({
    "userID": [1, 1, 1, 2],
    "itemID": ["A", "B", "C", "D"],
    "rating": [1.0, 1.0, 1.0, 1.0],
})
pred = pd.DataFrame({
    "userID": [1] * 5 + [2] * 5,
    "itemID": ["A", "X", "B", "Y", "Z", "W", "D", "V", "U", "T"],
    "prediction": [5, 4, 3, 2, 1, 5, 4, 3, 2, 1],
})
K = 5

# --- hand-computed expectations -------------------------------------------
# precision@5: u1 hits=2 -> 2/5 ; u2 hits=1 -> 1/5 ; mean = 0.3
exp_prec = (2 / 5 + 1 / 5) / 2
# recall@5:   u1 2/3 ; u2 1/1 ; mean
exp_rec = (2 / 3 + 1 / 1) / 2
# nDCG@5 (binary, loge, disc = 1/ln(rank+1)):
#   u1 hits at ranks 1,3 -> dcg = 1/ln2 + 1/ln4 ; ideal 3 hits (min(3,5)) at 1,2,3
u1_dcg = 1 / np.log(2) + 1 / np.log(4)
u1_idcg = 1 / np.log(2) + 1 / np.log(3) + 1 / np.log(4)
#   u2 hit at rank 2 -> dcg = 1/ln3 ; ideal 1 hit at rank 1
u2_dcg = 1 / np.log(3)
u2_idcg = 1 / np.log(2)
exp_ndcg = (u1_dcg / u1_idcg + u2_dcg / u2_idcg) / 2
# MAP@5 (Spark: divide by min(R, k)):
#   u1: hit1 at rank1 -> 1/1 ; hit2 at rank3 -> 2/3 ; sum=1.6667 / min(3,5)=3
#   u2: hit1 at rank2 -> 1/2 ; sum=0.5 / min(1,5)=1
exp_map = ((1 / 1 + 2 / 3) / 3 + (1 / 2) / 1) / 2
# R-precision: u1 R=3, hits within top-3 = A(1), B(3) -> 2/3 ; u2 R=1, top-1=W -> 0
exp_rprec = (2 / 3 + 0 / 1) / 2

checks = [
    ("precision@k", precision_at_k(truth, pred, k=K), exp_prec),
    ("recall@k", recall_at_k(truth, pred, k=K), exp_rec),
    ("ndcg@k", ndcg_at_k(truth, pred, k=K), exp_ndcg),
    ("map@k", map_at_k(truth, pred, k=K), exp_map),
    ("r_precision@k", r_precision_at_k(truth, pred, k=K), exp_rprec),
]

ok = True
for name, got, want in checks:
    good = abs(got - want) < 1e-9
    ok &= good
    print(f"{'PASS' if good else 'FAIL'}  {name:16s} got={got:.10f} want={want:.10f}")

# --- coverage / novelty ----------------------------------------------------
train_ref = pd.DataFrame({"userID": 0, "itemID": list("ABCDVWXYZTU")})
cov = catalog_coverage(train_ref, pred)
print(f"{'PASS' if abs(cov - 10/11) < 1e-9 else 'FAIL'}  catalog_coverage got={cov:.6f} want={10/11:.6f}")

# 10 distinct items each recommended once -> entropy = log2(10)
dc = distributional_coverage(train_ref, pred)
print(f"{'PASS' if abs(dc - np.log2(10)) < 1e-9 else 'FAIL'}  dist_coverage    got={dc:.6f} want={np.log2(10):.6f}")

# uniform reference -> every item novelty = log2(11); mean over 10 recs
nv = novelty(train_ref, pred)
print(f"{'PASS' if abs(nv - np.log2(11)) < 1e-9 else 'FAIL'}  novelty          got={nv:.6f} want={np.log2(11):.6f}")

# weighted novelty: item A carries 100x the weight -> A itself is far LESS
# novel, while every other (now comparatively rare) item becomes MORE novel.
from metrics import historical_item_novelty  # noqa: E402
w = train_ref.assign(weight=[100.0] + [1.0] * 10)
per_item = historical_item_novelty(w, col_weight="weight").set_index("itemID")["item_novelty"]
a_nov, b_nov = per_item["A"], per_item["B"]
exp_a, exp_b = -np.log2(100 / 110), -np.log2(1 / 110)
good = abs(a_nov - exp_a) < 1e-9 and abs(b_nov - exp_b) < 1e-9 and a_nov < b_nov
print(f"{'PASS' if good else 'FAIL'}  weighted novelty A={a_nov:.6f} (want {exp_a:.6f}) "
      f"B={b_nov:.6f} (want {exp_b:.6f})")

# --- edge cases ------------------------------------------------------------
empty_pred = pred.iloc[0:0]
for fn in (precision_at_k, recall_at_k, ndcg_at_k, map_at_k):
    v = fn(truth, empty_pred, k=K)
    print(f"{'PASS' if v == 0.0 else 'FAIL'}  {fn.__name__} on empty preds -> {v}")

# no overlapping users
other = pred.assign(userID=99)
v = ndcg_at_k(truth, other, k=K)
print(f"{'PASS' if v == 0.0 else 'FAIL'}  ndcg with disjoint users -> {v}")

# perfect prediction -> all metrics 1.0 where defined
perfect = truth.rename(columns={"rating": "prediction"})
print("perfect:", {n: round(f(truth, perfect, k=K), 6) for n, f in
                   [("prec", precision_at_k), ("rec", recall_at_k),
                    ("ndcg", ndcg_at_k), ("map", map_at_k)]})

# --- splitters -------------------------------------------------------------
rng = np.random.default_rng(0)
df = pd.DataFrame({
    "userID": np.repeat(np.arange(50), 20),
    "itemID": rng.integers(0, 200, 1000),
    "rating": 1.0,
    "timestamp": rng.integers(0, 10_000, 1000),
})
tr, te = python_stratified_split(df, ratio=0.75, seed=42)
print(f"stratified: train={len(tr)} test={len(te)} total={len(tr)+len(te)} "
      f"users_in_both={len(set(tr.userID) & set(te.userID))}/50")
assert len(tr) + len(te) == len(df)
assert len(set(tr.userID) & set(te.userID)) == 50

tr, te = python_chrono_split(df, ratio=0.75)
overlap = tr.groupby("userID").timestamp.max() <= te.groupby("userID").timestamp.min()
print(f"chrono: train={len(tr)} test={len(te)} chronologically_ordered={overlap.all()}")
assert overlap.all()

a, b, c = python_random_split(df, ratio=[0.6, 0.2, 0.2], seed=42)
print(f"3-way random: {len(a)}/{len(b)}/{len(c)} sum={len(a)+len(b)+len(c)}")
assert len(a) + len(b) + len(c) == len(df)

topk = get_top_k_items(pred, col_rating="prediction", k=3)
print(f"get_top_k_items: {len(topk)} rows, ranks {sorted(topk['rank'].unique())}")
assert len(topk) == 6 and list(topk["rank"].unique()) == [1, 2, 3]

print("\nALL METRIC CHECKS PASSED" if ok else "\nSOME CHECKS FAILED")
