#!/usr/bin/env bash
# =============================================================================
# install.sh — Subread / featureCounts 宿主机本地安装脚本
#
# 归属    ：bioskills modules/subread/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::subread
#   - binary 路线（无 conda 兜底）：官方 SourceForge 预编译二进制，用户级前缀安装
#     到 --prefix（默认 ~/software/subread-<ver>），无需 root、不写 /opt/biosoft
#   - 版本默认 2.0.1，与 modules/subread/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage   : http://subread.sourceforge.net/
#   SourceForge: https://sourceforge.net/projects/subread/files/subread-2.0.1/
#   bioconda   : https://anaconda.org/bioconda/subread
#   (容器：quay.io/biocontainers/subread:2.0.1--h7132678_2 / depot.galaxyproject.org
#    —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 注意：SourceForge 预编译包仅覆盖 linux-x64 / macos-x64（Linux-x86_64 / MacOS-x86_64），
#       其余平台请走 conda 路线。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: subread）
#   bash install.sh --method binary                   # 强制官方 SourceForge 预编译二进制
#   bash install.sh --conda-env sr --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/subread            # binary 模式自定义前缀
#   bash install.sh --version 2.0.6                   # 覆盖版本（binary 模式 URL 模板；跳过内嵌校验）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.0.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/subread-$DEFAULT_VERSION}"
CONDA_ENV="subread"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
SHA256=""              # 可选：显式提供时校验下载包（默认不内嵌，避免编造摘要）

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
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
        --sha256)      SHA256="${2:?--sha256 需要 64 位摘要}"; shift 2 ;;
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

# binary 模式仅官方预编译包覆盖的平台（linux-x64 / macos-x64）
platform_ok_binary() {
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 版本断言（安装后运行 featureCounts -v 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -v 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local create_cmd env_exists
    log "使用 conda 安装 subread=$VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 顺序固定 conda-forge 在前，避免依赖冲突
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "subread=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "subread=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV featureCounts -v"
    "$CONDA_BIN" run -n "$CONDA_ENV" featureCounts -v 2>&1 | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 featureCounts / subread-align / subjunc"
}

# ---------------- 路线 B：官方 SourceForge 预编译二进制 ----------------
install_binary() {
    local plat url srcdir
    case "$OS" in
        Linux)  plat="Linux-x86_64" ;;
        Darwin) plat="MacOS-x86_64" ;;
    esac
    url="https://sourceforge.net/projects/subread/files/subread-${VERSION}/subread-${VERSION}-${plat}.tar.gz/download"

    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/subread.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/subread.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载预编译包"
    fi

    # 未内嵌 sha256（按录入规范禁真实下载核对）；--sha256 显式提供时才校验
    if [[ -n "$SHA256" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256  $tmp/subread.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256  $tmp/subread.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "未提供 --sha256，跳过摘要校验（可自行核对 SourceForge 发布摘要）"
    fi

    tar -xzf "$tmp/subread.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" && -d "$srcdir/bin" ]] \
        || die "预编译包内未找到 bin/ 目录（URL 或版本号有误？）"
    # 拷贝整套 bin（featureCounts / subread-align / subjunc / subread-buildindex 等）
    mkdir -p "$PREFIX/bin"
    cp -a "$srcdir/bin/." "$PREFIX/bin/"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/featureCounts"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# subread (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 featureCounts 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "subread $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方预编译包，无法自动安装"
        fi ;;
esac
log "安装成功"
