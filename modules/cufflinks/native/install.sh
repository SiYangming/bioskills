#!/usr/bin/env bash
# =============================================================================
# install.sh — Cufflinks 宿主机本地安装脚本
#
# ⚠️ 淘汰技术：Cufflinks 2.2.1 为最后稳定版（约 2014），官方已停更；新项目请改用 StringTie
#    （转录本组装）+ DESeq2/edgeR（差异表达）。本脚本仅供历史复现。
#
# 归属    ：bioskills modules/cufflinks/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::cufflinks
#   - binary 路线（无 conda 兜底）：官方预编译二进制（Linux/OSX x86_64），用户级前缀安装
#     到 --prefix（默认 ~/software/cufflinks-<ver>），无需 root、不写 /opt
#   - 版本默认 2.2.1，与 modules/cufflinks/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://cole-trapnell-lab.github.io/cufflinks/
#   bioconda : https://anaconda.org/bioconda/cufflinks
#   binaries : http://cole-trapnell-lab.github.io/cufflinks/assets/downloads/cufflinks-2.2.1.{Linux,OSX}_x86_64.tar.gz
#   (容器：quay.io/biocontainers/cufflinks —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: cufflinks）
#   bash install.sh --method binary                   # 强制官方预编译二进制（无需 conda）
#   bash install.sh --conda-env cl --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/cufflinks          # binary 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

warn_deprecated() {
    printf '\033[1;33m[install] ⚠️  Cufflinks 为淘汰技术（最后稳定版 2.2.1，官方停更）；仅建议历史复现，新项目请用 StringTie / DESeq2 / edgeR。\033[0m\n' >&2
}

DEFAULT_VERSION="2.2.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/cufflinks-$DEFAULT_VERSION}"
CONDA_ENV="cufflinks"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方预编译二进制内嵌 sha256（仅 linux-64 / osx-64）
SHA256_LINUX_X86_64="d891c58e18d9256004a337f256d71393002fe69734d28b95dda2e6d0374d7e23"
SHA256_OSX_X86_64="98a78cdf9e38783f9809d74faadc70654977d5f6120e262ef623a04840da00c6"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

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

warn_deprecated

OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

platform_ok_binary() {
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; }
}

assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 cufflinks=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "cufflinks=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "cufflinks=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV cufflinks --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" cufflinks --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 cufflinks / cuffmerge / cuffcompare / cuffdiff"
}

# ---------------- 路线 B：官方预编译二进制 ----------------
install_binary() {
    local plat url sha tmp srcdir
    case "$OS" in
        Linux)  plat="Linux_x86_64"; sha="$SHA256_LINUX_X86_64" ;;
        Darwin) plat="OSX_x86_64";   sha="$SHA256_OSX_X86_64" ;;
    esac
    url="http://cole-trapnell-lab.github.io/cufflinks/assets/downloads/cufflinks-${VERSION}.${plat}.tar.gz"

    log "下载官方二进制: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/cufflinks.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/cufflinks.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载二进制"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/cufflinks.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/cufflinks.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi

    tar -xzf "$tmp/cufflinks.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "压缩包内未找到解压目录"

    local bin f
    for f in cufflinks cuffmerge cuffcompare cuffdiff cuffquant cuffnorm gffread gffcompare; do
        bin="$(find "${srcdir:-$tmp}" -maxdepth 2 -type f -name "$f" -perm -u+x | head -1)"
        [[ -n "$bin" ]] && install -m 0755 "$bin" "$PREFIX/bin/$f"
    done
    [[ -x "$PREFIX/bin/cufflinks" ]] || die "未找到可执行文件 cufflinks（URL 或版本号有误？）"

    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/cufflinks"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# cufflinks (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 cufflinks 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "cufflinks $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方二进制（仅 linux-x64 / macos-x64）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方二进制，无法自动安装"
        fi ;;
esac
log "安装成功（⚠️ 淘汰技术，仅供历史复现）"
