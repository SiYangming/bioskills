#!/usr/bin/env bash
# =============================================================================
# install.sh — Canu 宿主机本地安装脚本
#
# 归属    ：bioskills modules/canu/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 + 官方预编译二进制包优先）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::canu=2.0
#   - binary 路线（无 conda 兜底）：官方 GitHub release v2.0 预编译包
#     （canu-2.0.Linux-amd64.tar.xz / canu-2.0.Darwin-amd64.tar.xz），用户级前缀
#     安装到 --prefix（默认 ~/software/canu-2.0），无需 root、不写 /opt
#
# 官方来源：
#   homepage : https://github.com/marbl/canu
#   release  : https://github.com/marbl/canu/releases/tag/v2.0
#   bioconda : https://anaconda.org/bioconda/canu
#   (容器：quay.io/biocontainers/canu —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方预编译包
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: canu）
#   bash install.sh --method binary                   # 强制官方 release 预编译包（无需 conda）
#   bash install.sh --conda-env canu20 --force        # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/canu               # binary 模式自定义前缀
#   bash install.sh --version 2.3 --method conda      # 覆盖 conda 版本（binary 仅 v2.0 有预编译包）
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/canu-$DEFAULT_VERSION}"
CONDA_ENV="canu"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release v2.0 预编译包内嵌 sha256（2026-09 实测下载后 shasum -a 256 得到，非编造）
SHA256_LINUX_X86_64="29352586a4e242fa601b14c77edafe81ac3a49511587fdb4c73c2f19dec6c295"
SHA256_OSX_X86_64="5cf5d6215c4e34c652cccac422ca98caec1d5d4c13d6d60bd344c7756ebeeab1"

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
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|binary}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# binary 模式仅官方 v2.0 release 覆盖的平台（linux-x64 / macos-x64）
platform_ok_binary() {
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 canu=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "canu=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "canu=$VERSION"
    fi
    local out
    out="$("$CONDA_BIN" run -n "$CONDA_ENV" canu --version 2>&1 | head -n 1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}"
    log "完成：conda activate $CONDA_ENV 后即可使用 canu"
}

# ---------------- 路线 B：官方 GitHub release 预编译包 ----------------
install_binary() {
    local plat url sha inner
    case "$OS" in
        Linux)  plat="Linux-amd64";  sha="$SHA256_LINUX_X86_64" ;;
        Darwin) plat="Darwin-amd64"; sha="$SHA256_OSX_X86_64" ;;
    esac
    url="https://github.com/marbl/canu/releases/download/v${VERSION}/canu-${VERSION}.${plat}.tar.xz"

    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/canu.tar.xz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/canu.tar.xz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/canu.tar.xz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/canu.tar.xz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（v2.0 之外官方未提供预编译包）"
    fi

    tar -xJf "$tmp/canu.tar.xz" -C "$PREFIX"
    inner="$(find "$PREFIX" -maxdepth 1 -mindepth 1 -type d -name "canu-*" | head -1)"
    [[ -n "$inner" ]] || die "解压后未找到 canu-* 目录"
    local bindir="$inner/${plat}/bin"
    [[ -x "$bindir/canu" ]] || die "未找到 $bindir/canu（包结构是否变化？）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    local out
    out="$("$bindir/canu" --version 2>&1 | head -n 1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$bindir:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$bindir" "$PROFILE"; then
            log "PATH 已包含 $bindir，跳过写入 $PROFILE"
        else
            { echo ""; echo "# canu (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 canu 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$bindir:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "Canu $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译包（仅 linux-x64 / macos-x64 v2.0）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方预编译包，无法自动安装"
        fi ;;
esac
log "安装成功"
