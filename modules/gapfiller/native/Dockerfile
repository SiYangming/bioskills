# gapfiller native Docker 镜像配方（自建兜底：apt 最小化 + 官方 Perl GapFiller.pl v1.11，禁 miniconda）
#
# 背景：本文档目标为 **Perl GapFiller.pl v1.11**（三代修改版，BaseClear Boetzer & Pirovano）。
#       ⚠️ 官方渠道 bioconda/quay.io/biocontainers/depot.galaxyproject.org 的**同名 gapfiller**
#       实为 **C++ v2.1.2 系列**（bioconda recipe 源码 gapfiller-2.1.2.tar.gz、test 命令
#       `GapFiller --help`；CLI 为 `GapFiller --seed1 … --seed-ins …`），与本模块的 Perl
#       GapFiller.pl（`-l library.txt -s genome.fa -T N`）**不是同一工具** → Perl v1.11 无官方
#       镜像/conda 包，故本模块自建配方（2026-09 逐渠道核实：bioconda latest 2.1.2、quay tag
#       2.1.2--h7ff8a90_4、depot 200，但均为 C++ v2 系列）。
#       GapFiller.pl 为单文件 Perl 脚本，按自身目录 $Bin/bowtie/bowtie、$Bin/bwa/bwa 查找比对器；
#       依赖 Perl 核心模块（Storable/File::Path/File::Copy/FindBin/threads/Text::Wrap/Getopt::Std）。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/gapfiller:1.11 -f modules/gapfiller/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 GapFiller.pl；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/gapfiller:1.11 \
#       -l library.txt -s genome.fa -T 4
# 驱动 main.py（python 入口，镜像内 base.py + 软件级 meta 已就位）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/gapfiller:1.11 \
#       /opt/skill/main.py fill -l /data/library.txt -s /data/genome.fa --threads 4

ARG GAPFILLER_REF=master
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="gapfiller"
LABEL version="1.11"
LABEL org.bioskills.software="gapfiller"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL gapfiller_version="1.11"
LABEL pkg_route="apt (perl/bowtie/bwa) + upstream Perl GapFiller.pl (lufuhao/gapfiller)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：运行本体（perl + bowtie + bwa）+ 驱动（python3/python3-yaml）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        perl \
        bowtie \
        bwa \
        ca-certificates \
        curl \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方 Perl 脚本下载 + $Bin 相对比对器布局 + 版本断言
RUN set -eux; \
    mkdir -p /opt/gapfiller/bowtie /opt/gapfiller/bwa; \
    curl -fsSL -o /opt/gapfiller/GapFiller.pl \
        "https://raw.githubusercontent.com/lufuhao/gapfiller/${GAPFILLER_REF}/GapFiller.pl"; \
    chmod 0755 /opt/gapfiller/GapFiller.pl; \
    ln -sf /usr/bin/bowtie /opt/gapfiller/bowtie/bowtie; \
    ln -sf /usr/bin/bowtie-build /opt/gapfiller/bowtie/bowtie-build; \
    ln -sf /usr/bin/bwa /opt/gapfiller/bwa/bwa; \
    grep -qE 'version *= *"v1\.11"' /opt/gapfiller/GapFiller.pl; \
    perl -e 'use Storable; use File::Path; use File::Copy; use FindBin; use threads; use Text::Wrap; use Getopt::Std; use threads::shared;' ; \
    perl -c /opt/gapfiller/GapFiller.pl >/dev/null

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY gapfiller/native/main.py /opt/skill/main.py
COPY gapfiller/meta.yaml /opt/skill/gapfiller/meta.yaml
COPY gapfiller/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/gf_commands.txt \
    && grep -q '^fill' /tmp/gf_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/gf_schema.json \
    && test -s /tmp/gf_schema.json \
    && rm -f /tmp/gf_commands.txt /tmp/gf_schema.json

# 4) 清理四连（构建期 curl 移除）
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
    PATH=/opt/gapfiller:$PATH

WORKDIR /data

# ENTRYPOINT tini：本体即 Perl GapFiller.pl（$Bin=/opt/gapfiller，bowtie/bwa 已就位）
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/gapfiller/GapFiller.pl"]
