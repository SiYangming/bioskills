# prottest native Docker 镜像配方（自建兜底：apt 最小化 + 官方预编译 Java 包，禁 miniconda）
# ---------------------------------------------------------------------------
# 背景：ProtTest3 3.4.2 无任何官方 conda/容器渠道（2026-09 核实 bioconda
#       https://api.anaconda.org/package/bioconda/prottest 404、quay.io/biocontainers/prottest
#       无仓库、depot.galaxyproject.org/singularity/prottest 404），官方以 GitHub release
#       预编译 Java 包 + 源码归档分发。因此走「debian:bookworm-slim + apt openjdk-17-jre-headless
#       + 官方预编译 tarball」自建路线。
# 来源：https://github.com/ddarriba/prottest3/releases/download/3.4.2-release/prottest-3.4.2-20160508.tar.gz
#       （2026-09 核实 200，sha256 已内嵌；tar 内 jar 名 prottest-3.4.2.jar）
# 版本：ProtTest3 3.4.2（java -jar prottest-3.4.2.jar -h 用法行含 3.4.2），与 meta software_versions.native 对齐。
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/prottest:3.4.2 -f modules/prottest/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 prottest 包装脚本；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/prottest:3.4.2 run aln.phy -all-distributions -F -AIC -BIC -tc 0.5 -threads 4 -o prottest.out
# 驱动 main.py（python 入口，镜像内 base.py + 软件级 meta 已就位）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/prottest:3.4.2 \
#       /opt/skill/main.py run /data/aln.phy -o /data/prottest.out
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG PROTTEST_VERSION=3.4.2
ARG PROTTEST_TARBALL_NAME=prottest-3.4.2-20160508.tar.gz
ARG PROTTEST_TARBALL_URL=https://github.com/ddarriba/prottest3/releases/download/3.4.2-release/prottest-3.4.2-20160508.tar.gz
ARG PROTTEST_TARBALL_SHA256=d5afd55972e5b9903942eab4f0273f9614848bf4b6747a7839d3c675dc9067e6

LABEL maintainer="bioskills"
LABEL software="prottest"
LABEL prottest_version="${PROTTEST_VERSION}"
LABEL org.bioskills.software="prottest"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt openjdk-17-jre-headless + official prebuilt tarball (java -jar)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp \
    JAVA_TOOL_OPTIONS="-Xmx8g -Djava.io.tmpdir=/tmp"

# 1) apt 最小依赖：运行（openjdk-17-jre-headless）+ 驱动（python3/python3-yaml）+ 构建期 curl
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless \
        ca-certificates \
        curl \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方预编译包下载 + sha256 + 解压布署 + 包装脚本 + 版本断言
RUN set -eux; \
    curl -fSL -o "/tmp/${PROTTEST_TARBALL_NAME}" "${PROTTEST_TARBALL_URL}"; \
    echo "${PROTTEST_TARBALL_SHA256}  /tmp/${PROTTEST_TARBALL_NAME}" | sha256sum -c -; \
    mkdir -p /opt/prottest-3.4.2; \
    tar -xzf "/tmp/${PROTTEST_TARBALL_NAME}" -C /opt/prottest-3.4.2 --strip-components=1; \
    test -f "/opt/prottest-3.4.2/prottest-${PROTTEST_VERSION}.jar"; \
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'export PROTTEST_HOME=/opt/prottest-3.4.2' \
        'exec java ${JAVA_OPTS:-} -jar /opt/prottest-3.4.2/prottest-'"${PROTTEST_VERSION}"'.jar "$@"' \
        > /usr/local/bin/prottest; \
    chmod 0755 /usr/local/bin/prottest; \
    java -jar /opt/prottest-3.4.2/prottest-${PROTTEST_VERSION}.jar -h 2>&1 | grep -q "${PROTTEST_VERSION}"; \
    rm -rf /tmp/*

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY prottest/native/main.py /opt/skill/main.py
COPY prottest/meta.yaml /opt/skill/prottest/meta.yaml
COPY prottest/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/pt_commands.txt \
    && grep -q '^run' /tmp/pt_commands.txt \
    && grep -q '^hpc' /tmp/pt_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/pt_schema.json \
    && test -s /tmp/pt_schema.json \
    && rm -f /tmp/pt_commands.txt /tmp/pt_schema.json

# 4) 清理四连（构建期下载工具 curl 移除）
RUN set -eux; \
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
        /var/tmp/*

ENV PYTHONPATH=/opt/skill \
    PROTTEST_HOME=/opt/prottest-3.4.2 \
    PATH=/usr/local/bin:$PATH

WORKDIR /data

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/prottest"]
CMD ["-h"]
