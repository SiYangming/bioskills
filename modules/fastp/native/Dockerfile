# fastp native Docker 镜像配方（bookworm-slim + micromamba 引导 bioconda env）
# ---------------------------------------------------------------------------
# 路线说明：fastp 不在 Debian bookworm apt 源，因此采用
#   "apt 装最小运行时（python3/procps/tini）+ curl 拉 micromamba 静态二进制，
#    用 environment.yml 构建 bioconda env 到 /opt/env"。
# 不使用 miniconda（镜像更大、启动更慢、HPC 解析延迟）。
#
# 运行提示（重要）：fastp 会向工作目录写输出文件，容器内默认是 root，
# 因此 Docker 运行必须挂载宿主目录并指定宿主用户，否则产物归 root 所有：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/fastp:0.24.0-v1.0 \
#       run -i R1.fq.gz -I R2.fq.gz -o clean_R1.fq.gz -O clean_R2.fq.gz -h r.html -j r.json
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

LABEL maintainer="bioskills"
LABEL software="fastp"
LABEL version="0.24.0-v1.0"
LABEL fastp_version="0.24.0"
LABEL pkg_route="apt(runtime) + micromamba(bioconda fastp=0.24.0 -> /opt/env)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp \
    MAMBA_ROOT_PREFIX=/opt/micromamba \
    PATH=/opt/env/bin:$PATH

# 1) apt 最小运行时（curl 仅用于构建，稍后删除）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3-minimal \
        python3 \
        ca-certificates \
        procps \
        tini \
        curl \
    ; \
    ln -sf /usr/bin/python3 /usr/bin/python

# 2) micromamba 静态二进制（官方 micro.mamba.pm 分发）
RUN set -eux; \
    mkdir -p /opt/micromamba; \
    curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
        | tar -xvj -C /opt/micromamba bin/micromamba; \
    /opt/micromamba/bin/micromamba --version

# 3) 用 environment.yml 构建 /opt/env（bioconda fastp=0.24.0）
COPY environment.yml /opt/environment.yml
RUN set -eux; \
    /opt/micromamba/bin/micromamba create -y -p /opt/env -f /opt/environment.yml; \
    /opt/env/bin/fastp --version; \
    /opt/env/bin/python -c "import yaml; print('pyyaml ok')"

# 4) 拷贝 native 驱动
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

ENV PYTHONPATH=/opt/skill

# 5) 清理四连 + 删构建期 curl 与 micromamba 下载缓存
RUN set -eux; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /usr/bin/curl; \
    rm -rf /opt/micromamba/pkgs; \
    # 版本断言：env 中 fastp 必须停在 0.24.0，防止未来镜像 tag 漂移
    /opt/env/bin/fastp --version 2>&1 | grep -q '0\.24\.0'

WORKDIR /data

# ENTRYPOINT tini：负责正确收割僵尸进程 + 转发信号
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/skill/main.py"]
