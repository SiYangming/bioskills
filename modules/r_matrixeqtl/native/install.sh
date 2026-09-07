#!/usr/bin/env bash
# =============================================================================
# install.sh — r_matrixeqtl（Matrix eQTL R 包）宿主机本地安装脚本
#
# 归属    ：bioskills modules/r_matrixeqtl/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   Matrix eQTL 是以 R 包分发的无 CLI 软件，官方容器仅老版（2.1.1/R3.3），
#   因此宿主机安装以「R CRAN 直装」为主路线：
#     - R 路线（默认优先）：检测 Rscript → R install.packages('MatrixEQTL') 到用户库
#     - conda 路线（无 Rscript 兜底）：建独立 env（r-base），再用该 env 的 Rscript 从 CRAN 装包
#   - 版本默认 2.3，与 modules/r_matrixeqtl/meta.yaml software_versions.native 对齐；
#     CRAN 已于 2026-09 发布 2.4，install.packages() 实际安装以 CRAN 当前版为准（接口一致）。
#
# 官方来源：
#   CRAN     : https://cran.r-project.org/package=MatrixEQTL
#   conda r 频道 : https://anaconda.org/channels/r/packages/r-matrixeqtl/overview
#   容器     : quay.io/biocontainers/r-matrixeqtl（官方仅 2.1.1/老 R）→ 推荐模块自建
#              native/Dockerfile（rocker/r-ver:4.5.2 + MatrixEQTL），容器用法见模块 README
#
# 用法示例：
#   bash install.sh                                   # auto：有 Rscript 走 R CRAN，否则 conda 路线
#   bash install.sh --method R                        # 强制 R CRAN 路线（需本机 Rscript）
#   bash install.sh --method conda                    # 强制 conda 路线（建独立 env: r-matrixeqtl）
#   bash install.sh --conda-env eqtl --force          # 指定环境名 / 已存在时强制重建
#   bash install.sh --version 2.3                     # 覆盖版本（安装后版本断言对齐）
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="2.3"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="r-matrixeqtl"
METHOD="auto"          # auto | R | conda
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
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
    out="$("$rscript" -e 'cat(as.character(packageVersion("MatrixEQTL")))' 2>/dev/null)" || die "版本断言失败：无法读取 MatrixEQTL 包版本"
    printf '  MatrixEQTL %s\n' "$out"
    if [[ -n "$VERSION" ]]; then
        grep -qE "${VERSION//./\.}" <<<"$out" || warn "版本校验提示：期望 ${VERSION}，实装 ${out}（CRAN 版本漂移属正常，见模块 README）"
    fi
    log "MatrixEQTL 可用（Rscript: ${rscript}）"
}

# ---------------- 路线 R：CRAN 直装 ----------------
install_r() {
    local rscript="$1"
    log "使用 ${rscript} 从 CRAN 安装 MatrixEQTL（版本 ${VERSION} 起）"
    "$rscript" -e 'install.packages("MatrixEQTL", repos = "https://cloud.r-project.org")'
    assert_version "$rscript"
    log "完成：R 中 library(MatrixEQTL) 即可使用；CLI 驱动见 native/main.py analyze"
}

# ---------------- 路线 conda：独立 env（r-base）+ CRAN 装包 ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists
    log "使用 conda 创建环境 $CONDA_ENV（r-base）并装 MatrixEQTL"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge r-base
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge r-base
    fi
    local env_rscript
    env_rscript="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/Rscript"
    [[ -x "$env_rscript" ]] || die "环境 Rscript 不存在: $env_rscript"
    install_r "$env_rscript"
    log "完成：conda activate $CONDA_ENV 后运行 python native/main.py analyze ..."
}

# ---------------- 主流程 ----------------
log "r_matrixeqtl $VERSION 安装开始"
case "$METHOD" in
    R)
        command -v Rscript >/dev/null 2>&1 || die "--method R 但 PATH 中无 Rscript（先装 R>=4.2，或改用 conda 路线）"
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
            die "未检测到 Rscript 且无 mamba/conda；请先安装 R>=4.2（或 mamba），再运行本脚本"
        fi ;;
esac
log "安装成功"
