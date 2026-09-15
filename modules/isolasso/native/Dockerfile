# isolasso native Docker 镜像配方（自建兜底：apt 最小化 + 官方源码 make，禁 miniconda）
#
# 背景：IsoLasso（LASSO 回归 RNA-seq 转录本组装，v2.6.1）无官方镜像/conda 包 ——
#       bioconda（api.anaconda.org/package/bioconda/isolasso 404）、quay.io/biocontainers（quay API
#       401 = 仓库不存在，对照 samtools 200）、depot.galaxyproject.org（无）2026-09 核实全无；
#       nf-core / snakemake-wrappers / brew 亦无（404）。官方仅源码（alumni.cs.ucr.edu/~liw/
#       isolasso-2.6.1.tar.gz），安装 = src 目录 make。
# ⚠️ 编译依赖（源码 src/Makefile 链接 -lglpk -lCGAL -lgsl -lgslcblas -lm）：CGAL / GSL / GLPK / GMP
#      （Debian：libcgal-dev libgsl-dev libglpk-dev libgmp-dev）；历史 CentOS 6 文档另提及 boost_thread。
# ⚠️ 编译兼容性（未实际构建验证）：2012 年代 C++ 源码在 bookworm g++12 下可能有新告警/需小修；
#     源码内含 isolassocpp/CGAL 副本，若系统 CGAL 版本不兼容可在 src 内改用副本头文件。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/isolasso:2.6.1 -f modules/isolasso/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 python3 驱动；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/isolasso:2.6.1 \
#       assemble /data/alignments.bam -o /data/sample

ARG ISOLASSO_VERSION=2.6.1
ARG ISOLASSO_TARBALL=isolasso-2.6.1.tar.gz
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="isolasso"
LABEL version="${ISOLASSO_VERSION}"
LABEL isolasso_version="${ISOLASSO_VERSION}"
LABEL org.bioskills.software="isolasso"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt build deps (CGAL/GSL/GLPK/GMP) + upstream source (make)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：编译（build-essential + CGAL/GSL/GLPK/GMP）+ 运行（python3/python3-yaml 驱动 + samtools 供 BAM）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        libcgal-dev \
        libgsl-dev \
        libglpk-dev \
        libgmp-dev \
        samtools \
        python3 \
        python3-yaml \
        ca-certificates \
        curl \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源码下载 + make + 部署（编译产物在源码 bin/：isolasso / processsam / runlasso.py 等）
RUN set -eux; \
    curl -fSL -o /tmp/isolasso.tar.gz \
        "http://alumni.cs.ucr.edu/~liw/isolasso-${ISOLASSO_VERSION}.tar.gz"; \
    mkdir -p /tmp/src && tar -xzf /tmp/isolasso.tar.gz -C /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d | head -1)"; \
    cd "$SRC/src"; \
    make -j"$(nproc)"; \
    test -x "$SRC/bin/isolasso"; \
    mkdir -p /opt/isolasso; \
    cp -a "$SRC/bin/." /opt/isolasso/; \
    ln -sf /opt/isolasso/runlasso.py /usr/local/bin/runlasso.py; \
    ln -sf /opt/isolasso/processsam /usr/local/bin/processsam; \
    ln -sf /opt/isolasso/isolasso /usr/local/bin/isolasso; \
    chmod +x /opt/isolasso/runlasso.py /usr/local/bin/runlasso.py; \
    rm -rf /tmp/src /tmp/isolasso.tar.gz

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY isolasso/native/main.py /opt/skill/main.py
COPY isolasso/meta.yaml /opt/skill/isolasso/meta.yaml
COPY isolasso/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/iso_commands.txt \
    && grep -q '^assemble' /tmp/iso_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/iso_schema.json \
    && test -s /tmp/iso_schema.json \
    && rm -f /tmp/iso_commands.txt /tmp/iso_schema.json

# 4) 清理四连（构建期下载工具 curl 移除；编译库保留以便容器内排查）
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
    PATH=/opt/isolasso:/usr/local/bin:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体为 python3 驱动的 main.py
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/bin/python3", "/opt/skill/main.py"]
