# syntax=docker/dockerfile:1
# =============================================================================
# ampliconnoise native 自建容器配方（无官方镜像，apt 最小化 + 官方归档源码 MPI 编译）
#
# 路线判定（2026-09 核实）：AmpliconNoise（V1.27，454 时代去噪/嵌合体检测，Quince et al. 2011）
#   bioconda api.anaconda.org/package/bioconda/ampliconnoise → 404；quay.io/biocontainers/ampliconnoise → 无；
#   depot.galaxyproject.org → 无。原 Google Code 站 code.google.com/p/ampliconnoise 已死（curl 000），
#   但 Google Code 归档发布包可达（HTTP 200）→ 自建兜底：
#   debian:bookworm-slim + apt --no-install-recommends（build-essential + mpich）+ 官方归档源码
#   make && make install。各程序为 MPI 程序，依赖 mpicc/mpirun。不使用 miniconda。
#
# 构建：docker build -t bioskills/ampliconnoise:1.27 native/
# 运行（必须 -u $(id -u):$(id -g)；AmpliconNoise 为 MPI 程序，用 mpirun 启动）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/ampliconnoise:1.27 \
#       mpirun -np 4 PyroNoise -s /data/reads.sff -d /opt/ampliconnoise-1.27/Data -o /data/out
# =============================================================================
FROM debian:bookworm-slim

LABEL maintainer="bioskills" \
      org.bioskills.software="ampliconnoise" \
      org.bioskills.impl="native" \
      org.bioskills.base_image="debian:bookworm-slim" \
      org.bioskills.ampliconnoise_version="1.27" \
      org.bioskills.pkg_route="apt(build-essential+mpich) + Google Code 归档源码 make"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp \
    PATH=/opt/ampliconnoise-1.27/bin:$PATH

ARG AMPLICONNOISE_VERSION=1.27
ARG AM_URL="https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/ampliconnoise/AmpliconNoiseV${AMPLICONNOISE_VERSION}.tar.gz"

# 1) apt 最小构建依赖（curl 仅构建用，稍后删除；mpich 提供 mpicc 与 mpirun）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        mpich \
        ca-certificates \
        procps \
        tini \
        curl \
    ;

# 2) 官方 Google Code 归档源码 -> make && make install（bin/ 在源码目录内）
RUN set -eux; \
    curl -fsSL -o /tmp/ampliconnoise.tar.gz "${AM_URL}"; \
    tar -xzf /tmp/ampliconnoise.tar.gz -C /opt; \
    rm -f /tmp/ampliconnoise.tar.gz; \
    mv "/opt/AmpliconNoiseV${AMPLICONNOISE_VERSION}" /opt/ampliconnoise-1.27; \
    cd /opt/ampliconnoise-1.27; \
    make; \
    make install; \
    test -x /opt/ampliconnoise-1.27/bin/PyroNoise; \
    test -f /opt/ampliconnoise-1.27/Data/LookUp.dat

# 3) 清理四连 + 删构建期 curl / build-essential（保留 mpich 运行时 mpirun）
RUN set -eux; \
    apt-get purge -y curl build-essential; \
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

# 4) 构建期断言：程序可执行 + 归档版本目录 + Data 资源齐备（AmpliconNoise 无 --version 旗标）
RUN set -eux; \
    ls /opt/ampliconnoise-1.27/bin; \
    test -x /opt/ampliconnoise-1.27/bin/PyroNoise; \
    test -x /opt/ampliconnoise-1.27/bin/PerseusD; \
    test -f /opt/ampliconnoise-1.27/Data/LookUp.dat

WORKDIR /data

# 不创建固定账号：运行时用 -u $(id -u):$(id -g) 接管（避免 HPC UID 冲突 / 产物归 root）
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["PyroNoise"]
