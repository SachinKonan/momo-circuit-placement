# MOMO placer image for the challenge's Docker evaluation (built with network, run with --network none).
# Same base as the judges' standard image (PyTorch 2.5.1, CUDA 12.4, Python 3.11), devel variant to build
# upstream Xplace (external/Xplace, 49cf66b) for RTX 6000 Ada (sm_89) as well as A100/H100.
#
#   git clone --recursive <this repo> && cd momo-circuit-placement
#   docker build -t momo-placer .
#   docker run --rm --network none --gpus all --cpus 16 --memory 64g momo-placer            # all 17 IBM designs
#   docker run --rm --network none --gpus all momo-placer submissions/momo/placer.py -b ibm01
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel

ENV DEBIAN_FRONTEND=noninteractive PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bison flex libboost-all-dev libcairo2-dev libfl-dev ninja-build pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Xplace's Python dependencies, at the versions of the environment we evaluated in
# (setup/cuda-env-requirements.txt); torchvision comes with the base image.
RUN pip install --no-cache-dir numpy==2.2.6 scipy==1.17.1 tqdm==4.70.1 absl-py==2.5.1 matplotlib==3.11.2 \
        pandas==3.0.6 numba==0.68.0 cairocffi==1.7.1 cmake==3.31.6 ninja==1.13.2 pybind11==3.1.0 protobuf==7.36.2 \
        opencv-python-headless==5.0.0.93 seaborn==0.13.2 igraph==1.0.0 pulp==3.3.2 \
    && python -c "import cv2, seaborn, igraph, pulp, torchvision, cairocffi, numba, pandas"

# Challenge evaluator (996193c) with the benchmark data the evaluation loads.
WORKDIR /challenge
COPY external/macro-place-challenge-2026/macro_place/ /challenge/macro_place/
COPY external/macro-place-challenge-2026/pyproject.toml external/macro-place-challenge-2026/requirements.txt external/macro-place-challenge-2026/README.md external/macro-place-challenge-2026/LICENSE.md /challenge/
COPY external/macro-place-challenge-2026/external/MacroPlacement/Testcases/ICCAD04/ /challenge/external/MacroPlacement/Testcases/ICCAD04/
COPY external/macro-place-challenge-2026/external/MacroPlacement/CodeElements/Plc_client/ /challenge/external/MacroPlacement/CodeElements/Plc_client/
COPY external/macro-place-challenge-2026/external/MacroPlacement/Flows/NanGate45/ariane133/netlist/output_CT_Grouping/ /challenge/external/MacroPlacement/Flows/NanGate45/ariane133/netlist/output_CT_Grouping/
COPY external/macro-place-challenge-2026/external/MacroPlacement/Flows/NanGate45/ariane136/netlist/output_CT_Grouping/ /challenge/external/MacroPlacement/Flows/NanGate45/ariane136/netlist/output_CT_Grouping/
COPY external/macro-place-challenge-2026/external/MacroPlacement/Flows/NanGate45/mempool_tile/netlist/output_CT_Grouping/ /challenge/external/MacroPlacement/Flows/NanGate45/mempool_tile/netlist/output_CT_Grouping/
COPY external/macro-place-challenge-2026/external/MacroPlacement/Flows/NanGate45/nvdla/netlist/output_CT_Grouping/ /challenge/external/MacroPlacement/Flows/NanGate45/nvdla/netlist/output_CT_Grouping/
RUN pip install --no-cache-dir --no-deps -e .

# Upstream Xplace. Its CMake requires torch.cuda.is_available(), which is false during `docker build`
# (no GPU); like ArchGen's Dockerfile we check for a CUDA build of Torch instead. Code is unchanged.
COPY external/Xplace/ /opt/Xplace/
RUN cd /opt/Xplace && rm -rf build cpp_to_py/cpybin/*.so \
    && python -c "from pathlib import Path; p=Path('CMakeLists.txt'); s=p.read_text(); p.write_text(s.replace('print(int(torch.cuda.is_available()))', 'print(int(torch.version.cuda is not None))'))" \
    && cmake -S . -B build -G Ninja "-DCMAKE_CUDA_ARCHITECTURES=80;89;90" -DPYTHON_EXECUTABLE="$(which python)" \
    && cmake --build build --parallel 8 && cmake --install build && rm -rf build
RUN cd /opt/Xplace && python -c "import torch; from cpp_to_py.cpybin import dct_cuda, io_parser, gpudp; print('Xplace extensions OK')"

# MOMO: placer, the search program MOMO found, and its C evaluator (compiled here, not at run time).
COPY submissions/momo/ /challenge/submissions/momo/
RUN python /challenge/submissions/momo/momo_proxy/build.py \
    && python -c "import sys; sys.path.insert(0, '/challenge/submissions/momo'); import momo_proxy"

# Files are copied with the build host's permissions; make them readable for any run-time user.
RUN chmod -R a+rX /opt/Xplace /challenge

# Thread count for Xplace (the placer otherwise uses os.cpu_count(), the host's cores): the judges' 16.
ENV MOMO_XPLACE_ROOT=/opt/Xplace MOMO_SEARCH_SECONDS=fill MOMO_TOTAL_SECONDS=3000 OMP_NUM_THREADS=16

ENTRYPOINT ["python", "-m", "macro_place.evaluate"]
CMD ["submissions/momo/placer.py", "--all"]
