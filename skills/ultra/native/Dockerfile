# ---------------------------------------------------------------------------
# bioskills / ultra native Dockerfile
# Route: Debian bookworm-slim + apt(运行时) + micromamba(bioconda ultra_bioinformatics=0.1)
#   Debian apt 无 ultra 包（uLTRA 仅 bioconda 提供），故用 micromamba 引导安装；
#   minimap2 / namfinder / samtools 为 uLTRA align 运行时依赖，一并装入 /opt/conda。
# 目标：无 miniconda、仅保留运行必需、apt 立即清理，保持镜像最小。
# 运行时要求：docker run -u $(id -u):$(id -g) 避免输出文件被 root 持有。
#
# 构建：docker build -t bioskills/ultra:0.1-v1.0 -f Dockerfile .
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data bioskills/ultra:0.1-v1.0 align ...
# ---------------------------------------------------------------------------

FROM debian:bookworm-slim

LABEL maintainer="bioskills"
LABEL software="ultra"
LABEL version="0.1-v1.0"
LABEL ultra_bioinformatics_version="0.1"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt 运行时（python3 驱动 SkillBase；curl/bzip2 仅用于 micromamba 引导，末尾 purge）
# 2) micromamba 引导 -> /opt/conda（无 miniconda），安装 ultra_bioinformatics=0.1 全家桶
# 3) 版本断言 + 清理四连
RUN set -eux; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        bzip2 \
        procps \
        tini \
        python3-minimal \
        python3 \
        python3-yaml; \
    # ---- micromamba 引导（禁止 miniconda）---- \
    curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj -C /tmp bin/micromamba; \
    /tmp/bin/micromamba create -y -p /opt/conda -c conda-forge -c bioconda \
        python=3.11 \
        ultra_bioinformatics=0.1 \
        minimap2 \
        namfinder \
        samtools \
        pyyaml; \
    # ---- 版本断言：uLTRA 必须为 0.1，且依赖二进制在 PATH 可解析 ---- \
    /tmp/bin/micromamba list -p /opt/conda | grep -E '^ultra_bioinformatics[[:space:]]+0\.1'; \
    /opt/conda/bin/uLTRA --version >/dev/null 2>&1; \
    /opt/conda/bin/samtools --version | head -n1; \
    /opt/conda/bin/minimap2 --version >/dev/null 2>&1; \
    /opt/conda/bin/namfinder --help >/dev/null 2>&1 || true; \
    # 去掉引导临时文件与 conda 包缓存
    rm -rf /tmp/bin /tmp/pkgs /opt/conda/pkgs; \
    # ---- 清理四连（缺一不可）---- \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false curl bzip2; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/locale/* /var/cache/debconf/*; \
    ln -sf /usr/bin/python3 /usr/bin/python

# 2) 拷贝 native 驱动到 /opt/skill
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

ENV PYTHONPATH=/opt/skill \
    PATH=/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /data

# ENTRYPOINT tini：负责正确收割僵尸进程 + 转发信号
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/skill/main.py"]
