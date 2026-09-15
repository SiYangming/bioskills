# fusionmap native Docker 镜像配方（自建兜底：apt 最小化 + 官方预编译 tar.gz，禁 miniconda）
#
# 背景：FusionMap（RNA-seq 融合基因检测，C# 编写）无官方镜像/conda 包 —— bioconda
#       （api.anaconda.org 404）、quay.io/biocontainers（biocontainers 镜像由 bioconda 自动构建，
#       bioconda 无包 → 无对应镜像）、depot.galaxyproject.org（fusionmap:2015-03-31 → 404）
#       2026-09 核实全无；nf-core / snakemake-wrappers / Homebrew 亦无。
#       官方发布为 OmicSoft 预编译 tar.gz（FusionMap_2015-03-31.tar.gz）：Windows 版为
#       FusionMap.exe（Linux 下用 mono 运行），官方另有 Linux 直接可执行的构建。
#       因此本配方走「debian:bookworm-slim + apt 最小化（mono-runtime 等）+ 官方 tar.gz」。
#
# ⚠️ 商业/许可受限：FusionMap 官方声明 free for noncommercial use（非商业免费），商业用途需向
#    OmicSoft 获取授权。构建本镜像 = 下载并打包官方软件，**仅供本地非商业使用，不得再分发**。
#    官方下载经 Cloudflare/许可页，自动化 curl 通常返回 403（2026-09 实测）→ 构建若失败，请从
#    官方下载页获取包后，用可访问的镜像 URL 覆盖 --build-arg FUSIONMAP_URL=<URL>，或本机自行部署。
#    本配方未在本仓库实际构建验证（受上述许可/网络限制）。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/fusionmap:2015-03-31 -f modules/fusionmap/native/Dockerfile modules/
#   # 或指定可访问的官方/镜像包 URL：
#   docker build -t bioskills/fusionmap:2015-03-31 \
#       --build-arg FUSIONMAP_URL=<可访问的 FusionMap_2015-03-31.tar.gz URL> \
#       -f modules/fusionmap/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 FusionMap launcher：原生优先，否则 mono 运行 .exe；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/fusionmap:2015-03-31 \
#       --fusion DetectFusion --input /data/reads.fastq --ref /data/Ref --output /data/out --thread 8
# 驱动 main.py（python 入口，镜像内 base.py + 软件级 meta 已就位）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/fusionmap:2015-03-31 \
#       /opt/skill/main.py detect --input /data/reads.fastq --ref /data/Ref --output /data/out --thread 8

ARG FUSIONMAP_VERSION=2015-03-31
ARG FUSIONMAP_URL=http://www.omicsoft.com/downloads/fusionmap/FusionMap_2015-03-31.tar.gz
# 基础镜像可用 --build-arg BASE_IMAGE=<国内加速 registry>/library/debian:bookworm-slim 覆盖（默认官方源）
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

# ARG 在 FROM 之后重新声明，方可在构建阶段使用（供 LABEL 与下载步骤引用）
ARG FUSIONMAP_VERSION
ARG FUSIONMAP_URL

LABEL maintainer="bioskills"
LABEL software="fusionmap"
LABEL version="${FUSIONMAP_VERSION}"
LABEL fusionmap_version="${FUSIONMAP_VERSION}"
LABEL org.bioskills.software="fusionmap"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt minimal + OmicSoft prebuilt tarball"
LABEL license="Free for noncommercial use (commercial license required)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：运行（mono-runtime 供 FusionMap.exe；python3/python3-yaml 供 main.py 驱动）
#    + ca-certificates/curl（构建期下载，末段 purge）+ tini/procps
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        mono-runtime \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方预编译包下载 + 解压部署 /opt/fusionmap
#    （⚠️ 商业/许可受限；自动化下载多因 Cloudflare/许可页 403 失败，请用 --build-arg 覆盖 URL）
RUN set -eux; \
    curl -fSL -o /tmp/fusionmap.tar.gz "${FUSIONMAP_URL}"; \
    mkdir -p /opt/fusionmap; \
    tar -xzf /tmp/fusionmap.tar.gz -C /opt/fusionmap; \
    BIN_NATIVE="$(find /opt/fusionmap -maxdepth 3 -type f -name FusionMap -perm -111 | head -1)"; \
    BIN_EXE="$(find /opt/fusionmap -maxdepth 3 -type f -name 'FusionMap.exe' | head -1)"; \
    test -n "${BIN_NATIVE}${BIN_EXE}" || { echo "包内未找到 FusionMap / FusionMap.exe"; exit 1; }; \
    echo "native=${BIN_NATIVE:-none} exe=${BIN_EXE:-none}"; \
    rm -f /tmp/fusionmap.tar.gz

# 3) launcher（/usr/local/bin/FusionMap）：原生优先，否则 mono 运行 FusionMap.exe
RUN set -eux; \
    BIN_NATIVE="$(find /opt/fusionmap -maxdepth 3 -type f -name FusionMap -perm -111 | head -1)"; \
    BIN_EXE="$(find /opt/fusionmap -maxdepth 3 -type f -name 'FusionMap.exe' | head -1)"; \
    { \
      echo '#!/usr/bin/env bash'; \
      echo '# FusionMap launcher（原生优先；否则 mono FusionMap.exe）'; \
      if [ -n "$BIN_NATIVE" ]; then echo "if [[ -x \"$BIN_NATIVE\" ]]; then exec \"$BIN_NATIVE\" \"\$@\"; fi"; fi; \
      if [ -n "$BIN_EXE" ]; then \
        echo "if [[ -f \"$BIN_EXE\" ]]; then exec mono \"$BIN_EXE\" \"\$@\"; fi"; \
      fi; \
      echo 'echo "FusionMap 可执行文件未找到" >&2; exit 127'; \
    } > /usr/local/bin/FusionMap; \
    chmod 0755 /usr/local/bin/FusionMap

# 4) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY fusionmap/native/main.py /opt/skill/main.py
COPY fusionmap/meta.yaml /opt/skill/fusionmap/meta.yaml
COPY fusionmap/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/fm_commands.txt \
    && grep -q '^detect' /tmp/fm_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/fm_schema.json \
    && test -s /tmp/fm_schema.json \
    && rm -f /tmp/fm_commands.txt /tmp/fm_schema.json

# 5) 清理四连（构建期下载工具 curl 移除；mono-runtime/python3 保留为运行依赖）
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

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体即 FusionMap launcher
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/FusionMap"]
