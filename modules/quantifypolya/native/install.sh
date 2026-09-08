#!/usr/bin/env bash
# =============================================================================
# install.sh — QuantifyPolyA（R 包）宿主机本地安装脚本
#
# 归属    ：bioskills modules/quantifypolya/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   QuantifyPolyA 以 R 包分发、无官方 conda 包/镜像 → 宿主机安装为双路线：
#     - R 路线（默认 auto 优先）：检测 Rscript → Rscript 运行同目录
#       install_deps_QuantifyPolyA.R（BiocManager/CRAN 装依赖 + sourceforge 0.3.0
#       源码包安装；ggalt 从 CRAN Archive/conda-forge 拉取）
#     - conda 路线（无 Rscript 兜底）：用同目录 environment.yml 建独立 env
#       （r-base + r-ggalt + 需编译依赖的预编译包），再用该 env 的 Rscript 跑
#       install_deps_QuantifyPolyA.R 补齐剩余 CRAN/Bioc 依赖
#   - 版本默认 0.3.0，与 modules/quantifypolya/meta.yaml software_versions.native 对齐
#     （0.3.0 即 sourceforge 最新版，2026-09 在线核实）
#
# 官方来源：
#   homepage : https://sourceforge.net/projects/quantifypoly-a/
#   source   : https://sourceforge.net/projects/quantifypoly-a/files/QuantifyPolyA_0.3.0.tar.gz
#   ggalt    : https://cran.r-project.org/src/contrib/Archive/ggalt/ggalt_0.4.0.tar.gz
#   (无官方容器/conda 包；R 运行时也可用 rocker/r-ver 镜像，见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 Rscript 走 R 路线，否则 conda
#   bash install.sh --method R                        # 强制 R 路线（需本机 Rscript）
#   bash install.sh --method conda                    # 强制 conda 路线（environment.yml）
#   bash install.sh --conda-env qpa --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --version 0.3.0                   # 对齐版本（默认即 0.3.0）
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="0.3.0"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="r-quantifypolya"
METHOD="auto"          # auto | R | conda
FORCE=0

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)   VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --method)    METHOD="${2:?--method 需要 auto|R|conda}"; shift 2 ;;
        --conda-env) CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --force)     FORCE=1; shift ;;
        --help|-h)   usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|R|conda) ;; *) die "--method 仅支持 auto|R|conda（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（安装后读取 packageVersion） ----------------
assert_version() {
    local rscript="$1" out
    out="$("$rscript" -e 'cat(as.character(packageVersion("QuantifyPolyA")))' 2>/dev/null)" \
        || die "版本断言失败：无法读取 QuantifyPolyA 包版本（install_deps 未成功？）"
    printf '  QuantifyPolyA %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望 ${VERSION}，实际 ${out}"
    log "QuantifyPolyA ${VERSION} 可用（Rscript: ${rscript}）"
}

# ---------------- 路线 R：Rscript 一键依赖 + 源码包安装 ----------------
install_r() {
    local rscript="$1"
    [[ -n "$VERSION" && "$VERSION" != "$DEFAULT_VERSION" ]] && {
        warn "--version ${VERSION} ≠ 默认 0.3.0：官方 sourceforge 仅发布 0.3.0（2026-09 核实），按 0.3.0 安装"
        VERSION="$DEFAULT_VERSION"
    }
    log "使用 ${rscript} 运行 install_deps_QuantifyPolyA.R（依赖 + 包 ${VERSION}）"
    "$rscript" "$SELF_DIR/install_deps_QuantifyPolyA.R"
    assert_version "$rscript"
    log "完成：library(QuantifyPolyA) 即可；分析驱动见 native/main.py quant"
}

# ---------------- 路线 conda：environment.yml 建 env + env Rscript 补齐 ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    log "使用 environment.yml 创建环境 $CONDA_ENV"
    "$CONDA_BIN" env create -y -n "$CONDA_ENV" -f "$SELF_DIR/environment.yml"
    local env_rscript
    env_rscript="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/Rscript"
    [[ -x "$env_rscript" ]] || die "环境 Rscript 不存在: $env_rscript"
    install_r "$env_rscript"
    log "完成：conda activate $CONDA_ENV 后运行 python native/main.py quant ..."
}

# ---------------- 主流程 ----------------
log "QuantifyPolyA ${VERSION} 安装开始"
case "$METHOD" in
    R)
        command -v Rscript >/dev/null 2>&1 || die "--method R 但 PATH 中无 Rscript（先装 R>=4.0，或改用 conda 路线）"
        install_r "$(command -v Rscript)" ;;
    conda)
        install_conda ;;
    auto)
        if command -v Rscript >/dev/null 2>&1; then
            install_r "$(command -v Rscript)"
        elif [[ -n "$CONDA_BIN" ]]; then
            warn "未检测到 Rscript，改走 conda 路线"
            install_conda
        else
            die "未检测到 Rscript 且无 mamba/conda；请先安装 R>=4.0（或 mamba），再运行本脚本"
        fi ;;
esac
log "安装成功"
