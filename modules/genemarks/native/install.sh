#!/usr/bin/env bash
# =============================================================================
# install.sh — GeneMarkS / GeneMarkS-2 宿主机本地安装脚本（原核基因预测）
#
# 归属    ：bioskills modules/genemarks/native/install.sh（native 实现安装方式）
# 说明（重要）：
#   GeneMarkS/GeneMarkS-2 **无官方 conda 包、无公开镜像**（bioconda/quay/depot 2026-09 核实全无），
#   官方仅提供**预编译包**（genemark_suite_linux_64 / gms2_linux_64.gz），且**下载需先在线申请密钥/
#   同意学术许可**（https://exon.gatech.edu/GeneMark/license_download.cgi，学术非营利免费、一年有效、
#   商业另行授权）。官方下载链接由表单动态生成、无法硬编码，故本脚本安装「用户已授权的压缩包」。
#   本工具**区别于第七节 GeneMark-ES/ET（真核版）**，此处是原核版 GeneMarkS。
#   - 安装：解压预编译包到用户级前缀（默认 ~/software/genemarks-<ver>），写 PATH，无需 root
#   - 密钥：gms2 -> ~/.gmhmmp2_key；旧版 -> ~/.gm_key（脚本会检查并提示）
#   - 版本默认 1.14_1.25_lic（GeneMarkS-2；官方下载页标注）
#
# 官方来源：
#   homepage : http://exon.gatech.edu/GeneMark/
#   申请密钥 : https://exon.gatech.edu/GeneMark/license_download.cgi
#
# 用法示例：
#   # 先申请并下载授权压缩包（gms2_linux_64.gz / genemark_suite_linux_64.tar.gz），再：
#   bash install.sh --tarball ~/Downloads/gms2_linux_64.gz
#   bash install.sh --url "https://<授权直链>/gms2_linux_64.gz"   # 直接下载
#   bash install.sh --tarball pkg.gz --key ~/Downloads/gm_key_64.gms2
#   bash install.sh --prefix ~/software/genemarks --no-path-update
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="1.14_1.25_lic"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/genemarks-$DEFAULT_VERSION}"
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
TARBALL=""
URL=""
KEY_FILE=""

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --tarball)     TARBALL="${2:?--tarball 需要压缩包路径}"; shift 2 ;;
        --url)         URL="${2:?--url 需要下载链接}"; shift 2 ;;
        --key)         KEY_FILE="${2:?--key 需要密钥文件路径}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

log "genemarks $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"

# ---------------- 取得压缩包 ----------------
tmp=""
cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
trap cleanup_tmp EXIT
tmp="$(mktemp -d)"

pkg="$TARBALL"
if [[ -z "$pkg" && -n "$URL" ]]; then
    log "下载已授权压缩包: $URL"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL -o "$tmp/genemarks.pkg.gz" "$URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/genemarks.pkg.gz" "$URL"
    else
        die "需要 curl 或 wget 下载压缩包"
    fi
    pkg="$tmp/genemarks.pkg.gz"
fi
[[ -n "$pkg" ]] || die "缺少官方压缩包：请先用 --tarball <本地压缩包> 或 --url <授权直链>（申请见 http://exon.gatech.edu/GeneMark/license_download.cgi ）"
[[ -f "$pkg" ]] || die "压缩包不存在: $pkg"

# ---------------- 解压安装 ----------------
if [[ -d "$PREFIX" && "$FORCE" != 1 ]]; then
    die "前缀已存在: $PREFIX（加 --force 覆盖，或改用 --prefix）"
fi
mkdir -p "$PREFIX"

log "解压到: $PREFIX"
# 兼容 .gz（单文件 gz）与 .tar.gz
if tar -tzf "$pkg" >/dev/null 2>&1; then
    tar -xzf "$pkg" -C "$PREFIX"
elif gzip -dc "$pkg" > "$tmp/not_tar" 2>/dev/null && ! tar -tzf "$pkg" >/dev/null 2>&1; then
    # 单文件 gz（如 gms2_linux_64.gz 解出 tar）；先解 gz 再判 tar
    gzip -dc "$pkg" > "$tmp/unwrapped"
    if tar -tf "$tmp/unwrapped" >/dev/null 2>&1; then
        tar -xf "$tmp/unwrapped" -C "$PREFIX"
    else
        die "无法识别压缩包格式（既非 tar.gz 也非 tar 包裹）: $pkg"
    fi
else
    die "无法识别压缩包格式: $pkg"
fi

# 赋予可执行权限（gms2.pl / gmsn.pl / gmhmmp2 等）
find "$PREFIX" -maxdepth 3 \( -name '*.pl' -o -name 'gmhmmp2' -o -name 'gmhmmp' -o -name 'biogem' -o -name 'compp' \) -exec chmod +x {} \; 2>/dev/null || true

test -n "$(find "$PREFIX" -maxdepth 3 -name 'gms2.pl' -print -quit)" \
    || warn "未在 $PREFIX 内找到 gms2.pl（若是旧版 genemark_suite 包，请以 gmsn.pl 为准）"

# ---------------- 密钥 ----------------
key_dst="$HOME/.gmhmmp2_key"
if [[ -n "$KEY_FILE" ]]; then
    [[ -f "$KEY_FILE" ]] || die "密钥文件不存在: $KEY_FILE"
    # gm_key_64.gms2.gz 为 gzip 包裹；若是 .gz 则解压
    if gzip -t "$KEY_FILE" >/dev/null 2>&1; then
        gzip -dc "$KEY_FILE" > "$key_dst"
    else
        cp "$KEY_FILE" "$key_dst"
    fi
    chmod 600 "$key_dst"
    log "密钥已安装: $key_dst"
fi
if [[ -f "$HOME/.gmhmmp2_key" ]]; then
    log "检测到 GeneMarkS-2 密钥：$HOME/.gmhmmp2_key"
else
    warn "未检测到 ~/.gmhmmp2_key —— GeneMarkS-2 运行前请先申请并放置密钥"
    warn "  申请：https://exon.gatech.edu/GeneMark/license_download.cgi（gms2 密钥解出后放 ~/.gmhmmp2_key）"
fi
if [[ -f "$HOME/.gm_key" ]]; then
    log "检测到旧版 GeneMarkS 密钥：$HOME/.gm_key"
fi

# ---------------- PATH ----------------
if [[ "$UPDATE_PATH" == 1 ]]; then
    # 定位含 gms2.pl / gmsn.pl 的实际可执行目录
    bin_dir="$PREFIX"
    found_pl="$(find "$PREFIX" -maxdepth 3 \( -name 'gms2.pl' -o -name 'gmsn.pl' \) -print -quit)"
    if [[ -n "$found_pl" ]]; then bin_dir="$(dirname "$found_pl")"; fi
    line="export PATH=\"$bin_dir:\$PATH\""
    if [[ -f "$PROFILE" ]] && grep -qF "$bin_dir" "$PROFILE"; then
        log "PATH 已包含 $bin_dir，跳过写入 $PROFILE"
    else
        { echo ""; echo "# genemarks (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
        log "已追加 PATH 到 $PROFILE（bin 目录：$bin_dir）"
    fi
else
    log "完成（未改 PATH）：bin 目录在 $PREFIX"
fi

rm -rf "$tmp"; tmp=""; trap - EXIT
log "安装成功（版本 $VERSION；运行前请确认密钥已就位）"
