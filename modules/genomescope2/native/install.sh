#!/usr/bin/env bash
# =============================================================================
# install.sh — GenomeScope 2.0 (genomescope2) 宿主机本地安装脚本
#
# 归属    ：bioskills modules/genomescope2/native/install.sh（native 实现安装方式）
# 路线    ：
#   - conda 路线（auto 首选）：mamba/conda 建独立环境，装 bioconda::genomescope2
#     （自动含 jellyfish 依赖；bioconda 现行版本 2.1.0，无 1.0.0 包）
#   - r 路线（无 conda 兜底）：官方 GitHub R 包源码 tag v1.0.0（R CMD INSTALL），
#     genomescope.R 软链到用户前缀 bin（免 root）
#
# 版本：conda 默认 2.1.0（bioconda 最新）；官方 R 包源码默认 tag v1.0.0（文档目标版本）。
#       二者对应 GenomeScope 2.0 的不同打包通道，见 modules/genomescope2/meta.yaml。
#
# 官方来源：
#   homepage : https://github.com/tbenavi1/genomescope2.0
#   bioconda : https://anaconda.org/bioconda/genomescope2
#
# 用法示例：
#   bash install.sh                            # auto：有 conda/mamba 走 bioconda，否则 R 包源码
#   bash install.sh --method conda             # 强制 conda（默认建独立 env: genomescope2）
#   bash install.sh --method r                 # 强制官方 R 包源码（tag v1.0.0）
#   bash install.sh --conda-env gs --force     # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/software/gs --r-version 1.0.0
# =============================================================================
set -euo pipefail

# ---------------- 默认值 ----------------
CONDA_VERSION="2.1.0"           # bioconda 现行版本（无 1.0.0 包）
R_VERSION="1.0.0"               # 官方 GitHub R 包 tag
PREFIX="${PREFIX:-$HOME/software/genomescope2-$R_VERSION}"
CONDA_ENV="genomescope2"
METHOD="auto"                   # auto | conda | r
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     CONDA_VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --r-version)   R_VERSION="${2:?--r-version 需要 tag}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";          shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|r}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}";  shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";         shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|r) ;; *) die "--method 仅支持 auto|conda|r（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 genomescope2=$CONDA_VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "genomescope2=$CONDA_VERSION"
    log "验证：conda list -n $CONDA_ENV genomescope2"
    "$CONDA_BIN" list -n "$CONDA_ENV" genomescope2 | sed 's/^/  /'
    "$CONDA_BIN" list -n "$CONDA_ENV" genomescope2 | grep -q "$CONDA_VERSION" \
        || die "版本校验失败：未在环境 $CONDA_ENV 中找到 genomescope2 $CONDA_VERSION"
    "$CONDA_BIN" run -n "$CONDA_ENV" bash -c 'command -v genomescope.R' | sed 's/^/  /'
    log "版本校验通过：genomescope2 $CONDA_VERSION"
    log "完成：conda activate $CONDA_ENV 后即可使用 genomescope.R"
}

# ---------------- 路线 B：官方 R 包源码（tag v<ver>） ----------------
install_r() {
    local url archive libdir
    url="https://github.com/tbenavi1/genomescope2.0/archive/v${R_VERSION}.tar.gz"
    libdir="${R_LIBS:-$HOME/.R_libs}"
    command -v R >/dev/null 2>&1 || die "--method r 需要 R（R/Rscript 未在 PATH）"

    log "下载官方 R 包源码: $url"
    log "安装前缀: $PREFIX（R 库: $libdir）"
    [[ -d "$PREFIX" && "$FORCE" != 1 ]] && die "目标前缀已存在：${PREFIX}（加 --force 重建）"
    [[ "$FORCE" == 1 ]] && rm -rf "$PREFIX"
    mkdir -p "$PREFIX/bin" "$PREFIX/src" "$libdir"

    local tmp=""; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/gs.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/gs.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载 R 包源码"
    fi
    archive="$tmp/gs.tar.gz"

    tar -xzf "$archive" -C "$PREFIX/src"
    local srcdir; srcdir="$(find "$PREFIX/src" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "源码包内未找到 genomescope2.0 目录"

    grep -q "Version: ${R_VERSION}" "$srcdir/DESCRIPTION" \
        || warn "DESCRIPTION 中未直接匹配 Version: ${R_VERSION}，请人工核对"

    log "R CMD INSTALL --library=$libdir"
    R CMD INSTALL --library="$libdir" "$archive"

    install -m 0755 "$srcdir/genomescope.R" "$PREFIX/bin/genomescope.R"
    test -x "$PREFIX/bin/genomescope.R" || die "genomescope.R 部署失败"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    grep -q "Version: ${R_VERSION}" "$srcdir/DESCRIPTION" \
        && log "版本校验通过：R 包 v${R_VERSION}"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# genomescope2 (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    fi
    log "完成：确保 R_LIBS=${libdir}（可写入 ~/.Renviron）后执行 genomescope.R -h"
}

# ---------------- 主流程 ----------------
log "genomescope2 安装开始"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    r)
        install_r ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v R >/dev/null 2>&1; then
            install_r
        else
            die "未检测到 mamba/conda 且无 R，无法自动安装（请先装 conda 或 R）"
        fi ;;
esac
log "安装成功"
