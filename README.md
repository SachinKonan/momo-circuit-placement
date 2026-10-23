# MOMO macro placer: a post-deadline result for the Partcl/HRT Macro Placement Challenge 2026

MOMO's placer averages a proxy cost of **0.9131** on the 17 IBM benchmarks. The two winning entries,
re-run alongside it in the same setup, average **0.9520** (ArchGen) and **0.9513** (AbuPlace). Every
score comes from the challenge's own evaluator.

| Method | Mean IBM proxy cost (17 designs) | Leaderboard | Mean runtime / design |
|---|---|---|---|
| **MOMO, 3,000 s budget** (`momofill`) | **0.9131** | — | 2,966 s |
| MOMO, 300 s search (`momo300`) | 0.9297 | — | 370 s |
| ArchGen (1st place) | 0.9520 | 0.9507 | 2,422 s |
| AbuPlace / Carrotato (2nd place) | 0.9513 | 0.9522 | 719 s |

- **Per design:** MOMO beats the better of the two winners on 14 of 17 designs with the 3,000 s budget
  and on 13 of 17 with the 300 s search.
- **Repeats:** MOMO-300 ran 3 times per design and the others 2 times, with the same seeds each time,
  so the spread between repeats is runtime nondeterminism (at most 0.028).
- **Reproduction:** both winners land within 0.15% of their leaderboard scores.
- **Validity:** all 189 runs are valid by the leaderboard's criterion: zero overlaps, finite values,
  fixed macros unchanged. All finish under 1 hour.
- **Timing:** this work was done **after the May 21, 2026 deadline**, and we report it as a later
  research result, not a contest entry.

Per design ([`results/per_design.csv`](results/per_design.csv)):

| Design | MOMO 3,000 s | MOMO 300 s | ArchGen | AbuPlace |
|---|---|---|---|---|
| ibm01 | **0.7296** | 0.7417 | 0.7561 | 0.7597 |
| ibm02 | **0.8441** | 0.8755 | 0.9492 | 0.9454 |
| ibm03 | **0.8352** | 0.8450 | 0.8732 | 0.8564 |
| ibm04 | **0.8472** | 0.8609 | 0.8811 | 0.8868 |
| ibm06 | **0.9733** | 0.9879 | 1.0302 | 1.0149 |
| ibm07 | **0.9073** | 0.9125 | 0.9528 | 0.9472 |
| ibm08 | **0.9550** | 0.9712 | 1.0042 | 0.9904 |
| ibm09 | **0.7236** | 0.7338 | 0.7398 | 0.7529 |
| ibm10 | **0.8662** | 0.8947 | 0.8907 | 0.9580 |
| ibm11 | **0.7444** | 0.7592 | 0.7675 | 0.7717 |
| ibm12 | **1.0072** | 1.0237 | 1.0406 | 1.0595 |
| ibm13 | **0.7729** | 0.7920 | 0.8143 | 0.8845 |
| ibm14 | 1.0800 | 1.0996 | 1.0943 | **1.0784** |
| ibm15 | **0.9887** | 1.0033 | 1.0457 | 1.0168 |
| ibm16 | 0.9904 | 1.0051 | 0.9936 | **0.9860** |
| ibm17 | 1.1347 | 1.1578 | 1.1532 | **1.1129** |
| ibm18 | **1.1229** | 1.1414 | 1.1974 | 1.1509 |
| **Mean** | **0.9131** | 0.9297 | 0.9520 | 0.9513 |

## Check the placements without running anything

[`results/placements/`](results/placements) holds every placement from every run, for every method
(189 files, the `[num_macros, 2]` centers each placer returned).
[`results/verify.py`](results/verify.py) re-scores them with the challenge evaluator (pinned at
`996193c`). It checks legality the way the leaderboard did, and with the stricter
`validate_placement`, and compares each score with [`results/all_runs.csv`](results/all_runs.csv):

```sh
git clone --recursive https://github.com/SachinKonan/momo-circuit-placement && cd momo-circuit-placement
python results/verify.py --methods momofill        # any Python with torch and numpy
```

## MOMO's strategy

The placer ([`submissions/momo/placer.py`](submissions/momo/placer.py)) takes three steps within the
time budget:

