# soapfuse native Docker 镜像配方（自建兜底：apt 最小化 + 官方 SourceForge 预编译包，禁 miniconda）
#
# 背景：SOAPfuse（BGI 双端 RNA-seq 融合基因检测，Perl 实现）无官方镜像/conda 包 —— bioconda
#       （api.anaconda.org 404）、quay.io/biocontainers（biocontainers 由 bioconda 自动构建，
#       bioconda 无包 → 无对应镜像）、depot.galaxyproject.org（soapfuse:1.27 → 404）2026-09
#       核实全无；nf-core / snakemake-wrappers / Homebrew 亦无。
#       官方发布为 SourceForge 预编译包 SOAPfuse-v1.27.tar.gz（2016-01-19）；运行依赖
#       perl（>=5.8.5）+ samtools + bedtools。因此本配方走「debian:bookworm-slim + apt 最小化
#       （perl/samtools/bedtools）+ 官方预编译包」。v1.27 起需把 SOAPfuse perl 模块目录加入
#       PERL5LIB（官方 wiki 说明），镜像已通过 ENV 设置。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/soapfuse:1.27 -f modules/soapfuse/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 SOAPfuse-RUN.pl；须 -u 避免产物归 root；数据库/config 需挂载）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/soapfuse:1.27 \
#       -c /data/config.txt -fd /data/raw_data -l /data/sample.list -o /data/out
# 驱动 main.py（python 入口，镜像内 base.py + 软件级 meta 已就位）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/soapfuse:1.27 \
#       /opt/skill/main.py run -c /data/config.txt -fd /data/raw_data -l /data/sample.list -o /data/out

ARG SOAPFUSE_VERSION=1.27
ARG SOAPFUSE_URL=https://downloads.sourceforge.net/project/soapfuse/SOAPfuse_Package/SOAPfuse-v1.27.tar.gz
# 基础镜像可用 --build-arg BASE_IMAGE=<国内加速 registry>/library/debian:bookworm-slim 覆盖（默认官方源）
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

# ARG 在 FROM 之后重新声明，方可在构建阶段使用（供 LABEL 与下载步骤引用）
ARG SOAPFUSE_VERSION
ARG SOAPFUSE_URL

LABEL maintainer="bioskills"
LABEL software="soapfuse"
LABEL version="${SOAPFUSE_VERSION}"
LABEL soapfuse_version="${SOAPFUSE_VERSION}"
LABEL org.bioskills.software="soapfuse"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt minimal (perl/samtools/bedtools) + SourceForge prebuilt tarball"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：运行（perl + samtools + bedtools 为 SOAPfuse 流程依赖；python3/python3-yaml 供
#    main.py 驱动）+ ca-certificates/curl（构建期下载，末段 purge）+ tini/procps
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        perl \
        samtools \
        bedtools \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方预编译包下载 + 解压部署 /opt/soapfuse
RUN set -eux; \
    curl -fSL -o /tmp/soapfuse.tar.gz "${SOAPFUSE_URL}"; \
    mkdir -p /opt/soapfuse; \
    tar -xzf /tmp/soapfuse.tar.gz -C /opt/soapfuse --strip-components=1; \
    test -f /opt/soapfuse/SOAPfuse-RUN.pl || { echo "包内未找到 SOAPfuse-RUN.pl"; exit 1; }; \
    rm -f /tmp/soapfuse.tar.gz

# 3) 暴露 SOAPfuse-RUN.pl（驱动按 `perl SOAPfuse-RUN.pl ...` 解析）+ PERL5LIB（v1.27+ 模块要求）
ENV PERL5LIB=/opt/soapfuse/source:/opt/soapfuse/source/bin:/opt/soapfuse
RUN set -eux; \
    ln -sf /opt/soapfuse/SOAPfuse-RUN.pl /usr/local/bin/SOAPfuse-RUN.pl; \
    chmod 0755 /opt/soapfuse/SOAPfuse-RUN.pl

# 4) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY soapfuse/native/main.py /opt/skill/main.py
COPY soapfuse/meta.yaml /opt/skill/soapfuse/meta.yaml
COPY soapfuse/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/sf_commands.txt \
    && grep -q '^run' /tmp/sf_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/sf_schema.json \
    && test -s /tmp/sf_schema.json \
    && rm -f /tmp/sf_commands.txt /tmp/sf_schema.json

# 5) 清理四连（构建期下载工具 curl 移除；perl/samtools/bedtools/python3 保留为运行依赖）
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

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体即 SOAPfuse 主脚本（经 perl）
ENTRYPOINT ["/usr/bin/tini", "--", "perl", "/opt/soapfuse/SOAPfuse-RUN.pl"]
