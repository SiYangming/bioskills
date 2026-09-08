# syntax=docker/dockerfile:1
# =============================================================================
# omiga native 自建容器配方（多阶段，amd64；无官方镜像，官方预编译二进制兜底）
#
# 路线判定（2026-09-08 核实）：OmiGA 官方渠道全无 ——
#   bioconda omiga 页面 404 + api.anaconda.org HTTP 404 / quay.io/biocontainers/omiga 不存在
#   （quay API 401 = 无此仓库；对照已知仓库 200）/ depot.galaxyproject.org singularity
#   omiga:1.8.17 HTTP 404 / nf-core modules/omiga 404 / snakemake-wrappers bio/omiga 404；
#   quay.io/bioinfortools/omiga 仓库名存在但 0 tags（无可拉镜像）→ 自建兜底：debian:bookworm-slim
#   多阶段 + 官方预编译 tar.xz（仅 Linux x86_64 / amd64，自带运行时，不引入 miniconda/Julia）。
#
# 版本与分发（2026-09-07 抓取官方单源 https://omiga.bio/releases/latest.json）：
#   - OmiGA 1.8.17，filename=OmiGA-build-v1.8.17-x86_64.tar.xz
#   - 官方 sha256 = 6cfbed0b52085489d5a4b4b549c2343e6ae53921474087cdf28876c2c214ea23
#   - url = efile111.hpccube.com 一次性 token 直链（会随发版失效/更换 → 重建前重新抓 latest.json，
#     用 ARG 覆盖 OMIGA_URL / OMIGA_SHA256，勿沿用陈旧值）
# 本配方仅登记（linux/amd64），不参与实际构建。
#
# 构建：docker build -t omiga:1.8.17 native/
#   （token 失效时：OMIGA_URL=<新url> OMIGA_SHA256=<新sha> docker build --build-arg ...）
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data omiga:1.8.17 \
#         --mode cis --threads 4 --genotype geno --phenotype pheno.txt \
#         --prefix out --output-dir res
# 说明：ENV OMIGA_PATH=/opt/omiga/bin（官方 Installation.md：OMIGA_PATH 指向 bin 目录）；
#   runtime 装 ca-certificates/tini —— 支持 1.8.14+ 的 `omiga --update` 联网自升级。
# =============================================================================
FROM debian:bookworm-slim AS builder

ARG OMIGA_VERSION=1.8.17
ARG OMIGA_URL=https://efile111.hpccube.com:65014/efile/s/d/YWNyZHBkcXZieQ==/08410635d771c08d
ARG OMIGA_SHA256=6cfbed0b52085489d5a4b4b549c2343e6ae53921474087cdf28876c2c214ea23

LABEL org.bioskills.software="omiga" \
      org.bioskills.impl="native" \
      org.bioskills.base_image="debian:bookworm-slim (multi-stage)" \
      org.bioskills.omiga_version="${OMIGA_VERSION}" \
      org.bioskills.pkg_route="official prebuilt tar.xz (latest.json) + sha256sum verify"

# builder：下载官方 tar.xz → 官方 sha256 校验 → 解压到 /opt/omiga（--strip-components=1 去掉
#   OmiGA-build-<ver>-x86_64 顶层目录，使 bin/ 直接落在 /opt/omiga/bin）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl xz-utils; \
    curl -fsSL -o /tmp/omiga.tar.xz "${OMIGA_URL}"; \
    echo "${OMIGA_SHA256}  /tmp/omiga.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/omiga; \
    tar -Jxf /tmp/omiga.tar.xz -C /opt/omiga --strip-components=1; \
    chmod +x /opt/omiga/bin/*; \
    rm -f /tmp/omiga.tar.xz; \
    apt-get purge -y curl xz-utils; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/info /tmp/* /var/tmp/*

FROM debian:bookworm-slim

LABEL org.bioskills.software="omiga" \
      org.bioskills.impl="native" \
      org.bioskills.base_image="debian:bookworm-slim (runtime)" \
      org.bioskills.omiga_version="1.8.17" \
      org.bioskills.pkg_route="official prebuilt tar.xz (latest.json) + sha256sum verify; no miniconda"

# runtime：ca-certificates（联网 omiga --update / 下载）/ tini（PID1/信号转发）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates tini; \
    # 清理四连（缺一不可） \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/info /tmp/* /var/tmp/*

COPY --from=builder /opt/omiga /opt/omiga

ENV TMPDIR=/tmp \
    OMIGA_VERSION=1.8.17 \
    OMIGA_PATH=/opt/omiga/bin
ENV PATH="${OMIGA_PATH}:${PATH}"

# 构建末尾：首跑初始化 + 版本断言。
#   omiga --init 产出 OK 自检文件（官方 Installation.md：首跑前初始化）；容器内可能因
#   网络/权限受限失败 → || true 容忍（产物可后续手动 omiga --init 补做）；
#   omiga --version 输出必须含 1.8.17（断言失败 → 构建失败）。
RUN /opt/omiga/bin/omiga --init || true; \
    /opt/omiga/bin/omiga --version 2>&1 | tee /dev/stderr | grep -q '1.8.17'

# 不创建固定账号：运行时用 -u $(id -u):$(id -g) 接管（避免 HPC UID 冲突 / 产物归 root）
ENTRYPOINT ["/usr/bin/tini", "--", "omiga"]
CMD ["--help"]
