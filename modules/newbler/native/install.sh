#!/usr/bin/env bash
# =============================================================================
# install.sh — Newbler 2.9（GS De Novo Assembler）安装说明型脚本
#
# ⚠️ DEPRECATED（2026-09 登记）：Newbler 已淘汰，**不提供自动安装**。
#   本脚本不下载、不安装任何软件，仅输出历史复现说明（说明型）。
#
# 渠道核实（2026-09）：无任何官方渠道 ——
#   · bioconda newbler 404；quay.io/biocontainers/newbler 无；depot.galaxyproject.org 无
#   · nf-core modules、snakemake-wrappers、homebrew-core/brewsci/bio 两源均无
#   · 官网 454.com 已停服（software-request.asp 变为跳转占位页，不再提供下载）
#   · 官方下载包（历史）：DataAnalysis_2.9_All_20130530_1559.tgz（64 位 Linux 自解压）
# 软件已淘汰 → 不产出自建 Dockerfile/Apptainer.def；454 组装请改用
#   SPAdes / SOAPdenovo2 / MaSuRa 等替代工具。
#
# 用法：
#   bash install.sh --help       # 查看本说明
#   bash install.sh              # 打印历史复现说明（退出码 1，表示无自动安装）
#   bash install.sh --explain    # 同上（显式）
# =============================================================================
set -euo pipefail

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

explain() {
    cat <<'EOF'
[install] Newbler 2.9 无自动安装路线（deprecated 软件 + 官方渠道全无）。

历史复现步骤（需自备官方安装包 DataAnalysis_2.9_All_20130530_1559.tgz）：
  1) 解压安装包
       tar zxf ~/software/DataAnalysis_2.9_All_20130530_1559.tgz
       cd DataAnalysis_2.9_All/
  2) 安装 32 位运行库（Newbler 依赖 i686 库；现代发行版需 multilib）
       sudo yum --disablerepo=* --enablerepo=c6-media -y install \
           zlib* libXi* libXtst* libXaw* zlib*i686 libXi*i686 libXtst*i686 libXaw*i686
  3) 运行安装脚本（默认装到 /opt/biosoft/454；本仓库建议改为用户前缀）
       ./setup.sh          # 交互式，设定安装路径
  4) 加 PATH
       echo 'export PATH=$PATH:<安装目录>/bin/' >> ~/.bashrc && source ~/.bashrc
  5) 验证
       runAssembly        # 无参数应打印用法

注意：官网 454.com 已停服，上述安装包需自行从历史存档获取；454 测序平台已停产，
      64-only 发行版需 multilib 支持。新项目请改用 SPAdes / SOAPdenovo2 / MaSuRa 等。
EOF
    exit 1
}

case "${1:-}" in
    --help|-h) usage ;;
    "")        explain ;;
    --explain) explain ;;
    --version)
        echo "newbler 2.9（GS De Novo Assembler / Newbler；deprecated）"
        exit 0 ;;
    --method)
        echo "[install] 无 --method 路线可用：Newbler 无官方 conda 包、无官方镜像、无预编译分发；见 --explain。" >&2
        exit 1 ;;
    *)
        echo "[install] 未知参数: $1（--help 查看用法）" >&2
        exit 2 ;;
esac
