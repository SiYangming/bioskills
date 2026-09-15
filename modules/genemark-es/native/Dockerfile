# =============================================================================
# genemark-es native Docker 镜像配方（自建兜底路线）
# ---------------------------------------------------------------------------
# 路线：GeneMark-ES/ET 官方渠道全无（2026-09-11 核实：bioconda 404、quay 未找到、
#   depot.galaxyproject.org 无 genemark*），且官方许可禁止再分发软件包与密钥，
#   因此本配方采用 debian:bookworm-slim + apt 最小化 + **用户自备官方 gmes 包**：
#   构建前请把在官网同意许可后下载的 gmes_linux_64_*.tar.gz 放到本目录（构建上下文），
#   默认文件名 gmes_linux_64_4.tar.gz（可用 --build-arg GMES_TARBALL=... 覆盖）。
#
# 许可与密钥：运行需 ~/.gm_key（官网申请 gm_key_64.gz 后 gzip -dc ... > ~/.gm_key），
#   运行期以 -v 挂载到容器用户 HOME（见下方 docker run 示例）。
#
# 官方来源：
#   homepage : http://topaz.gatech.edu/GeneMark/（现 https://exon.gatech.edu/GeneMark/）
#   download : http://topaz.gatech.edu/GeneMark/license_download.cgi
#
# 构建：
#   cp ~/Downloads/gmes_linux_64_4.tar.gz modules/genemark-es/native/
#   docker build -t bioskills/genemark-es:4.72-v1.0 modules/genemark-es/native
#
# 运行提示（重要）：产物需归宿主用户，必须挂载宿主目录 + 指定宿主用户：
#   docker run --rm -u $(id -u):$(id -g) -v ~/.gm_key:/opt/gmkey -v $PWD:/data -w /data \
#       -e HOME=/tmp -e GM_KEY_PATH=/opt/gmkey \
#       bioskills/genemark-es:4.72-v1.0 \
#       es /data/genome.fasta --fungus --threads 8
# =============================================================================
FROM debian:bookworm-slim

LABEL maintainer="bioskills"
LABEL software="genemark-es"
LABEL version="4.72-v1.0"
LABEL genemark_es_version="4.72_lic"
LABEL pkg_route="apt(minimal) + user-provided official gmes tarball (license-gated; no official bioconda/quay/depot)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp \
    GENEMARK_PATH=/opt/gmes

# 1) apt 最小化：perl 运行时 + GeneMark 所需 CPAN 模块的 Debian 包 + tini/procps/python3
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        perl \
        libyaml-perl \
        libhash-merge-perl \
        liblogger-simple-perl \
        libparallel-forkmanager-perl \
        python3-minimal \
        python3 \
        ca-certificates \
        procps \
        tini \
    ; \
    ln -sf /usr/bin/python3 /usr/bin/python

# 2) 官方 gmes 包（用户自备，许可禁止再分发）：解压到 /opt/gmes 并软链入口脚本
ARG GMES_TARBALL=gmes_linux_64_4.tar.gz
COPY ${GMES_TARBALL} /tmp/gmes.tar.gz
RUN set -eux; \
    mkdir -p /opt/gmes; \
    tar -xzf /tmp/gmes.tar.gz -C /opt/gmes --strip-components=1; \
    test -f /opt/gmes/gmes_petap.pl; \
    ln -sf /opt/gmes/gmes_petap.pl /usr/local/bin/gmes_petap.pl; \
    ln -sf /opt/gmes/hints2genemarkETintron.pl /usr/local/bin/hints2genemarkETintron.pl; \
    rm -f /tmp/gmes.tar.gz

# 3) 拷贝 native 驱动
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

ENV PYTHONPATH=/opt/skill

# 4) 清理四连 + 结构/入口断言（gmes_petap.pl 无 --version，改为入口存在性断言）
RUN set -eux; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/locale/* \
           /var/cache/debconf/* /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    command -v gmes_petap.pl; \
    test -f /opt/gmes/gmes_petap.pl

WORKDIR /data

# ENTRYPOINT tini：正确收割僵尸进程 + 转发信号
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/skill/main.py"]
