# syntax=docker/dockerfile:1
# =============================================================================
# lftp native 自建容器配方（amd64；查无生物官方镜像 → 通用网络工具 apt 最小化）
#
# 路线判定（2026-09-08 核实）：生物官方渠道全无 ——
#   bioconda lftp 页面 404 + api.anaconda.org HTTP 404 / quay.io/biocontainers/lftp 不存在
#   （quay API 401 = 无此仓库；对照已知仓库 biocontainers/samtools 200）/
#   depot.galaxyproject.org singularity lftp:4.9.3 HTTP 404 / nf-core modules/lftp 404 /
#   snakemake-wrappers bio/lftp 404 → 自建兜底：debian:bookworm-slim + apt lftp（最小化）。
#   lftp 是通用网络工具（FTP/HTTP/SFTP 客户端），conda-forge/brew 为宿主机首选（见模块 README）。
#
# 版本：debian:bookworm(oldstable) apt lftp=4.9.2-2（2026-09 用户核实；bookworm 是 frozen 发行版，
#   apt 版本固定为 4.9.2 系）；meta software_versions.native lftp=4.9.3 为上游/conda-forge/brew
#   版本 —— 两者有 minor 差异（4.9.2 vs 4.9.3），本容器按 bookworm 实际 4.9.2 系断言，不强行 pin
#   上游源码编译（保持 apt 最小化、CVE 补丁随 Debian 安全源推送）。
#
# 构建：docker build -t lftp:4.9.2 modules/lftp/native/
# 运行（直接透传 lftp 参数；必须 -u $(id -u):$(id -g)，否则下载产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data lftp:4.9.2 \
#       -e "get -c /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra; exit" \
#       ftp-trace.ncbi.nlm.nih.gov
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data lftp:4.9.2 --version
# 说明：native/main.py 驱动在宿主机跑（conda/brew/源码装的 lftp）；本镜像直接提供 lftp 二进制。
# =============================================================================
FROM debian:bookworm-slim

LABEL org.bioskills.software="lftp" \
      org.bioskills.impl="native" \
      org.bioskills.base_image="debian:bookworm-slim" \
      org.bioskills.lftp_version="4.9.2-2 (apt bookworm; 上游/conda-forge/brew=4.9.3)" \
      org.bioskills.pkg_route="apt-get install --no-install-recommends lftp ca-certificates; no miniconda"

# 最小依赖：lftp 本体 + ca-certificates（HTTPS/FTP over TLS 根证书）
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends lftp ca-certificates; \
    # 版本断言：bookworm apt lftp 为 4.9.2 系（dpkg 版本含 4.9.2-2；与 4.9.3 minor 差异见文件头） \
    dpkg -l | awk '$2=="lftp"{print $3}' | grep -Eq '^4\.9'; \
    lftp --version 2>&1 | head -n 1; \
    # 清理四连（缺一不可） \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/info /tmp/* /var/tmp/*

ENV TMPDIR=/tmp

# 不创建固定账号：运行时用 -u $(id -u):$(id -g) 接管（避免 HPC UID 冲突 / 下载产物归 root）
ENTRYPOINT ["/usr/bin/lftp"]
CMD ["--version"]
