# syntax=docker/dockerfile:1
# =============================================================================
# aspera-connect native 自建容器配方（amd64；无官方镜像，官方 Connect 安装器兜底）
#
# 路线判定（2026-09-08 核实）：官方渠道全无 ——
#   bioconda/conda-forge 无 aspera 包（api 全 404）/ quay.io/biocontainers/aspera-connect 无 /
#   depot.galaxyproject.org singularity aspera-connect:4.2.19.956 404 / nf-core modules 无 /
#   snakemake-wrappers bio/ 无 / homebrew 两源无 → 自建兜底：debian:bookworm-slim + ca-certificates +
#   官方 ibm-aspera-connect tar.gz（内层自解压 .sh 安装器）。
#
# 官方最新（2026-09-08 抓取 https://www.ibm.com/aspera/connect/ + HEAD 实测 HTTP 200）：
#   https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz
#   （latest 为滚动指针、文件名带 -HEAD；版本号可能继续更新 → 重建前重查官方页面，用 ARG 覆盖 URL）
# 安装：tar -zxvf <pkg>.tar.gz → sh ibm-aspera-connect_<ver>[-HEAD]_linux_x86_64.sh
#   （IBM 官方手册：按用户安装到 $HOME/.aspera/connect，勿以 root 运行安装器）
#   → 本配方以构建期 nobody 用户 + HOME=/opt/aspera 运行安装器，
#     ascp 落于 /opt/aspera/.aspera/connect/bin/ascp，再软链到 /usr/local/bin/ascp。
#   ENV HOME=/opt/aspera：使容器内 main.py 默认密钥路径（~/.aspera/connect/etc/...）与安装位置一致。
#   IBM 官方页面未公布安装包 sha256（2026-09-08 核实）→ 本配方不内嵌伪造校验和。
#
# ⚠️ 专有许可：Aspera 为 IBM 专有软件（非开源，不随本镜像分发 EULA 文本）；本配方仅供个人/机构
#    内部使用，不得随意再分发；使用前请阅读并遵守 IBM 官方 EULA（见 https://www.ibm.com/products/aspera
#    与安装包内文档）。本配方仅「录入」，未实跑构建（build 前请按需核对安装器行为）。
#
# 构建：docker build -t aspera-connect:4.2.19.956 modules/aspera-connect/native/
#   （latest 指针更新后：ASCP_URL=<新url> docker build --build-arg ASCP_URL=...）
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data aspera-connect:4.2.19.956 \
#         ascp -T -l 200M -i /opt/aspera/.aspera/connect/etc/<key文件> \
#         --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv \
#         /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 .
#   （若 4.2+ 随包无 asperaweb_id_dsa.openssh —— 实机核查 macOS 4.2.13 App 已无该 DSA 密钥（仅
#     aspera_tokenauth_id_rsa），Linux 4.2.19.956 包未实跑核实 → 大概率需自备密钥：把宿主密钥挂载进
#     容器再 -i 指向：-v $PWD/asperaweb_id_dsa.openssh:/key/asperaweb_id_dsa.openssh -i /key/...）
#   ascp --version 实机输出示例：'IBM Aspera Connect version 4.2.13 (820)' / 'ascp version 4.4.3.820'
#     （ascp 自报版本与 Connect 包版本不一致属正常 → 本配方断言以 'ascp version'/'Usage: ascp' 为准）
# =============================================================================
FROM debian:bookworm-slim

ARG ASCP_VERSION=4.2.19.956
ARG ASCP_URL=https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz

LABEL org.bioskills.software="aspera-connect" \
      org.bioskills.impl="native" \
      org.bioskills.base_image="debian:bookworm-slim" \
      org.bioskills.aspera_connect_version="${ASCP_VERSION}" \
      org.bioskills.pkg_route="official Connect tar.gz (self-extracting .sh installer) + runuser nobody; no miniconda" \
      org.bioskills.license_note="IBM proprietary (EULA not redistributed; internal use only)"

ENV DEBIAN_FRONTEND=noninteractive \
    TMPDIR=/tmp \
    ASPERA_VERSION=4.2.19.956 \
    HOME=/opt/aspera

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget; \
    wget -q -O /tmp/aspera-connect.tar.gz "${ASCP_URL}"; \
    mkdir -p /tmp/aspera-inst; \
    tar -xzf /tmp/aspera-connect.tar.gz -C /tmp/aspera-inst; \
    installer="$(find /tmp/aspera-inst -maxdepth 1 -type f -name 'ibm-aspera-connect*.sh' | head -n 1)"; \
    test -n "${installer}"; \
    mkdir -p /opt/aspera; \
    chown nobody:nogroup /opt/aspera; \
    # IBM 官方手册：勿以 root 运行 Connect 安装器 → 以 nobody + HOME=/opt/aspera 执行 \
    runuser -u nobody -- env HOME=/opt/aspera sh "${installer}"; \
    test -x /opt/aspera/.aspera/connect/bin/ascp; \
    chown -R root:root /opt/aspera; \
    chmod -R a+rX /opt/aspera; \
    # 运行期 ascp 若需在安装目录下建 session/log 子项 → 目录打 sticky 位（各用户自建自管） \
    chmod 1777 /opt/aspera/.aspera/connect; \
    ln -s /opt/aspera/.aspera/connect/bin/ascp /usr/local/bin/ascp; \
    rm -rf /tmp/aspera-connect.tar.gz /tmp/aspera-inst; \
    apt-get purge -y wget; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/info /tmp/* /var/tmp/*

# 构建末尾断言：ascp 存在且 --version/--help 可自报（自报版本号与包版本 4.2.19.956 对应未核实 →
# 不断言具体数字，只断言 'ascp version'/'Usage: ascp' 字样）
RUN set -eux; \
    out="$({ ascp --version 2>&1 || true; ascp --help 2>&1 || true; } | head -n 20)"; \
    printf '%s\n' "$out" | head -n 4; \
    printf '%s\n' "$out" | grep -qiE 'ascp version|Usage: ascp'; \
    echo "aspera-connect ascp assertion OK"

# 不创建固定账号：运行时用 -u $(id -u):$(id -g) 接管（避免 HPC UID 冲突 / 产物归 root）
ENTRYPOINT ["/usr/local/bin/ascp"]
CMD ["--help"]
