#!/usr/bin/env bash
# =============================================================================
# install.sh — MaSuRCA 宿主机本地安装脚本
#
# 归属    ：bioskills modules/masurca/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::masurca=3.4.1
#     （⚠️ 官方 README 警告 bioconda 安装可能因 mummer 冲突损坏，生产组装建议源码编译）
#   - source 路线（官方推荐，无 conda 兜底）：官方 release MaSuRCA-3.4.1.tar.gz，
#     设置 BOOST_ROOT 后 ./install.sh，用户级前缀安装到 --prefix（默认 ~/software/MaSuRCA-3.4.1）
#
# 官方来源：
#   homepage : https://github.com/alekseyzimin/masurca
#   release  : https://github.com/alekseyzimin/masurca/releases/tag/v3.4.1
#   bioconda : https://anaconda.org/bioconda/masurca
#   (容器：quay.io/biocontainers/masurca —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: masurca）
#   bash install.sh --method source --boost-root ~/software/boost_1_64_0
#   bash install.sh --conda-env masurca --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/MaSuRCA-3.4.1      # source 模式自定义前缀
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="3.4.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/MaSuRCA-$DEFAULT_VERSION}"
CONDA_ENV="masurca"
BOOST_ROOT="${BOOST_ROOT:-}"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --boost-root)  BOOST_ROOT="${2:?--boost-root 需要路径}"; shift 2 ;;
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

# ---------------- 版本断言（masurca 的版本输出方式随版本而异，做自适应） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 || true)"
    if ! grep -qE "${VERSION//./\.}" <<<"$out"; then
        out="$("$bin" -h 2>&1 || true)"
        grep -qE "MaSuRCA|masurca" <<<"$out" || die "版本校验失败：${bin} 未按预期输出（期望包含 ${VERSION}）"
        warn "masurca --version 未返回版本号（该版本可能不支持），已用 -h 输出确认二进制可用"
    fi
    printf '  %s\n' "$(head -n 1 <<<"$out")"
    log "版本校验通过：${VERSION}（或已确认二进制可用）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 masurca=$VERSION 到环境: $CONDA_ENV（⚠️ 官方不推荐 bioconda 安装）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "masurca=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "masurca=$VERSION"
    fi
    local out
    out="$("$CONDA_BIN" run -n "$CONDA_ENV" masurca --version 2>&1 | head -n 1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || warn "conda 路线未从 masurca --version 读到版本号，请人工核对"
    log "完成：conda activate $CONDA_ENV 后即可使用 masurca"
}

# ---------------- 路线 B：官方源码编译（BOOST_ROOT + ./install.sh） ----------------
install_source() {
    log "源码编译 MaSuRCA $VERSION（官方推荐路线，需 Boost）"
    command -v make >/dev/null 2>&1 || die "源码编译需要 make/g++"
    command -v g++  >/dev/null 2>&1 || die "源码编译需要 g++"

    if [[ -z "$BOOST_ROOT" || ! -d "$BOOST_ROOT" ]]; then
        die "源码编译需要 Boost：请用 --boost-root <path> 或 export BOOST_ROOT=<path> 指定（如 boost_1_64_0）"
    fi
    log "使用 BOOST_ROOT=$BOOST_ROOT"

    local url="https://github.com/alekseyzimin/masurca/releases/download/v${VERSION}/MaSuRCA-${VERSION}.tar.gz"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    log "下载官方源码: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/masurca.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/masurca.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    tar -xzf "$tmp/masurca.tar.gz" -C "$tmp"
    local srcdir; srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'MaSuRCA-*' | head -1)"
    [[ -n "$srcdir" ]] || die "解压失败（URL 或版本号有误？）"

    log "编译并安装到 $PREFIX（./install.sh，遵循 BOOST_ROOT）..."
    ( cd "$srcdir" && BOOST_ROOT="$BOOST_ROOT" ./install.sh )
    mkdir -p "$(dirname "$PREFIX")"
    rm -rf "$PREFIX"
    cp -R "$srcdir" "$PREFIX"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -x "$PREFIX/bin/masurca" ]] || die "未找到 $PREFIX/bin/masurca（编译是否成功？）"
    assert_version "$PREFIX/bin/masurca"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# masurca (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 masurca 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "MaSuRCA $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
