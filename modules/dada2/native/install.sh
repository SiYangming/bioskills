#!/usr/bin/env bash
# =============================================================================
# install.sh — dada2（DADA2 R 包）宿主机本地安装脚本
#
# 归属    ：bioskills modules/dada2/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   DADA2 是以 R 包分发的无 CLI 软件，官方镜像由 bioconda 自动构建（quay.io/biocontainers/
#   bioconductor-dada2）；宿主机安装以「R/Bioconductor 直装」为主路线：
#     - R 路线（默认优先）：检测 Rscript → BiocManager::install("dada2") 到用户库
#     - conda 路线（无 Rscript 兜底）：建独立 env（bioconductor-dada2），pin 1.38.0
#   - 版本默认 1.38.0，与 modules/dada2/meta.yaml software_versions.native 对齐；
#     R 路线以当前 Bioconductor 发布版为准（接口一致）。
#
# 官方来源：
#   BioConductor : https://bioconductor.org/packages/dada2/
#   bioconda     : https://anaconda.org/bioconda/bioconductor-dada2
#   官网         : https://benjjneb.github.io/dada2/
#   容器         : quay.io/biocontainers/bioconductor-dada2（官方镜像，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                   # auto：有 Rscript 走 Bioconductor，否则 conda
#   bash install.sh --method R                        # 强制 R 路线（需本机 Rscript）
#   bash install.sh --method conda                    # 强制 conda 路线（建独立 env: dada2）
#   bash install.sh --conda-env dada2 --force         # 指定环境名 / 已存在时强制重建
#   bash install.sh --version 1.38.0                  # 覆盖版本（安装后版本断言对齐）
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="1.38.0"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="dada2"
METHOD="auto"          # auto | R | conda
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
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

# ---------------- 版本断言（安装后读取 packageVersion("dada2")） ----------------
assert_version() {
    local rscript="$1" out
    out="$("$rscript" -e 'cat(as.character(packageVersion("dada2")))' 2>/dev/null)" \
        || die "版本断言失败：无法读取 dada2 包版本（Rscript: ${rscript}）"
    printf '  dada2 %s\n' "$out"
    if [[ -n "$VERSION" ]]; then
        grep -qE "${VERSION//./\.}" <<<"$out" \
            || warn "版本校验提示：期望 ${VERSION}，实装 ${out}（Bioconductor 版本漂移属正常，见模块 README）"
    fi
    log "dada2 可用（Rscript: ${rscript}）"
}

# ---------------- 路线 R：Bioconductor 直装 ----------------
install_r() {
    local rscript="$1"
    log "使用 ${rscript} 从 Bioconductor 安装 dada2（版本 ${VERSION} 起）"
    "$rscript" -e 'if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager", repos = "https://cloud.r-project.org"); BiocManager::install("dada2", update = FALSE, ask = FALSE)'
    assert_version "$rscript"
    log "完成：R 中 library(dada2) 即可使用；CLI 驱动见 native/main.py"
}

# ---------------- 路线 conda：独立 env（bioconductor-dada2） ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists
    log "使用 conda 安装 bioconductor-dada2=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "bioconductor-dada2=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "bioconductor-dada2=$VERSION"
    fi
    local env_rscript
    env_rscript="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/Rscript"
    [[ -x "$env_rscript" ]] || die "环境 Rscript 不存在: $env_rscript"
    assert_version "$env_rscript"
    log "完成：conda activate $CONDA_ENV 后运行 python native/main.py ..."
}

# ---------------- 主流程 ----------------
log "dada2 $VERSION 安装开始"
case "$METHOD" in
    R)
        command -v Rscript >/dev/null 2>&1 || die "--method R 但 PATH 中无 Rscript（先装 R>=4.3，或改用 conda 路线）"
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
            die "未检测到 Rscript 且无 mamba/conda；请先安装 R>=4.3（或 mamba），再运行本脚本"
        fi ;;
esac
log "安装成功"
