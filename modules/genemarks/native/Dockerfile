# genemarks native Docker 镜像配方（自建兜底：apt 最小化 + 官方预编译包；禁 miniconda）
#
# 背景：GeneMarkS / GeneMarkS-2（原核基因预测）无官方镜像/conda 包 —— bioconda
#       （api.anaconda.org/package/bioconda/genemarks 及 genemark-s/genemark/gms2 均 404）、
#       quay.io/biocontainers（quay API 401 = 仓库不存在）、depot.galaxyproject.org（无）2026-09 核实全无；
#       nf-core / snakemake-wrappers / brew 亦无（404）。官方提供预编译包
#       （genemark_suite_linux_64 / gms2_linux_64.gz），但**下载需先在线申请密钥/同意学术许可**
#       （https://exon.gatech.edu/GeneMark/license_download.cgi），下载链接由表单动态生成，
#       无法硬编码 → 本配方以「构建时提供已授权压缩包 URL/文件」方式安装。
# ⚠️ 密钥：运行时须在容器内提供 ~/.gmhmmp2_key（GeneMarkS-2）或 ~/.gm_key（旧版 GeneMarkS）。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层；须先在线申请并取得 GMS2_URL 授权下载链接）：
#   docker build -t bioskills/genemarks:1.14_1.25_lic \
#       --build-arg GMS2_URL="<官方授权下载链接>" \
#       -f modules/genemarks/native/Dockerfile modules/
#   # 亦可把已下载的压缩包放到构建上下文，改用本地路径：
#   #   先在 modules/genemarks/native/ 放 gms2_linux_64.gz，再以 --build-arg GMS2_URL=genemarks/native/gms2_linux_64.gz 配合 COPY 方式（见注释）
# 运行（ENTRYPOINT 为 python3 驱动；须 -u + 挂载密钥）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       -v $HOME/.gmhmmp2_key:/root/.gmhmmp2_key:ro bioskills/genemarks:1.14_1.25_lic \
#       gms2 -i /data/genome.fasta --genome-type bacteria --gcode 11 --format gff -o /data/gms2.gff

ARG GENEMARKS_VERSION=1.14_1.25_lic
# 官方授权下载链接（必填；由 license_download.cgi 申请后获得）。留空则构建报错并提示。
ARG GMS2_URL=""
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="genemarks"
LABEL version="${GENEMARKS_VERSION}"
LABEL genemarks_version="${GENEMARKS_VERSION}"
LABEL org.bioskills.software="genemarks"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt runtime (perl/python3) + upstream precompiled GeneMarkS-2 package (license key required)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：perl（gms2.pl/gmsn.pl 本体）+ python3/python3-yaml（/opt/skill/main.py 驱动）+ gzip
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        perl \
        gzip \
        python3 \
        python3-yaml \
        ca-certificates \
        curl \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方预编译包下载 + 解压部署（需已授权 URL）
RUN set -eux; \
    test -n "${GMS2_URL}" || { echo "错误：需 --build-arg GMS2_URL=<官方授权下载链接>（见 http://exon.gatech.edu/GeneMark/license_download.cgi）" >&2; exit 1; }; \
    mkdir -p /opt/genemarks; \
    curl -fSL -o /tmp/gms2.tar.gz "${GMS2_URL}"; \
    tar -xzf /tmp/gms2.tar.gz -C /opt/genemarks --strip-components=0 2>/dev/null || \
        ( mkdir -p /tmp/gm && tar -xzf /tmp/gms2.tar.gz -C /tmp/gm && cp -a /tmp/gm/. /opt/genemarks/ ); \
    find /opt/genemarks -maxdepth 2 -name 'gms2.pl' -exec chmod +x {} \; ; \
    find /opt/genemarks -maxdepth 2 -name 'gmsn.pl' -exec chmod +x {} \; ; \
    find /opt/genemarks -maxdepth 2 -name 'gmhmmp2' -exec chmod +x {} \; ; \
    test -n "$(find /opt/genemarks -maxdepth 2 -name 'gms2.pl' -print -quit)"; \
    rm -rf /tmp/gm /tmp/gms2.tar.gz

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY genemarks/native/main.py /opt/skill/main.py
COPY genemarks/meta.yaml /opt/skill/genemarks/meta.yaml
COPY genemarks/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/gm_commands.txt \
    && grep -q '^gms2' /tmp/gm_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/gm_schema.json \
    && test -s /tmp/gm_schema.json \
    && rm -f /tmp/gm_commands.txt /tmp/gm_schema.json

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
    PATH=/opt/genemarks:/usr/local/bin:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体为 python3 驱动的 main.py
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/bin/python3", "/opt/skill/main.py"]
