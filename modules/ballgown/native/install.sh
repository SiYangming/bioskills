#!/usr/bin/env bash
# =============================================================================
# install.sh — ballgown（Ballgown R/Bioconductor 包）宿主机本地安装脚本
#
# 归属    ：bioskills modules/ballgown/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（官方镜像优先；Ballgown 无独立二进制 → 仅 conda / R 两条路线）
#   - conda 路线（默认优先）：mamba/conda 建独立环境，pin bioconda::bioconductor-ballgown
#   - R 路线（无 conda 兜底）：BiocManager::install("ballgown")（R/Bioconductor 原生）
#   - 版本默认 2.42.0，与 modules/ballgown/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/alyssafrazee/ballgown
#   bioconda : https://anaconda.org/bioconda/bioconductor-ballgown
#   (容器：quay.io/biocontainers/bioconductor-ballgown；用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda 走 bioconda，否则 BiocManager
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: ballgown）
#   bash install.sh --method R                        # 强制 BiocManager（需本机 Rscript）
#   bash install.sh --conda-env diffexpr --force      # 指定环境名 / 已存在时强制重建
#   bash install.sh --version 2.42.0                  # 覆盖版本（安装后版本断言对齐）
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="2.42.0"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="ballgown"
METHOD="auto"          # auto | conda | R
FORCE=0

CONDA_PKG="bioconductor-ballgown"
R_PKG="ballgown"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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

assert_version() {
    local rscript="$1" out
    out="$("$rscript" -e "cat(as.character(packageVersion('${R_PKG}')))" 2>/dev/null)" \
        || die "版本断言失败：无法读取 ${R_PKG} 包版本"
    printf '  %s %s\n' "$R_PKG" "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || warn "版本校验提示：期望 ${VERSION}，实装 ${out}（Bioconductor 版本漂移属正常）"
    log "${R_PKG} 可用（Rscript: ${rscript}）"
}

install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists
    log "使用 conda 安装 ${CONDA_PKG}=${VERSION}（含 genefilter 依赖）到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "${CONDA_PKG}=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "${CONDA_PKG}=${VERSION}"
    fi
    local env_rscript
    env_rscript="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/Rscript"
    [[ -x "$env_rscript" ]] || die "环境 Rscript 不存在: $env_rscript"
    assert_version "$env_rscript"
    log "完成：conda activate $CONDA_ENV 后运行 python native/main.py analyze ..."
}

install_r() {
    local rscript="$1"
    log "使用 ${rscript} 经 BiocManager 安装 ${R_PKG}（版本 ${VERSION} 起）"
    "$rscript" -e 'if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager", repos = "https://cloud.r-project.org"); BiocManager::install("'"${R_PKG}"'", ask = FALSE, update = FALSE)'
    assert_version "$rscript"
    log "完成：R 中 library(${R_PKG}) 即可使用；CLI 驱动见 native/main.py analyze"
}

log "ballgown $VERSION 安装开始"
case "$METHOD" in
    conda)
        install_conda ;;
    R)
        command -v Rscript >/dev/null 2>&1 || die "--method R 但 PATH 中无 Rscript（先装 R，或改用 conda 路线）"
        install_r "$(command -v Rscript)" ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v Rscript >/dev/null 2>&1; then
            warn "未检测到 mamba/conda，改走 BiocManager 路线"
            install_r "$(command -v Rscript)"
        else
            die "未检测到 mamba/conda 且无 Rscript；请先安装 mamba 或 R，再运行本脚本"
        fi ;;
esac
log "安装成功"
