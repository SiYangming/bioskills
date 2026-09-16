# tmhmm native Docker 镜像配方（自建兜底：bookworm-slim + apt perl 运行时 + 用户自备授权 tarball）
# ---------------------------------------------------------------------------
# 路线说明（AGENT.md §7 自建兜底）：TMHMM 不在 bioconda / quay.io/biocontainers /
# depot.galaxyproject.org（2026-09 核实均无），Debian bookworm 亦无该包。
# ⚠️ 许可受限：官方 tarball tmhmm-2.0c.Linux.tar.gz 需用 edu 邮箱向 DTU 申请下载链接，
#    禁止商用。本配方不提供、也不伪造任何官方直链，构建时必须由用户提供自备的授权包：
#      docker build --build-arg TMHMM_URL=https://<your-mirror>/tmhmm-2.0c.Linux.tar.gz \
#          -t bioskills/tmhmm:2.0c modules/tmhmm/native
#    （申请入口：https://services.healthtech.dtu.dk/services/software.php）
# 构建期修正 bin/tmhmm* 的 Perl 解释器路径（安装关键步骤）。
#
# 运行：镜像为「tmhmm 二进制容器」；native/main.py 驱动在宿主机运行，不随镜像分发。
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/tmhmm:2.0c /data/proteins_mature.fasta
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG TMHMM_VERSION=2.0c
ARG TMHMM_URL=

LABEL maintainer="bioskills"
LABEL software="tmhmm"
LABEL version="2.0c-v1.0"
LABEL tmhmm_version="${TMHMM_VERSION}"
LABEL pkg_route="apt(perl runtime) + user-provided licensed tmhmm tarball -> /opt/tmhmm"

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
    mkdir -p /opt/tmhmm

# 2) 部署用户自备的官方授权 tarball + 修正 Perl 路径（TMHMM_URL 必填）
RUN set -eux; \
    test -n "${TMHMM_URL}" || { \
        echo "需 --build-arg TMHMM_URL=<自备授权 tmhmm-${TMHMM_VERSION}.Linux.tar.gz>（官方需 edu 邮箱申请）" >&2; \
        exit 1; \
    }; \
    curl -fL "${TMHMM_URL}" -o /tmp/tmhmm.tar.gz; \
    tar -xzf /tmp/tmhmm.tar.gz -C /opt/tmhmm --strip-components=1; \
    perl -p -i -e 's#/usr/local/bin/perl#/usr/bin/perl#' /opt/tmhmm/bin/tmhmm*; \
    test -x /opt/tmhmm/bin/tmhmm; \
    /opt/tmhmm/bin/tmhmm -version

# 3) 清理四连 + 删构建期 curl
RUN set -eux; \
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /usr/bin/curl

ENV PATH=/opt/tmhmm/bin:$PATH
WORKDIR /data

# TMHMM 脚本依赖同目录相对路径，故直接指向 bin/tmhmm（不软链）
ENTRYPOINT ["/opt/tmhmm/bin/tmhmm"]
CMD ["-h"]
