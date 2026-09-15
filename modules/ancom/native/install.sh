#!/usr/bin/env bash
# =============================================================================
# install.sh — ANCOM 宿主机本地安装脚本
#
# 归属    ：bioskills modules/ancom/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」对齐）
#   ANCOM 为 R 脚本（无独立二进制），原始实现无官方 conda/容器渠道，故宿主机路线：
#     - R    路线（默认优先）：检测 Rscript -> 装 R 依赖 -> 下载 ANCOM 源码到 --ancom-home
#     - conda 路线（无 Rscript 兜底）：建独立 env（r-base + r-tidyverse/r-compositions/r-nlme）
#   - 版本默认 2.1（ANCOM 用户手册自述 v2.1；上游代码归档无 releases/tags），
#     与 modules/ancom/meta.yaml software_versions.native 对齐。
#
# 官方来源：
#   code     : https://github.com/FrederickHuangLin/ANCOM（归档，重定向 ANCOM-Code-Archive）
#   zenodo   : https://doi.org/10.5281/zenodo.3577802
#   后继实现 : bioconda bioconductor-ancombc=2.14.0（ANCOM-BC，官方渠道；本脚本装原始 ANCOM）
#   (容器：原始 ANCOM 无官方镜像 → 模块自建 native/Dockerfile + Apptainer.def，见 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 Rscript 走 R 路线，否则 conda
#   bash install.sh --method R                        # 强制 R 路线（需本机 Rscript）
#   bash install.sh --method conda                    # 强制 conda 路线（建独立 env: ancom）
#   bash install.sh --ancom-home ~/software/ANCOM     # 指定 ANCOM 源码目录
#   bash install.sh --conda-env ancom --force         # 指定环境名 / 已存在时强制重建
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="2.1"
VERSION="$DEFAULT_VERSION"
ANCOM_HOME="${ANCOM_HOME:-$HOME/software/ANCOM}"
CONDA_ENV="ancom"
METHOD="auto"          # auto | R | conda
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# ANCOM 代码归档（无 releases/tags，master 为移动目标 → 不内嵌 sha256，安装时打印提示）
ANCOM_TARBALL="https://github.com/FrederickHuangLin/ANCOM-Code-Archive/archive/refs/heads/master.tar.gz"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)    VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --ancom-home|--prefix) ANCOM_HOME="${2:?--ancom-home 需要路径}"; shift 2 ;;
        --method)     METHOD="${2:?--method 需要 auto|R|conda}"; shift 2 ;;
        --conda-env)  CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)    PROFILE="${2:?--profile 需要路径}"; shift 2 ;;
        --force)      FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)    usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|R|conda) ;; *) die "--method 仅支持 auto|R|conda（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 下载并部署 ANCOM 源码 ----------------
fetch_ancom() {
    log "下载 ANCOM 源码（代码归档 master）-> $ANCOM_HOME"
    warn "ANCOM 上游无发布版 tag，master 为移动目标，未内嵌 sha256（可自行核对下载内容）"
    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "$tmp/ancom.tar.gz" "$ANCOM_TARBALL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/ancom.tar.gz" "$ANCOM_TARBALL"
    else
        die "需要 curl 或 wget 下载 ANCOM 源码"
    fi
    tar -xzf "$tmp/ancom.tar.gz" -C "$tmp"
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'ANCOM*' | head -1)"
    [[ -n "$srcdir" && -f "$srcdir/programs/ancom.R" ]] \
        || die "源码包内未找到 programs/ancom.R（下载或解压异常？）"
    mkdir -p "$ANCOM_HOME"
    cp -R "$srcdir"/. "$ANCOM_HOME/"
    rm -rf "$tmp"; tmp=""; trap - EXIT
    log "ANCOM 源码已部署: $ANCOM_HOME"
}

# ---------------- 版本断言（源码可 source 且 ANCOM 函数存在） ----------------
assert_ancom() {
    local rscript="$1" out
    out="$(ANCOM_HOME="$ANCOM_HOME" "$rscript" -e 'suppressPackageStartupMessages(source(file.path(Sys.getenv("ANCOM_HOME"), "programs", "ancom.R"))); cat(as.character(exists("ANCOM")), "\n")' 2>&1)" || {
        printf '%s\n' "$out" >&2; die "ANCOM 源码加载失败（R 依赖未装全？）"
    }
    grep -q "TRUE" <<<"$out" || { printf '%s\n' "$out" >&2; die "ANCOM 函数未找到"; }
    log "ANCOM 可用（版本 ${VERSION}，源码 ${ANCOM_HOME}）"
}

# ---------------- 路线 R：本机 Rscript 直装 ----------------
install_r() {
    local rscript="$1"
    log "使用 ${rscript} 安装 ANCOM R 依赖（nlme/tidyverse/compositions）"
    "$rscript" -e 'install.packages(c("nlme", "tidyverse", "compositions"), repos = "https://cloud.r-project.org")'
    fetch_ancom
    assert_ancom "$rscript"
    log "完成：Rscript native/run_ancom.R <params.tsv> 即可使用（ANCOM_HOME=${ANCOM_HOME}）"
}

# ---------------- 路线 conda：独立 env + R 依赖 ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists env_rscript
    log "使用 conda 创建环境 $CONDA_ENV（r-base + r-tidyverse/r-compositions/r-nlme）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge r-base r-tidyverse r-compositions r-nlme
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge r-base r-tidyverse r-compositions r-nlme
    fi
    env_rscript="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/Rscript"
    [[ -x "$env_rscript" ]] || die "环境 Rscript 不存在: $env_rscript"
    fetch_ancom
    assert_ancom "$env_rscript"
    log "完成：conda activate $CONDA_ENV 后运行 python native/main.py analyze ..."
}

# ---------------- 主流程 ----------------
log "ANCOM $VERSION 安装开始"
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

# ---------------- 写 ANCOM_HOME 到 profile ----------------
if [[ "$UPDATE_PATH" == 1 ]]; then
    line="export ANCOM_HOME=\"$ANCOM_HOME\""
    if [[ -f "$PROFILE" ]] && grep -qF "ANCOM_HOME=\"$ANCOM_HOME\"" "$PROFILE"; then
        log "ANCOM_HOME 已在 $PROFILE 中，跳过写入"
    else
        { echo ""; echo "# ANCOM (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
        log "已追加 ANCOM_HOME 到 $PROFILE"
    fi
fi
log "安装成功"
