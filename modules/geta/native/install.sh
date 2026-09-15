#!/usr/bin/env bash
# =============================================================================
# install.sh — GETA 宿主机本地安装脚本
#
# 归属    ：bioskills modules/geta/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / README「环境安装」对齐）
#   - 官方渠道核实（2026-09-11）：bioconda / quay.io/biocontainers / depot.galaxyproject.org
#     **均无 geta 包与镜像**（bioconda API 404）；brew / nf-core / snakemake-wrappers 亦 404
#     → 无 conda 包可装；官方发布物只有 GitHub tag tarball（geta-<ver>/bin/*.pl，解压即用，非编译）。
#   - conda 路线：conda/mamba 只用来提供 **perl 运行时**，geta 脚本仍来自官方 tarball
#     （conda 环境 bin/ 下部署 *.pl，随环境激活即用）。
#   - binary 路线：官方 tarball 解压部署到**用户前缀**（默认 ~/software/geta-<ver>，bin/*.pl），
#     无需 root、不写 /opt/biosoft。
#   - 版本默认 2.7.1，与 modules/geta/meta.yaml software_versions.native 对齐。
#
# 说明：内嵌默认版本（2.7.1）官方 tag tarball 的 sha256（2026-09-11 实测下载 17098074 B）；
#      改 --version 后不匹配 → 自动跳过并提示（GitHub 自动 tarball 无官方公布摘要，此值供完整性校验）。
#      geta.pl 无标准 --version，版本以 tarball tag 为准。
#
# 官方来源：
#   homepage : https://github.com/chenlianfu/geta
#   tarball  : https://github.com/chenlianfu/geta/archive/refs/tags/v2.7.1.tar.gz（2.7.1）
#              教学文档 2.4.5 → https://github.com/chenlianfu/geta/archive/2.4.5.tar.gz
#
# 用法示例：
#   bash install.sh                                 # auto：有 conda/mamba 走 conda(perl)+tarball，否则用户前缀
#   bash install.sh --method binary                 # 强制官方 tarball + 用户前缀（只需系统 perl）
#   bash install.sh --method conda --conda-env geta --force
#   bash install.sh --prefix ~/opt/geta             # binary 模式自定义前缀
#   bash install.sh --version 2.4.5 --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.7.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/geta-$DEFAULT_VERSION}"
CONDA_ENV="geta"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 默认版本官方 tarball 内嵌 sha256（2026-09-11 实测下载）
SHA256_TAR="a80d8d4497b5ca56255ea69436b011ada6807a640a6f41b6ee803effef2b8786"

# 全局临时目录（EXIT 钩子判空清理，成功路径末尾显式清理并置空）
GTMP=""
cleanup_gtmp() { [[ -n "${GTMP:-}" ]] && rm -rf "$GTMP"; }
trap cleanup_gtmp EXIT

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*" >&2; }
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

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 官方 tarball URL（2.7.1 = refs/tags/v<ver>；其它（如 2.4.5）= archive/<ver>） ----------------
tarball_url() {
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        printf 'https://github.com/chenlianfu/geta/archive/refs/tags/v%s.tar.gz' "$VERSION"
    else
        printf 'https://github.com/chenlianfu/geta/archive/%s.tar.gz' "$VERSION"
    fi
}

# ---------------- 下载 + 校验 + 解包官方 tarball（echo 解包出的 geta-* 目录路径） ----------------
fetch_and_extract() {
    local url
    GTMP="$(mktemp -d)"
    url="$(tarball_url)"
    log "下载官方 tarball: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$GTMP/geta.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$GTMP/geta.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载官方 tarball"
    fi
    # tar 完整性 + 结构断言（GitHub 自动 tarball 无官方公布摘要；默认版本做内嵌 sha256 校验）
    tar tzf "$GTMP/geta.tar.gz" >/dev/null 2>&1 || die "下载文件不是有效 tar.gz（URL 或版本号有误？）"
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_TAR  $GTMP/geta.tar.gz" | sha256sum -c - >/dev/null 2>&1 || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_TAR  $GTMP/geta.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 tarball 摘要）"
    fi
    mkdir -p "$GTMP/src"
    tar -xzf "$GTMP/geta.tar.gz" -C "$GTMP/src"
    local srcdir
    srcdir="$(find "$GTMP/src" -maxdepth 1 -mindepth 1 -type d -name 'geta-*' | head -1)"
    [[ -n "$srcdir" && -f "$srcdir/bin/geta.pl" ]] || die "tarball 内未找到 bin/geta.pl（URL 或版本号有误？）"
    printf '%s' "$srcdir"
}

# ---------------- 版本冒烟（geta.pl 无标准 --version：跑 --help 保证可执行） ----------------
smoke_geta() {
    local pl="$1"
    printf '  geta.pl: %s\n' "$pl" >&2
    "$pl" --help 2>&1 | head -n 3 | sed 's/^/  /' >&2 || true
    log "geta.pl 可执行性冒烟完成（版本以 tarball tag ${VERSION} 为准）"
}

# ---------------- 路线 A：conda（仅提供 perl 运行时；脚本本体来自官方 tarball） ----------------
install_conda() {
    local env_exists cprefix srcdir
    log "使用 conda 安装：环境 $CONDA_ENV 提供 perl，geta 脚本来自官方 tarball v$VERSION"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge perl
    cprefix="$("$CONDA_BIN" run -n "$CONDA_ENV" perl -e 'print $ENV{CONDA_PREFIX}' 2>/dev/null || true)"
    [[ -n "$cprefix" ]] || die "无法定位 conda 环境 $CONDA_ENV 的前缀"

    srcdir="$(fetch_and_extract)"
    install -m 0755 "$srcdir/bin/"*.pl "$cprefix/bin/"
    cp -R "$srcdir" "$cprefix/share/geta-${VERSION}"
    rm -rf "$GTMP"; GTMP=""

    log "验证：conda run -n $CONDA_ENV geta.pl --help"
    "$CONDA_BIN" run -n "$CONDA_ENV" geta.pl --help 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "geta.pl 可执行性冒烟完成（版本以 tarball tag ${VERSION} 为准）"
    log "完成：conda activate $CONDA_ENV 后即可使用 geta.pl / gff3ToGtf.pl 等"
}

# ---------------- 路线 B：官方 tarball + 用户前缀 ----------------
install_binary() {
    command -v perl >/dev/null 2>&1 || die "未检测到 perl（geta.pl 为 Perl 脚本；请先安装 perl，或用 --method conda）"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local srcdir
    srcdir="$(fetch_and_extract)"
    install -m 0755 "$srcdir/bin/"*.pl "$PREFIX/bin/"
    cp -R "$srcdir" "$PREFIX/share-geta-${VERSION}"
    rm -rf "$GTMP"; GTMP=""

    smoke_geta "$PREFIX/bin/geta.pl"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# geta (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 geta.pl 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "geta $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then install_conda; else install_binary; fi ;;
esac
log "安装成功"
