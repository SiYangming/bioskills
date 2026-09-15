#!/usr/bin/env bash
# =============================================================================
# install.sh — ViennaRNA 宿主机本地安装脚本
#
# 归属    ：bioskills modules/viennarna/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::viennarna
#   - binary 路线（无 conda 兜底）：TBI 官方源码归档编译（RNAfold/RNAeval/RNAplot 等），
#     用户级前缀安装到 --prefix（默认 ~/software/viennarna-<ver>），无需 root、不写 /opt
#   - 版本默认 2.7.2，与 modules/viennarna/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://www.tbi.univie.ac.at/RNA/
#   bioconda : https://anaconda.org/bioconda/viennarna
#   source   : https://www.tbi.univie.ac.at/RNA/download/sourcecode/2_7_x/ViennaRNA-2.7.2.tar.gz
#   (容器：quay.io/biocontainers/viennarna —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: viennarna）
#   bash install.sh --method binary                   # 强制官方源码编译（无需 conda）
#   bash install.sh --conda-env vrn --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/viennarna          # binary 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.7.2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/viennarna-$DEFAULT_VERSION}"
CONDA_ENV="viennarna"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码归档内嵌 sha256
SRC_URL="https://www.tbi.univie.ac.at/RNA/download/sourcecode/2_7_x/ViennaRNA-${DEFAULT_VERSION}.tar.gz"
SHA256_SRC="ffb98b2dd76fcf08590cd435f60273e8e194493d5cdd96e12387a8fe2adf0b91"

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
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" ]]; }
}

# ---------------- 版本断言（安装后运行 RNAfold --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 viennarna=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "viennarna=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "viennarna=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV RNAfold --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" RNAfold --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 RNAfold / RNAeval / RNAplot"
}

# ---------------- 路线 B：TBI 官方源码编译 ----------------
install_binary() {
    local tmp srcdir
    log "下载官方源码归档: $SRC_URL"
    log "安装前缀: $PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/vienna.tar.gz" "$SRC_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/vienna.tar.gz" "$SRC_URL"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SRC  $tmp/vienna.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载的源码归档不完整或被篡改"
        else
            echo "$SHA256_SRC  $tmp/vienna.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载的源码归档不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（URL 模板已按 2_7_x 处理，版本号需自行核对）"
    fi

    tar -xzf "$tmp/vienna.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'ViennaRNA-*' | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档内未找到 ViennaRNA-* 目录"

    command -v make >/dev/null 2>&1 || die "源码编译需要 make"
    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || die "源码编译需要 C 编译器（cc/gcc）"

    ( cd "$srcdir" && ./configure --prefix="$PREFIX" --without-perl --without-python && make && make install )

    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/RNAfold"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# viennarna (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 RNAfold 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "viennarna $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 不受支持；请改用 conda 路线"
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
