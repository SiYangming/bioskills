# finishersc native Docker 镜像配方（自建兜底：apt 最小化 + 官方源码，禁 miniconda）
#
# 背景：FinisherSC（Finishing Tool v2.1，kakitone/finishingTool）官方渠道全无 —— bioconda
#       （api.anaconda.org/bioconda/finishersc 404）、quay.io/biocontainers（401=无仓库）、
#       depot.galaxyproject.org（singularity finishersc:latest 404）2026-09 核实；nf-core /
#       snakemake-wrappers / brew 亦 404。官方发布即 GitHub 源码（教学文档 zip 名
#       kakitone-finishingTool-v2.1-2-ga1f2608.zip = v2.1）。
#       ⚠️ finisherSC.py 为 **Python 2 语法**（bookworm 已移除 Python 2）→ 底座取
#       **debian:bullseye-slim**（仍提供 python2.7），apt 安装 python2.7 + MUMmer(mummer)。
# 底座：Debian 11 bullseye-slim（因 Python 2.7 依赖；非 bookworm）
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/finishersc:2.1 -f modules/finishersc/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 python2.7 finisherSC.py；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/finishersc:2.1 \
#       -par 8 -l True -o contigs.fasta_improved3.fasta /data /usr/bin
# 驱动 main.py：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/finishersc:2.1 \
#       /opt/skill/main.py finish /data /usr/bin --large --threads 8

ARG FINISHERSC_REF=master
ARG BASE_IMAGE=debian:bullseye-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="finishersc"
LABEL version="2.1"
LABEL org.bioskills.software="finishersc"
LABEL impl="native"
LABEL base_image="debian:bullseye-slim"
LABEL finishersc_version="2.1"
LABEL pkg_route="apt (python2.7/mummer) + upstream source (kakitone/finishingTool)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：Python 2.7 + MUMmer（运行本体）+ Python 3 驱动
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python2.7 \
        python2.7-minimal \
        mummer \
        ca-certificates \
        curl \
        unzip \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    ln -sf /usr/bin/python2.7 /usr/local/bin/python; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源码下载 + 部署 + 结构化版本断言（finisherSC.py 无 --version）
RUN set -eux; \
    mkdir -p /tmp/src; \
    curl -fsSL -o /tmp/src.zip \
        "https://codeload.github.com/kakitone/finishingTool/legacy.zip/${FINISHERSC_REF}"; \
    unzip -q /tmp/src.zip -d /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d | head -1)"; \
    test -f "$SRC/finisherSC.py"; \
    mkdir -p /opt/finisherSC; \
    cp -R "$SRC"/. /opt/finisherSC/; \
    chmod 0755 /opt/finisherSC/finisherSC.py; \
    python2.7 -c "import argparse, time"; \
    command -v nucmer >/dev/null; \
    rm -rf /tmp/src /tmp/src.zip

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY finishersc/native/main.py /opt/skill/main.py
COPY finishersc/meta.yaml /opt/skill/finishersc/meta.yaml
COPY finishersc/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/fsc_commands.txt \
    && grep -q '^finish' /tmp/fsc_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/fsc_schema.json \
    && test -s /tmp/fsc_schema.json \
    && rm -f /tmp/fsc_commands.txt /tmp/fsc_schema.json

# 4) 清理四连（构建期 curl/unzip 移除）
RUN set -eux; \
    apt-get purge -y curl unzip; \
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
    FINISHERSC_HOME=/opt/finisherSC \
    FINISHERSC_PYTHON=python2.7 \
    PATH=/opt/finisherSC:$PATH

WORKDIR /data

# ENTRYPOINT tini：本体即 Python 2 的 finisherSC.py（MUMmer 在 /usr/bin，作第 2 位置参数传 /usr/bin）
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/bin/python2.7", "/opt/finisherSC/finisherSC.py"]
