#!/usr/bin/env bash
# =============================================================================
# install.sh — wtdbg2 宿主机本地安装脚本
#
# 归属    ：bioskills modules/wtdbg2/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 + 官方预编译二进制包优先）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::wtdbg=2.5
#     （⚠️ bioconda 包名为 wtdbg，非 wtdbg2）
#   - binary 路线（无 conda 兜底）：官方 release v2.5 预编译包 wtdbg-2.5_x64_linux.tgz，
#     用户级前缀安装到 --prefix（默认 ~/software/wtdbg-2.5），无需 root、不写 /opt
#
# 官方来源：
#   homepage : https://github.com/ruanjue/wtdbg2
#   release  : https://github.com/ruanjue/wtdbg2/releases/tag/v2.5
#   bioconda : https://anaconda.org/bioconda/wtdbg
#   (容器：quay.io/biocontainers/wtdbg —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方预编译包
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: wtdbg2）
#   bash install.sh --method binary                   # 强制官方 release 预编译包（Linux x86_64）
#   bash install.sh --conda-env wtdbg --force         # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/wtdbg2             # binary 模式自定义前缀
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.5"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/wtdbg-$DEFAULT_VERSION}"
CONDA_ENV="wtdbg2"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release v2.5 预编译包（仅 linux-x86_64）内嵌 sha256
# （2026-09 实测下载 wtdbg-2.5_x64_linux.tgz 后 shasum -a 256 得到，非编造）
SHA256_LINUX_X86_64="a3ed9ef2587fba7aaf9cc19108288cddd43938dc16665dafead9fc66d200b780"

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

# 官方 release 预编译包仅覆盖 linux-x86_64
platform_ok_binary() { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }

# ---------------- 路线 A：conda / bioconda（包名 wtdbg） ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 wtdbg=$VERSION 到环境: $CONDA_ENV（bioconda 包名为 wtdbg）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "wtdbg=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "wtdbg=$VERSION"
    fi
    local out
    out="$("$CONDA_BIN" run -n "$CONDA_ENV" wtdbg2 -V 2>&1 | head -n 1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}"
    log "完成：conda activate $CONDA_ENV 后即可使用 wtdbg2 / wtpoa-cns"
}

# ---------------- 路线 B：官方 GitHub release 预编译包 ----------------
install_binary() {
    local url="https://github.com/ruanjue/wtdbg2/releases/download/v${VERSION}/wtdbg-${VERSION}_x64_linux.tgz"
    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/wtdbg.tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/wtdbg.tgz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_LINUX_X86_64  $tmp/wtdbg.tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_LINUX_X86_64  $tmp/wtdbg.tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    tar -xzf "$tmp/wtdbg.tgz" -C "$tmp"
    local srcdir; srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "解压失败（URL 或版本号有误？）"

    local b
    for b in wtdbg2 wtpoa-cns wtdbg-cns kbm2 pgzf wtdbg2.pl; do
        [[ -f "$srcdir/$b" ]] && install -m 0755 "$srcdir/$b" "$PREFIX/bin/$b"
    done
    [[ -x "$PREFIX/bin/wtdbg2" ]] || die "预编译包内未找到 wtdbg2 可执行文件"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    local out
    out="$("$PREFIX/bin/wtdbg2" -V 2>&1 | head -n 1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# wtdbg2 (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 wtdbg2 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "wtdbg2 $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译包（仅 linux-x86_64）；macOS/ARM 请改用 conda 或源码编译（https://github.com/ruanjue/wtdbg2）"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方预编译包；请从 https://github.com/ruanjue/wtdbg2 源码编译"
        fi ;;
esac
log "安装成功"
