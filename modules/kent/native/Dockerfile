# kent native Docker 镜像配方（自建兜底：bioconda/quay/depot 无 kent 整体包）
# 底座：Debian 12 bookworm-slim
# 安装：apt 只装运行时（zlib/openssl/png/mariadb/gsl/curl 等）+ 官方 UCSC 预编译二进制
#       （hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/<tool>）布署到 /opt/kent/bin
# 清理：apt lists / docs / man / cache + 构建期 curl
#
# 构建：docker build -t bioskills/kent:jksrc-v330 -f Dockerfile .
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data --entrypoint faToTwoBit bioskills/kent:jksrc-v330 genome.fa genome.2bit
#
# 备注：文档要求源码编译 jksrc v330（用于 GBrowse 的 jkweb.a）；本镜像走官方预编译二进制路线（更轻、免编译），
#       源码编译路线见 README「官方源码编译」。

FROM debian:bookworm-slim

LABEL maintainer="bioskills"
LABEL software="kent"
LABEL version="jksrc-v330"
LABEL pkg_route="apt runtime + UCSC prebuilt binaries (hgdownload.soe.ucsc.edu/admin/exe)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp \
    PATH=/opt/kent/bin:/usr/local/bin:/usr/bin:/bin

# 1) apt 最小运行时依赖 + 官方预编译二进制 + 清理四连
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        procps \
        curl \
        zlib1g \
        libssl3 \
        libpng16-16 \
        libmariadb3 \
        libgsl27 \
        libcurl4 \
        libbz2-1.0 \
        libpq5 \
    ; \
    mkdir -p /opt/kent/bin; \
    for t in faToTwoBit twoBitToFa twoBitInfo blat bedToBigBed bigWigToBedGraph; do \
        curl -fsSL -o "/opt/kent/bin/$t" "https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/$t"; \
        chmod 0755 "/opt/kent/bin/$t"; \
        ln -sf "/opt/kent/bin/$t" "/usr/local/bin/$t"; \
    done; \
    # 功能冒烟：FASTA -> 2bit
    printf '>chr_test\nACGTACGTACGT\n' > /tmp/smoke.fa; \
    /opt/kent/bin/faToTwoBit /tmp/smoke.fa /tmp/smoke.2bit; \
    test -s /tmp/smoke.2bit; \
    rm -f /tmp/smoke.fa /tmp/smoke.2bit; \
    # 仅构建期需要的 curl 移除 + 清理四连
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf \
        /usr/share/doc/* \
        /usr/share/man/* \
        /usr/share/info/* \
        /var/lib/apt/lists/* \
        /var/cache/debconf/* \
        /tmp/* \
        /var/tmp/*

WORKDIR /data

# 多工具镜像：CMD 提供交互 shell；运行指定工具用 `docker run ... <tool> ...`
CMD ["bash"]
