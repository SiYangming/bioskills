#!/usr/bin/env bash
# =============================================================================
# install.sh — MISA（misa.pl v2.1）宿主机本地安装脚本
#
# 归属    ：bioskills modules/misa/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / README「环境安装」对齐）
#   - 官方渠道核实（2026-09）：bioconda / quay.io/biocontainers / depot.galaxyproject.org
#     **均无 misa 包与镜像**（bioconda API 404 "misa" could not be found）→ 无 conda 包可装；
#     官方发布物只有源码包 https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip
#     （内含 misa.pl + misa.ini，纯 Perl，无需编译）。
#   - conda 路线：conda/mamba 只用来提供 **perl 运行时**，misa.pl/misa.ini 仍来自官方源包
#     （conda 环境 bin/ 下部署 misa.pl，随环境激活即用）。
#   - binary 路线：官方源包解压部署到**用户前缀**（默认 ~/software/misa-<ver>，
#     bin/misa.pl + share/misa/misa.ini），无需 root、不写 /opt/biosoft。
#   - 版本默认 2.1，与 modules/misa/meta.yaml software_versions.native 对齐。
#
# 官方来源：
#   homepage : https://webblast.ipk-gatersleben.de/misa/
#   source   : https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip
#              （v2.1，2020-08-25；sha256 43d90953489dbf428f4ed051a099a942314d3ccbea6226a7c72fd44216b243b8）
#   GitHub 备份（同源文件，v2.1 升级版；可选参考）：
#              https://github.com/SiYangming/SSR_marker_design（misa.pl / misa.ini / misa_primer3.pl）
#
# 用法示例：
#   bash install.sh                                 # auto：有 conda/mamba 走 conda(perl)+官方源包，否则用户前缀
#   bash install.sh --method binary                 # 强制官方源包 + 用户前缀（只需系统 perl）
#   bash install.sh --method conda --conda-env misa --force
#   bash install.sh --prefix ~/opt/misa             # binary 模式自定义前缀
#   bash install.sh --version 2.1 --profile ~/.zshrc --no-path-update
#
# 说明：misa.pl 无 --version；版本以 `misa.pl -help` 头部
#       「Program name: misa.pl / Release date: 25/08/20 (version 2.1)」为准（-help 走 die，退出码 255）。
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/misa-$DEFAULT_VERSION}"
CONDA_ENV="misa"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

MISA_ZIP_URL="https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip"
# 官方源包（misa_sourcecode_25082020.zip，2026-09 实测下载）内嵌 sha256
SHA256_ZIP="43d90953489dbf428f4ed051a099a942314d3ccbea6226a7c72fd44216b243b8"

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

[[ "$VERSION" == "$DEFAULT_VERSION" ]] || \
    warn "非默认版本（${VERSION}）：官方仅提供 2020-08-25 单一源包（v2.1），将沿用同一 URL 并跳过内嵌 sha256 校验"

# ---------------- 下载官方源包（返回下载文件路径） ----------------
fetch_zip() {
    local tmp="$1" zip="$1/misa_sourcecode.zip"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$zip" "$MISA_ZIP_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$zip" "$MISA_ZIP_URL"
    else
        die "需要 curl 或 wget 下载官方源包"
    fi
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_ZIP  $zip" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_ZIP  $zip" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    fi
    printf '%s' "$zip"
}

# ---------------- 解包官方源包到目标目录（misa.pl + misa.ini） ----------------
extract_zip() {
    local zip="$1" dest="$2"
    mkdir -p "$dest"
    if command -v unzip >/dev/null 2>&1; then
        unzip -o -q "$zip" -d "$dest"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$dest"
    else
        die "需要 unzip 或 python3 解压官方源包"
    fi
    [[ -f "$dest/misa.pl" ]] || die "源包内未找到 misa.pl（URL 或版本号有误？）"
    [[ -f "$dest/misa.ini" ]] || die "源包内未找到 misa.ini（URL 或版本号有误？）"
}

# ---------------- 版本断言（misa.pl 无 --version：-help 头部含 version 版本号，且退出码 255） ----------------
# 用法：assert_version <命令...>（自动追加 -help；如 assert_version perl /path/misa.pl）
assert_version() {
    local out
    out="$("$@" -help 2>&1 || true)"
    printf '%s\n' "$out" | sed 's/^/  /'
    grep -qE "version[[:space:]]+${VERSION//./\\.}" <<<"$out" \
        || die "版本校验失败：期望 -help 头部含 version ${VERSION}，实际输出见上"
    log "版本校验通过：misa.pl $VERSION"
}

# ---------------- 路线 A：conda（仅提供 perl 运行时；工具本体来自官方源包） ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装：环境 $CONDA_ENV 提供 perl，misa.pl 来自官方源包 v$VERSION"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 官方无 misa conda 包 → 只装 perl 运行时（conda-forge）
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge perl

    local cprefix tmp=""
    # 环境内只有 perl（官方无 misa conda 包）→ 用 perl 读 CONDA_PREFIX 定位环境前缀
    cprefix="$("$CONDA_BIN" run -n "$CONDA_ENV" perl -e 'print $ENV{CONDA_PREFIX}' 2>/dev/null || true)"
    [[ -n "$cprefix" ]] || die "无法定位 conda 环境 $CONDA_ENV 的前缀"
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    local zip
    zip="$(fetch_zip "$tmp")"
    extract_zip "$zip" "$tmp/src"
    install -m 0755 "$tmp/src/misa.pl" "$cprefix/bin/misa.pl"
    mkdir -p "$cprefix/share/misa"
    install -m 0644 "$tmp/src/misa.ini" "$cprefix/share/misa/misa.ini"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    log "验证：conda run -n $CONDA_ENV misa.pl -help"
    assert_version "$CONDA_BIN" run -n "$CONDA_ENV" misa.pl
    log "完成：conda activate $CONDA_ENV 后即可使用 misa.pl（misa.ini 位于 \$CONDA_PREFIX/share/misa/misa.ini；运行时需在当前目录，或用 native/main.py 自动准备）"
}

# ---------------- 路线 B：官方源包 + 用户前缀 ----------------
install_binary() {
    command -v perl >/dev/null 2>&1 || die "未检测到 perl（misa.pl 为 Perl 脚本；请先安装 perl，或用 --method conda）"
    log "下载官方源包: $MISA_ZIP_URL"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin" "$PREFIX/share/misa"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    local zip
    zip="$(fetch_zip "$tmp")"
    extract_zip "$zip" "$tmp/src"
    install -m 0755 "$tmp/src/misa.pl" "$PREFIX/bin/misa.pl"
    install -m 0644 "$tmp/src/misa.ini" "$PREFIX/share/misa/misa.ini"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version perl "$PREFIX/bin/misa.pl"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# misa (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 misa.pl 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
    log "misa.ini 位于 $PREFIX/share/misa/misa.ini（misa.pl 只从当前工作目录读 misa.ini，使用时需拷入运行目录或由 main.py 自动准备）"
}

# ---------------- 主流程 ----------------
log "misa $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
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
