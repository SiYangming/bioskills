# gstama native Docker 镜像配方（CONDA 路线：micromamba 引导 bioconda env，禁止 miniconda）
# 底座：Debian 12 bookworm-slim
# 安装：apt 仅装 python3-minimal/ca-certificates/procps/tini/curl，curl 引导 micromamba，
#       再 micromamba create bioconda::gs-tama=1.0.4 env（含 samtools + python3 + pyyaml）
# 清理：apt lists / docs / man / cache + micromamba pkgs，尽力保持镜像尺寸
#
# 构建：docker build -t bioskills/gstama:1.0.4-v1.0 -f Dockerfile .
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data bioskills/gstama:1.0.4-v1.0 ...

FROM debian:bookworm-slim AS build

LABEL maintainer="bioskills"
LABEL software="gstama"
LABEL version="1.0.4-v1.0"
LABEL gstama_conda_version="1.0.4"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt 最小依赖 + micromamba 引导 bioconda env + 硬删 docs/man/apt cache/pkgs
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3-minimal \
        python3 \
        ca-certificates \
        tini \
        procps \
        curl \
    ; \
    # 官方 micromamba 引导（免 miniconda）
    curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj -C /usr/local bin/micromamba; \
    export MAMBA_ROOT_PREFIX=/opt/micromamba; \
    micromamba create -y -p /opt/micromamba/envs/gstama -c conda-forge -c bioconda \
        gs-tama=1.0.4 \
        samtools=1.21 \
        python=3.11 \
        pyyaml \
    ; \
    micromamba clean -a -y; \
    # 仅构建期需要的 curl 移除 + 清理四连
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
        /var/tmp/* \
        /opt/micromamba/pkgs; \
    ln -sf /usr/bin/python3 /usr/bin/python; \
    # 版本断言：env 内必须存在 gs-tama 提供的三个脚本
    test -x /opt/micromamba/envs/gstama/bin/tama_flnc_polya_cleanup.py; \
    test -x /opt/micromamba/envs/gstama/bin/tama_collapse.py; \
    test -x /opt/micromamba/envs/gstama/bin/tama_merge.py

# 2) 拷贝 native 驱动到 /opt/skill
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

ENV PYTHONPATH=/opt/skill \
    PATH=/opt/micromamba/envs/gstama/bin:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割僵尸进程 + 转发信号；python 驱动用 env python（自带 pyyaml）
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/micromamba/envs/gstama/bin/python", "/opt/skill/main.py"]
