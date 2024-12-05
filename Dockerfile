# syntax=docker/dockerfile:1
ARG UBUNTU_VERSION=22.04
ARG NVIDIA_CUDA_VERSION=11.8.0
# CUDA architectures, required by Colmap and tiny-cuda-nn. Use >= 8.0 for faster TCNN.
ARG CUDA_ARCHITECTURES="90;89;86;80;75;70;61"

# Pull source either provided or from git.
FROM scratch as source_copy

FROM nvidia/cuda:${NVIDIA_CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} as builder
ARG CUDA_ARCHITECTURES
ARG NVIDIA_CUDA_VERSION
ARG UBUNTU_VERSION

ENV DEBIAN_FRONTEND=noninteractive
ENV QT_XCB_GL_INTEGRATION=xcb_egl
RUN apt-get update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        git \
        cmake \
        ninja-build \
        build-essential \
        python3.10-dev \
        python3-pip

# Upgrade pip and install dependencies.
# pip install torch==2.2.2 torchvision==0.17.2 --index-url https://download.pytorch.org/whl/cu118 && \
RUN pip install --no-cache-dir --upgrade pip 'setuptools<70.0.0' && \
    pip install --no-cache-dir torch==2.0.1+cu118 torchvision==0.15.2+cu118 'numpy<2.0.0' --extra-index-url https://download.pytorch.org/whl/cu118 && \
    pip install fvcore iopath plotly rich plyfile==0.8.1 jupyterlab nodejs ipywidgets open3d && \
    pip install --upgrade PyMCubes
    
RUN export TORCH_CUDA_ARCH_LIST="$(echo "$CUDA_ARCHITECTURES" | tr ';' '\n' | awk '$0 > 70 {print substr($0,1,1)"."substr($0,2)}' | tr '\n' ' ' | sed 's/ $//')" && \
    export FORCE_CUDA=1 && \
    pip install --no-cache-dir "git+https://github.com/facebookresearch/pytorch3d.git@297020a4b1d7492190cb4a909cafbd2c81a12cb5"

RUN export TORCH_CUDA_ARCH_LIST="$(echo "$CUDA_ARCHITECTURES" | tr ';' '\n' | awk '$0 > 70 {print substr($0,1,1)"."substr($0,2)}' | tr '\n' ' ' | sed 's/ $//')" && \
    pip install --no-cache-dir "git+https://github.com/facebookresearch/pytorch3d.git@297020a4b1d7492190cb4a909cafbd2c81a12cb5" && \
    git clone https://github.com/Anttwo/SuGaR.git && \
    cd SuGaR/gaussian_splatting/submodules/diff-gaussian-rasterization/ && \
    pip install . && \
    cd ../simple-knn/ && \
    pip install . && \
    cd ../../../ && \
    git clone https://github.com/NVlabs/nvdiffrast && \
    cd nvdiffrast && \
    pip install . && \
    cd ../
        
# Fix permissions
RUN chmod -R go=u /usr/local/lib/python3.10

#
# Docker runtime stage.
#
FROM nvidia/cuda:${NVIDIA_CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION} as runtime
ARG CUDA_ARCHITECTURES
ARG NVIDIA_CUDA_VERSION
ARG UBUNTU_VERSION

LABEL org.opencontainers.image.licenses = "Apache License 2.0"
LABEL org.opencontainers.image.base.name="docker.io/library/nvidia/cuda:${NVIDIA_CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}"

# Minimal dependencies to run COLMAP binary compiled in the builder stage.
# Note: this reduces the size of the final image considerably, since all the
# build dependencies are not needed.
RUN apt-get update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        python3.10 \
        python3.10-dev \
        build-essential \
        python-is-python3 \
        ffmpeg

# Copy packages from builder stage.
COPY --from=builder /usr/local/lib/python3.10/dist-packages/ /usr/local/lib/python3.10/dist-packages/

# Bash as default entrypoint.
CMD /bin/bash -l
