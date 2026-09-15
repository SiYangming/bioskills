# microbiomeutil native Docker 镜像配方（自建兜底：apt 最小化 + 官方 SourceForge 源码 make，禁 miniconda）
#
# 背景：MicrobiomeUtilities（microbiomeutil）为 Broad Institute 的 16S rRNA 工具套件，含
#       ChimeraSlayer（嵌合体检测）/ NAST-iEr（NAST 比对）/ WigeoN（Pintail 类异常检测）。
#       无官方镜像/conda 包：bioconda（microbiomeutil / chimeraslayer 均 404）、
#       quay.io/biocontainers（401 = 仓库不存在）、depot.galaxyproject.org（404）、
#       nf-core / snakemake-wrappers / homebrew 均无（2026-09 核实）。
#       官方仅提供 SourceForge 源码包 microbiomeutil-r20110519.tgz（133,623,556 bytes；仅公布 md5）。
#       因此本配方走「debian:bookworm-slim + apt 构建依赖 + 官方源码 make」：
#         * NAST-iEr 为 C 程序（gcc 编译）；ChimeraSlayer / WigeoN 为 Perl 脚本（无需编译）
#         * 运行期外部依赖：megablast（ncbi-blast+）、cdbtools（cdbfasta/cdbyank）→ 由 apt 提供
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/microbiomeutil:r20110519 -f modules/microbiomeutil/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 python 驱动 main.py；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/microbiomeutil:r20110519 --list-commands
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/microbiomeutil:r20110519 chimeraslayer --query-nast /data/q.NAST

ARG BASE_IMAGE=debian:bookworm-slim
ARG MBU_VERSION=r20110519
ARG MBU_TARBALL=microbiomeutil-r20110519.tgz
ARG MBU_URL=https://downloads.sourceforge.net/project/microbiomeutil/microbiomeutil-r20110519.tgz
ARG MBU_MD5=11eaac4b0468c05297ba88ec27bd4b56

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="microbiomeutil"
LABEL version="${MBU_VERSION}"
LABEL microbiomeutil_version="${MBU_VERSION}"
LABEL org.bioskills.software="microbiomeutil"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt build deps + SourceForge source (make)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：构建（build-essential/gcc/make）+ 运行（ncbi-blast+/cdbfasta/perl）
#    + 驱动层（python3/python3-yaml/procps/tini）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        make \
        ncbi-blast+ \
        cdbfasta \
        perl \
        ca-certificates \
        curl \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源码归档下载 + md5 校验 + make + 部署
RUN set -eux; \
    curl -fSL -o /tmp/mbu.tgz "${MBU_URL}"; \
    echo "${MBU_MD5}  /tmp/mbu.tgz" | md5sum -c -; \
    mkdir -p /tmp/src && tar -xzf /tmp/mbu.tgz -C /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d -name 'microbiomeutil*' | head -1)"; \
    test -n "$SRC"; \
    cd "$SRC"; \
    make; \
    test -x ./NAST-iEr/NAST-iEr; \
    test -f ./ChimeraSlayer/ChimeraSlayer.pl; \
    mv "$SRC" /opt/microbiomeutil; \
    test -x /opt/microbiomeutil/NAST-iEr/NAST-iEr; \
    rm -rf /tmp/src /tmp/mbu.tgz

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY microbiomeutil/native/main.py /opt/skill/main.py
COPY microbiomeutil/meta.yaml /opt/skill/microbiomeutil/meta.yaml
COPY microbiomeutil/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/mbu_commands.txt \
    && grep -q '^chimeraslayer' /tmp/mbu_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/mbu_schema.json \
    && test -s /tmp/mbu_schema.json \
    && rm -f /tmp/mbu_commands.txt /tmp/mbu_schema.json

# 4) 清理四连（构建期下载工具 curl 移除）
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
    PATH=/opt/microbiomeutil/ChimeraSlayer:/opt/microbiomeutil/NAST-iEr:/opt/microbiomeutil/WigeoN:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；驱动层用 python 调 /opt/skill/main.py
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/bin/python3", "/opt/skill/main.py"]
