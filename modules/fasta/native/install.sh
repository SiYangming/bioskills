#!/usr/bin/env bash
# =============================================================================
# install.sh — FASTA（上游 wrpearson/fasta36）宿主机本地安装脚本
#
# 归属    ：bioskills modules/fasta/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方镜像优先，宿主机走 conda / 官方资产）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::fasta3
#     （⚠️ bioconda 包名为 fasta3，提供 fasta36 等二进制）
#   - binary 路线（无 conda 兜底）：官方 GitHub release 预编译二进制（linux64）；
#     macOS / 其它平台退回官方源码 make 编译（Makefile.os_x86_64 / linux_sse2）
#     用户级前缀安装到 --prefix（默认 ~/software/fasta36-<ver>），无需 root、不写 /opt
#   - 版本默认 36.3.8i，与 modules/fasta/meta.yaml software_versions.fasta_native 对齐
#
# 官方来源：
#   homepage : https://github.com/wrpearson/fasta36
#   bioconda : https://anaconda.org/bioconda/fasta3
#   release  : https://github.com/wrpearson/fasta36/releases/tag/v36.3.8i_14-Nov-2020
#              （资产 fasta-36.3.8i-linux64.tar.gz；源码 v36.3.8i_14-Nov-2020.tar.gz）
#   （容器：quay.io/biocontainers/fasta3 —— 本脚本为宿主机安装，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方资产
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: fasta36）
#   bash install.sh --method binary                   # 强制官方预编译 / 源码编译（无需 conda）
#   bash install.sh --conda-env fa --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/fasta36            # binary 模式自定义前缀
#   bash install.sh --version 36.3.8h                 # 覆盖版本（conda pin；官方 release 资产名随之变化）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="36.3.8i"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/fasta36-$DEFAULT_VERSION}"
CONDA_ENV="fasta36"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release 资产（默认版本，已在线核实存在）：
#   https://github.com/wrpearson/fasta36/releases/download/v36.3.8i_14-Nov-2020/fasta-36.3.8i-linux64.tar.gz
#   https://github.com/wrpearson/fasta36/archive/refs/tags/v36.3.8i_14-Nov-2020.tar.gz
# 说明：预编译资产未内嵌 sha256（release 页可自行核对）；非默认版本资产名含发行日期，脚本会提示核对。

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'
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

# ---------------- 版本断言（<binary> 无参运行时打印版本横幅） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" </dev/null 2>&1 | head -n 5 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 fasta3=$VERSION 到环境: $CONDA_ENV（bioconda 包名 fasta3 提供 FASTA）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "fasta3=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "fasta3=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV fasta36"
    "$CONDA_BIN" run -n "$CONDA_ENV" fasta36 </dev/null 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 fasta36/ssearch36/... "
}

# ---------------- 路线 B：官方预编译资产 / 源码编译 ----------------
install_binary() {
    local tmp srcdir
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    mkdir -p "$PREFIX/bin"

    if [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; then
        local url="https://github.com/wrpearson/fasta36/releases/download/v${VERSION}_14-Nov-2020/fasta-${VERSION}-linux64.tar.gz"
        [[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}），release 资产名含发行日期，可能不匹配，请核对 GitHub release"
        log "下载官方预编译二进制: $url"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$tmp/fasta.tar.gz" "$url"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$tmp/fasta.tar.gz" "$url"
        else
            die "需要 curl 或 wget 下载 release"
        fi
        tar -xzf "$tmp/fasta.tar.gz" -C "$tmp"
        srcdir="$(find "$tmp" -maxdepth 2 -type d -name bin | head -1)"
        [[ -n "$srcdir" ]] || die "预编译包解压后未找到 bin/（URL 或版本号有误？）"
        for exe in "$srcdir"/*; do
            install -m 0755 "$exe" "$PREFIX/bin/$(basename "$exe")"
        done
        ln -sf "$PREFIX/bin/fasta36" "$PREFIX/bin/fasta"
    else
        # macOS / 其它平台：官方源码 make 编译
        command -v make >/dev/null 2>&1 || die "--method binary 在 ${OS}/${ARCH} 需 make 编译官方源码（未在 PATH 中找到）"
        local mk="Makefile.linux_sse2"
        [[ "$OS" == "Darwin" ]] && mk="Makefile.os_x86_64"
        local url="https://github.com/wrpearson/fasta36/archive/refs/tags/v${VERSION}_14-Nov-2020.tar.gz"
        log "下载官方源码: $url（make -f ../make/${mk} all）"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$tmp/fasta-src.tar.gz" "$url"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$tmp/fasta-src.tar.gz" "$url"
        else
            die "需要 curl 或 wget 下载源码"
        fi
        tar -xzf "$tmp/fasta-src.tar.gz" -C "$tmp"
        srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "fasta36-*" | head -1)"
        [[ -n "$srcdir" ]] || die "源码包解压目录异常"
        ( cd "$srcdir/src" && make -f "../make/${mk}" all && make -f "../make/${mk}" install )
        for exe in "$srcdir"/bin/*; do
            install -m 0755 "$exe" "$PREFIX/bin/$(basename "$exe")"
        done
        ln -sf "$PREFIX/bin/fasta36" "$PREFIX/bin/fasta"
    fi
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/fasta36"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# fasta36 (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 fasta36 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "fasta36 $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_binary
        fi ;;
esac
log "安装成功"
