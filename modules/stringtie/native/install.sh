#!/usr/bin/env bash
# =============================================================================
# install.sh — StringTie 宿主机本地安装脚本
#
# 归属    ：bioskills modules/stringtie/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「安装方式（本地）」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::stringtie
#   - binary 路线（无 conda 兜底）：官方 GitHub release 二进制，用户级前缀安装
#     到 --prefix（默认 ~/software/stringtie-<ver>），无需 root、不写 /opt
#   - 版本默认 3.0.3，与 modules/stringtie/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://ccb.jhu.edu/software/stringtie/
#   bioconda : https://anaconda.org/bioconda/stringtie
#   release  : https://github.com/gpertea/stringtie/releases
#   (容器：quay.io/biocontainers/stringtie —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: stringtie）
#   bash install.sh --method binary                   # 强制官方 release 二进制（无需 conda）
#   bash install.sh --conda-env st --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/stringtie          # binary 模式自定义前缀
#   bash install.sh --version 3.0.2                   # 覆盖版本（binary 模式 URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="3.0.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/stringtie-$DEFAULT_VERSION}"
CONDA_ENV="stringtie"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release 二进制（仅 linux-64 / osx-64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_LINUX_X86_64="dcd8b0c0069d0707db2decc9ecb7e7455b4e3b3f6c08ef13744860a9fb03acef"
SHA256_OSX_X86_64="cca7e9b173514904becd379cd3974c9462cb2753dd1ea10a51ee443381367009"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
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

# binary 模式仅官方 release 覆盖的平台（linux-x64 / macos-x64）可用
platform_ok_binary() {
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 版本断言（安装后运行 stringtie --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local create_cmd env_exists
    log "使用 conda 安装 stringtie=$VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 用 mamba 时回退 conda；顺序固定 conda-forge 在前，避免依赖冲突
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "stringtie=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "stringtie=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV stringtie --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" stringtie --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 stringtie"
}

# ---------------- 路线 B：官方 GitHub release 二进制 ----------------
install_binary() {
    local plat url tar sha srcdir bin_src
    case "$OS" in
        Linux)  plat="Linux_x86_64"; sha="$SHA256_LINUX_X86_64" ;;
        Darwin) plat="OSX_x86_64";   sha="$SHA256_OSX_X86_64" ;;
    esac
    url="https://github.com/gpertea/stringtie/releases/download/v${VERSION}/stringtie-${VERSION}.${plat}.tar.gz"

    log "下载官方二进制: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/stringtie.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/stringtie.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/stringtie.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/stringtie.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    tar -xzf "$tmp/stringtie.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    bin_src="$(find "${srcdir:-$tmp}" -maxdepth 1 -type f -name stringtie -perm -111 | head -1)"
    [[ -n "$bin_src" ]] || die "release 包内未找到可执行文件 stringtie（URL 或版本号有误？）"

    install -m 0755 "$bin_src" "$PREFIX/bin/stringtie"
    # 附带的 prepDE.py3（DEXSeq 用计数矩阵准备脚本，官方随 release 分发）一并放置
    if [[ -f "${srcdir:-$tmp}/prepDE.py3" ]]; then
        install -m 0755 "${srcdir}/prepDE.py3" "$PREFIX/bin/prepDE.py3"
        log "附赠 prepDE.py3 已放入 $PREFIX/bin"
    fi
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/stringtie"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# stringtie (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 stringtie 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "stringtie $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方二进制（仅 linux-x64 / macos-x64）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方二进制，无法自动安装"
        fi ;;
esac
log "安装成功"
