# gce native Docker 镜像配方（自建兜底：apt 最小化 + 官方 tarball 源码 make，禁 miniconda）
# ---------------------------------------------------------------------------
# 背景：GCE 1.0.0 无任何官方 conda/容器渠道（2026-09 核实 bioconda
#       https://api.anaconda.org/package/bioconda/gce 404、quay.io/biocontainers/gce
#       不存在、depot.galaxyproject.org/singularity/gce:1.0.0--0 404），官方发布源
#       ftp://ftp.genomics.org.cn/pub/gce 已停服（HTTP/HTTPS 探测 000）。
#       因此走「debian:bookworm-slim + apt 构建依赖（g++/make）+ 官方 tarball 源码 make」。
# 来源：tarball 首选 SiYangming/GCE 版本化 release
#       （github.com/SiYangming/GCE/releases/download/gce-1.0.0/gce-1.0.0.tar.gz，2026-09 核实 200），
#       fallback 社区镜像 github.com/nottwy/genome-character-estimator（gce-1.0.0.tar.gz，2026-09 核实 200）；
#       两源为同一 tarball，sha256 已内嵌；官方后继仓库 fanagislab/GCE 含 gce-1.0.2。
# 版本：GCE 1.0.0（gce -h 打印 Version: 1.0.0），与 meta software_versions.native 对齐。
# 说明：tarball 内 kmerfreq 子程序（kmer_freq_hash / kmer_freq_array）为 2012 年预编译
#       x86_64 二进制、无源码，直接布署；现代 glibc 兼容性未核实。主程序 gce 由源码重编译。
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/gce:1.0.0 -f modules/gce/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 gce；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/gce:1.0.0 \
#       -f out.freq.stat -g 273206457 -m 1 -D 8 -b 1
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint kmer_freq_hash bioskills/gce:1.0.0 -k 21 -l reads.list -t 8 -p out
# 驱动 main.py（python 入口，镜像内 base.py + 软件级 meta 已就位）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/gce:1.0.0 \
#       /opt/skill/main.py gce -f /data/out.freq.stat -g 273206457 -H
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG GCE_VERSION=1.0.0
ARG GCE_TARBALL_URL=https://github.com/SiYangming/GCE/releases/download/gce-1.0.0/gce-1.0.0.tar.gz
ARG GCE_TARBALL_URL_FALLBACK=https://github.com/nottwy/genome-character-estimator/raw/master/gce-1.0.0.tar.gz
ARG GCE_TARBALL_SHA256=0eb4f2d3247527d9881e5ab993a12e9800a0b465d8acb4451ede951b2bdf99e1

LABEL maintainer="bioskills"
LABEL software="gce"
LABEL gce_version="${GCE_VERSION}"
LABEL org.bioskills.software="gce"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt build deps + official tarball source (make) + bundled 2012 kmerfreq binaries"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt 最小依赖：构建（g++/make）+ 运行（python3/python3-yaml 供 /opt/skill/main.py 驱动）
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

# 2) 官方 tarball 下载 + sha256 + 源码编译 gce + 布署 kmerfreq 二进制 + 冒烟
RUN set -eux; \
    curl -fSL -o /tmp/gce.tar.gz "${GCE_TARBALL_URL}" \
      || curl -fSL -o /tmp/gce.tar.gz "${GCE_TARBALL_URL_FALLBACK}"; \
    echo "${GCE_TARBALL_SHA256}  /tmp/gce.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/src && tar -xzf /tmp/gce.tar.gz -C /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d -name 'gce-*' | head -1)"; \
    cd "$SRC"; \
    make; \
    test -x ./gce; \
    install -m 0755 ./gce /usr/local/bin/gce; \
    install -m 0755 ./kmerfreq/kmer_freq_hash/kmer_freq_hash /usr/local/bin/kmer_freq_hash; \
    for b in kmer_freq kmer_freq_pfile kmer_freq_pread; do \
        install -m 0755 "./kmerfreq/kmer_freq_array/$b" "/usr/local/bin/$b"; \
    done; \
    gce -h 2>&1 | grep -q "Version:" ; \
    gce -h 2>&1 | grep -q "${GCE_VERSION}"; \
    command -v kmer_freq_hash; \
    rm -rf /tmp/src /tmp/gce.tar.gz

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY gce/native/main.py /opt/skill/main.py
COPY gce/meta.yaml /opt/skill/gce/meta.yaml
COPY gce/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/gce_commands.txt \
    && grep -q '^gce' /tmp/gce_commands.txt \
    && grep -q '^kmer_freq_hash' /tmp/gce_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/gce_schema.json \
    && test -s /tmp/gce_schema.json \
    && rm -f /tmp/gce_commands.txt /tmp/gce_schema.json

# 4) 清理四连（构建期下载/编译器 curl 等移除）
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

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体即 gce 二进制
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/gce"]
CMD ["-h"]
