#!/usr/bin/env bash
# =============================================================================
# install.sh — snoscan 宿主机本地安装脚本
#
# 归属    ：bioskills modules/snoscan/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::snoscan
#   - binary 路线（无 conda 兜底）：官方源码归档 https://trna.ucsc.edu/software/snoscan.tar.gz
#     源码编译（squid 库 + snoscan/sort-snos），用户级前缀安装到 --prefix
#     （默认 ~/software/snoscan-<ver>），无需 root、不写 /opt
#   - 版本默认 1.0（bioconda 最新版），与 modules/snoscan/meta.yaml
#     software_versions.native 对齐
#
# 官方来源：
#   homepage : https://lowelab.ucsc.edu/snoscan/
#   bioconda : https://anaconda.org/bioconda/snoscan
#   source   : https://trna.ucsc.edu/software/snoscan.tar.gz（snoscan-0.9.1，官方现存源码归档）
#   (容器：quay.io/biocontainers/snoscan —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 注意：bioconda snoscan=1.0 的 source URL（lowelab.ucsc.edu/software/snoscan-1.0.tar.gz）
#       2026-09 已 404；官方现存可下载源码归档为 trna.ucsc.edu 上的 snoscan-0.9.1。
#       故 binary 路线编译得到的是 0.9.1；需要 1.0 请走 conda 路线。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: snoscan）
#   bash install.sh --method binary                   # 强制官方源码编译（无需 conda）
#   bash install.sh --conda-env snoscan --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/snoscan            # binary 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/snoscan-$DEFAULT_VERSION}"
CONDA_ENV="snoscan"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码归档（snoscan-0.9.1）内嵌 sha256；binary 路线固定使用该归档
SRC_URL="https://trna.ucsc.edu/software/snoscan.tar.gz"
SHA256_SRC="e6ad2f10354cb0c4c44d46d5f298476dbe250a4817afcc8d1c56d252e08ae19e"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
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

# binary 路线（源码编译）仅覆盖 linux/macos
platform_ok_binary() {
    { [[ "$OS" == "Linux"  ]] || [[ "$OS" == "Darwin" ]]; }
}

# ---------------- 版本断言（安装后运行 snoscan -h 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -h 2>&1 || true)"
    printf '%s\n' "$out" | sed 's/^/  /'
    grep -qi "snoscan" <<<"$out" || die "版本校验失败：snoscan -h 未输出预期内容"
    log "版本校验通过（snoscan -h 正常）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 snoscan=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "snoscan=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "snoscan=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV snoscan -h"
    "$CONDA_BIN" run -n "$CONDA_ENV" snoscan -h 2>&1 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 snoscan"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_binary() {
    local tmp srcdir
    log "下载官方源码归档: $SRC_URL"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/snoscan.tar.gz" "$SRC_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/snoscan.tar.gz" "$SRC_URL"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        echo "$SHA256_SRC  $tmp/snoscan.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
            || die "sha256 校验失败：下载的源码归档不完整或被篡改"
    else
        echo "$SHA256_SRC  $tmp/snoscan.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
            || die "sha256 校验失败：下载的源码归档不完整或被篡改"
    fi
    log "sha256 校验通过"

    tar -xzf "$tmp/snoscan.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'snoscan*' | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档内未找到 snoscan 目录"

    command -v make >/dev/null 2>&1 || die "源码编译需要 make"
    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || die "源码编译需要 C 编译器（cc/gcc）"

    ( cd "$srcdir" && { make -C squid-1.5.11 2>/dev/null || true; } && make )

    # 逐个安装编译产物（不同版本产物集合略有差异）
    local installed=0 f base
    for f in snoscan snoscanY snoscanH snoscanA sort-snos; do
        if [[ -f "$srcdir/$f" ]]; then
            install -m 0755 "$srcdir/$f" "$PREFIX/bin/$f"; installed=1
        fi
    done
    [[ "$installed" == 1 ]] || die "源码编译后未找到 snoscan 可执行文件"

    # sort-snos 首行 shebang 可能指向构建机 perl，改写为 /usr/bin/env perl
    if [[ -f "$PREFIX/bin/sort-snos" ]]; then
        perl -i -pe 's{^#! ?.*perl.*$}{#!/usr/bin/env perl}' "$PREFIX/bin/sort-snos" 2>/dev/null || true
        chmod 0755 "$PREFIX/bin/sort-snos"
    fi

    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/snoscan"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# snoscan (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 snoscan 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "snoscan $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 不受支持（源码编译仅 linux/macos）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无法源码编译，无法自动安装"
        fi ;;
esac
log "安装成功"
