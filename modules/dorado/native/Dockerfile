# dorado native Docker 镜像配方（bookworm-slim + 官方二进制下载路线）
# ---------------------------------------------------------------------------
# 路线说明：dorado 不在 Debian bookworm apt、也不在 bioconda，官方只发布
# Linux x64 静态二进制 tar.gz。因此采用：
#   "apt 装最小运行时（python3/procps/tini）+ curl 下载官方 dorado tar.gz 到 /opt/dorado，
#    软链 bin/dorado 到 /usr/local/bin"。
# 不使用 miniconda / micromamba（dorado 无 conda 包）。
#
# 版本：默认 ARG DORADO_VERSION=0.9.1（示例 pin），构建时可用
#   --build-arg DORADO_VERSION=<release> 覆盖；保持 "latest" 语义由用户指定。
# 官方发布页：https://github.com/nanoporetech/dorado/releases
#
# 运行提示（重要）：dorado basecaller 需要模型目录（--model），首次运行会自动下载；
# 模型文件较大，建议挂载宿主机模型缓存目录。产物归 root 的问题：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/dorado:latest-v1.0 \
#       basecall rna004_130bps_sup@v5.1.0 pod5/ --output-dir out --emit-fastq
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG DORADO_VERSION=0.9.1

LABEL maintainer="bioskills"
LABEL software="dorado"
LABEL version="latest-v1.0"
LABEL dorado_version="${DORADO_VERSION}"
LABEL pkg_route="apt(runtime) + official dorado binary (cdn.oxfordnanoportal.com) -> /opt/dorado"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt 最小运行时（curl 仅用于构建，稍后删除）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3-minimal \
        python3 \
        ca-certificates \
        procps \
        tini \
        curl \
    ; \
    ln -sf /usr/bin/python3 /usr/bin/python

# 2) 下载官方 dorado 静态二进制（含 GPU 版 CUDA libs；CPU 推断可用 --device cpu）
RUN set -eux; \
    mkdir -p /opt/dorado; \
    curl -Ls "https://cdn.oxfordnanoportal.com/software/analysis/dorado-${DORADO_VERSION}-linux-x64.tar.gz" \
        | tar -xz -C /opt/dorado --strip-components=1; \
    chmod +x /opt/dorado/bin/dorado; \
    ln -sf /opt/dorado/bin/dorado /usr/local/bin/dorado; \
    /usr/local/bin/dorado --version

# 3) 拷贝 native 驱动
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

ENV PYTHONPATH=/opt/skill

# 4) 清理四连 + 删构建期 curl
RUN set -eux; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /usr/bin/curl

WORKDIR /data

# ENTRYPOINT tini：负责正确收割僵尸进程 + 转发信号
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/skill/main.py"]
