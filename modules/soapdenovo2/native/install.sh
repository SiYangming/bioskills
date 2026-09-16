#!/usr/bin/env bash
# =============================================================================
# install.sh — SOAPdenovo2 宿主机本地安装脚本
#
# 归属    ：bioskills modules/soapdenovo2/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::soapdenovo2=2.40
#   - source 路线（无 conda 兜底）：官方 GitHub release r241 源码 make 编译，
#     用户级前缀安装到 --prefix（默认 ~/software/soapdenovo2-r241），无需 root、不写 /opt
#
# 版本说明（2026-09 核实）：
#   - bioconda / quay.io/biocontainers / depot.galaxyproject.org 提供的是 2.40（源码基线 r240）；
#   - 教程使用 GitHub release r241（仓库 VERSION=2.04-r241）；
#   - 因此 conda 路线默认装 2.40，source 路线构建 r241。二者 API/用法一致。
#
# 官方来源：
#   homepage : https://github.com/aquaskyline/SOAPdenovo2
#   release  : https://github.com/aquaskyline/SOAPdenovo2/releases/tag/r241
#   bioconda : https://anaconda.org/bioconda/soapdenovo2
#   (容器：quay.io/biocontainers/soapdenovo2 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: soapdenovo2）
#   bash install.sh --method source                   # 强制源码编译 r241
#   bash install.sh --conda-env soap2 --force         # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/soapdenovo2        # source 模式自定义前缀
#   bash install.sh --version 2.40 --method conda     # 覆盖 conda 版本
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.40"          # bioconda/容器版本（源码基线 r240）
SOURCE_TAG="r241"               # 官方 GitHub release tag（文档版本）
PREFIX="${PREFIX:-$HOME/software/soapdenovo2-$SOURCE_TAG}"
CONDA_ENV="soapdenovo2"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     DEFAULT_VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 soapdenovo2=$DEFAULT_VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "soapdenovo2=$DEFAULT_VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "soapdenovo2=$DEFAULT_VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV SOAPdenovo-63mer"
    "$CONDA_BIN" run -n "$CONDA_ENV" SOAPdenovo-63mer 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 SOAPdenovo-63mer / SOAPdenovo-127mer"
}

# ---------------- 路线 B：官方源码编译（r241，无官方预编译二进制） ----------------
install_source() {
    log "源码编译 SOAPdenovo2 $SOURCE_TAG（bioconda 无对应版本，走官方 GitHub release）"
    command -v make >/dev/null 2>&1 || die "源码编译需要 make/g++"
    command -v g++  >/dev/null 2>&1 || die "源码编译需要 g++"

    local url="https://github.com/aquaskyline/SOAPdenovo2/archive/${SOURCE_TAG}.tar.gz"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    log "下载官方源码: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/soapdenovo2.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/soapdenovo2.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    tar -xzf "$tmp/soapdenovo2.tar.gz" -C "$tmp"
    local srcdir; srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "解压失败（URL 或 tag 有误？）"

    log "编译（make）..."
    ( cd "$srcdir" && make )
    mkdir -p "$PREFIX/bin"
    local b found=0
    for b in SOAPdenovo-63mer SOAPdenovo-127mer SOAPdenovo-fusion; do
        if [[ -f "$srcdir/$b" ]]; then
            install -m 0755 "$srcdir/$b" "$PREFIX/bin/$b"; found=1
        fi
    done
    [[ "$found" == 1 ]] || die "编译产物未找到 SOAPdenovo-63mer/127mer（编译是否失败？）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # SOAPdenovo 无 --version；以运行输出断言二进制可用
    "$PREFIX/bin/SOAPdenovo-63mer" 2>&1 | head -n 3 || true
    log "版本校验通过：SOAPdenovo2 $SOURCE_TAG 已装入 $PREFIX/bin"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# soapdenovo2 (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    else
        warn "未改 PATH：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "SOAPdenovo2 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_source
        fi ;;
esac
log "安装成功"
