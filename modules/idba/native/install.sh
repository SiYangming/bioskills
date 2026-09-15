#!/usr/bin/env bash
# =============================================================================
# install.sh — IDBA 宿主机本地安装脚本
#
# 归属    ：bioskills modules/idba/native/install.sh（native 实现安装方式）
# 路线    ：
#   - conda 路线（auto 首选）：mamba/conda 建独立环境，pin bioconda::idba=1.1.3
#   - source 路线（无 conda 兜底）：官方 GitHub release 1.1.3 源码包，configure+make，
#     可选打补丁 kMaxShortSequence 128→N（文档示例 160，处理更长 reads 需要）
#
# 版本默认 1.1.3，与 modules/idba/meta.yaml software_versions.native 对齐。
#
# 官方来源：
#   homepage : https://github.com/loneknightpy/idba
#   release  : https://github.com/loneknightpy/idba/releases/tag/1.1.3
#   bioconda : https://anaconda.org/bioconda/idba
#
# 用法示例：
#   bash install.sh                                # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                 # 强制 conda（默认建独立 env: idba）
#   bash install.sh --method source                # 强制官方源码编译
#   bash install.sh --method source --patch-max-short-seq 160   # 源码编译并打补丁（长 reads）
#   bash install.sh --prefix ~/software/idba --force
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.1.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/idba-$DEFAULT_VERSION}"
CONDA_ENV="idba"
METHOD="auto"                   # auto | conda | source
PATCH_MAX_SHORT_SEQ=""          # 非空则源码编译时替换 kMaxShortSequence
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)            VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)             PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)             METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)          CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --patch-max-short-seq) PATCH_MAX_SHORT_SEQ="${2:?需要数值（文档示例 160）}"; shift 2 ;;
        --profile)            PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)              FORCE=1; shift ;;
        --no-path-update)     UPDATE_PATH=0; shift ;;
        --help|-h)            usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 idba=$VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "idba=$VERSION"
    log "验证：conda list -n $CONDA_ENV idba"
    "$CONDA_BIN" list -n "$CONDA_ENV" idba | sed 's/^/  /'
    "$CONDA_BIN" list -n "$CONDA_ENV" idba | grep -q "$VERSION" \
        || die "版本校验失败：未在环境 $CONDA_ENV 中找到 idba $VERSION"
    "$CONDA_BIN" run -n "$CONDA_ENV" bash -c 'command -v idba_ud && command -v fq2fa' | sed 's/^/  /'
    log "版本校验通过：idba $VERSION"
    warn "conda 版默认 kMaxShortSequence=128；处理更长 reads 请用 --method source --patch-max-short-seq 160"
    log "完成：conda activate $CONDA_ENV 后即可使用 idba_ud / fq2fa"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_source() {
    local url
    url="https://github.com/loneknightpy/idba/releases/download/${VERSION}/idba-${VERSION}.tar.gz"
    command -v g++ >/dev/null 2>&1 || die "--method source 需要 g++（未在 PATH）"
    command -v make >/dev/null 2>&1 || die "--method source 需要 make（未在 PATH）"

    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"
    [[ -d "$PREFIX" && "$FORCE" != 1 ]] && die "目标前缀已存在：${PREFIX}（加 --force 重建）"
    [[ "$FORCE" == 1 ]] && rm -rf "$PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/idba.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/idba.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    tar -xzf "$tmp/idba.tar.gz" -C "$tmp"
    local src; src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name 'idba-*' | head -1)"
    [[ -n "$src" ]] || die "源码包内未找到 idba-* 目录"

    if [[ -n "$PATCH_MAX_SHORT_SEQ" ]]; then
        log "打补丁：src/sequence/short_sequence.h kMaxShortSequence 128 -> ${PATCH_MAX_SHORT_SEQ}"
        perl -p -i -e "s/kMaxShortSequence = 128/kMaxShortSequence = ${PATCH_MAX_SHORT_SEQ}/" \
            "$src/src/sequence/short_sequence.h"
        grep -q "kMaxShortSequence = ${PATCH_MAX_SHORT_SEQ}" "$src/src/sequence/short_sequence.h" \
            || die "补丁未生效：未在 short_sequence.h 找到目标常量（上游可能改名）"
    fi

    local nproc_="4"
    nproc_="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
    log "configure + make（-j${nproc_}）"
    ( cd "$src" && ./configure --prefix="$PREFIX" && make -j"$nproc_" && make install )

    rm -rf "$tmp"; tmp=""; trap - EXIT

    test -x "$PREFIX/bin/idba_ud" || die "编译产物缺失：$PREFIX/bin/idba_ud"
    test -x "$PREFIX/bin/fq2fa" || die "编译产物缺失：$PREFIX/bin/fq2fa"
    log "版本校验（源码 tarball 版本 ${VERSION}）："
    "$PREFIX/bin/idba_ud" 2>&1 | head -n 3 | sed 's/^/  /' || true

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# idba (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    fi
    log "完成：idba_ud / fq2fa 位于 $PREFIX/bin"
}

# ---------------- 主流程 ----------------
log "IDBA $VERSION 安装开始"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v g++ >/dev/null 2>&1; then
            install_source
        else
            die "未检测到 mamba/conda 且无 g++，无法自动安装（请先装 conda 或编译器）"
        fi ;;
esac
log "安装成功"
