#!/usr/bin/env bash
# =============================================================================
# install.sh — SNAP（KorfLab）宿主机本地安装脚本
#
# 归属    ：bioskills modules/snap/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方镜像优先，宿主机走 conda）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::snap
#   - source 路线（无 conda 兜底）：从官方 GitHub 仓库源码 make 编译（SNAP 上游
#     不提供预编译二进制；旧官网分发页 korflab.ucdavis.edu 当前不可达，故走 GitHub）
#     用户级前缀安装到 --prefix（默认 ~/software/snap-<ver>），无需 root、不写 /opt
#   - 版本默认 2013_11_29，与 modules/snap/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/KorfLab/SNAP
#   bioconda : https://anaconda.org/bioconda/snap
#   source   : https://github.com/KorfLab/SNAP（官方仓库；make 编译 fathom/forge/snap/hmm-assembler.pl）
#   （容器：quay.io/biocontainers/snap —— 本脚本为宿主机安装，容器用法见模块 README）
#
# ⚠️ 注意：bioconda 的 snap 是 KorfLab 基因预测 SNAP，不是 Ubuntu 的 snap 包管理器。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: snap）
#   bash install.sh --method source                   # 强制从 GitHub 源码 make 编译（无需 conda）
#   bash install.sh --conda-env snap-gp --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/snap               # source 模式自定义前缀
#   bash install.sh --version 2017_03_01              # 覆盖版本（conda pin；source 模式忽略）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2013_11_29"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/snap-$DEFAULT_VERSION}"
CONDA_ENV="snap"
METHOD="auto"          # auto | conda | source（binary 视为 source 别名）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# SNAP 上游无预编译二进制、无版本化源码归档（GitHub 仓库无对应 tag），source 模式编译当前
# 默认分支 master；因此 source 模式不保证与 conda pin 的 2013_11_29 完全一致。未内嵌 sha256
# （上游无稳定发行归档可核对）。

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'
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

# binary 作为 source 的别名（历史/习惯用法）
[[ "$METHOD" == "binary" ]] && METHOD="source"
case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言 ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" 2>&1 | head -n 3 || true)"
    printf '  %s\n' "$out"
    log "已安装 $(basename "$bin")（SNAP 无 --version 选项，输出见上）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 snap=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "snap=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "snap=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV snap"
    "$CONDA_BIN" run -n "$CONDA_ENV" snap 2>&1 | head -n 2 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 snap/fathom/forge/hmm-assembler.pl"
}

# ---------------- 路线 B：官方 GitHub 源码 make 编译 ----------------
install_source() {
    local url tmp srcdir
    command -v make >/dev/null 2>&1 || die "--method source 需要 make（未在 PATH 中找到）"
    url="https://github.com/KorfLab/SNAP/archive/refs/heads/master.tar.gz"

    log "下载官方源码: $url"
    warn "source 模式编译 GitHub master（上游无版本化归档），版本可能与 conda pin 的 ${VERSION} 不一致"
    log "安装前缀: $PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/snap.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/snap.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    tar -xzf "$tmp/snap.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "SNAP-*" | head -1)"
    [[ -n "$srcdir" ]] || die "源码包解压目录异常（URL 有误？）"
    ( cd "$srcdir" && make -j 4 )

    mkdir -p "$PREFIX/bin"
    for exe in snap fathom forge hmm-assembler.pl; do
        local src
        src="$(find "$srcdir" -maxdepth 2 -type f -name "$exe" | head -1)"
        [[ -n "$src" ]] || die "编译产物未找到: $exe"
        install -m 0755 "$src" "$PREFIX/bin/$exe"
    done
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/snap"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# snap (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 snap 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "snap $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
