#!/usr/bin/env bash
# =============================================================================
# install.sh — miRDeep2 宿主机本地安装脚本
#
# 归属    ：bioskills modules/mirdeep2/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先，推荐）：mamba/conda 创建独立环境，pin bioconda::mirdeep2
#     （bioconda 包自动带 bowtie / viennarna / randfold / perl 模块等依赖）
#   - binary 路线（无 conda 兜底）：官方 GitHub 源码归档（rajewsky-lab/mirdeep2）
#     部署 Perl 脚本到用户级前缀 --prefix，并提示外部依赖需自行安装
#     （bowtie / ViennaRNA(RNAfold) / randfold / perl PDF::API2 等）
#   - 版本默认 2.0.1.3，与 modules/mirdeep2/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/rajewsky-lab/mirdeep2
#   bioconda : https://anaconda.org/bioconda/mirdeep2
#   source   : https://github.com/rajewsky-lab/mirdeep2/archive/v0.1.3.tar.gz（tag v0.1.3 = 2.0.1.3）
#   (容器：quay.io/biocontainers/mirdeep2 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码部署
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: mirdeep2）
#   bash install.sh --method binary                   # 强制官方源码脚本部署（需自备依赖）
#   bash install.sh --conda-env md2 --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/mirdeep2           # binary 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.0.1.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/mirdeep2-$DEFAULT_VERSION}"
CONDA_ENV="mirdeep2"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 GitHub 源码归档（tag v0.1.3 对应 2.0.1.3）内嵌 sha256
SRC_URL="https://github.com/rajewsky-lab/mirdeep2/archive/v0.1.3.tar.gz"
SHA256_SRC="d6bac420d163a9541ce1760b8ef1a5a2edb671d22d50bd06adf45f2a6afa8d2f"

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

platform_ok_binary() {
    { [[ "$OS" == "Linux"  ]] || [[ "$OS" == "Darwin" ]]; }
}

# ---------------- 版本断言（安装后运行 miRDeep2.pl -h 校验；返回 0/1） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -h 2>&1 || true)"
    printf '%s\n' "$out" | head -n 3 | sed 's/^/  /'
    grep -qi "mirdeep2" <<<"$out" || return 1
    log "版本校验通过（miRDeep2.pl -h 正常）"
    return 0
}

# ---------------- 路线 A：conda / bioconda（推荐） ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 mirdeep2=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mirdeep2=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mirdeep2=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV miRDeep2.pl -h"
    "$CONDA_BIN" run -n "$CONDA_ENV" miRDeep2.pl -h 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 mapper.pl / miRDeep2.pl / quantifier.pl"
}

# ---------------- 路线 B：官方 GitHub 源码脚本部署 ----------------
install_binary() {
    local tmp srcdir
    log "下载官方源码归档: $SRC_URL"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/mirdeep2.tar.gz" "$SRC_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/mirdeep2.tar.gz" "$SRC_URL"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        echo "$SHA256_SRC  $tmp/mirdeep2.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
            || die "sha256 校验失败：下载的源码归档不完整或被篡改"
    else
        echo "$SHA256_SRC  $tmp/mirdeep2.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
            || die "sha256 校验失败：下载的源码归档不完整或被篡改"
    fi
    log "sha256 校验通过"

    tar -xzf "$tmp/mirdeep2.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'mirdeep2-*' | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档内未找到 mirdeep2-* 目录"

    # 部署 Perl 脚本与随附数据到用户前缀
    local share="$PREFIX/share/mirdeep2"
    mkdir -p "$share"
    cp -R "$srcdir/src" "$share/" 2>/dev/null || true
    cp "$srcdir/Rfam_for_miRDeep.fa" "$share/" 2>/dev/null || true
    local sc
    for sc in "$srcdir"/src/*.pl; do
        [[ -f "$sc" ]] || continue
        install -m 0755 "$sc" "$PREFIX/bin/"
        perl -i -pe 's{^#! ?.*perl.*$}{#!/usr/bin/env perl}' "$PREFIX/bin/$(basename "$sc")" 2>/dev/null || true
    done
    [[ -x "$PREFIX/bin/miRDeep2.pl" ]] || die "未部署到 miRDeep2.pl（源码归档结构异常？）"

    rm -rf "$tmp"; tmp=""; trap - EXIT

    warn "binary 路线仅部署 miRDeep2 Perl 脚本；以下外部依赖需自行安装到 PATH："
    warn "  bowtie、ViennaRNA(RNAfold)、randfold、perl PDF::API2/Font::TTF/Compress::Raw::Zlib/LWP"
    warn "建议优先使用 conda 路线（自动带齐依赖）：bash $0 --method conda"

    if assert_version "$PREFIX/bin/miRDeep2.pl"; then
        :
    else
        warn "miRDeep2.pl -h 未通过（可能缺依赖）；补依赖后再运行 --help 校验"
    fi

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# mirdeep2 (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "mirdeep2 $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 不受支持"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无法部署，无法自动安装"
        fi ;;
esac
log "安装成功"
