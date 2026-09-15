#!/usr/bin/env bash
# =============================================================================
# install.sh — BRAKER2（Gaius-Augustus/BRAKER）宿主机本地安装脚本
#
# 归属    ：bioskills modules/braker/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方镜像优先，宿主机走 conda / 官方源码）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::braker2
#     （自动带入 AUGUSTUS/GeneMark 等依赖）
#   - binary 路线（无 conda 兜底）：官方 GitHub tarball v2.1.5（纯 Perl 脚本，无编译），
#     解压后把 scripts/ 下脚本软链到用户前缀 bin（默认 ~/software/braker-<ver>/bin），无需 root、不写 /opt
#   - 版本默认 2.1.5，与 modules/braker/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/Gaius-Augustus/BRAKER
#   release  : https://github.com/Gaius-Augustus/BRAKER/archive/v2.1.5.tar.gz
#   bioconda : https://anaconda.org/bioconda/braker2
#   （容器：quay.io/biocontainers/braker2 —— 本脚本为宿主机安装，容器用法见模块 README）
#
# 依赖说明：BRAKER 为 Perl 驱动，运行依赖 AUGUSTUS / GeneMark-ES/ET / ProtHint /
#   GenomeThreader(gth) / samtools / bamtools / ncbi-rmblast / diamond / PASA；
#   binary 路线仅部署 BRAKER 脚本本体，依赖工具需另行安装（推荐直接走 conda 路线，自动带入）。
#   GeneMark 需 ~/.gm_key，并设置 AUGUSTUS_CONFIG_PATH / GENEMARK_PATH 等环境变量。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方源码脚本
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: braker）
#   bash install.sh --method binary                   # 强制官方脚本部署（需自行准备依赖工具）
#   bash install.sh --conda-env braker2 --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/braker             # binary 模式自定义前缀
#   bash install.sh --version 2.1.6                   # 覆盖版本（conda pin / GitHub tag）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.1.5"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/braker-$DEFAULT_VERSION}"
CONDA_ENV="braker"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 GitHub tarball（纯 Perl 脚本，无编译）；未内嵌 sha256（可对照 GitHub release/仓库自行核对）。

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

# ---------------- 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（braker.pl --version 输出形如 "braker.pl version 2.1.5"） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 | head -n 2 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 braker2=$VERSION 到环境: $CONDA_ENV（自动带入 AUGUSTUS/GeneMark 等依赖）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "braker2=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "braker2=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV braker.pl --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" braker.pl --version 2>&1 | head -n 2 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 braker.pl / gtf2gff3.pl"
}

# ---------------- 路线 B：官方 GitHub 脚本部署 ----------------
install_binary() {
    local url tmp srcdir
    url="https://github.com/Gaius-Augustus/BRAKER/archive/v${VERSION}.tar.gz"
    log "下载官方源码（纯 Perl 脚本，无需编译）: $url"
    warn "binary 路线仅部署 BRAKER 脚本本体；AUGUSTUS/GeneMark/ProtHint/gth/samtools/bamtools/rmblast/diamond/PASA 需另行安装"
    log "安装前缀: $PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/braker.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/braker.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi
    tar -xzf "$tmp/braker.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "BRAKER-*" | head -1)"
    [[ -n "$srcdir" ]] || die "源码包解压目录异常（URL 或版本号有误？）"

    mkdir -p "$PREFIX/bin"
    local found=0
    for exe in "$srcdir"/scripts/*; do
        [[ -f "$exe" ]] || continue
        ln -sf "$exe" "$PREFIX/bin/$(basename "$exe")"
        found=1
    done
    [[ "$found" == 1 ]] || die "scripts/ 下未找到任何脚本（URL 或版本号有误？）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/braker.pl"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# braker (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 braker.pl 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "braker $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
