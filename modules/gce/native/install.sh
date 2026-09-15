#!/usr/bin/env bash
# =============================================================================
# install.sh — GCE (Genome Characteristics Estimation) 宿主机本地安装脚本
#
# 归属    ：bioskills modules/gce/native/install.sh（native 实现安装方式）
# 背景    ：GCE 1.0.0 无任何官方 conda 包 / 容器渠道（2026-09 核实 bioconda →
#           quay.io/biocontainers → depot.galaxyproject.org 全无），官方发布源
#           ftp://ftp.genomics.org.cn/pub/gce 已停服（HTTP/HTTPS 探测 000）。
#           因此本脚本走「官方 tarball 源码 make」路线（tarball 亦随包提供 2012 年
#           预编译 x86_64 二进制，可用 --method binary 直接布署，兼容性未核实）。
#
# 版本默认 1.0.0，与 modules/gce/meta.yaml software_versions.native 对齐。
#
# 官方来源：
#   homepage : https://github.com/fanagislab/GCE（官方后继仓库，含 gce-1.0.2）
#   ftp      : ftp://ftp.genomics.org.cn/pub/gce/gce-1.0.0.tar.gz（已停服）
#   镜像①（首选，版本化 release，与本仓库同账号维护）：
#           https://github.com/SiYangming/GCE/releases/download/gce-1.0.0/gce-1.0.0.tar.gz
#           2026-09 核实 200，sha256 与下方内嵌值一致（同一 tarball）
#   镜像②（fallback）：https://github.com/nottwy/genome-character-estimator（gce-1.0.0.tar.gz）
#
# 用法示例：
#   bash install.sh                                # 默认 source：下载 tarball 后 make 重编译 gce
#   bash install.sh --method binary                # 直接用 tarball 内预编译二进制（不编译）
#   bash install.sh --prefix ~/opt/gce --force     # 自定义前缀 / 已存在时强制重建
#   bash install.sh --no-path-update               # 不写 PATH
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.0.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/gce-$DEFAULT_VERSION}"
METHOD="auto"          # auto | source | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 tarball 下载源（按序尝试；两源为同一 tarball，已内嵌其 sha256）
#   ① SiYangming/GCE 版本化 release（首选）② nottwy 社区镜像（fallback）
TARBALL_URLS=(
    "https://github.com/SiYangming/GCE/releases/download/gce-${DEFAULT_VERSION}/gce-${DEFAULT_VERSION}.tar.gz"
    "https://github.com/nottwy/genome-character-estimator/raw/master/gce-${DEFAULT_VERSION}.tar.gz"
)
SHA256_TARBALL="0eb4f2d3247527d9881e5ab993a12e9800a0b465d8acb4451ede951b2bdf99e1"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|source|binary}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|source|binary) ;; *) die "--method 仅支持 auto|source|binary（收到: ${METHOD}）" ;; esac
[[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}）：本脚本仅内嵌 1.0.0 的镜像 URL/sha256，其余版本请自行核对来源"

OS="$(uname -s)"; ARCH="$(uname -m)"

# ---------------- 版本断言（gce -h 打印 Version: 1.0.0） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -h 2>&1 || true)"
    printf '  %s\n' "$(printf '%s' "$out" | head -n 2)"
    grep -q "${DEFAULT_VERSION//./\.}" <<<"$out" || die "版本校验失败：期望输出含 ${DEFAULT_VERSION}"
    log "版本校验通过：${DEFAULT_VERSION}"
}

# ---------------- 下载 tarball（多源按序尝试 + sha256 校验） ----------------
verify_sha256() {
    local dest="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$SHA256_TARBALL  $dest" | sha256sum -c - >/dev/null 2>&1
    else
        echo "$SHA256_TARBALL  $dest" | shasum -a 256 -c - >/dev/null 2>&1
    fi
}

download_tarball() {
    local dest="$1" url ok=0
    for url in "${TARBALL_URLS[@]}"; do
        log "下载 tarball：$url"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$dest" "$url" || { warn "下载失败，尝试下一来源：$url"; continue; }
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$dest" "$url" || { warn "下载失败，尝试下一来源：$url"; continue; }
        else
            die "需要 curl 或 wget 下载 tarball"
        fi
        if [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
            log "非默认版本，跳过 sha256 校验"
            ok=1; break
        fi
        if verify_sha256 "$dest"; then
            log "sha256 校验通过（${url}）"
            ok=1; break
        fi
        warn "sha256 校验失败，尝试下一来源：$url"
    done
    [[ "$ok" == 1 ]] || die "全部下载源均失败或校验不通过：${TARBALL_URLS[*]}"
}

# ---------------- 主流程 ----------------
log "GCE ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
if [[ -d "$PREFIX" && "$FORCE" != 1 ]]; then
    die "目标前缀已存在：${PREFIX}（加 --force 重建，或改用 --prefix 指定其它路径）"
fi
[[ "$FORCE" == 1 ]] && rm -rf "$PREFIX"
mkdir -p "$PREFIX/bin"

TMP="$(mktemp -d)"
cleanup_tmp() { [[ -n "${TMP:-}" ]] && rm -rf "$TMP"; }
trap cleanup_tmp EXIT

download_tarball "$TMP/gce.tar.gz"
tar -xzf "$TMP/gce.tar.gz" -C "$TMP"
SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name 'gce-*' | head -1)"
[[ -n "$SRC" ]] || die "tarball 内未找到 gce-* 源码目录"

if [[ "$METHOD" == "binary" ]]; then
    if [[ "$OS" != "Linux" || "$ARCH" != "x86_64" ]]; then
        die "--method binary 的预编译二进制为 linux x86_64（2012 年产物），本机 ${OS}/${ARCH} 不适用；请用 --method source"
    fi
    log "使用 tarball 内预编译二进制（不编译；现代 glibc 兼容性未核实）"
else
    command -v g++ >/dev/null 2>&1 || die "--method source 需要 g++（请先安装编译器）"
    log "源码编译 gce（make：g++ -o gce gce.cpp）"
    ( cd "$SRC" && make )
fi

install -m 0755 "$SRC/gce" "$PREFIX/bin/gce"
[[ -f "$SRC/kmerfreq/kmer_freq_hash/kmer_freq_hash" ]] \
    && install -m 0755 "$SRC/kmerfreq/kmer_freq_hash/kmer_freq_hash" "$PREFIX/bin/kmer_freq_hash"
for b in kmer_freq kmer_freq_pfile kmer_freq_pread; do
    [[ -f "$SRC/kmerfreq/kmer_freq_array/$b" ]] && install -m 0755 "$SRC/kmerfreq/kmer_freq_array/$b" "$PREFIX/bin/$b"
done

rm -rf "$TMP"; TMP=""; trap - EXIT

assert_version "$PREFIX/bin/gce"

if [[ "$UPDATE_PATH" == 1 ]]; then
    line="export PATH=\"$PREFIX/bin:\$PATH\""
    if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
        log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
    else
        { echo ""; echo "# gce (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
        log "已追加 PATH 到 $PROFILE"
    fi
    log "完成：重新登录或 source $PROFILE 后执行 gce -h 即可"
else
    log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
fi
log "安装成功"
