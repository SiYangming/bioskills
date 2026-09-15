# syntax=docker/dockerfile:1
# =============================================================================
# qiime2 native 自建容器配方（无 bioconda/quay.io/biocontainers/depot 官方镜像，micromamba 兜底）
#
# 路线判定（2026-09 核实）：
#   bioconda api.anaconda.org/package/bioconda/qiime2 → 404；quay.io/biocontainers/qiime2 → 无；
#   depot.galaxyproject.org → 无。QIIME 2 官方只以 **Conda 发行版**（qiime2-amplicon-*-conda.yml）分发，
#   不在 apt / bioconda；故自建兜底 = debian:bookworm-slim + apt 最小运行时 + curl 拉 micromamba
#   静态二进制 + 用官方 2026.1 amplicon conda.yml 建 /opt/env（不使用 miniconda）。
#   另：QIIME 2 项目在 Quay 官方发布发行版镜像 quay.io/qiime2/amplicon:2026.1（可直接拉取，见 README）。
#
# 构建：docker build -t bioskills/qiime2:2026.1 native/
# 运行（必须 -u $(id -u):$(id -g)，否则产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/qiime2:2026.1 \
#       tools.peek /data/demux.qza
# =============================================================================
FROM debian:bookworm-slim

LABEL maintainer="bioskills" \
      org.bioskills.software="qiime2" \
      org.bioskills.impl="native" \
      org.bioskills.base_image="debian:bookworm-slim" \
      org.bioskills.qiime2_version="2026.1" \
      org.bioskills.pkg_route="apt(runtime) + micromamba(QIIME 2 2026.1 amplicon conda.yml -> /opt/env)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp \
    MAMBA_ROOT_PREFIX=/opt/micromamba \
    PATH=/opt/env/bin:/opt/micromamba/bin:$PATH

ARG QIIME2_VERSION=2026.1

# 1) apt 最小运行时（curl/bzip2 仅用于构建，稍后删除；tini 负责收僵尸/转发信号）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3-minimal \
        python3 \
        ca-certificates \
        procps \
        tini \
        curl \
        bzip2 \
    ; \
    ln -sf /usr/bin/python3 /usr/bin/python

# 2) micromamba 静态二进制（官方 micro.mamba.pm 分发）
RUN set -eux; \
    mkdir -p /opt/micromamba; \
    curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
        | tar -xvj -C /opt/micromamba bin/micromamba; \
    /opt/micromamba/bin/micromamba --version

# 3) 用官方 QIIME 2 发行版 conda.yml 建 /opt/env（2026.1 amplicon）
RUN set -eux; \
    curl -fsSL -o /opt/qiime2-env.yml \
        "https://raw.githubusercontent.com/qiime2/distributions/refs/heads/dev/${QIIME2_VERSION}/amplicon/released/qiime2-amplicon-ubuntu-latest-conda.yml"; \
    /opt/micromamba/bin/micromamba create -y -p /opt/env -f /opt/qiime2-env.yml; \
    rm -f /opt/qiime2-env.yml

# 4) 版本断言 + 清理四连 + 删构建期 curl / micromamba 缓存
RUN set -eux; \
    qiime --version | grep -q "${QIIME2_VERSION}"; \
    qiime info | head -n 5; \
    apt-get purge -y curl bzip2; \
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
        /var/tmp/*; \
    rm -rf /opt/micromamba/pkgs

WORKDIR /data

# 不创建固定账号：运行时用 -u $(id -u):$(id -g) 接管（避免 HPC UID 冲突 / 产物归 root）
ENTRYPOINT ["/usr/bin/tini", "--", "qiime"]
CMD ["info"]
