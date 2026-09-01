# td2 native Docker 镜像配方（bookworm-slim + micromamba 引导 bioconda env）
# ---------------------------------------------------------------------------
# 路线说明：td2 不在 Debian bookworm apt 源，因此采用
#   "apt 装最小运行时（python3/procps/tini）+ curl 拉 micromamba 静态二进制，
#    用 environment.yml 构建 bioconda env 到 /opt/env"。
# 不使用 miniconda（镜像更大、启动更慢、HPC 解析延迟）。
#
# 运行提示（重要）：TD2 会向工作目录写文件，容器内默认是 root，
# 因此 Docker 运行必须挂载宿主目录并指定宿主用户，否则产物归 root 所有：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/td2:1.0.6-v1.0 \
#       longorfs -t transcripts.fa -O out --strand-specific
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

LABEL maintainer="bioskills"
LABEL software="td2"
LABEL version="1.0.6-v1.0"
LABEL td2_version="1.0.6"
LABEL pkg_route="apt(runtime) + micromamba(bioconda td2=1.0.6 -> /opt/env)"

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

# 3) 用 environment.yml 构建 /opt/env（bioconda td2=1.0.6）
COPY environment.yml /opt/environment.yml
RUN set -eux; \
    /opt/micromamba/bin/micromamba create -y -p /opt/env -f /opt/environment.yml; \
    /opt/env/bin/TD2.LongOrfs --version; \
    /opt/env/bin/TD2.Predict --version; \
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
    # 版本断言：env 中 td2 必须停在 1.0.6，防止未来镜像 tag 漂移
    /opt/env/bin/TD2.Predict --version | grep -q '1\.0\.6'

WORKDIR /data

# ENTRYPOINT tini：负责正确收割僵尸进程 + 转发信号
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/skill/main.py"]
