# =============================================================================
# Dockerfile — snogps（自建兜底配方）
#
# 归属   ：bioskills modules/snogps/native/Dockerfile
# 理由   ：官方渠道全无（bioconda snogps 未找到 / quay.io/biocontainers/snogps 401 /
#          depot.galaxyproject.org 404，2026-09 核实）→ 自建 apt 最小化 + 官方源码编译
# 路线   ：debian:bookworm-slim + apt --no-install-recommends（build-essential/curl 仅构建期）
#          + 官方源码 https://trna.ucsc.edu/software/snoGPS-0.2.tar.gz（sha256 内嵌校验）
# 运行   ：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data snogps:0.2 \
#              <sequence.fa> <descriptor>
# =============================================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TMPDIR=/tmp \
    MYPERLMODULEDIR=/opt/snogps/share/perlModules/

ARG SNOGPS_VERSION=0.2
ARG SNOGPS_SRC_URL=https://trna.ucsc.edu/software/snoGPS-0.2.tar.gz
ARG SNOGPS_SHA256=184abd9ca6ce24b34c65ddb24ee445c8d5ecfef1a1315d75055b80a284845027

RUN set -eux; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl perl procps; \
    curl -fsSL -o /tmp/snogps.tar.gz "$SNOGPS_SRC_URL"; \
    echo "$SNOGPS_SHA256  /tmp/snogps.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/snogps; \
    tar -xzf /tmp/snogps.tar.gz -C /opt/snogps --strip-components=1; \
    make -C /opt/snogps/src clean >/dev/null 2>&1 || true; \
    make -C /opt/snogps/src BINDIR=/usr/local/bin; \
    mkdir -p /opt/snogps/share; \
    for d in scripts data desc targs scoretables perlModules; do \
        if [ -d "/opt/snogps/$d" ]; then cp -R "/opt/snogps/$d" /opt/snogps/share/; fi; \
    done; \
    if [ -d /opt/snogps/share/scripts ]; then \
        for sc in /opt/snogps/share/scripts/*.pl; do \
            [ -f "$sc" ] && install -m 0755 "$sc" /usr/local/bin/; \
        done; \
    fi; \
    apt-get purge -y --auto-remove build-essential curl; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 自检：二进制可用且 usage 正常
RUN snoGPS -h 2>&1 | grep -qi usage

WORKDIR /data
ENTRYPOINT ["/usr/local/bin/snoGPS"]
CMD ["-h"]

LABEL org.bioskills.software="snogps" \
      org.bioskills.impl="snogps_native" \
      org.bioskills.base_image="debian:bookworm-slim" \
      org.bioskills.snogps_version="0.2" \
      org.bioskills.pkg_route="apt(build-essential) + 官方源码编译(trna.ucsc.edu/snoGPS-0.2.tar.gz)"
