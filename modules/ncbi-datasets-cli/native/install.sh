#!/usr/bin/env bash
# =============================================================================
# install.sh — NCBI Datasets CLI（ncbi-datasets-cli）宿主机本地安装脚本
#
# 归属    ：bioskills modules/ncbi-datasets-cli/native/install.sh（native 实现安装方式）
# 官方来源：
#   homepage : https://www.ncbi.nlm.nih.gov/datasets/  /  https://github.com/ncbi/datasets
#   release  : https://github.com/ncbi/datasets/releases（v18.36.0，assets 均为平台 zip：
#              linux-amd64 / linux-arm64 / darwin-amd64 / darwin-arm64 / windows-amd64 的
#              <plat>.cli.package.zip，包内含 datasets 与 dataformat 两个可执行）
#   ftp      : https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/LATEST/
#   container: quay.io/biocontainers/ncbi-datasets-cli:14.26.0（官方容器，版本滞后见 README）
#   conda    : conda-forge 有 ncbi-datasets-cli（18.36.0，与上游一致；2026-09 核实。
#              ——早期误判「bioconda 无包即无 conda 路线」，实际包在 conda-forge）
#
# 安装路线（method=auto 默认）：
#   - conda 路线（默认优先）：mamba/conda 建独立环境，-c conda-forge 安装 ncbi-datasets-cli
#   - binary 路线（无 conda 兜底）：官方 GitHub release 平台 zip，用户级前缀（默认
#     ~/software/datasets-<ver>），免 root；装后 datasets --version 断言
# 其它说明：
#   - Homebrew core/brewsci 无公式（2026-09 核实）→ 无 brew 路线。
#   - 官方 release 无公开 sha256 资产 → binary 下载后不做完整性校验（见 --help 说明）。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 conda-forge，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: ncbi-datasets-cli）
#   bash install.sh --method binary                   # 强制官方 release 二进制（无需 conda）
#   bash install.sh --conda-env datasets --force      # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/datasets           # binary 模式自定义前缀
#   bash install.sh --version 18.36.0                 # 覆盖版本（默认 18.36.0，与 meta software_versions.native 对齐）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="18.36.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/datasets-$DEFAULT_VERSION}"
CONDA_ENV="ncbi-datasets-cli"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'
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

# 官方 release 二进制平台串（linux-amd64/arm64、darwin-amd64/arm64）
platform_plat() {
    case "$OS/$ARCH" in
        Linux/x86_64)  echo "linux-amd64" ;;
        Linux/aarch64) echo "linux-arm64" ;;
        Darwin/arm64)  echo "darwin-arm64" ;;
        Darwin/x86_64) echo "darwin-amd64" ;;
        *) return 1 ;;
    esac
}

# ---------------- 版本断言（安装后运行 datasets --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / conda-forge ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 ncbi-datasets-cli=$VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 用 mamba 时回退 conda；包在 conda-forge（非 bioconda）
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge "ncbi-datasets-cli=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge "ncbi-datasets-cli=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV datasets --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" datasets --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 datasets / dataformat"
}

# ---------------- 路线 B：官方 GitHub release 二进制 ----------------
install_binary() {
    local plat url datasets_src dataformat_src tmp srcdir
    plat="$(platform_plat)" || die "官方二进制不支持 ${OS}/${ARCH}（支持 linux-amd64/arm64、darwin-amd64/arm64）；请改用 conda 路线"
    url="https://github.com/ncbi/datasets/releases/download/v${VERSION}/${plat}.cli.package.zip"

    if [[ -d "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "安装前缀 $PREFIX 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "安装前缀 $PREFIX 已存在；加 --force 重建，或改用 --prefix 指定其它路径"
        fi
    fi
    mkdir -p "$PREFIX/bin"

    tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if ! command -v unzip >/dev/null 2>&1; then
        die "需要 unzip 解压官方 release 包（Debian/Ubuntu: apt-get install -y unzip）"
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/package.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/package.zip" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    warn "官方 release 无公开 sha256 资产（2026-09 核实），已跳过下载完整性校验；请自行核对 https://github.com/ncbi/datasets/releases"
    log "下载完成，解压中：$url"
    unzip -q "$tmp/package.zip" -d "$tmp/x"
    srcdir="$tmp/x"

    # 官方 zip 解压后 datasets/dataformat 位于包根或子目录，用 find 定位可执行文件
    datasets_src="$(find "$srcdir" -type f -name datasets -perm -111 2>/dev/null | head -n 1)"
    [[ -n "$datasets_src" ]] || die "release 包内未找到可执行文件 datasets（URL 或版本号有误？）"
    dataformat_src="$(find "$srcdir" -type f -name dataformat -perm -111 2>/dev/null | head -n 1)"
    [[ -n "$dataformat_src" ]] || warn "release 包内未找到 dataformat（同装兄弟工具，缺失不影响 datasets）"

    install -m 0755 "$datasets_src" "$PREFIX/bin/datasets"
    log "datasets -> $PREFIX/bin/datasets"
    if [[ -n "$dataformat_src" ]]; then
        install -m 0755 "$dataformat_src" "$PREFIX/bin/dataformat"
        log "dataformat（附赠兄弟工具）-> $PREFIX/bin/dataformat"
    fi
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/datasets"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# ncbi-datasets-cli (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 datasets / dataformat 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "NCBI Datasets CLI（ncbi-datasets-cli）$VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_plat >/dev/null 2>&1; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方二进制，无法自动安装"
        fi ;;
esac
log "安装成功（版本 ${VERSION}）"
