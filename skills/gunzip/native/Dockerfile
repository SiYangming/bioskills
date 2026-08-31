# ---------------------------------------------------------------------------
# bioskills / gunzip native Dockerfile
# Route: Debian bookworm-slim + apt（APT 路线）
#   安装 gzip=1.12-1（Debian bookworm stable）+ python3 运行驱动。
# 目标：无 miniconda、仅保留运行必需、apt 立即清理，保持镜像最小。
# 运行时要求：docker run -u $(id -u):$(id -g) 避免输出文件被 root 持有。
#
# 构建：docker build -t bioskills/gunzip:1.12-v1.0 -f Dockerfile .
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data bioskills/gunzip:1.12-v1.0 gunzip /data/in.fa.gz -o /data/in.fa
# ---------------------------------------------------------------------------

FROM debian:bookworm-slim

LABEL maintainer="bioskills"
LABEL software="gunzip"
LABEL version="1.12-v1.0"
LABEL gzip_apt_version="1.12-1"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt 最小化安装 + 版本断言 + 清理四连
RUN set -eux; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends \
        gzip=1.12-1 \
        python3-minimal \
        python3 \
        python3-yaml \
        ca-certificates \
        tini \
        procps \
    ; \
    # 仅保留运行必需：python3 提供标准库；base.py 需要 python3-yaml
    # 清理文档、手册、locale、apt 缓存、临时文件（清理四连：autoremove/clean/lists/tmp）
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
    # 顺手把 /usr/bin/python 指到 python3
    ln -sf /usr/bin/python3 /usr/bin/python; \
    # 版本断言：避免 bookworm-upgrades 把 gzip 推到更新版
    dpkg -l | awk '$2=="gzip"{print $3}' | grep -Eq '^1\.12(-|$)'

# 2) 拷贝 native 驱动到 /opt/skill
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

ENV PYTHONPATH=/opt/skill \
    PATH=/opt/skill:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割僵尸进程 + 转发信号
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/skill/main.py"]