1. **Starting layouts.** It runs upstream [Xplace](https://github.com/cuhk-eda/Xplace) global
   placement three times, at target densities 0.75, 0.90 and 0.60, and makes each result overlap-free
   with a simple greedy legalizer.
2. **Pick a start.** It runs 6 s of quick search from each layout and keeps the best.
3. **Search** ([`momo_search.py`](submissions/momo/momo_search.py), 250 lines, the program MOMO found).
   This is simulated annealing on the exact proxy cost:
   - **Moves.** Each step proposes 30 single-macro moves: a random nudge, a jump next to a macro on a
     shared net, a push away from its net's centre, or occasionally a random spot. Any move that would
     overlap a hard macro is dropped.
   - **Scoring.** All 30 are scored exactly and incrementally (about 1 ms each). The best is accepted
     if it improves the cost, or otherwise with a probability that shrinks over time.
   - **Objective schedule.** For the first 15% of the time it minimises the true proxy cost. From 15%
     to 60% it minimises a congestion-weighted version (0.1·wirelength + 0.1·density + 1.8·congestion).
     For the last 40% it returns to the true cost. It always keeps the best layout by true proxy cost.

Moves are scored by [`momo_proxy`](submissions/momo/momo_proxy), an incremental C version of the
official scorer. We wrote it only from the challenge's Python evaluator, not from any entry's code. It
matches the official scorer to about 1e-6.

How it differs from the winners: the search accepts some uphill moves (both winners accept only
improving moves) and spends the middle of its run on congestion. There is no design-specific tuning,
no fallback path and no GPU work beyond the one-minute Xplace step. We have not ablated which of these
choices explains the gain.

## How the program was found

`momo_search.py` was written by a language model, not by hand, using MOMO (Mixture of Model
Optimization). Each model is trained with reinforcement learning to improve programs it has already
written for this one problem. Programs are scored by the mean proxy cost over the 17 IBM designs, and
a program that makes any design invalid gets zero reward.

| Round | Models | Best mean proxy cost (training harness) |
|---|---|---|
| 1 | Qwen3.5-27B, Gemma-4-31B and Muse-Glimmer-30B, each trained alone (about 15 steps) | 0.9318 (Gemma) |
| 2 | Qwen3.5-27B, continuing from Gemma-4-31B's best programs (its state buffer), 10 steps | **0.9214**, this program |
| 3 | Further handoffs | No further gain |

The program shipped here is the best one from Round 2 (Gemma → Qwen), unchanged (sha256
`d4832342…`).

The training harness was not the contest setup:
- each design got 300 s of search on 4 CPU cores, with no GPU;
- the harness supplied the starting layouts, including the three Xplace global placements AbuPlace
  starts from, and an incremental evaluator.

For this submission we replaced the harness's pieces with our own:
- **Starts:** upstream Xplace, run as in step 1.
- **Evaluator:** `momo_proxy`.

Two ablations on the IBM designs back this up:
- **Starts:** AbuPlace's starting layouts versus our upstream Xplace layouts give 0.9177 versus 0.9187.
- **Evaluator:** our evaluator gives the same result as the harness's (0.9180).

## How we reproduced the comparison

All methods ran under one harness ([`eval/`](eval)) on Princeton's Della cluster:

- **Placement.** Each run calls the method's own `placer.py` from its own repository, the way the
  challenge's `evaluate.py` does: `submissions/final_placer.py` for ArchGen and `abuplace/placer.py`
  for AbuPlace.
- **Scoring.** We re-score what the placer returned, unchanged, with the pinned challenge evaluator.
- **Baselines.** ArchGen and AbuPlace are git submodules pinned to the exact commits we ran
  (`6b3661b` and `a24087c`). Each is set up as its README describes ([`setup/setup.sh`](setup/setup.sh)):
  - ArchGen's patched Xplace-RA is built per its Dockerfile.
  - AbuPlace runs on Python 3.12 with Torch 2.10.0+cu126 and the package versions in its `uv.lock`.
  - AbuPlace's Xplace extensions are built from source, because its prebuilt release asset returns 404.
  - Neither baseline's code is modified.
- **Budget.** Every time-filling method gets 3,000 s per design, under the 1-hour rule:
  - ArchGen: `EVO_TARGET_TOTAL_TIME_S=3000`, other settings from its README.
  - AbuPlace: its own wall guard (2,500 s by default).
  - MOMO's 3,000 s total includes reading the netlist, Xplace and legalization.
- **Hardware.**
  - Jobs ran on NVIDIA H100 nodes, 1 hour each, drawing tasks from a shared file queue.
  - Each task was pinned to its own 12-core slice with a 64 GB memory limit, a clean environment and
    a private home and temp directory.
  - GPU-bound placers (ArchGen, AbuPlace) had the GPU to themselves; MOMO, which is CPU-bound, could
    share one.
  - The judges used a 16-core AMD EPYC 9655P with 100 GB and an RTX 6000 Ada. Our 12-core slices
    likely disadvantage the CPU-bound MOMO, and the H100 likely favours the GPU-bound baselines.
- **Validity.** Each result records two checks:
  - the leaderboard's criterion: zero overlaps, finite, correct shape, fixed macros unchanged;
  - the stricter `validate_placement`, which also checks canvas bounds.

  Under the strict check, 26 of ArchGen's 42 runs exceed the canvas by one float32 ULP. They are valid
  under the leaderboard's criterion, which also reproduces its 0.9507.

To run everything:

```sh
git clone --recursive https://github.com/SachinKonan/momo-circuit-placement && cd momo-circuit-placement
setup/setup.sh                                 # envs and Xplace builds into $FAIR_EVAL_WORK (default ./work)
work/env/cuda/bin/python eval/make_eval_tasks.py   # 189 tasks: 21 designs x (3 + 2 + 2 + 2) runs
sbatch --export=ALL,REPO=$PWD --array=0-79%20 eval/pli_queue.sbatch   # Slurm settings are our cluster's
work/env/cuda/bin/python eval/aggregate.py     # coverage, validity, log checks, per-design comparison
```

### Run MOMO the way the judges run a submission

The [`Dockerfile`](Dockerfile) packages MOMO for the challenge's Docker evaluation. It uses the judges'
base image (PyTorch 2.5.1, CUDA 12.4, Python 3.11; the devel variant, to compile Xplace), builds
upstream Xplace for A100, RTX 6000 Ada and H100, and compiles `momo_proxy` at build time. At run time
it needs no network:

```sh
git clone --recursive https://github.com/SachinKonan/momo-circuit-placement && cd momo-circuit-placement
docker build -t momo-placer .
docker run --rm --network none --gpus all --cpus 16 --memory 64g momo-placer          # all 17 IBM designs
docker run --rm --network none --gpus all momo-placer submissions/momo/placer.py -b ibm01
```

The image runs MOMO with a 3,000 s budget per design (`MOMO_SEARCH_SECONDS=fill`,
`MOMO_TOTAL_SECONDS=3000`). Set `-e MOMO_SEARCH_SECONDS=300` for the 300 s search.

Without Docker, after `setup/setup.sh`:

```sh
cd external/macro-place-challenge-2026
MOMO_XPLACE_ROOT=../Xplace MOMO_SEARCH_SECONDS=fill MOMO_TOTAL_SECONDS=3000 \
  ../../work/env/cuda/bin/python -m macro_place.evaluate ../../submissions/momo/placer.py --all
```

## NG45 designs

Proxy cost on the four public NG45 designs (same harness, same runs):

| Method | ariane133 | ariane136 | mempool_tile | nvdla | Mean |
|---|---|---|---|---|---|
| MOMO, 3,000 s | **0.5889** | **0.5819** | 0.6849 | **0.7014** | **0.6393** |
| MOMO, 300 s | 0.5912 | 0.5860 | **0.6815** | 0.7165 | 0.6438 |
| ArchGen | 0.7278 | 0.7439 | 0.8132 | 0.7765 | 0.7654 |
| AbuPlace | 0.8249 | 0.8180 | 0.9495 | 0.7439 | 0.8341 |

On NG45, ArchGen's placer logs `PLC unavailable ... using fallback`: it looks up netlists only under
the IBM paths. We ran it as submitted.

## Layout

```
Dockerfile               MOMO image for the challenge's Docker evaluation
submissions/momo/        MOMO placer: placer.py, momo_search.py (found by MOMO), momo_proxy/ (C evaluator)
submissions/archgen/     ArchGen @ 6b3661b (git submodule, unmodified)
submissions/abuplace/    AbuPlace @ a24087c (git submodule, unmodified)
external/                challenge repo @ 996193c, Xplace @ 49cf66b (git submodules)
setup/                   setup.sh and the frozen package lists of the environments we ran
eval/                    evaluation harness: eval_one.py, queue, Slurm job, aggregate.py
results/                 all_runs.csv, per_design.csv, placements/, verify.py
```

## Licenses

MOMO's code here is released under Apache-2.0, matching the challenge repository. ArchGen, AbuPlace
and the challenge repository are Apache-2.0 and Xplace is BSD-3-Clause, under their own licenses as
submodules.
