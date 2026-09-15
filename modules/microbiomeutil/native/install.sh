#!/usr/bin/env bash
# =============================================================================
# install.sh — microbiomeutil 宿主机本地安装脚本
#
# 归属    ：bioskills modules/microbiomeutil/native/install.sh（native 实现安装方式）
# 迁移形态：自建兜底路线（AGENT.md §7：官方渠道 bioconda → quay.io/biocontainers →
#   depot.galaxyproject.org 全无 → 才自建；本脚本为宿主机源码编译安装）
#   - 官方渠道核实（2026-09）：bioconda（microbiomeutil / chimeraslayer）404、
#     quay.io/biocontainers 401（不存在）、depot.galaxyproject.org 404、nf-core / snakemake-wrappers
#     /homebrew 均无 → 无官方镜像/conda 包
#   - 官方仅提供 SourceForge 源码包（无预编译二进制），故走「源码 make」路线：
#       基于系统 gcc（NAST-iEr 为 C 程序）+ perl（ChimeraSlayer/WigeoN 为 Perl）
#   - 安装到 --prefix（默认 ~/software/microbiomeutil-<ver>），无需 root、不写 /opt
#   - 版本默认 r20110519，与 meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://microbiomeutil.sourceforge.net/
#   download : https://sourceforge.net/projects/microbiomeutil/files/
#              microbiomeutil-r20110519.tgz （133,623,556 bytes；SourceForge 仅公布 md5）
#
# 运行期外部依赖（需自行确保在 PATH 中，容器配方已内置）：
#   megablast （ncbi-blast+ 提供；apt install ncbi-blast+）
#   cdbtools  （cdbfasta/cdbyank；apt install cdbfasta）
#
# 用法示例：
#   bash install.sh                              # auto：无 conda 包，直接源码编译
#   bash install.sh --method source              # 显式源码编译
#   bash install.sh --prefix ~/opt/microbiomeutil
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="r20110519"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/microbiomeutil-$DEFAULT_VERSION}"
METHOD="auto"          # auto | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 SourceForge 源码包（SourceForge API 仅公布 md5；未公布 sha256）
SOURCE_URL="https://downloads.sourceforge.net/project/microbiomeutil/microbiomeutil-r20110519.tgz"
SOURCE_MD5="11eaac4b0468c05297ba88ec27bd4b56"

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
        --method)      METHOD="${2:?--method 需要 auto|source}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|source) ;; *) die "--method 仅支持 auto|source（收到: ${METHOD}；microbiomeutil 无 conda/官方镜像，仅源码路线）" ;; esac

OS="$(uname -s)"; ARCH="$(uname -m)"

# ---------------- 版本断言（microbiomeutil 无 --version；校验组件可执行文件） ----------------
assert_version() {
    local root="$1"
    [[ -x "$root/NAST-iEr/NAST-iEr" ]] || die "缺少 NAST-iEr 可执行文件: $root/NAST-iEr/NAST-iEr"
    [[ -f "$root/ChimeraSlayer/ChimeraSlayer.pl" ]] || die "缺少 ChimeraSlayer.pl: $root/ChimeraSlayer/ChimeraSlayer.pl"
    [[ -f "$root/WigeoN/run_WigeoN.pl" ]] || die "缺少 run_WigeoN.pl: $root/WigeoN/run_WigeoN.pl"
    log "组件校验通过：NAST-iEr / ChimeraSlayer.pl / run_WigeoN.pl 均已就位（版本 $VERSION）"
}

# ---------------- 主线：SourceForge 源码 make ----------------
install_source() {
    local tmp srcdir
    command -v make >/dev/null 2>&1 || die "缺少 make；请先安装构建工具（apt: build-essential / yum: gcc make）"
    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 \
        || die "缺少 C 编译器（gcc/cc）；apt: build-essential / yum: gcc"
    command -v perl >/dev/null 2>&1 || die "缺少 perl（ChimeraSlayer/WigeoN 为 Perl 脚本）"

    [[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}）：本脚本固定下载官方 r20110519 源码包"

    log "下载官方源码（SourceForge，约 127 MB）: $SOURCE_URL"
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fSL -o "$tmp/microbiomeutil.tgz" "$SOURCE_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/microbiomeutil.tgz" "$SOURCE_URL"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    if command -v md5sum >/dev/null 2>&1; then
        echo "$SOURCE_MD5  $tmp/microbiomeutil.tgz" | md5sum -c - >/dev/null 2>&1 \
            || die "md5 校验失败：下载文件不完整或被篡改"
    else
        echo "$SOURCE_MD5  $tmp/microbiomeutil.tgz" | md5 -q -c - >/dev/null 2>&1 \
            || die "md5 校验失败：下载文件不完整或被篡改"
    fi
    log "md5 校验通过"

    tar -xzf "$tmp/microbiomeutil.tgz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'microbiomeutil*' | head -1)"
    [[ -n "$srcdir" ]] || die "解压后未找到 microbiomeutil 源码目录"

    log "编译（make：构建 NAST-iEr C 程序；ChimeraSlayer/WigeoN 为 Perl 无需编译）"
    ( cd "$srcdir" && make ) || die "make 失败"

    log "安装到: $PREFIX"
    mkdir -p "$PREFIX"
    if [[ "$FORCE" != 1 && -e "$PREFIX/ChimeraSlayer" ]]; then
        die "$PREFIX 下已存在 microbiomeutil；加 --force 覆盖，或改用 --prefix"
    fi
    rm -rf "$PREFIX/ChimeraSlayer" "$PREFIX/NAST-iEr" "$PREFIX/WigeoN" "$PREFIX/RESOURCES"
    cp -R "$srcdir/ChimeraSlayer" "$srcdir/NAST-iEr" "$srcdir/WigeoN" "$srcdir/RESOURCES" "$PREFIX/"
    cp -R "$srcdir/README" "$PREFIX/README" 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX"

    if ! command -v megablast >/dev/null 2>&1; then
        warn "未检测到 megablast（ChimeraSlayer/WigeoN 运行期依赖）：apt install ncbi-blast+"
    fi
    if ! command -v cdbyank >/dev/null 2>&1; then
        warn "未检测到 cdbfasta/cdbyank（ChimeraSlayer/NAST-iEr 运行期依赖）：apt install cdbfasta"
    fi

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local d line
        for d in ChimeraSlayer NAST-iEr WigeoN; do
            line="export PATH=\"$PREFIX/$d:\$PATH\""
            if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/$d" "$PROFILE"; then
                log "PATH 已包含 $PREFIX/$d，跳过写入 $PROFILE"
            else
                { echo ""; echo "# microbiomeutil ($d) (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
                log "已追加 PATH 到 $PROFILE（$d）"
            fi
        done
        log "完成：重新登录或 source $PROFILE 后执行 ChimeraSlayer.pl 即可"
    else
        log "完成（未改 PATH）：使用时请手动把 \$PREFIX/{ChimeraSlayer,NAST-iEr,WigeoN} 加入 PATH"
    fi
}

# ---------------- 主流程 ----------------
log "microbiomeutil $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    source) install_source ;;
    auto)
        warn "bioconda 无 microbiomeutil 包（2026-09 核实 404），走官方 SourceForge 源码编译路线"
        install_source ;;
esac
log "安装成功"
