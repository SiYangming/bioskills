# misa native Docker 镜像配方（自建兜底：apt 最小化 + 官方源包，禁 miniconda）
#
# 背景：MISA（misa.pl v2.1，IPK Gatersleben）**无官方镜像 / 无 conda 包** —— 2026-09 核实：
#       bioconda（api.anaconda.org/package/bioconda/misa → 404 "misa" could not be found；无
#       misa-web / misa-tools 等别名）、quay.io/biocontainers（quay API 401 = 仓库不存在）、
#       depot.galaxyproject.org（无）、brew / nf-core modules / snakemake-wrappers 亦 404。
#       官方仅发布源码包 https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip
#       （v2.1，2020-08-25；内含 misa.pl + misa.ini，纯 Perl，无需编译）。
#       因此本配方走「debian:bookworm-slim + apt（perl + python3 驱动）+ 官方源包解包部署」。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/misa:2.1 -f modules/misa/native/Dockerfile modules/
# 运行（CLI = misa.pl；须 -u 避免产物归 root；misa.pl 只从当前工作目录读 misa.ini）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/misa:2.1 -help
# 驱动 main.py（镜像内 base.py + 软件级 meta 已就位；--outdir 内自动准备 misa.ini 与输入软链）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/misa:2.1 \
#       /opt/skill/main.py detect /data/genome.fasta --outdir /data/misa_out

ARG MISA_VERSION=2.1
# 官方源包（站点仅此单包，2020-08-25 发布 = v2.1）；国内加速可 --build-arg MISA_ZIP_URL=<镜像 URL>
ARG MISA_ZIP_URL=https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip
# 官方源包 sha256（2026-09 实测下载）
ARG MISA_ZIP_SHA256=43d90953489dbf428f4ed051a099a942314d3ccbea6226a7c72fd44216b243b8
# 基础镜像可用 --build-arg BASE_IMAGE=<国内加速 registry>/library/debian:bookworm-slim 覆盖（默认官方源）
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

# ARG 在 FROM 之前声明只对 FROM 生效；要在 stage 内使用必须重新声明（否则 sh 报 "parameter not set"）
ARG MISA_VERSION
ARG MISA_ZIP_URL
ARG MISA_ZIP_SHA256

LABEL maintainer="bioskills"
LABEL software="misa"
LABEL version="${MISA_VERSION}"
LABEL misa_version="${MISA_VERSION}"
LABEL org.bioskills.software="misa"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt (perl) + official source zip (misa.pl)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小依赖：运行 perl + python3/python3-yaml（供 /opt/skill/main.py 驱动）+ 构建期 curl/unzip
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        perl \
        ca-certificates \
        curl \
        unzip \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源包下载 + sha256 校验 + 部署 misa.pl / misa.ini + 真实迷你 SSR 检测冒烟
RUN set -eux; \
    curl -fSL -o /tmp/misa.zip "$MISA_ZIP_URL"; \
    echo "$MISA_ZIP_SHA256  /tmp/misa.zip" | sha256sum -c -; \
    mkdir -p /tmp/misa_src /opt/misa; \
    unzip -q -o /tmp/misa.zip -d /tmp/misa_src; \
    test -f /tmp/misa_src/misa.pl; \
    test -f /tmp/misa_src/misa.ini; \
    install -m 0755 /tmp/misa_src/misa.pl /usr/local/bin/misa.pl; \
    install -m 0644 /tmp/misa_src/misa.ini /opt/misa/misa.ini; \
    # 冒烟 A：GFF: false → <fasta>.misa + <fasta>.statistics（下游 misa_primer3.pl 需要的形态）
    mkdir -p /tmp/smoke_a /tmp/smoke_b; \
    cd /tmp/smoke_a; \
    printf 'definition(unit_size,min_repeats): 1-10 2-6 3-5 4-5 5-5 6-5\ninterruptions(max_difference_for_2_SSRs): 100\nGFF: false\n' > misa.ini; \
    printf '>seq1\nACGTACGTACGTACGTACGTACGTTTTTTTTTTTTTTTTTTCAGCAGCAGCAGCAGCAGCAGAAAAAAAAGGGGGGGGGGGG\n' > genome.fasta; \
    misa.pl genome.fasta 2>/dev/null; \
    test -s genome.fasta.misa; \
    test -s genome.fasta.statistics; \
    grep -q '^seq1' genome.fasta.misa; \
    # 冒烟 B：官方 misa.ini（GFF: true）→ 逐序列 .gff，且**不产出 .misa**（v2.1 产物互斥）
    cd /tmp/smoke_b; \
    cp /opt/misa/misa.ini .; \
    printf '>seq1\nACGTACGTACGTACGTACGTACGTTTTTTTTTTTTTTTTTTCAGCAGCAGCAGCAGCAGCAGAAAAAAAAGGGGGGGGGGGG\n' > genome.fasta; \
    misa.pl genome.fasta 2>/dev/null; \
    test -f seq1.gff; \
    test ! -e genome.fasta.misa; \
    cd /; \
    rm -rf /tmp/misa_src /tmp/misa.zip /tmp/smoke_a /tmp/smoke_b

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY misa/native/main.py /opt/skill/main.py
COPY misa/meta.yaml /opt/skill/misa/meta.yaml
COPY misa/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/misa_commands.txt \
    && grep -q '^detect' /tmp/misa_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/misa_schema.json \
    && test -s /tmp/misa_schema.json \
    && rm -f /tmp/misa_commands.txt /tmp/misa_schema.json

# 4) 清理四连（仅构建期使用的 curl/unzip 移除）
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
    PATH=/usr/local/bin:$PATH

WORKDIR /data

# ENTRYPOINT tini：正确收割子进程 + 转发信号；本体即 misa.pl。
# 不设默认 CMD：misa.pl 无参数即打印用法（die，退出码 255）；运行需传入 <FASTA> 且 cwd 下要有 misa.ini
# （推荐直接用驱动 main.py，自动准备 misa.ini 与输入软链，见文件头示例）。
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/misa.pl"]
