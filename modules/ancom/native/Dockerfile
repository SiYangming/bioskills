# ancom 自建容器（native/Dockerfile）
#
# 路线：原始 ANCOM 无官方镜像（bioconda/quay.io/biocontainers/depot.galaxyproject.org 均无 ancom，
#       2026-09 核实）→ 走自建兜底。debian:bookworm-slim + apt 最小化装 R 运行时与依赖
#       （r-base-core + r-cran-nlme/r-cran-tidyverse/r-cran-compositions 均在 bookworm apt 源），
#       再布署 ANCOM 源码归档到 /opt/ANCOM。
#       后继实现 ANCOM-BC 有官方渠道（quay.io/biocontainers/bioconductor-ancombc:2.14.0--r45hdfd78af_0）。
# 构建：
#   docker build -t ancom:2.1 .
# 运行（等价能力由 native/main.py analyze 子命令提供；务必加 -u $(id -u):$(id -g)）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       ancom:2.1 Rscript /opt/skill/run_ancom.R /data/params.tsv

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TMPDIR=/tmp \
    ANCOM_HOME=/opt/ANCOM

RUN set -eux; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends \
        r-base-core r-cran-nlme r-cran-tidyverse r-cran-compositions \
        ca-certificates curl procps; \
    curl -fsSL --retry 3 -o /tmp/ancom.tar.gz \
        https://github.com/FrederickHuangLin/ANCOM-Code-Archive/archive/refs/heads/master.tar.gz; \
    mkdir -p /opt/ANCOM; \
    tar -xzf /tmp/ancom.tar.gz -C /tmp; \
    cp -R /tmp/ANCOM-Code-Archive-master/. /opt/ANCOM/; \
    Rscript -e 'source(file.path(Sys.getenv("ANCOM_HOME"), "programs", "ancom.R")); stopifnot(exists("ANCOM"))'; \
    apt-get purge -y --auto-remove curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* /usr/share/man/* /usr/share/info/*

COPY run_ancom.R /opt/skill/run_ancom.R
RUN chmod +x /opt/skill/run_ancom.R

WORKDIR /data

CMD ["Rscript"]
