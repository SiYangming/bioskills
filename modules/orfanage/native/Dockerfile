# orfanage native Docker 镜像配方（micromamba 路线，Debian bookworm-slim）
# 构建：docker build -t bioskills/orfanage:1.2.0-v1.0 -f Dockerfile .
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data bioskills/orfanage:1.2.0-v1.0 ...

FROM debian:bookworm-slim AS build

LABEL maintainer="bioskills"
LABEL software="orfanage"
LABEL version="1.2.0-v1.0"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp \
    MAMBA_ROOT_PREFIX=/opt/micromamba

# 1) apt 运行时 + micromamba 静态二进制
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl procps tini bzip2 \
    ; \
    curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj -C /usr/local/bin bin/micromamba; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2) 用 environment.yml 建 /opt/env（清理 micromamba pkgs cache）
COPY environment.yml /tmp/environment.yml
RUN micromamba create -y -f /tmp/environment.yml -p /opt/env \
    && micromamba clean -ay; \
    rm -rf /usr/local/bin/micromamba /tmp/environment.yml

ENV PATH=/opt/env/bin:$PATH

# 3) 拷贝 native 驱动
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

WORKDIR /data

ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/opt/skill/main.py"]
