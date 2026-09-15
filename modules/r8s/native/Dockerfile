# r8s native Docker 镜像配方（自建兜底：官方渠道全无 → apt 构建依赖 + 官方源码 make）
# ---------------------------------------------------------------------------
# 背景：r8s 1.81 无任何官方 conda/容器渠道（2026-09 核实 bioconda
#       https://api.anaconda.org/package/bioconda/r8s 404、bioconda-recipes recipes/r8s 404、
#       quay.io/biocontainers/r8s 仓库不存在、depot.galaxyproject.org/singularity/r8s 404），
#       官方发布源为 SourceForge（r8s1.81.tar.gz，2026-09 核实 200）。
#       因此走「debian:bookworm-slim + apt 构建依赖（gfortran/gcc/make）+ 官方源码 make」。
# 版本：r8s 1.81（r8s -v -b 打印 "r8s version 1.81"，以退出码 1 结束属正常），与 meta
#       software_versions.native 对齐。
# 说明：r8s 为 Fortran/C 混合；旧 makefile 依赖 /usr/include/*.h（仅 macOS 需去依赖，此处一并
#       去除以保证可移植），gfortran 10+ 对旧 Fortran 实参不匹配需 -fallow-argument-mismatch，
#       旧 C 代码需 -fcommon。r8s 运行期依赖 libgfortran5，故保留编译工具链避免 autoremove 误删
#       （如需极致瘦身可另做 multi-stage 拷贝 r8s + libgfortran*）。
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/r8s:1.81 -f modules/r8s/native/Dockerfile modules/
# 运行（ENTRYPOINT 为 r8s；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/r8s:1.81 -b -f r8s_in.txt
# 驱动 main.py：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /usr/bin/python3 bioskills/r8s:1.81 /opt/skill/main.py run /data/r8s_in.txt
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG R8S_VERSION=1.81
ARG R8S_TARBALL_URL=https://downloads.sourceforge.net/project/r8s/r8s1.81.tar.gz
ARG R8S_TARBALL_SHA256=9e89d7851d74d74487d147b77177a717e6c659b485c9b67f516340a6ed595080

LABEL maintainer="bioskills"
LABEL software="r8s"
LABEL r8s_version="${R8S_VERSION}"
LABEL org.bioskills.software="r8s"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt build deps (gfortran/gcc/make) + official sourceforge tarball source (make)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt 最小依赖：构建（gfortran/gcc/make/libc6-dev）+ 运行（python3/python3-yaml 供 /opt/skill/main.py 驱动）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        gfortran \
        gcc \
        make \
        libc6-dev \
        ca-certificates \
        curl \
        python3 \
        python3-yaml \
        procps \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) 官方源码下载 + sha256 + 补丁 makefile + 源码编译 r8s + 版本断言
RUN set -eux; \
    curl -fSL -o /tmp/r8s.tar.gz "${R8S_TARBALL_URL}"; \
    echo "${R8S_TARBALL_SHA256}  /tmp/r8s.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/src && tar -xzf /tmp/r8s.tar.gz -C /tmp/src; \
    SRC="$(find /tmp/src -mindepth 1 -maxdepth 1 -type d -name 'r8s*' | head -1)"; \
    cd "$SRC/src"; \
    sed -e 's#/usr/include/[^ ]*##g' makefile > makefile.new && mv makefile.new makefile; \
    make CC=gcc FC=gfortran LPATH= CFLAGS="-O2 -w -fcommon" FFLAGS="-fallow-argument-mismatch -w" -j"$(nproc)" r8s; \
    test -x ./r8s; \
    install -m 0755 ./r8s /usr/local/bin/r8s; \
    r8s -v -b 2>&1 | grep -qF "r8s version ${R8S_VERSION}"; \
    rm -rf /tmp/src /tmp/r8s.tar.gz

# 3) 拷贝驱动层（context=modules/）：base.py + main.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY r8s/native/main.py /opt/skill/main.py
COPY r8s/meta.yaml /opt/skill/r8s/meta.yaml
COPY r8s/native/test/ /opt/skill/test/
RUN /usr/bin/python3 /opt/skill/main.py --list-commands >/tmp/r8s_commands.txt \
    && grep -q '^run' /tmp/r8s_commands.txt \
    && grep -q '^version' /tmp/r8s_commands.txt \
    && /usr/bin/python3 /opt/skill/main.py --schema >/tmp/r8s_schema.json \
    && test -s /tmp/r8s_schema.json \
    && rm -f /tmp/r8s_commands.txt /tmp/r8s_schema.json

# 4) 清理四连（构建期下载用 curl 移除；编译工具链保留，避免 autoremove 误删 libgfortran5）
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
    PATH=/usr/local/bin:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体即 r8s 二进制
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/r8s"]
CMD ["-v", "-b"]
