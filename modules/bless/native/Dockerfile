# bless native Docker 镜像配方（自建兜底：apt 最小化 + 官方 SourceForge 源码 make，禁 miniconda）
#
# 背景：BLESS / BLESS 2（Bloom-filter NGS reads 错误修正）无官方镜像/conda 包 —— bioconda
#       （api.anaconda.org 404）、quay.io/biocontainers（bioconda 无包 → 无自动构建镜像）、
#       depot.galaxyproject.org（目录列表无 bless* sif）2026-09 核实全无；GitHub 亦无官方仓库
#       （nsaunders/bless、sfu-compbio/bless、sfu-compbio/bless2 均 404）。
#       官方发布站为 SourceForge bless-ec，最新发布 bless.v1p02.tgz（BLESS 1.02 / BLESS 2，
#       2015-06-10，GPLv3 源码；V1.01 起 tgz 内含全部依赖库 Boost/sparsehash/klib/KMC/
#       murmurhash3/zlib/pigz，编译仅需 make + g++ + MPI 开发库）。
#       因此本配方走「debian:bookworm-slim + apt 构建依赖（g++/make/mpich）+ 官方源码 make」。
# ⚠️ 编译兼容性（未核实）：官方测试环境为 GCC 4.9.2 + MPICH 3.1.3 / OpenMPI 1.8.2（2015 年代）；
#     bookworm 为 g++ 12 + mpich 4.x，2015 年代码可能需小修（本仓库只做录入，未实际构建验证）。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/bless:1.02 -f modules/bless/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 bless launcher：自动在 CWD 放置 kmc/bin/kmc + MPI hostname 兜底；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/bless:1.02 \
#       -read1 /data/reads_1.fastq -read2 /data/reads_2.fastq -kmerlength 21 -prefix out/illumina -notrim
# 驱动 main.py（python 入口，镜像内 base.py + 软件级 meta 已就位）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/bless:1.02 \
#       /opt/skill/main.py correct -1 /data/reads_1.fastq -2 /data/reads_2.fastq -k 21 -p out/illumina

ARG BLESS_VERSION=1.02
# 官方源码归档（SourceForge token；直链 downloads.sourceforge.net 会自动重定向到镜像）
ARG BLESS_TARBALL=bless.v1p02.tgz
# 基础镜像可用 --build-arg BASE_IMAGE=<国内加速 registry>/library/debian:bookworm-slim 覆盖（默认官方源）
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="bless"
LABEL version="${BLESS_VERSION}"
LABEL bless_version="${BLESS_VERSION}"
LABEL org.bioskills.software="bless"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt build deps + SourceForge source (make)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：构建（g++/make/mpich/libmpich-dev）+ 运行（python3/python3-yaml 供 /opt/skill/main.py 驱动；
#    libmpich 运行时由 mpich 包携带）+ tini/procps
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        g++ \
        make \
        ca-certificates \
        curl \
        mpich \
        libmpich-dev \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源码归档下载 + make（tgz 内含全部依赖库；make 编译 KMC/kmer 计数与 bless 本体）
RUN set -eux; \
    curl -fSL -o /tmp/bless.tgz \
        "https://downloads.sourceforge.net/project/bless-ec/${BLESS_TARBALL}"; \
    mkdir -p /tmp/src && tar -xzf /tmp/bless.tgz -C /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d | head -1)"; \
    cd "$SRC"; \
    make -j"$(nproc)"; \
    test -x ./bless; \
    test -f ./kmc/bin/kmc || echo "[warn] kmc/bin/kmc 未在源码树中找到（运行期 launcher 需其存在）"; \
    # 部署：真实二进制 + kmc（runtime 拷贝源）→ /opt/bless
    mkdir -p /opt/bless/kmc/bin; \
    install -m 0755 ./bless /opt/bless/bless; \
    if [ -f ./kmc/bin/kmc ]; then install -m 0755 ./kmc/bin/kmc /opt/bless/kmc/bin/kmc; fi; \
    # 断言：无参运行应打印全部选项（bless 无 --help/-v）
    (getent hosts "$(hostname)" >/dev/null 2>&1 || echo "127.0.0.1 $(hostname)" >> /etc/hosts); \
    cd /tmp && /opt/bless/bless 2>&1 | grep -q '\-kmerlength' \
        && /opt/bless/bless 2>&1 | grep -q '\-prefix' || { echo "bless 无参输出断言失败"; exit 1; }; \
    rm -rf /tmp/src /tmp/bless.tgz

# 3) bless launcher（/usr/local/bin/bless）：运行时 CWD 下放置 kmc/bin/kmc（用户文档 alias 依据）
#    + MPI hostname 解析兜底（用户文档：hostname localhost）；然后 exec 真实二进制
RUN set -eux; \
    { \
      echo '#!/usr/bin/env bash'; \
      echo '# BLESS 运行时要求 CWD 下存在 kmc/bin/kmc（用户文档 alias 依据）；launcher 保证之'; \
      echo 'if [[ ! -x kmc/bin/kmc ]]; then'; \
      echo '    if mkdir -p kmc/bin 2>/dev/null; then'; \
      echo '        cp /opt/bless/kmc/bin/kmc kmc/bin/ 2>/dev/null || true'; \
      echo '    fi'; \
      echo 'fi'; \
      echo '# MPI hostname 解析问题兜底（用户文档：hostname localhost）'; \
      echo 'if ! getent hosts "$(hostname 2>/dev/null)" >/dev/null 2>&1; then'; \
      echo '    echo "127.0.0.1 $(hostname 2>/dev/null)" >> /etc/hosts 2>/dev/null || true'; \
      echo 'fi'; \
      echo 'exec /opt/bless/bless "$@"'; \
    } > /usr/local/bin/bless; \
    chmod 0755 /usr/local/bin/bless

# 4) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY bless/native/main.py /opt/skill/main.py
COPY bless/meta.yaml /opt/skill/bless/meta.yaml
COPY bless/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/bl_commands.txt \
    && grep -q '^correct' /tmp/bl_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/bl_schema.json \
    && test -s /tmp/bl_schema.json \
    && rm -f /tmp/bl_commands.txt /tmp/bl_schema.json

# 5) 清理四连（构建期下载工具 curl 移除；g++/make/mpich 保留以便容器内排查/二次构建）
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

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体即 bless（launcher）
# 说明：bless 无 --help/-v；无参运行即打印全部选项（故不设默认 CMD）
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/bless"]
