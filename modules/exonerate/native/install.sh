#!/usr/bin/env bash
# =============================================================================
# install.sh — exonerate 宿主机本地安装脚本
#
# 归属    ：bioskills modules/exonerate/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::exonerate=2.2.0
#   - binary 路线（无 conda 兜底）：官方预编译二进制 exonerate-2.2.0-x86_64.tar.gz（EBI FTP），
#     解压到用户前缀（默认 ~/software/exonerate-2.2.0），无需 root、不写 /opt
#   - 版本默认 2.2.0，与 modules/exonerate/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage  : https://www.ebi.ac.uk/about/vertebrate-genomics/software/exonerate
#   prebuilt  : http://ftp.ebi.ac.uk/pub/software/vertebrategenomics/exonerate/exonerate-2.2.0-x86_64.tar.gz
#   source    : http://ftp.ebi.ac.uk/pub/software/vertebrategenomics/exonerate/exonerate-2.2.0.tar.gz
#   bioconda  : https://anaconda.org/bioconda/exonerate
#   (容器：quay.io/biocontainers/exonerate:2.2.0--1 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方预编译二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: exonerate）
#   bash install.sh --method binary                   # 强制官方预编译二进制（仅 linux-x86_64）
#   bash install.sh --prefix ~/opt/exonerate          # binary 模式自定义前缀
#   bash install.sh --version 2.2.0 --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.2.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/exonerate-$DEFAULT_VERSION}"
CONDA_ENV="exonerate"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方预编译二进制（仅 linux-x86_64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_LINUX_X86_64="8fcb0cf3cf795d66e84cc185e38e6208fda047778940128a3decbe7dec010b2d"

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

# binary 模式仅官方预编译覆盖的平台（linux-x86_64）
platform_ok_binary() { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }

# ---------------- 版本断言（exonerate --version：输出含 "exonerate" 且含版本号） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\\.}" <<<"$out" || die "版本校验失败：期望输出含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 exonerate=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "exonerate=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "exonerate=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV exonerate --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" exonerate --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 exonerate"
}

# ---------------- 路线 B：官方预编译二进制（EBI FTP） ----------------
install_binary() {
    local url sha tmp src
    sha="$SHA256_LINUX_X86_64"
    url="http://ftp.ebi.ac.uk/pub/software/vertebrategenomics/exonerate/exonerate-${VERSION}-x86_64.tar.gz"

    log "下载官方预编译二进制: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/exonerate.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/exonerate.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载预编译二进制"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/exonerate.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/exonerate.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 EBI 发布摘要）"
    fi

    tar -xzf "$tmp/exonerate.tar.gz" -C "$PREFIX"
    src="$(find "$PREFIX" -maxdepth 1 -mindepth 1 -type d -name 'exonerate-*' | head -1)"
    [[ -n "$src" && -x "$src/bin/exonerate" ]] || die "预编译包内未找到 bin/exonerate（URL 或版本号有误？）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$src/bin/exonerate"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$src/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$src/bin" "$PROFILE"; then
            log "PATH 已包含 $src/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# exonerate (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 exonerate 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$src/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "exonerate $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译二进制（仅 linux-x86_64）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方预编译二进制，无法自动安装"
        fi ;;
esac
log "安装成功"
