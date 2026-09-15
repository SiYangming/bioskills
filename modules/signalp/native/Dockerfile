# signalp native Docker 镜像配方（自建兜底：bookworm-slim + apt perl 运行时 + 用户自备授权 tarball）
# ---------------------------------------------------------------------------
# 路线说明（AGENT.md §7 自建兜底）：SignalP 不在 bioconda / quay.io/biocontainers /
# depot.galaxyproject.org（2026-09 核实均无），Debian bookworm 亦无该包。
# ⚠️ 许可受限：官方 tarball signalp-5.0.Linux.tar.gz 需用 edu 邮箱向 DTU 申请下载链接，
#    禁止商用。本配方不提供、也不伪造任何官方直链，构建时必须由用户提供自备的授权包：
#      docker build --build-arg SIGNALP_URL=https://<your-mirror>/signalp-5.0.Linux.tar.gz \
#          -t bioskills/signalp:5.0 modules/signalp/native
#    （申请入口：https://services.healthtech.dtu.dk/services/software.php）
#
# 运行：镜像为「signalp 二进制容器」；native/main.py 驱动在宿主机运行，不随镜像分发。
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/signalp:5.0 -org euk -fasta /data/proteins.fasta -gff3 -mature
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG SIGNALP_VERSION=5.0
ARG SIGNALP_URL=

LABEL maintainer="bioskills"
LABEL software="signalp"
LABEL version="5.0-v1.0"
LABEL signalp_version="${SIGNALP_VERSION}"
LABEL pkg_route="apt(perl runtime) + user-provided licensed signalp tarball -> /opt/signalp"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp

# 1) apt 最小运行时（Perl；curl 仅用于构建，稍后删除）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        perl \
        ca-certificates \
        procps \
        curl \
    ; \
    mkdir -p /opt/signalp

# 2) 部署用户自备的官方授权 tarball（SIGNALP_URL 必填，官方直链需 edu 邮箱申请）
RUN set -eux; \
    test -n "${SIGNALP_URL}" || { \
        echo "需 --build-arg SIGNALP_URL=<自备授权 signalp-${SIGNALP_VERSION}.Linux.tar.gz>（官方需 edu 邮箱申请）" >&2; \
        exit 1; \
    }; \
    curl -fL "${SIGNALP_URL}" -o /tmp/signalp.tar.gz; \
    tar -xzf /tmp/signalp.tar.gz -C /opt/signalp --strip-components=1; \
    test -x /opt/signalp/bin/signalp; \
    /opt/signalp/bin/signalp -version

# 3) 清理四连 + 删构建期 curl
RUN set -eux; \
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /usr/bin/curl

ENV PATH=/opt/signalp/bin:$PATH
WORKDIR /data

# SignalP 脚本依赖同目录相对路径，故直接指向 bin/signalp（不软链）
ENTRYPOINT ["/opt/signalp/bin/signalp"]
CMD ["-h"]
