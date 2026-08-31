# ---------------------------------------------------------------------------
# bioskills / fastqc native Dockerfile
# Route: Debian bookworm-slim + apt(openjdk-17 + perl) + Babraham 官方 zip
#   版本与 nf-core/modules / snakemake-wrappers 的 bioconda fastqc=0.12.1 对齐。
# 目标：无 miniconda、仅保留运行必需、apt 立即清理，保持最小镜像。
# 运行时要求：docker run -u $(id -u):$(id -g) 避免文件属主污染。
# ---------------------------------------------------------------------------

FROM debian:bookworm-slim AS base

# apt 最小化安装：openjdk-17-jre-headless 足够跑 fastqc；perl 是 fastqc 启动脚本依赖；
# curl+ca-certificates 在 build 阶段下载官方 zip，build 末尾移除可再节省 ~7MB。
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    JAVA_TOOL_OPTIONS="-Xmx8g -Djava.io.tmpdir=/tmp" \
    FASTQC_VERSION="0.12.1"

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        openjdk-17-jre-headless \
        perl \
        procps \
        unzip \
 # ---- cleanup: 标准 4 连 ----
 && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false curl \
 && apt-get autoremove -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 用 ADD 直接拉 babraham 官方 zip 并解压。ADD 可处理 URL 解压，但对 zip 需手动 unzip；
# 先 curl (已 purge)，用已安装 unzip 处理更稳，再删 zip / 临时文件。
# Buildkit 里 --mount=type=cache 能省流量，但这里为最小兼容写法使用 RUN。
RUN set -eux; \
    curl -fSL "https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v${FASTQC_VERSION}.zip" -o /tmp/fastqc.zip; \
    unzip -q /tmp/fastqc.zip -d /opt; \
    chmod +x /opt/FastQC/fastqc; \
    ln -sf /opt/FastQC/fastqc /usr/local/bin/fastqc; \
    rm -rf /tmp/*

WORKDIR /work

# 用户态友好：默认 root；运行时 -u $(id -u):$(id -g) 会覆盖成调用方 UID，
# 因此这里不创建专用账号（避免 HPC 场景下 UID 冲突导致 HOME 不可写）。
# JAVA 临时目录 /tmp 全局可写；fastqc 输出目录由 docker -v 挂载，
# 配合 -u 参数直接落到宿主机正确属主。

ENTRYPOINT ["/usr/local/bin/fastqc"]
CMD ["--help"]
