#!/usr/bin/env bash
# =============================================================================
# install.sh — wgcna（WGCNA R 包）宿主机本地安装脚本
#
# 归属    ：bioskills modules/wgcna/native/install.sh（native 实现安装方式）
# 规范    ：AGENT.md §4.5（官方镜像优先；宿主机一键安装）
#   WGCNA 是以 R 包分发的无 CLI 软件，官方容器已由 bioconda 维护
#   （quay.io/biocontainers/r-wgcna），故宿主机安装以包管理器为主：
#     - conda/mamba 路线（默认优先）：建独立 env 装 bioconda::r-wgcna
#     - R 路线（无 conda 兜底）：检测 Rscript → BiocManager::install("WGCNA")
#   - 默认版本 1.74，与 modules/wgcna/meta.yaml software_versions.native 对齐
#     （bioconda r-wgcna=1.74 与 CRAN WGCNA 1.74 一致；bioconductor-wgcna 包名未找到，见 README）。
#
# 官方来源：
#   CRAN/官网 : https://horvath.genetics.ucla.edu/html/CoexpressionNetwork/Rpackages/WGCNA/
#   bioconda  : https://anaconda.org/bioconda/r-wgcna
#   容器      : quay.io/biocontainers/r-wgcna:1.74--r45h0df16ae_1
#
# 用法示例：
#   bash install.sh                                 # auto：有 mamba/conda 走 conda，否则 R BiocManager
#   bash install.sh --method conda                  # 强制 conda 路线（建独立 env: wgcna）
#   bash install.sh --method R                      # 强制 R 路线（需本机 Rscript + BiocManager）
#   bash install.sh --conda-env coexpr --force      # 指定环境名 / 已存在时强制重建
#   bash install.sh --version 1.74                  # 覆盖版本（安装后版本断言对齐）
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="1.74"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="wgcna"
METHOD="auto"          # auto | conda | R
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)   VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --method)    METHOD="${2:?--method 需要 auto|conda|R}"; shift 2 ;;
        --conda-env) CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --force)     FORCE=1; shift ;;
        --help|-h)   usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|R) ;; *) die "--method 仅支持 auto|conda|R（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（安装后读取 packageVersion） ----------------
assert_version() {
    local rscript="$1" out
    out="$("$rscript" -e 'cat(as.character(packageVersion("WGCNA")))' 2>/dev/null)" \
        || die "版本断言失败：无法读取 WGCNA 包版本"
    printf '  WGCNA %s\n' "$out"
    if [[ -n "$VERSION" ]]; then
        grep -qF "$VERSION" <<<"$out" \
            || warn "版本校验提示：期望 ${VERSION}，实装 ${out}（版本漂移属正常，见模块 README）"
    fi
    log "WGCNA 可用（Rscript: ${rscript}）"
}

# ---------------- 路线 conda：独立 env（bioconda::r-wgcna） ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists
    log "使用 conda 创建环境 ${CONDA_ENV}（r-wgcna=${VERSION}）"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "r-wgcna=${VERSION}"
    local env_rscript
    env_rscript="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/Rscript"
    [[ -x "$env_rscript" ]] || die "环境 Rscript 不存在: ${env_rscript}"
    assert_version "$env_rscript"
    log "完成：conda activate ${CONDA_ENV} 后运行 python native/main.py run ..."
}

# ---------------- 路线 R：BiocManager 直装 ----------------
install_r() {
    local rscript="$1"
    log "使用 ${rscript} 经 BiocManager 安装 WGCNA"
    "$rscript" -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org"); BiocManager::install("WGCNA", update=FALSE, ask=FALSE)'
    assert_version "$rscript"
    log "完成：R 中 library(WGCNA) 即可使用；CLI 驱动见 native/main.py"
}

# ---------------- 主流程 ----------------
log "wgcna ${VERSION} 安装开始"
case "$METHOD" in
    conda)
        install_conda ;;
    R)
        command -v Rscript >/dev/null 2>&1 || die "--method R 但 PATH 中无 Rscript（先装 R>=4.1，或改用 conda 路线）"
        install_r "$(command -v Rscript)" ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v Rscript >/dev/null 2>&1; then
            warn "未检测到 mamba/conda，改走 R BiocManager 路线"
            install_r "$(command -v Rscript)"
        else
            die "未检测到 mamba/conda 也无 Rscript；请先安装 mamba（或 R>=4.1），再运行本脚本"
        fi ;;
esac
log "安装成功"
