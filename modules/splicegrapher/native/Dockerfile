# splicegrapher native Docker 镜像配方（自建兜底：apt 最小化 + 官方 SourceForge 源码 setup.py install，禁 miniconda）
#
# 背景：SpliceGrapher（可变剪接分析，splicegrapher.sourceforge.net）无官方镜像/conda 包 ——
#       bioconda（api.anaconda.org/package/bioconda/splicegrapher 404）、quay.io/biocontainers
#       （quay API 401 = 仓库不存在；对照 samtools 200）、depot.galaxyproject.org（无）2026-09 核实全无；
#       nf-core/snakemake-wrappers/brew 亦无（404）。官方发布站为 SourceForge splicegrapher，
#       最新 SpliceGrapher-0.2.7.tgz（仅源码包；安装 = python setup.py build && install）。
# ⚠️ Python 版本：SpliceGrapher 0.2.7 是 Python 2.7 时代代码（setup.py 使用 py2 print 语法，
#     依赖 PyML）。Debian bookworm 已移除 python2，故本配方基础镜像取
#     debian:bullseye-slim（Debian 11，最后一个提供 python2.7 的稳定版）。
# ⚠️ 依赖兼容性（未实际构建验证）：PyML 0.7.14 / 旧 pysam 在 py2.7 下安装可能需要额外
#     系统库（zlib/bzip2/lzma/curl dev）；本配方按常见最小集安装，若遇报错请以源码/官方
#     userguide（http://splicegrapher.sourceforge.net/userguide.html）为准调整。
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/splicegrapher:0.2.7 -f modules/splicegrapher/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 python3 驱动；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       -e SG_FASTA_REF=/data/genome.fasta -e SG_GENE_MODEL=/data/genome.gff3 \
#       bioskills/splicegrapher:0.2.7 predict_graphs /data/filtered.sam -v

ARG SPLICEGRAPHER_VERSION=0.2.7
# 官方源码归档（SourceForge；直链 downloads.sourceforge.net 会自动重定向到镜像）
ARG SPLICEGRAPHER_TARBALL=SpliceGrapher-0.2.7.tgz
# 基础镜像可用 --build-arg BASE_IMAGE=<国内加速 registry>/library/debian:bullseye-slim 覆盖
ARG BASE_IMAGE=debian:bullseye-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="splicegrapher"
LABEL version="${SPLICEGRAPHER_VERSION}"
LABEL splicegrapher_version="${SPLICEGRAPHER_VERSION}"
LABEL org.bioskills.software="splicegrapher"
LABEL impl="native"
LABEL base_image="debian:bullseye-slim"
LABEL pkg_route="apt runtime + python2.7 + SourceForge source (setup.py build/install)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：python2.7（SpliceGrapher 本体）+ python3/python3-yaml（/opt/skill/main.py 驱动）
#    + 构建/运行依赖（build-essential、zlib/bz2/lzma/curl dev 供 PyML/pysam）+ samtools/hisat2（流程依赖）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python2.7 \
        python2.7-dev \
        python3 \
        python3-yaml \
        build-essential \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libcurl4-openssl-dev \
        samtools \
        hisat2 \
        ca-certificates \
        curl \
        procps \
        tini \
    ; \
    ln -sf /usr/bin/python2.7 /usr/local/bin/python; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源码下载 + python2 setup.py build && install + 版本断言（import SpliceGrapher.__version__）
RUN set -eux; \
    curl -fSL -o /tmp/sg.tgz \
        "https://downloads.sourceforge.net/project/splicegrapher/SpliceGrapher-0.2.7.tgz"; \
    mkdir -p /tmp/src && tar -xzf /tmp/sg.tgz -C /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d | head -1)"; \
    cd "$SRC"; \
    curl -fSL -o /tmp/get-pip27.py "https://bootstrap.pypa.io/pip/2.7/get-pip.py"; \
    python2 /tmp/get-pip27.py; \
    python2 -m pip install --no-cache-dir setuptools numpy PyML matplotlib pysam; \
    python2 setup.py build; \
    python2 setup.py install; \
    python2 -c "import SpliceGrapher, sys; sys.exit(0 if SpliceGrapher.__version__=='0.2.7' else 1)"; \
    rm -rf /tmp/src /tmp/sg.tgz /tmp/get-pip27.py

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY splicegrapher/native/main.py /opt/skill/main.py
COPY splicegrapher/meta.yaml /opt/skill/splicegrapher/meta.yaml
COPY splicegrapher/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/sg_commands.txt \
    && grep -q '^build_classifiers' /tmp/sg_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/sg_schema.json \
    && test -s /tmp/sg_schema.json \
    && rm -f /tmp/sg_commands.txt /tmp/sg_schema.json

# 4) 清理四连（构建期下载工具 curl 移除；python2.7/构建库保留以便容器内排查）
RUN set -eux; \
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf \
        /usr/share/doc/* \
        /usr/share/man/* \
        /usr/share/info/* \
        /usr/share/locale/* \
        /var/cache/debconf/* \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/*

ENV PYTHONPATH=/opt/skill \
    PATH=/usr/local/bin:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体为 python3 驱动的 main.py
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/bin/python3", "/opt/skill/main.py"]
