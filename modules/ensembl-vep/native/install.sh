#!/usr/bin/env bash
# =============================================================================
# install.sh — Ensembl VEP（ensembl-vep）宿主机本地安装脚本
#
# 归属    ：bioskills modules/ensembl-vep/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::ensembl-vep
#   - source 路线（无 conda 兜底）：官方 GitHub release 源码包（release/<ver>.tar.gz）
#     解压到用户级前缀 --prefix（默认 ~/software/ensembl-vep-<ver>），再以官方
#     `perl INSTALL.pl --AUTO a --NO_HTSLIB` 安装 Perl 依赖（需网络 / CPAN）
#   - 版本默认 116.2，与 modules/ensembl-vep/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://www.ensembl.org/info/docs/tools/vep/index.html
#   release  : https://github.com/Ensembl/ensembl-vep/archive/refs/tags/release/116.2.tar.gz
#   bioconda : https://anaconda.org/bioconda/ensembl-vep
#   (容器：quay.io/biocontainers/ensembl-vep —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 说明：VEP 源码 release 包较大且 Perl 依赖由 INSTALL.pl 动态下载，官方 release 源包
#      不内嵌 sha256（INSTALL.pl 会按 release 选择/更新组件）。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方源码
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: ensembl-vep）
#   bash install.sh --method source                   # 强制官方源码 + perl INSTALL.pl
#   bash install.sh --conda-env vep --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/vep                # source 模式自定义前缀
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="116.2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/ensembl-vep-$DEFAULT_VERSION}"
CONDA_ENV="ensembl-vep"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

platform_ok_source() { command -v perl >/dev/null 2>&1; }

# ---------------- 版本断言 ----------------
assert_version_vep() {
    local vep="$1" out
    out="$("$vep" --version 2>&1 || true)"
    if ! grep -qF "$VERSION" <<<"$out"; then
        out="$("$vep" --help 2>&1 || true)"   # 兜底：help 头部含版本
    fi
    printf '%s\n' "$out" | head -n 3 | sed 's/^/  /'
    grep -qF "$VERSION" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 ensembl-vep=$VERSION 到环境: $CONDA_ENV"
    if "$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {found=1} END {exit found?0:1}'; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "ensembl-vep=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "ensembl-vep=$VERSION"
    fi
    log "验证：$CONDA_BIN run -n $CONDA_ENV vep --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" vep --version 2>&1 | head -n 2 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 vep / vep_install / filter_vep"
}

# ---------------- 路线 B：官方源码 release + perl INSTALL.pl ----------------
install_source() {
    platform_ok_source || die "--method source 需宿主 Perl；请先安装 perl 或改用 conda 路线"
    local url="https://github.com/Ensembl/ensembl-vep/archive/refs/tags/release/${VERSION}.tar.gz"
    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/vep.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/vep.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi
    warn "官方源码 release 包不内嵌 sha256（Perl 依赖由 INSTALL.pl 动态下载）"

    tar -xzf "$tmp/vep.tar.gz" -C "$tmp"
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "${srcdir:-}" && -f "${srcdir}/INSTALL.pl" ]] || die "解压包内未找到 INSTALL.pl（下载异常？）"
    rm -rf "$PREFIX"
    mkdir -p "$PREFIX"
    cp -R "$srcdir/." "$PREFIX/"
    chmod +x "$PREFIX/vep" "$PREFIX/vep_install" "$PREFIX/filter_vep" 2>/dev/null || true

    log "安装 Perl 依赖：perl $PREFIX/INSTALL.pl --AUTO a --NO_HTSLIB --NO_UPDATE"
    ( cd "$PREFIX" && perl INSTALL.pl --AUTO a --NO_HTSLIB --NO_UPDATE ) \
        || warn "INSTALL.pl 自动安装 Perl 依赖失败（可能缺网络/CPAN 权限）；可手动在 $PREFIX 执行 perl INSTALL.pl"

    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -f "$PREFIX/vep" ]] || die "未找到 $PREFIX/vep"
    assert_version_vep "$PREFIX/vep"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "PATH 已包含 $PREFIX，跳过写入 $PROFILE"
        else
            { echo ""; echo "# ensembl-vep (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 vep 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "ensembl-vep $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        platform_ok_source || die "--method source 需宿主 Perl；请改用 conda 路线"
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_source; then
            install_source
        else
            die "未检测到 mamba/conda 且无 perl，无法自动安装"
        fi ;;
esac
log "安装成功"
