# ontologizer native Docker 镜像配方（自建兜底：bookworm-slim + apt openjdk 运行时 + 官方公开 jar）
# ---------------------------------------------------------------------------
# 路线说明（AGENT.md §7 自建兜底）：Ontologizer 不在 bioconda / quay.io/biocontainers /
# depot.galaxyproject.org（2026-09 核实均无），Debian bookworm 亦无该包。官方以公开 GPL jar
# 分发（非许可受限），构建期从官网直拉：
#   Ontologizer.jar      http://ontologizer.de/cmdline/Ontologizer.jar   （2.1，200）
#   OntologizerGui.jar   http://ontologizer.de/gui/OntologizerGui.jar    （200）
# 🚫 不使用 miniconda/micromamba（无 conda 包）。
#
# 运行：镜像为「Ontologizer 命令行容器」（ENTRYPOINT=java -jar Ontologizer.jar）；
#       native/main.py 驱动在宿主机运行，不随镜像分发。
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/ontologizer:2.1 -g go.obo -a gene_association.gaf -s study.list -p pop.list -o /data
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG ONTOLOGIZER_JAR_URL=http://ontologizer.de/cmdline/Ontologizer.jar
ARG ONTOLOGIZER_GUI_JAR_URL=http://ontologizer.de/gui/OntologizerGui.jar

LABEL maintainer="bioskills"
LABEL software="ontologizer"
LABEL version="2.1-v1.0"
LABEL ontologizer_version="2.1"
LABEL pkg_route="apt(openjdk-17-jre-headless) + official public Ontologizer.jar -> /opt/ontologizer"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp \
    JAVA_TOOL_OPTIONS="-Xmx6g -Djava.io.tmpdir=/tmp"

# 1) apt 最小运行时（JRE headless + tini；curl 仅用于构建，稍后删除）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless \
        ca-certificates \
        procps \
        tini \
        curl \
    ; \
    mkdir -p /opt/ontologizer

# 2) 下载官方公开 jar（GPL，非许可受限）
RUN set -eux; \
    curl -fL "${ONTOLOGIZER_JAR_URL}" -o /opt/ontologizer/Ontologizer.jar; \
    curl -fL "${ONTOLOGIZER_GUI_JAR_URL}" -o /opt/ontologizer/OntologizerGui.jar; \
    java -jar /opt/ontologizer/Ontologizer.jar -v

# 3) 清理四连 + 删构建期 curl
RUN set -eux; \
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /usr/bin/curl

WORKDIR /data

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体即 Ontologizer 命令行 jar
ENTRYPOINT ["/usr/bin/tini", "--", "java", "-jar", "/opt/ontologizer/Ontologizer.jar"]
CMD ["-h"]
