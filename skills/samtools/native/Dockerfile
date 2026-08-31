# samtools native Docker 镜像配方（apt 最小化版本）
# 底座：Debian 12 bookworm-slim
# 安装：samtools=1.21-1（Debian bookworm stable 官方 apt 源版本）+ python3 运行驱动
# 清理：apt lists / docs / man / cache，尽力保持镜像尺寸
#
# 构建：docker build -t bioskills/samtools:1.21-v1.0 -f Dockerfile .
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data bioskills/samtools:1.21-v1.0 ...

FROM debian:bookworm-slim AS build

LABEL maintainer="bioskills"
LABEL software="samtools"
LABEL version="1.21-v1.0"
LABEL samtools_apt_version="1.21-1"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt install + 硬删 docs/man/apt cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        samtools=1.21-1 \
        python3-minimal \
        python3 \
        ca-certificates \
        tini \
        procps \
    ; \
    # 仅保留运行必需：python3 提供标准库；base.py / main.py 无第三方 pip 依赖
    # 清理文档、手册、locale、apt 缓存、临时文件
    rm -rf \
        /usr/share/doc/* \
        /usr/share/man/* \
        /usr/share/info/* \
        /usr/share/locale/* \
        /var/cache/debconf/* \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/*; \
    # 顺手把 /usr/bin/python 指到 python3
    ln -sf /usr/bin/python3 /usr/bin/python; \
    # 版本断言：避免 bookworm-upgrades 把 samtools 推到更新版
    dpkg -l | awk '$2=="samtools"{print $3}' | grep -Eq '^1\.21(-|$)'

# 2) 拷贝 native 驱动到 /opt/skill
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

ENV PYTHONPATH=/opt/skill \
    PATH=/opt/skill:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割僵尸进程 + 转发信号
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/skill/main.py"]
