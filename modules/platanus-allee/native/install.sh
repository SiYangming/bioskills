#!/usr/bin/env bash
# =============================================================================
# install.sh — Platanus-allee 宿主机本地安装脚本
#
# 归属    ：bioskills modules/platanus-allee/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - source 路线（默认）：官方 GitHub 源码 tag v2.4.0 → make → 用户级前缀
#     （默认 ~/software/platanus-allee-2.4.0，免 root、不写 /opt）
#   - binary 路线：官方站点预编译二进制 tgz（需 --url 指定，官方直链本机不可达，不内置默认）
#   - ⚠️ 官方渠道（bioconda / quay.io / depot）2026-09 核实全无 Platanus-allee 包/镜像，
#     故本脚本不提供 conda 路线（conda 里没有该软件）。
#
# 官方来源：
#   homepage : http://platanus.bio.titech.ac.jp/platanus2
#   source   : https://github.com/rkajitani/Platanus-allee/archive/refs/tags/v2.4.0.tar.gz
#   prebuilt : http://platanus.bio.titech.ac.jp/?ddownload=431 (v2.2.2) / =347 (v2.0.2)
#   容器     ：本地自建（native/Dockerfile + Apptainer.def），无官方镜像
#
# 用法示例：
#   bash install.sh                                   # source：官方源码 make 到 ~/software/platanus-allee-2.4.0
#   bash install.sh --method source --prefix ~/opt/pa # 自定义前缀
#   bash install.sh --method binary --url <tgz或下载页URL>   # 官方预编译二进制
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.4.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/platanus-allee-$DEFAULT_VERSION}"
METHOD="source"        # auto|source|binary（无 conda 路线：官方无 bioconda 包）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
URL=""

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|source|binary}"; shift 2 ;;
        --url)         URL="${2:?--url 需要下载地址}";         shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|source|binary) ;; *) die "--method 仅支持 auto|source|binary（收到: ${METHOD}；官方无 conda 包）" ;; esac
[[ "$METHOD" == "auto" ]] && METHOD="source"

OS="$(uname -s)"; ARCH="$(uname -m)"

assert_binary() {
    local bin="$1" out
    [[ -x "$bin" ]] || die "未找到可执行文件: $bin"
    out="$("$bin" -v 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

write_path() {
    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# platanus-allee (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    else
        log "未改 PATH：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 路线 A：官方源码编译 ----------------
install_source() {
    command -v g++ >/dev/null 2>&1 || die "--method source 需要 g++（GCC>=4.4，支持 OpenMP）"
    command -v make >/dev/null 2>&1 || die "--method source 需要 make"
    local url="https://github.com/rkajitani/Platanus-allee/archive/refs/tags/v${VERSION}.tar.gz"
    log "下载官方源码: $url"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/pa.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/pa.tar.gz" "$url"
    else
        die "需要 curl 或 wget"
    fi
    tar -xzf "$tmp/pa.tar.gz" -C "$tmp"
    local srcdir; srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "源码解压失败"
    ( cd "$srcdir" && make -j"$(nproc 2>/dev/null || echo 4)" ) || die "make 编译失败（见上方 g++ 报错）"
    [[ -x "$srcdir/platanus_allee" ]] || die "编译后未找到 platanus_allee"
    mkdir -p "$PREFIX/bin"
    install -m 0755 "$srcdir/platanus_allee" "$PREFIX/bin/platanus_allee"
    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_binary "$PREFIX/bin/platanus_allee"
    write_path
}

# ---------------- 路线 B：官方预编译二进制 ----------------
install_binary() {
    [[ -n "$URL" ]] || die "--method binary 需要 --url（官方站点下载页，如 http://platanus.bio.titech.ac.jp/?ddownload=431；本机不可达，未内置默认）"
    log "下载官方预编译二进制: $URL"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/pa.tgz" "$URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/pa.tgz" "$URL"
    else
        die "需要 curl 或 wget"
    fi
    tar -xzf "$tmp/pa.tgz" -C "$tmp" 2>/dev/null || die "解压失败：--url 需指向 .tgz 预编译包"
    local bin_src; bin_src="$(find "$tmp" -type f -name platanus_allee -perm -111 | head -1)"
    [[ -n "$bin_src" ]] || die "预编译包内未找到 platanus_allee"
    mkdir -p "$PREFIX/bin"
    install -m 0755 "$bin_src" "$PREFIX/bin/platanus_allee"
    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_binary "$PREFIX/bin/platanus_allee"
    write_path
}

# ---------------- 主流程 ----------------
log "Platanus-allee $VERSION 安装开始（本机 ${OS}/${ARCH}；官方无 conda 包，走官方源码/预编译路线）"
case "$METHOD" in
    source) install_source ;;
    binary) install_binary ;;
esac
log "安装成功"
