# go_class native Docker 镜像配方（自建兜底：bookworm-slim + apt perl 运行时 + 用户自备 go_class.tar.gz）
# ---------------------------------------------------------------------------
# 路线说明（AGENT.md §7 自建兜底）：GO class 不在 bioconda / quay.io/biocontainers /
# depot.galaxyproject.org（2026-09 核实均无），Debian bookworm 亦无该包；分发介质为本地
# tar 包（go_class.tar.gz）、无官方下载页。本配方不伪造下载链接，构建时须由用户提供
# 自备 tar 包：
#   docker build --build-arg GO_CLASS_URL=https://<your-mirror>/go_class.tar.gz \
#       -t bioskills/go_class:latest modules/go_class/native
#
# 运行：go_class 为 Perl 脚本集（无统一二进制），镜像为「工具箱」；
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       bioskills/go_class:latest annot2wego.pl go.annot > go.wego
#   （PATH 已含 /opt/go_class/bin 与 /opt/go_class/svg，可直接按脚本名调用）
# ⚠️ make_go_class_config.pl 需 go.obo（用户提供）：可挂载后在容器内运行初始化配置。
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG GO_CLASS_URL=

LABEL maintainer="bioskills"
LABEL software="go_class"
LABEL version="latest-v1.0"
LABEL go_class_version="unversioned"
LABEL pkg_route="apt(perl runtime) + user-provided go_class tarball -> /opt/go_class"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/tmp \
    GO_CLASS_HOME=/opt/go_class \
    PATH=/opt/go_class/bin:/opt/go_class/svg:/usr/local/bin:/usr/bin:/bin

# 1) apt 最小运行时（Perl；curl 仅用于构建，稍后删除）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        perl \
        ca-certificates \
        procps \
        curl \
    ; \
    mkdir -p /opt/go_class

# 2) 部署用户自备的 go_class tar 包（GO_CLASS_URL 必填，无官方下载页）
RUN set -eux; \
    test -n "${GO_CLASS_URL}" || { \
        echo "需 --build-arg GO_CLASS_URL=<自备 go_class.tar.gz>（本地 tar 包，无官方下载页）" >&2; \
        exit 1; \
    }; \
    curl -fL "${GO_CLASS_URL}" -o /tmp/go_class.tar.gz; \
    tar -xzf /tmp/go_class.tar.gz -C /opt/go_class --strip-components=1; \
    test -f /opt/go_class/bin/make_go_class_config.pl; \
    test -f /opt/go_class/bin/annot2wego.pl; \
    test -f /opt/go_class/bin/get_Genes_From_GO.pl; \
    test -f /opt/go_class/bin/go_svg.pl; \
    chmod +x /opt/go_class/bin/*.pl; \
    chmod +x /opt/go_class/svg/*.pl 2>/dev/null || true

# 3) 清理四连 + 删构建期 curl
RUN set -eux; \
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /usr/bin/curl

WORKDIR /data

# 脚本集无统一二进制（kent 式工具箱）：不设 ENTRYPOINT，默认 shell；
# 用法：docker run ... bioskills/go_class:latest annot2wego.pl <args>
CMD ["/bin/bash"]
