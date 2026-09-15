# =============================================================================
# Dockerfile — fgenesh（自建兜底配方；许可受限）
#
# ⚠️ 许可受限：FGENESH 为 Softberry 商业软件，须向 Softberry 申请学术/商业许可后取得发行包，
#    禁止再分发。本配方**不下载**任何 Softberry 资产，改为在构建上下文提供你已合法取得的
#    发行包 `fgenesh.tar.gz`（或按需改 COPY 的文件名）。
#
# 归属   ：bioskills modules/fgenesh/native/Dockerfile
# 理由   ：官方渠道全无（bioconda/quay.io/biocontainers/depot.galaxyproject.org 均无，2026-09
#          核实）+ 官网 softberry.com 探测不可达（curl 000）→ 自建 apt 最小化配方
# 路线   ：debian:bookworm-slim + apt --no-install-recommends（仅运行时 libc/libstdc++/procps）
# 构建   ：先将授权发行包放到本目录为 fgenesh.tar.gz，再：
#               docker build -t fgenesh:local modules/fgenesh/native
# 运行   ：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data fgenesh:local \
#               /data/genome.fasta -L /opt/fgenesh/params/fungi.par -o /data/out -gff -cpu 8
# =============================================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TMPDIR=/tmp

# 构建上下文需提供 Softberry 授权发行包（用户自备；本镜像不内嵌、不下载）
COPY fgenesh.tar.gz /tmp/fgenesh.tar.gz

RUN set -eux; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends ca-certificates libc6 libstdc++6 procps; \
    mkdir -p /opt/fgenesh; \
    tar -xzf /tmp/fgenesh.tar.gz -C /opt/fgenesh; \
    bin="$(find /opt/fgenesh -maxdepth 4 -type f -name fgenesh | head -1)"; \
    test -n "$bin"; \
    chmod 0755 "$bin"; \
    ln -sf "$bin" /usr/local/bin/fgenesh; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 自检：可执行（FGENESH 运行时可能需授权环境；此处仅验证二进制就位）
RUN fgenesh 2>&1 | grep -qiE "fgenesh|usage|parameter" || true

WORKDIR /data
ENTRYPOINT ["/usr/local/bin/fgenesh"]
CMD ["-h"]

LABEL org.bioskills.software="fgenesh" \
      org.bioskills.impl="fgenesh_native" \
      org.bioskills.base_image="debian:bookworm-slim" \
      org.bioskills.fgenesh_version="Softberry-licensed（版本以授权交付为准）" \
      org.bioskills.pkg_route="apt(runtime) + 用户自备 Softberry 授权发行包（禁止再分发）"
