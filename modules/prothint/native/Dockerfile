# prothint native Docker 镜像配方（自建兜底：apt 最小化 + 官方 release tarball，禁 miniconda）
#
# 背景：ProtHint 官方渠道全无 —— bioconda（api.anaconda.org/bioconda/prothint 404）、
#       quay.io/biocontainers（2026-09 核实无仓库）、depot.galaxyproject.org（404）均未收录；
#       nf-core / snakemake-wrappers / brew 亦 404。官方唯一分发为 GitHub release 脚本 tarball
#       （内附 dependencies/diamond 与 dependencies/spaln 预编译二进制）→ 自建 apt 最小化容器。
# 底座：debian:bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/prothint:2.4.0 -f modules/prothint/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 prothint.py；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/prothint:2.4.0 \
#       genome.fasta proteins.fasta --workdir prothint_out --threads 8
# 驱动 main.py：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/prothint:2.4.0 \
#       /opt/skill/main.py predict /data/genome.fasta /data/proteins.fasta --threads 8
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG PROTHINT_VERSION=2.4.0

LABEL maintainer="bioskills"
LABEL software="prothint"
LABEL org.bioskills.software="prothint"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL prothint_version="${PROTHINT_VERSION}"
LABEL pkg_route="apt (python3/perl runtime) + upstream release tarball (ProtHint-${PROTHINT_VERSION}.tar.gz) -> /opt/ProtHint"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt 最小依赖：Python 3 驱动 + ProtHint 所需 Perl 模块（README 列出的 MCE::Mutex / YAML /
#    Thread::Queue / Math::Utils / threads）+ 运行本体；curl 仅构建期用，稍后删除
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-yaml \
        perl \
        libmce-perl \
        libyaml-perl \
        libmath-utils-perl \
        libthread-queue-perl \
        libthreads-perl \
        bash \
        ca-certificates \
        curl \
        procps \
        tini \
    ; \
    ln -sf /usr/bin/python3 /usr/bin/python

# 2) 官方 release tarball 下载 + 部署 + 结构化版本断言（prothint.py 无 --version 输出即版本号，
#    其 --version 由 VERSION 常量输出，见下）
RUN set -eux; \
    mkdir -p /tmp/src; \
    curl -fsSL -o /tmp/src/ProtHint.tar.gz \
        "https://github.com/gatech-genemark/ProtHint/releases/download/v${PROTHINT_VERSION}/ProtHint-${PROTHINT_VERSION}.tar.gz"; \
    mkdir -p /opt/ProtHint; \
    tar -xzf /tmp/src/ProtHint.tar.gz -C /opt/ProtHint --strip-components=1; \
    chmod 0755 /opt/ProtHint/bin/*.py /opt/ProtHint/bin/*.pl 2>/dev/null || true; \
    test -f /opt/ProtHint/bin/prothint.py; \
    python3 /opt/ProtHint/bin/prothint.py --version | grep -q "${PROTHINT_VERSION}"; \
    rm -rf /tmp/src

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY prothint/native/main.py /opt/skill/main.py
COPY prothint/meta.yaml /opt/skill/prothint/meta.yaml
COPY prothint/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/prothint_commands.txt \
    && grep -q '^predict' /tmp/prothint_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/prothint_schema.json \
    && test -s /tmp/prothint_schema.json \
    && rm -f /tmp/prothint_commands.txt /tmp/prothint_schema.json

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
    PROTHINT_HOME=/opt/ProtHint \
    PATH=/opt/ProtHint/bin:$PATH

WORKDIR /data

# ENTRYPOINT tini：本体即 Python 3 的 prothint.py（bin/ 已加 PATH）
ENTRYPOINT ["/usr/bin/tini", "--", "prothint.py"]
CMD ["--help"]
