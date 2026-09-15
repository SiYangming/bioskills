# =============================================================================
# Blast2GO / b2g4pipe 自建镜像（官方渠道无 Blast2GO 镜像 → 兜底配方）
#
# 路线：apt 最小化优先（debian:bookworm-slim + apt --no-install-recommends + 清理四连）。
#   Blast2GO 无 conda 包（bioconda 404）/ 无 quay / 无 depot，故不引入 conda 兜底，
#   仅安装 Java 运行时（openjdk-17-jre-headless）与 perl（注释库脚本）。
#
# ⚠️ Blast2GO 许可受限（需在官网注册/订阅获取发行包，无公开直链、无官方 sha256）。
#    构建前请自备命令行发行包 b2g4pipe_v2.5.zip 并放到本目录（与 Dockerfile 同级）：
#      cp ~/software/b2g4pipe_v2.5.zip modules/blast2go/native/
#    构建示例：
#      docker build -t blast2go:3.3 -f modules/blast2go/native/Dockerfile modules/blast2go/native/
#    运行（必须 -u $(id -u):$(id -g)，避免产物归 root）：
#      docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data blast2go:3.3 \
#          -in /data/nr.xml -out /data/go -annot -dat -annex
#
#    说明：容器仅打包无头命令行 b2g4pipe（B2GAnnotPipe）；Blast2GO 3.3 图形客户端为桌面程序，
#          请用 native/install.sh 在宿主机安装；本地注释库（install_blast2goDB.sh）依赖外部 MySQL。
# =============================================================================
FROM debian:bookworm-slim

ARG B2G4PIPE_ZIP=b2g4pipe_v2.5.zip

ENV DEBIAN_FRONTEND=noninteractive \
    TMPDIR=/tmp \
    B2G4PIPE_HOME=/opt/b2g4pipe \
    JAVA_OPTS="-Xmx6g -Djava.io.tmpdir=/tmp" \
    JAVA_TOOL_OPTIONS="-Xmx6g -Djava.io.tmpdir=/tmp"

# apt 最小化：JRE（无头）+ perl（install_blast2goDB.sh）；unzip 仅构建期用，之后 purge
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless \
        perl \
        ca-certificates \
        procps \
        unzip \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 部署用户自备的 b2g4pipe 发行包（归档可能含顶层 b2g4pipe/ 目录，压平到 /opt/b2g4pipe）
COPY ${B2G4PIPE_ZIP} /tmp/b2g4pipe.zip
RUN set -e; \
    mkdir -p /opt/b2g4pipe /tmp/b2gex; \
    unzip -q /tmp/b2g4pipe.zip -d /tmp/b2gex; \
    if [ -f /tmp/b2gex/b2gPipe.properties ]; then \
        cp -R /tmp/b2gex/. /opt/b2g4pipe/; \
    else \
        d="$(dirname "$(find /tmp/b2gex -maxdepth 2 -name b2gPipe.properties | head -n1)")"; \
        cp -R "$d"/. /opt/b2g4pipe/; \
    fi; \
    rm -rf /tmp/b2gex /tmp/b2g4pipe.zip; \
    test -f /opt/b2g4pipe/b2gPipe.properties; \
    apt-get purge -y --auto-remove unzip; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /data
# 命令行入口：b2g4pipe B2GAnnotPipe（classpath 通配由 JVM 展开）
ENTRYPOINT ["java", "-cp", "/opt/b2g4pipe/*:/opt/b2g4pipe/ext/*", "es.blast2go.prog.B2GAnnotPipe"]
CMD ["--help"]
