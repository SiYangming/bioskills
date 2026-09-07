# 使用Miniconda作为基础镜像，以最小化大小并轻松管理生物信息学依赖
# 自定义版本: 2.1 (添加了shebang和执行权限修复)
FROM continuumio/miniconda3:latest

LABEL version="2.1"

# 更新系统并安装必要的工具（使用Conda以避免编译问题）
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 创建Conda环境并安装依赖（使用bioconda通道）
RUN conda config --add channels defaults \
    && conda config --add channels bioconda \
    && conda config --add channels conda-forge \
    && conda install -y \
    perl \
    bowtie2 \
    tophat \
    r-base \
    r-e1071 \
    samtools \
    bedtools \
    && conda clean --all -y  # 清理缓存以最小化镜像大小

# 克隆RibORF仓库，添加shebang和执行权限，然后设置路径
RUN git clone https://github.com/zhejilab/RibORF.git /opt/riborf \
    && cd /opt/riborf/RibORF.2.0 \
    && for file in *.pl; do sed -i '1i#!/usr/bin/env perl' "$file"; done \
    && chmod +x *.pl

ENV PATH="/opt/riborf/RibORF.2.0:$PATH"

# 设置工作目录和默认命令（可选，用于交互式运行）
WORKDIR /data
CMD ["bash"]