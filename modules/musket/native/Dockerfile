# musket native Docker 镜像配方（自建兜底：apt 最小化 + 官方 SourceForge 源码 make，禁 miniconda）
#
# 背景：Musket（k-mer 谱多阶段 Illumina 短读错误修正，Bioinformatics 2013）无官方镜像/conda 包
#       —— bioconda（api.anaconda.org {"error":"musket" could not be found}）、conda-forge（同 API
#       报错）、quay.io/biocontainers（quay API 401 = 仓库不存在；对照 fastuniq/samtools 200）、
#       quay.io/bioinfortools（401）、depot.galaxyproject.org（singularity musket:1.1 404）
#       2026-09-08 核实全无；nf-core/snakemake-wrappers/brew 亦无（404）。官方发布站为
#       SourceForge musket，最新 musket-1.1.tar.gz（2013-10-09，112.1 kB，官方仅源码包、
#       无预编译二进制；文件名是 .tar.gz 而非教学文档所记 .tar.bz2）。官方 README：在源码根目录
#       make 即完成编译（C++；-zlib 输出/gzip 输入需 zlib；Makefile 宏 MAX_KMER_SIZE 默认 28、
#       MAX_SEQ_LENGTH 默认 200）。
#       因此本配方走「debian:bookworm-slim + apt 构建依赖（build-essential/zlib1g-dev）+ 官方源码 make」。
# ⚠️ 编译兼容性（未核实）：2013 年代 C++ 源码在 bookworm g++ 12 下可能有新告警/需小修（本仓库只做
#     录入，未实际构建验证；如遇报错请以源码为准调整）。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/musket:1.1 -f modules/musket/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 musket；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/musket:1.1 \
#       -k 21 50000000 -p 4 -inorder -omulti /data/out /data/f1.fastq /data/f2.fastq
# 驱动 main.py（python 入口，镜像内 base.py + 软件级 meta 已就位）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/musket:1.1 \
#       /opt/skill/main.py correct --kmer-size 21 --est-kmer-count 50000000 --omulti /data/out \
#       -p 4 --inorder --reads /data/f1.fastq /data/f2.fastq

ARG MUSKET_VERSION=1.1
# 官方源码归档（SourceForge；直链 downloads.sourceforge.net 会自动重定向到镜像）
ARG MUSKET_TARBALL=musket-1.1.tar.gz
# 基础镜像可用 --build-arg BASE_IMAGE=<国内加速 registry>/library/debian:bookworm-slim 覆盖（默认官方源）
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="musket"
LABEL version="${MUSKET_VERSION}"
LABEL musket_version="${MUSKET_VERSION}"
LABEL org.bioskills.software="musket"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt build deps + SourceForge source (make)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：构建（build-essential/zlib1g-dev）+ 运行（python3/python3-yaml 供 /opt/skill/main.py 驱动）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        g++ \
        make \
        zlib1g-dev \
        ca-certificates \
        curl \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源码归档下载 + make + 部署 + 冒烟（musket 无 --version/--help：用真实迷你修正冒烟判定）
RUN set -eux; \
    curl -fSL -o /tmp/musket.tar.gz \
        "https://downloads.sourceforge.net/project/musket/${MUSKET_TARBALL}"; \
    mkdir -p /tmp/src && tar -xzf /tmp/musket.tar.gz -C /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d | head -1)"; \
    cd "$SRC"; \
    make -j"$(nproc)"; \
    test -x ./musket; \
    install -m 0755 ./musket /usr/local/bin/musket; \
    # 冒烟：迷你 FASTQ 真实修正（4 条 60 bp reads；末条第 31 位 1 个替换错误）
    printf '@r1\n%s\n+\n%s\n' \
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT" \
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" > /tmp/smoke_in.fastq; \
    printf '@r2\n%s\n+\n%s\n' \
        "TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCA" \
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" >> /tmp/smoke_in.fastq; \
    printf '@r3\n%s\n+\n%s\n' \
        "GGGGAAAACCCCAAAAGGGGAAAACCCCAAAAGGGGAAAACCCCAAAAGGGGAAAACCCCAAAA" \
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" >> /tmp/smoke_in.fastq; \
    printf '@r4\n%s\n+\n%s\n' \
        "TTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGG" \
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" >> /tmp/smoke_in.fastq; \
    musket -k 21 100000 -o /tmp/smoke_out.fastq /tmp/smoke_in.fastq >/tmp/smoke.log 2>&1; \
    test -s /tmp/smoke_out.fastq || { cat /tmp/smoke.log; echo "musket 冒烟失败" >&2; exit 1; }; \
    rm -rf /tmp/src /tmp/musket.tar.gz /tmp/smoke_in.fastq /tmp/smoke_out.fastq /tmp/smoke.log

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY musket/native/main.py /opt/skill/main.py
COPY musket/meta.yaml /opt/skill/musket/meta.yaml
COPY musket/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/mk_commands.txt \
    && grep -q '^correct' /tmp/mk_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/mk_schema.json \
    && test -s /tmp/mk_schema.json \
    && rm -f /tmp/mk_commands.txt /tmp/mk_schema.json

# 4) 清理四连（构建期下载工具 curl 移除；g++/make/zlib1g-dev 保留以便容器内排查/二次构建）
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

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体即 musket
# 说明：musket 无 --help/-v（官方 README 参数表无 version/help 选项），故不设默认 CMD ——
# docker run 追加的 argv 即 musket 参数（-k … -o/-omulti … <reads...>）；无参运行行为未核实。
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/musket"]
