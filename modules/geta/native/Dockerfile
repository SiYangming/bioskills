# geta native Docker 镜像配方（自建兜底：apt 最小化 + 官方 tarball 解包，禁 miniconda）
#
# 背景：GETA（chenlianfu/geta）**无官方镜像 / 无 conda 包** —— 2026-09-11 核实：
#       bioconda（api.anaconda.org/package/bioconda/geta → 404）、quay.io/biocontainers、
#       depot.galaxyproject.org、brew 均无 geta；nf-core modules / snakemake-wrappers 亦 404。
#       官方仅以 GitHub tag tarball 分发（geta-<ver>/bin/*.pl，解压即用，非编译）。
#       因此本配方走「debian:bookworm-slim + apt（perl + python3 驱动）+ 官方 tarball 解包部署」。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/geta:2.7.1 -f modules/geta/native/Dockerfile modules/
# 运行（CLI = geta.pl；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/geta:2.7.1 --help
# 驱动 main.py（镜像内 base.py + 软件级 meta 已就位）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/geta:2.7.1 \
#       /opt/skill/main.py gff3_to_gtf /data/genome.fasta /data/bestGeneModels.gff3 -o /data/bestGeneModels.gtf

ARG GETA_VERSION=2.7.1
# 官方 tarball（GitHub 自动生成的 tag 归档；国内加速可 --build-arg GETA_TAR_URL=<镜像 URL>）
ARG GETA_TAR_URL=https://github.com/chenlianfu/geta/archive/refs/tags/v2.7.1.tar.gz
# 官方 tarball sha256（2026-09-11 实测下载 17098074 B；GitHub 自动 tarball 无官方公布摘要，此值供完整性校验）
ARG GETA_TAR_SHA256=a80d8d4497b5ca56255ea69436b011ada6807a640a6f41b6ee803effef2b8786
# 基础镜像可用 --build-arg BASE_IMAGE=<国内加速 registry>/library/debian:bookworm-slim 覆盖（默认官方源）
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

# ARG 在 FROM 之前声明只对 FROM 生效；要在 stage 内使用必须重新声明
ARG GETA_VERSION
ARG GETA_TAR_URL
ARG GETA_TAR_SHA256

LABEL maintainer="bioskills"
LABEL software="geta"
LABEL version="${GETA_VERSION}"
LABEL geta_version="${GETA_VERSION}"
LABEL org.bioskills.software="geta"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt (perl) + official GitHub tarball (bin/*.pl)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：运行 perl + python3/python3-yaml（供 /opt/skill/main.py 驱动）+ 构建期 curl
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        perl \
        ca-certificates \
        curl \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方 tarball 下载 + sha256 校验 + 解包（结构断言 bin/geta.pl）
RUN set -eux; \
    curl -fSL -o /tmp/geta.tar.gz "$GETA_TAR_URL"; \
    echo "$GETA_TAR_SHA256  /tmp/geta.tar.gz" | sha256sum -c -; \
    tar tzf /tmp/geta.tar.gz >/dev/null; \
    mkdir -p /tmp/geta_src /opt/geta; \
    tar -xzf /tmp/geta.tar.gz -C /tmp/geta_src; \
    srcdir="$(find /tmp/geta_src -maxdepth 1 -mindepth 1 -type d -name 'geta-*' | head -1)"; \
    test -n "$srcdir"; \
    test -f "$srcdir/bin/geta.pl"; \
    test -f "$srcdir/bin/gff3ToGtf.pl"; \
    install -m 0755 "$srcdir/bin/"*.pl /usr/local/bin/; \
    cp -R "$srcdir" /opt/geta/; \
    rm -rf /tmp/geta_src /tmp/geta.tar.gz; \
    geta.pl --help >/dev/null 2>&1 || true

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY geta/native/main.py /opt/skill/main.py
COPY geta/meta.yaml /opt/skill/geta/meta.yaml
COPY geta/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/geta_commands.txt \
    && grep -q '^geta' /tmp/geta_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/geta_schema.json \
    && test -s /tmp/geta_schema.json \
    && rm -f /tmp/geta_commands.txt /tmp/geta_schema.json

# 4) 清理四连（仅构建期使用的 curl 移除）
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

# ENTRYPOINT tini：正确收割子进程 + 转发信号；本体即 geta.pl（无参数即打印用法）。
# 推荐直接用驱动 main.py（见文件头示例）。
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/geta.pl"]
