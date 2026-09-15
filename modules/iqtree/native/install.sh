#!/usr/bin/env bash
# =============================================================================
# install.sh — IQ-TREE 宿主机本地安装脚本
#
# 归属    ：bioskills modules/iqtree/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5；官方镜像优先语境）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::iqtree=1.6.12
#   - binary 路线（无 conda 兜底）：官方 GitHub release 预编译包，解压到用户级前缀
#     --prefix（默认 ~/software/iqtree-1.6.12），无需 root、不写 /opt
#   - 版本默认 1.6.12，与 modules/iqtree/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://www.iqtree.org/
#   release  : https://github.com/Cibiv/IQ-TREE/releases/tag/v1.6.12
#   source   : https://github.com/Cibiv/IQ-TREE/archive/refs/tags/v1.6.12.tar.gz（cmake）
#   (容器：quay.io/biocontainers/iqtree:1.6.12--he513fc3_0 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                               # auto：有 conda/mamba 走 bioconda，否则官方预编译包
#   bash install.sh --method conda                # 强制 conda（默认建独立 env: iqtree）
#   bash install.sh --method binary               # 强制官方 release 包（仅 linux/macos x86_64）
#   bash install.sh --conda-env iq --force        # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/iqtree         # binary 模式自定义前缀
#   bash install.sh --version 1.6.12 --force      # 覆盖版本（跳过内嵌 sha256 校验并提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.6.12"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/iqtree-$DEFAULT_VERSION}"
CONDA_ENV="iqtree"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方预编译包（仅 linux-x86_64 / macos-x86_64）内嵌 sha256
SHA256_LINUX_X86_64="3762f471d8853d9fd2bdf5f18af60f916c10690fa53eed8015b71a8cc674d487"
SHA256_OSX_X86_64="7a5b21e6cada366d32b9dc32b843c6cb30d06a06a090e1e5cfbeec2e0f72c39f"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
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
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# binary 模式仅官方预编译覆盖的平台（linux-x64 / macos-x64）可用
platform_ok_binary() {
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 版本断言（安装后运行 iqtree --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 iqtree=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "iqtree=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "iqtree=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV iqtree --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" iqtree --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 iqtree"
}

# ---------------- 路线 B：官方 GitHub release 预编译包 ----------------
install_binary() {
    local plat url pkg sha srcdir bin_src
    case "$OS" in
        Linux)  plat="Linux";  pkg="iqtree-${VERSION}-Linux.tar.gz";  sha="$SHA256_LINUX_X86_64" ;;
        Darwin) plat="MacOSX"; pkg="iqtree-${VERSION}-MacOSX.zip";    sha="$SHA256_OSX_X86_64" ;;
    esac
    url="https://github.com/Cibiv/IQ-TREE/releases/download/v${VERSION}/${pkg}"

    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"
    [[ "$FORCE" == 1 || ! -e "$PREFIX" ]] || die "前缀已存在：${PREFIX}（加 --force 覆盖，或 --prefix 指定其它目录）"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/$pkg" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/$pkg" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/$pkg" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/$pkg" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    case "$pkg" in
        *.tar.gz) tar -xzf "$tmp/$pkg" -C "$tmp" ;;
        *.zip)    ( cd "$tmp" && unzip -q "$pkg" ) ;;
    esac
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'iqtree-*' | head -1)"
    [[ -n "$srcdir" ]] || die "release 包结构异常（未找到 iqtree-* 目录）"
    bin_src="$(find "$srcdir" -type f -path '*/bin/iqtree' -perm -111 | head -1)"
    [[ -n "$bin_src" ]] || die "release 包内未找到可执行文件 bin/iqtree（URL 或版本号有误？）"
    install -m 0755 "$bin_src" "$PREFIX/bin/iqtree"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/iqtree"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# iqtree (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 iqtree 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "iqtree $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译包（仅 linux-x64 / macos-x64）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方预编译包（Apple Silicon 请用 --method conda，或 Rosetta 跑 x86_64 包），无法自动安装"
        fi ;;
esac
log "安装成功"
