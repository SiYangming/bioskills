#!/usr/bin/env bash
# =============================================================================
# install.sh — ea-utils 宿主机本地安装脚本
#
# 归属    ：bioskills modules/ea-utils/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「安装方式（本地）」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::ea-utils=1.1.2.537
#   - source 路线（无 conda 兜底）：ea-utils 官方无预编译二进制，改从官方 GitHub
#     源码归档编译（make；依赖 g++ / gsl / zlib），安装到 --prefix（默认
#     ~/software/ea-utils-<ver>），无需 root、不写 /opt
#   - 版本默认 1.1.2.537（= 上游 1.1.2-537），与 meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://expressionanalysis.github.io/ea-utils/
#   bioconda : https://anaconda.org/bioconda/ea-utils
#   source   : https://github.com/ExpressionAnalysis/ea-utils （官方 GitHub 源码仓库）
#   (容器：quay.io/biocontainers/ea-utils:1.1.2.779--h9dd4a16_0 —— 官方容器仅 1.1.2.779 tag；
#    本脚本为宿主机安装，容器用法见模块 README)
#
# ⚠️ 版本说明：bioconda/quay 官方容器仅构建到 1.1.2.779；1.1.2.537 仅 bioconda conda 包提供。
#    GitHub 官方唯一带 tag 的源码归档为 1.04.807.tar.gz，其 ea-utils.spec 实为 1.1.2-779 源码
#    （见下方 SOURCE_URL / SOURCE_SHA256，与 bioconda recipe 一致）。因此：
#      * 需要精确的 1.1.2.537 → 请走 --method conda；
#      * 无 conda 时 source 路线编译得到 1.1.2-779（打印提示）。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: ea-utils）
#   bash install.sh --method source                   # 强制源码编译（需 g++ / gsl / zlib）
#   bash install.sh --conda-env eautils --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/ea-utils           # source 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.1.2.537"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/ea-utils-$DEFAULT_VERSION}"
CONDA_ENV="ea-utils"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码归档（GitHub tag 1.04.807；内容实为 1.1.2-779 源码；sha256 与 bioconda recipe 一致）
SOURCE_URL="https://github.com/ExpressionAnalysis/ea-utils/archive/1.04.807.tar.gz"
SOURCE_SHA256="aa09d25e6aa7ae71d2ce4198a98e58d563f151f8ff248e4602fa437f12b8d05f"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
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
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（ea-utils 无 --version；用 fastq-mcf -h 的 Version 行校验） ----------------
assert_version() {
    local bindir="$1" out
    for b in fastq-join fastq-mcf fastq-stats fastq-clipper; do
        [[ -x "$bindir/$b" ]] || die "缺少可执行文件: $bindir/$b"
    done
    out="$("$bindir/fastq-mcf" -h 2>&1 || true)"
    grep -qi "version" <<<"$out" || die "fastq-mcf -h 未输出 Version 行，安装可能不完整"
    log "可执行文件校验通过：fastq-join / fastq-mcf / fastq-stats / fastq-clipper 均已就位"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 ea-utils=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "ea-utils=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "ea-utils=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV fastq-mcf -h"
    "$CONDA_BIN" run -n "$CONDA_ENV" fastq-mcf -h 2>&1 | grep -i version | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 fastq-join / fastq-mcf 等"
}

# ---------------- 路线 B：官方 GitHub 源码编译 ----------------
install_source() {
    local tmp srcdir
    [[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "source 路线固定编译官方归档（1.1.2-779）；--version ${VERSION} 仅影响提示，不改变源码"
    command -v make >/dev/null 2>&1 || die "缺少 make；请先安装构建工具（apt: build-essential / yum: gcc-c++ make）"
    command -v c++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 \
        || die "缺少 C++ 编译器（g++/c++）；apt: build-essential / yum: gcc-c++"

    log "下载官方源码: $SOURCE_URL"
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/ea-utils.tar.gz" "$SOURCE_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/ea-utils.tar.gz" "$SOURCE_URL"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        echo "$SOURCE_SHA256  $tmp/ea-utils.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
            || die "sha256 校验失败：下载文件不完整或被篡改"
    else
        echo "$SOURCE_SHA256  $tmp/ea-utils.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
            || die "sha256 校验失败：下载文件不完整或被篡改"
    fi
    log "sha256 校验通过"

    tar -xzf "$tmp/ea-utils.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "解压后未找到源码目录"

    log "编译（make -j 4；需 gsl/zlib 开发头文件：apt gsl-bin libgsl-dev zlib1g-dev / yum gsl-devel zlib-devel）"
    ( cd "$srcdir/clipper" && make -j 4 ) \
        || die "make 失败（常见原因：缺少 gsl/zlib 开发包；安装后重试）"

    mkdir -p "$PREFIX/bin"
    local b
    for b in fastq-join fastq-mcf fastq-multx fastq-stats fastq-clipper sam-stats varcall gtf2bed; do
        [[ -x "$srcdir/clipper/$b" ]] && install -m 0755 "$srcdir/clipper/$b" "$PREFIX/bin/$b"
    done
    for b in gtf2bed determine-phred; do
        [[ -f "$srcdir/clipper/$b" ]] && install -m 0755 "$srcdir/clipper/$b" "$PREFIX/bin/$b"
    done
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# ea-utils (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 fastq-join 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        warn "source 路线编译产物为上游 1.1.2-779（官方唯一带 tag 源码归档）；如需精确 1.1.2.537 请走 --method conda"
    fi
}

# ---------------- 主流程 ----------------
log "ea-utils $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
            warn "未检测到 mamba/conda，改走官方源码编译路线"
            install_source
        fi ;;
esac
log "安装成功"
