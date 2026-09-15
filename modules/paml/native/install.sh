#!/usr/bin/env bash
# =============================================================================
# install.sh — PAML 宿主机本地安装脚本
#
# 归属    ：bioskills modules/paml/native/install.sh（native 实现安装方式）
# 路线    ：官方镜像优先（bioconda/quay/depot 已覆盖）→ 本脚本只管宿主机安装
#   - conda  路线：mamba/conda 创建独立环境，pin bioconda::paml=4.9
#                 （bioconda 无 "4.9i" 独立版；4.9 即 4.9 系列构建）
#   - source 路线（无 conda 兜底）：下载官方源码 paml4.9i.tgz（GitHub release pre-v4.10），
#                 make -f Makefile 编译出全部程序，安装到 --prefix/bin，无需 root
#   - 版本默认 4.9i（官方源码），与 modules/paml/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/abacus-gene/paml
#   source   : https://github.com/abacus-gene/paml/releases/download/pre-v4.10/paml4.9i.tgz
#   bioconda : https://anaconda.org/bioconda/paml
#   (容器：quay.io/biocontainers/paml —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: paml，装 paml=4.9）
#   bash install.sh --method source                   # 强制官方源码编译（paml4.9i，无需 conda）
#   bash install.sh --conda-env paml --force          # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/paml --method source # 自定义安装前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="4.9i"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/paml-$DEFAULT_VERSION}"
CONDA_ENV="paml"
CONDA_PAML_VERSION="4.9"   # bioconda 无 4.9i 独立版，最接近的 4.9 系列构建
METHOD="auto"              # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码 paml4.9i.tgz（平台无关，单一 sha256；2026-09 核实下载一致）
SHA256_SOURCE="48f474354434a28b3a2da25b31d3395591b3a49c61980418470cfc56562000e1"

# 源码 make -f Makefile 产出的全部程序（与 14.md「六」的 cp 列表一致，另含 mcmctree 同源 infinitesites）
PAML_PROGRAMS="baseml basemlg chi2 codeml evolver infinitesites mcmctree pamp yn00"

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
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（安装后运行 baseml 校验 banner：BASEML in paml version 4.9i） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" 2>&1 || true)"
    printf '  %s\n' "$(head -n 1 <<<"$out")"
    grep -qiE "paml version[[:space:]]+${VERSION//./\.}" <<<"$out" \
        || die "版本校验失败：期望 banner 含 'paml version ${VERSION}'，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    warn "bioconda 无 paml=${VERSION} 独立版（4.9i 为 4.9 系列补丁），conda 路线将安装 paml=${CONDA_PAML_VERSION}"
    log "使用 conda 安装 paml=${CONDA_PAML_VERSION} 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "paml=${CONDA_PAML_VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "paml=${CONDA_PAML_VERSION}"
    fi
    log "验证：conda run -n $CONDA_ENV baseml（banner 应含 paml version 4.9）"
    "$CONDA_BIN" run -n "$CONDA_ENV" baseml 2>&1 | head -n 1 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 baseml/codeml/mcmctree 等程序（PAML ${CONDA_PAML_VERSION} 系列）"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_source() {
    local url sha srcdir tmp=""
    url="https://github.com/abacus-gene/paml/releases/download/pre-v4.10/paml${VERSION}.tgz"
    sha="$SHA256_SOURCE"

    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 \
        || die "源码编译需要 C 编译器（cc/gcc）"

    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/paml.tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/paml.tgz" "$url"
    else
        die "需要 curl 或 wget 下载官方源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/paml.tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/paml.tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官方 release 摘要）"
    fi

    tar -xzf "$tmp/paml.tgz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "paml${VERSION}" | head -1)"
    [[ -n "$srcdir" ]] || die "解压后未找到源码目录 paml${VERSION}（版本号有误？）"
    ( cd "$srcdir/src" && make -f Makefile ) || die "make -f Makefile 编译失败"

    local prog
    for prog in $PAML_PROGRAMS; do
        [[ -x "$srcdir/src/$prog" ]] || die "编译产物缺失：src/$prog"
        install -m 0755 "$srcdir/src/$prog" "$PREFIX/bin/$prog"
    done
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/baseml"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# paml (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 baseml/codeml 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "paml $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_source
        fi ;;
esac
log "安装成功"
