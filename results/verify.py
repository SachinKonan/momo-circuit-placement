"""Re-score saved placements with the official challenge evaluator, without running any placer.

For every results/placements/<method>/<repeat>/<design>.npy, loads the design with the challenge's
loader (external/macro-place-challenge-2026 at 996193c), computes the proxy cost with
macro_place.objective.compute_proxy_cost, and checks legality the way the leaderboard did
(overlap_count == 0, finite, right shape, fixed macros unchanged) and with the stricter
macro_place.utils.validate_placement (also canvas bounds). Prints per-method means and compares every
score with results/all_runs.csv.

Usage (from the repo root, with any Python that has torch and numpy):
  python results/verify.py [--methods momofill,momo300,archgen,abuplace] [--designs ibm01,...]
"""
import argparse
import collections
import csv
from pathlib import Path
import statistics as st
import sys

import numpy as np
import torch

REPO = Path(__file__).resolve().parents[1]
CHALLENGE = REPO / 'external/macro-place-challenge-2026'
sys.path.insert(0, str(CHALLENGE))
from macro_place.loader import load_benchmark, load_benchmark_from_dir  # noqa: E402
from macro_place.objective import compute_proxy_cost  # noqa: E402
from macro_place.utils import validate_placement  # noqa: E402

NG45 = {'ariane133', 'ariane136', 'mempool_tile', 'nvdla'}


def load(design):
    if design in NG45:
        d = CHALLENGE / 'external/MacroPlacement/Flows/NanGate45' / design / 'netlist/output_CT_Grouping'
        return load_benchmark(str(d / 'netlist.pb.txt'), str(d / 'initial.plc'), name=design)
    return load_benchmark_from_dir(str(CHALLENGE / 'external/MacroPlacement/Testcases/ICCAD04' / design))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--methods')
    ap.add_argument('--designs')
    a = ap.parse_args()
    recorded = {(r['method'], r['repeat'], r['design']): float(r['proxy'])
                for r in csv.DictReader(open(REPO / 'results/all_runs.csv'))}
    files = sorted((REPO / 'results/placements').glob('*/*/*.npy'))
    if a.methods:
        files = [f for f in files if f.parts[-3] in a.methods.split(',')]
    if a.designs:
        files = [f for f in files if f.stem in a.designs.split(',')]
    files.sort(key=lambda f: f.stem)   # one design loaded at a time
    loaded, scores, bad = (None, None), collections.defaultdict(lambda: collections.defaultdict(list)), 0
    for f in files:
        method, repeat, design = f.parts[-3], f.parts[-2], f.stem
        if loaded[0] != design:
            loaded = (design, load(design))
        b, plc = loaded[1]
        pos = np.load(f)
        t = torch.from_numpy(pos)
        fixed = b.macro_fixed
        fixed_ok = bool(not fixed.any() or torch.allclose(b.macro_positions[fixed].to(t.dtype), t[fixed], atol=1e-3))
        m = compute_proxy_cost(t, b, plc)
        valid = (pos.shape == tuple(b.macro_positions.shape) and bool(np.isfinite(pos).all()) and fixed_ok
                 and int(m['overlap_count']) == 0)
        strict, _ = validate_placement(t, b)
        proxy = float(m['proxy_cost'])
        same = abs(proxy - recorded[(method, repeat, design)]) < 1e-6
        bad += (not valid) or (not same)
        print(f'{method:9s} {repeat} {design:13s} proxy {proxy:.6f} overlaps {int(m["overlap_count"])} '
              f'valid {valid} strict {strict} matches_record {same}')
        scores[method][design].append(proxy)
    print()
    for method, per in scores.items():
        ibm = [st.mean(v) for d, v in per.items() if d not in NG45]
        ng = [st.mean(v) for d, v in per.items() if d in NG45]
        print(f'{method:9s} IBM mean {st.mean(ibm):.4f} over {len(ibm)} designs'
              + (f'; NG45 mean {st.mean(ng):.4f} over {len(ng)}' if ng else ''))
    print('all valid and matching the record' if not bad else f'{bad} placements invalid or not matching')


if __name__ == '__main__':
    main()
