# 归档说明（2026-09）：Linux/amd64 conda-build 容器（配合 scripts/build_conda.sh 或直接
# docker build 本目录），用于把 modules/<sw>/native/conda-recipe/<platform> 构建产物
# 输出到挂载的 /build/dist（本地 channel，可 conda index 后 anaconda upload 发布）。
# 从 modules/docker-conda-builder 归位至此。
FROM --platform=linux/amd64 docker.1ms.run/continuumio/miniconda3:latest

# Configure Tsinghua mirror for faster downloads
RUN conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/ && \
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/ && \
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/ && \
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/bioconda/ && \
    conda config --set show_channel_urls yes

# Install conda-build and conda-verify
# Downgrade python to <3.13 to satisfy conda-verify requirements
RUN conda install -y "python<3.13" conda-build conda-verify anaconda-client && \
    conda clean -afy

# Set the working directory
WORKDIR /build

# Entrypoint script to handle build arguments
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
