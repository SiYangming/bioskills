# platanus-allee native Docker 镜像配方（自建兜底：apt 最小化 + 官方 v2.4.0 源码 make，禁 miniconda）
#
# 背景：Platanus-allee（二倍体单倍型组装器，Nat Commun 2019）无官方镜像/conda 包 —— 2026-09
#       逐渠道核实：bioconda platanus / platanus-allee 均 404、quay.io/biocontainers/platanus-allee
#       401（= 仓库不存在，对照 dbg2olc 200）、depot.galaxyproject.org singularity platanus-allee
#       404；nf-core / snakemake-wrappers 均 404；homebrew-core / brewsci-bio 均无公式。
#       官方同时提供「预编译二进制包」（官方站点 v2.2.2 / v2.0.2 Linux x86_64）与「源码编译」
#       （GitHub tag v2.4.0）；本容器走后者（可复现、可控），源码 common.cpp：
#       platanus::ConstParam::VERSION = "2.4.0"；main.cpp 启动即打印 "platanus_allee version: 2.4.0"。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/platanus-allee:2.4.0 -f modules/platanus-allee/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 native/main.py 驱动；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/platanus-allee:2.4.0 assemble -t 8 -f /data/illumina.1.fastq /data/illumina.2.fastq
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/platanus-allee:2.4.0 phase -t 8 -c /data/out_contig.fa /data/out_junctionKmer.fa \
#       -IP1 /data/illumina.1.fastq /data/illumina.2.fastq -p /data/subreads.fasta

ARG PLATANUS_VERSION=2.4.0
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="platanus-allee"
LABEL version="${PLATANUS_VERSION}"
LABEL platanus_allee_version="${PLATANUS_VERSION}"
LABEL org.bioskills.software="platanus-allee"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt build deps + GitHub source (make)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：构建（build-essential）+ 运行（python3/python3-yaml 供 /opt/skill/main.py 驱动）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        g++ \
        make \
        ca-certificates \
        curl \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源码归档下载 + make + 部署 + 版本断言（platanus_allee -v -> "platanus_allee version: 2.4.0"）
RUN set -eux; \
    curl -fSL -o /tmp/platanus-allee.tar.gz \
        "https://github.com/rkajitani/Platanus-allee/archive/refs/tags/v${PLATANUS_VERSION}.tar.gz"; \
    mkdir -p /tmp/src && tar -xzf /tmp/platanus-allee.tar.gz -C /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d | head -1)"; \
    cd "$SRC"; \
    make -j"$(nproc)"; \
    test -x ./platanus_allee; \
    ./platanus_allee -v 2>&1 | grep -q "${PLATANUS_VERSION}"; \
    install -m 0755 ./platanus_allee /usr/local/bin/platanus_allee; \
    rm -rf /tmp/src /tmp/platanus-allee.tar.gz

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY platanus-allee/native/main.py /opt/skill/main.py
COPY platanus-allee/meta.yaml /opt/skill/platanus-allee/meta.yaml
COPY platanus-allee/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/pa_commands.txt \
    && grep -q '^assemble' /tmp/pa_commands.txt \
    && grep -q '^phase' /tmp/pa_commands.txt \
    && grep -q '^consensus' /tmp/pa_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/pa_schema.json \
    && test -s /tmp/pa_schema.json \
    && rm -f /tmp/pa_commands.txt /tmp/pa_schema.json

# 4) 清理四连（构建期下载工具 curl 移除；g++/make 保留以便容器内排查/二次构建）
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

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/bin/python3", "/opt/skill/main.py"]
