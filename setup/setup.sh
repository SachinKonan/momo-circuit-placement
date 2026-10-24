#!/bin/bash
# Build everything the evaluation needs, as we ran it (Princeton Della: CUDA 12.6, Boost 1.85, uv).
# Products go to $FAIR_EVAL_WORK (default: <repo>/work). GPU builds target A100 and H100 (sm_80, sm_90).
#
#   1. CUDA env (Python 3.11.13, Torch 2.5.1+cu124, the judges' standard image versions) with the
#      challenge package, and upstream Xplace (external/Xplace, 49cf66b) built for MOMO in
#      $FAIR_EVAL_WORK/Xplace-momo. Every Xplace copy gets the build-time CMake edit ArchGen's and our
#      Dockerfile use (check for a CUDA build of Torch, not a visible GPU), so a GPU-free node can build.
#   2. ArchGen's Xplace-RA: upstream Xplace + submissions/archgen/support/xplace_patches + its CMake
#      torch-CUDA check fix (ArchGen's Dockerfile recipe).
#   3. AbuPlace: Python 3.12 venv with the exact packages we ran (Torch 2.10.0+cu126, pulp 3.3.1 as in
#      its uv.lock), and upstream Xplace's extensions built against that Torch with the C++11 ABI and
#      copied into abuplace/Xplace/cpp_to_py/cpybin (its README fallback; the prebuilt asset 404s).
#   Packages are installed --no-deps from the frozen lists of the environments we ran.
#   4. MOMO's evaluator library (submissions/momo/momo_proxy/libmomoproxy.so).
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${FAIR_EVAL_WORK:-$REPO/work}
UV=${UV:-uv}
ARCHS=${CUDA_ARCHS:-80;90}
mkdir -p "$WORK"
module load cudatoolkit/12.6 boost/1.85.0 2>/dev/null || true
export CUDA_HOME=${CUDA_HOME:-/usr/local/cuda-12.6}
git -C "$REPO" submodule update --init --recursive

xplace_copy() {  # dest: a fresh copy of external/Xplace with the GPU-free CMake check
  rm -rf "$1" && cp -a "$REPO/external/Xplace" "$1" && rm -rf "$1/build" "$1/cpp_to_py/cpybin/"*.so
  sed -i 's/print(int(torch.cuda.is_available()))/print(int(torch.version.cuda is not None))/' "$1/CMakeLists.txt"
}
xplace_build() {  # src_tree python build_dir extra_cmake_args...
  local tree=$1 py=$2 bdir=$3; shift 3
  ( cd "$tree" && rm -rf "$bdir" && rm -f cpp_to_py/cpybin/*.so
    export PATH=$(dirname "$py"):$CUDA_HOME/bin:$PATH
    cmake -S . -B "$bdir" -G Ninja "-DCMAKE_CUDA_ARCHITECTURES=$ARCHS" -DPYTHON_EXECUTABLE="$py" "$@"
    cmake --build "$bdir" --parallel 16 && cmake --install "$bdir" )
}

# 1. CUDA env + upstream Xplace for MOMO
PY=$WORK/env/cuda/bin/python
[ -x "$PY" ] || $UV --no-config venv -q --python 3.11.13 "$WORK/env/cuda"
$UV --no-config pip install -q --python "$PY" --index-strategy unsafe-best-match \
    --extra-index-url https://download.pytorch.org/whl/cu124 --no-deps -r "$REPO/setup/cuda-env-requirements.txt"
$UV --no-config pip install -q --python "$PY" --no-deps -e "$REPO/external/macro-place-challenge-2026"
xplace_copy "$WORK/Xplace-momo"
xplace_build "$WORK/Xplace-momo" "$PY" build

# 2. ArchGen's Xplace-RA
xplace_copy "$WORK/Xplace-archgen"
cp -r "$REPO/submissions/archgen/support/xplace_patches/." "$WORK/Xplace-archgen/"
xplace_build "$WORK/Xplace-archgen" "$PY" build

# 3. AbuPlace
A=$REPO/submissions/abuplace
[ -x "$A/.venv/bin/python" ] || $UV venv -q --python 3.12.12 "$A/.venv"
$UV pip install -q --python "$A/.venv/bin/python" --index-strategy unsafe-best-match \
    --extra-index-url https://download.pytorch.org/whl/cu126 --no-deps -r "$REPO/setup/abuplace-requirements.txt"
$UV pip install -q --python "$A/.venv/bin/python" --no-deps -e "$A"
xplace_copy "$WORK/Xplace-abu"
xplace_build "$WORK/Xplace-abu" "$A/.venv/bin/python" build -DCMAKE_CXX_ABI=1
rm -f "$A/abuplace/Xplace/cpp_to_py/cpybin/"*.so && cp -a "$WORK/Xplace-abu/cpp_to_py/cpybin/." "$A/abuplace/Xplace/cpp_to_py/cpybin/"
( cd "$A" && PYTHONPATH=$A/abuplace/Xplace .venv/bin/python -c "import torch; from cpp_to_py.cpybin import dct_cuda, io_parser, gpudp" )

# 4. MOMO's evaluator
"$PY" "$REPO/submissions/momo/momo_proxy/build.py"
echo SETUP_OK
