#!/usr/bin/env bash
# =============================================================================
# install.sh — Jellyfish 宿主机本地安装脚本
#
# 归属    ：bioskills modules/jellyfish/native/install.sh（native 实现安装方式）
# 现代规范（AGENT.md §7 官方镜像优先 / README「安装方式（本地）」对齐）：
#   - conda  路线（auto 首选）：mamba/conda 创建独立环境，pin bioconda::kmer-jellyfish
#     （Jellyfish k-mer 计数器的 bioconda 现行包名）
#   - binary 路线（无 conda 兜底）：官方 release 预编译静态二进制 jellyfish-linux，
#     用户级前缀（默认 ~/software/jellyfish-<ver>），无需 root
#   - 版本默认 2.3.0，与 modules/jellyfish/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/gmarcais/Jellyfish
#   release  : https://github.com/gmarcais/Jellyfish/releases/tag/v2.3.0
#   bioconda : https://anaconda.org/bioconda/kmer-jellyfish
#
# 用法示例：
#   bash install.sh                          # auto：有 conda/mamba 走 bioconda，否则官方静态二进制
#   bash install.sh --method conda           # 强制 conda（默认建独立 env: jellyfish）
#   bash install.sh --method binary          # 强制官方 release 静态二进制（仅 linux-x64）
#   bash install.sh --conda-env jf --force   # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/jellyfish # binary 模式自定义前缀
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.3.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/jellyfish-$DEFAULT_VERSION}"
CONDA_ENV="jellyfish"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release 预编译静态二进制（仅 linux-x64）；已内嵌 sha256
BINARY_URL="https://github.com/gmarcais/Jellyfish/releases/download/v${DEFAULT_VERSION}/jellyfish-linux"
SHA256_LINUX_X86_64="8c6e46c12f7fa3f00a45a9d6030e24535d5dec21491777538d411c463bf978c0"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
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

OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

platform_ok_binary() { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }

assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda（kmer-jellyfish） ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 kmer-jellyfish=$VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "kmer-jellyfish=$VERSION"
    log "验证：conda run -n $CONDA_ENV jellyfish --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" jellyfish --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 jellyfish"
}

# ---------------- 路线 B：官方 release 静态二进制 ----------------
install_binary() {
    local url sha
    url="$BINARY_URL"; sha="$SHA256_LINUX_X86_64"
    if [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        url="https://github.com/gmarcais/Jellyfish/releases/download/v${VERSION}/jellyfish-linux"
        sha=""
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    log "下载官方静态二进制: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/jellyfish-linux" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/jellyfish-linux" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ -n "$sha" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/jellyfish-linux" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/jellyfish-linux" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    fi

    install -m 0755 "$tmp/jellyfish-linux" "$PREFIX/bin/jellyfish"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/jellyfish"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# jellyfish (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 jellyfish --version 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "jellyfish $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方二进制（仅 linux-x64）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方静态二进制，无法自动安装"
        fi ;;
esac
log "安装成功"
