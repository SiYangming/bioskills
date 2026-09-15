#!/usr/bin/env bash
# =============================================================================
# install.sh — GeneWise（wise2）宿主机本地安装脚本
#
# 归属    ：bioskills modules/genewise/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::wise2=2.4.1（提供 genewise）
#   - source 路线（无 conda 兜底）：官方源码 wise2.4.1.tar.gz 解压 + make all，含教学文档
#     要求的 glibc/getline 兼容修补，安装到用户前缀（默认 ~/software/wise2-2.4.1），无需 root
#   - 版本默认 2.4.1，与 modules/genewise/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage  : https://www.ebi.ac.uk/~birney/wise2/
#   source    : https://www.ebi.ac.uk/~birney/wise2.4.1.tar.gz
#   bioconda  : https://anaconda.org/bioconda/wise2
#   (容器：quay.io/biocontainers/wise2:2.4.1--h17e8430_6 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: genewise）
#   bash install.sh --method source                   # 强制官方源码编译（需 make/cc/glib/perl）
#   bash install.sh --prefix ~/opt/wise2              # source 模式自定义前缀
#   bash install.sh --version 2.4.1 --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.4.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/wise2-$DEFAULT_VERSION}"
CONDA_ENV="genewise"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

WISE2_URL="https://www.ebi.ac.uk/~birney/wise2.4.1.tar.gz"
# 官方源码归档内嵌 sha256（2026-09-11 实测下载；与 bioconda 配方 wise2 2.4.1 一致）
SHA256_SRC="240e2b12d6cd899040e2efbcb85b0d3c10245c255f3d07c1db45d0af5a4d5fa1"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
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

# ---------------- 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（genewise -version） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -version 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\\.}" <<<"$out" || die "版本校验失败：期望输出含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 wise2=$VERSION（genewise）到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "wise2=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "wise2=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV genewise -version"
    "$CONDA_BIN" run -n "$CONDA_ENV" genewise -version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 genewise（封装脚本 homolog_genewise 由 GETA 提供，见 README）"
}

# ---------------- 路线 B：官方源码编译（含 glibc/getline 兼容修补） ----------------
install_source() {
    command -v make >/dev/null 2>&1 || die "未检测到 make；源码编译需要 make + C 编译器 + glib + perl，或改用 --method conda"
    command -v perl >/dev/null 2>&1 || die "未检测到 perl（兼容修补需要 perl）"

    log "下载官方源码: $WISE2_URL"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    local tar="$tmp/wise2.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tar" "$WISE2_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tar" "$WISE2_URL"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SRC  $tar" | sha256sum -c - >/dev/null 2>&1 || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_SRC  $tar" | shasum -a 256 -c - >/dev/null 2>&1 || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 EBI 发布摘要）"
    fi

    tar -xzf "$tar" -C "$tmp"
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'wise2*' | head -1)"
    [[ -n "$srcdir" && -d "$srcdir/src" ]] || die "源码包结构异常（未找到 wise2*/src）"

    cd "$srcdir/src"
    # --- 教学文档 docs/10.md 第三节要求的兼容修补 ---
    # 1) 旧 makefile 里的 glib-config → pkg-config --libs glib-2.0
    find . -name makefile -print0 | xargs -0 -r perl -pi -e 's/glib-config/pkg-config --libs glib-2.0/g'
    # 2) HMMer2/sqio.c 的 getline 与 glibc 新版冲突 → get_line
    [[ -f ./HMMer2/sqio.c ]] && perl -pi -e 's/getline/get_line/g' ./HMMer2/sqio.c
    # 3) models/phasemodel.c 的 isnumber 非标准 → isdigit
    [[ -f ./models/phasemodel.c ]] && perl -pi -e 's/isnumber/isdigit/' ./models/phasemodel.c

    log "开始编译（make all）..."
    make all >/dev/null 2>&1 || make all

    local bin="$srcdir/src/bin/genewise"
    [[ -x "$bin" ]] || bin="$(find "$srcdir/src" -maxdepth 2 -type f -name genewise -perm -111 | head -1)"
    [[ -n "$bin" && -x "$bin" ]] || die "编译完成但未找到 genewise 可执行文件"

    # 归档到用户前缀（保留 wisecfg 供 WISECONFIGDIR）
    local dest="$PREFIX/wise2-$VERSION"
    mkdir -p "$dest"
    cp -R "$srcdir/src/bin" "$dest/bin"
    cp -R "$srcdir/wisecfg" "$dest/wisecfg" 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT
    cd "$dest"

    assert_version "$dest/bin/genewise"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local done=0
        if [[ -f "$PROFILE" ]] && grep -qF "$dest/bin" "$PROFILE"; then
            log "PATH 已包含 $dest/bin，跳过写入 $PROFILE"; done=1
        else
            { echo ""; echo "# genewise / wise2 (bioskills install.sh)";
              echo "export PATH=\"$dest/bin:\$PATH\"";
              [[ -d "$dest/wisecfg" ]] && echo "export WISECONFIGDIR=\"$dest/wisecfg\""; } >> "$PROFILE"
            log "已追加 PATH（及 WISECONFIGDIR）到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 genewise 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$dest/bin:\$PATH\"（并设 WISECONFIGDIR=\"$dest/wisecfg\"）"
    fi
}

# ---------------- 主流程 ----------------
log "genewise / wise2 $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then install_conda; else install_source; fi ;;
esac
log "安装成功"
