#!/usr/bin/env bash
# =============================================================================
# install.sh — Trinity 宿主机本地安装脚本
#
# 归属    ：bioskills modules/trinity/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::trinity
#   - source 路线（无 conda 兜底）：官方 GitHub release FULL 源码归档（Trinity 官方
#     未提供按平台划分的预编译二进制，已核实），编译到用户级前缀
#     --prefix（默认 ~/software/trinity-<ver>），无需 root、不写 /opt
#   - 版本默认 2.11.0，与 modules/trinity/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/trinityrnaseq/trinityrnaseq/
#   bioconda : https://anaconda.org/bioconda/trinity
#   release  : https://github.com/trinityrnaseq/trinityrnaseq/releases
#   (容器：quay.io/biocontainers/trinity —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 FULL 源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: trinity）
#   bash install.sh --method source                   # 强制官方 release FULL 源码编译（无需 conda）
#   bash install.sh --conda-env tr --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/trinity --jobs 8   # source 模式自定义前缀 / 并行编译数
#   bash install.sh --version 2.11.0 --sha256 <hex>   # 非默认版本需自备 sha256（或核对后省略）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.11.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/trinity-$DEFAULT_VERSION}"
CONDA_ENV="trinity"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
USER_SHA256=""

# 官方 FULL 源码归档（跨平台同一包）内嵌 sha256（2026-09 实测官方 asset）；
# 非默认版本或未提供 --sha256 时会打印实际下载文件摘要供与 release 页核对。
SHA256_LINUX_X86_64="230798b3c2eea7043098de3055a1fe150213929b0773e6d374fc0c7219c310c6"
SHA256_OSX_X86_64="230798b3c2eea7043098de3055a1fe150213929b0773e6d374fc0c7219c310c6"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
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
        --jobs|-j)     JOBS="${2:?--jobs 需要数字}";           shift 2 ;;
        --sha256)      USER_SHA256="${2:?--sha256 需要 64 位十六进制}"; shift 2 ;;
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

# source 模式：官方 FULL 归档为跨平台源码，Linux / macOS 均可编译（官方无预编译二进制）
platform_ok_source() {
    [[ "$OS" == "Linux" || "$OS" == "Darwin" ]]
}

# ---------------- 版本断言（安装后运行 Trinity --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 | grep -E '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 trinity=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "trinity=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "trinity=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV Trinity --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" Trinity --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 Trinity"
}

# ---------------- 路线 B：官方 FULL 源码编译 ----------------
install_source() {
    local sha url tar plat
    case "$OS" in
        Linux)  sha="$SHA256_LINUX_X86_64" ;;
        Darwin) sha="$SHA256_OSX_X86_64" ;;
    esac
    sha="${USER_SHA256:-$sha}"
    url="https://github.com/trinityrnaseq/trinityrnaseq/releases/download/v${VERSION}/trinityrnaseq-v${VERSION}.FULL.tar.gz"

    log "下载官方 FULL 源码归档: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/trinity.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/trinity.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/trinity.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/trinity.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}）且未提供 --sha256，跳过校验（请自行核对 GitHub release 摘要）"
    else
        warn "本模块未内嵌 trinity ${VERSION} 官方 sha256（未编造）；实际下载文件摘要如下，请与 release 页核对："
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$tmp/trinity.tar.gz" | sed 's/^/    /'
        else
            shasum -a 256 "$tmp/trinity.tar.gz" | sed 's/^/    /'
        fi
    fi

    tar -xzf "$tmp/trinity.tar.gz" -C "$PREFIX"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    local srcdir
    srcdir="$(find "$PREFIX" -maxdepth 1 -mindepth 1 -type d -name 'trinityrnaseq-*' | head -1)"
    [[ -n "$srcdir" ]] || die "release 包结构异常（未找到 trinityrnaseq-* 目录）"
    log "编译 Trinity（make -j ${JOBS}）…"
    ( cd "$srcdir" && make -j "$JOBS" )
    log "安装 plugins（make plugins）…"
    ( cd "$srcdir" && make plugins ) || warn "make plugins 失败（可稍后单独重试；不影响主程序使用）"

    assert_version "$srcdir/Trinity"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$srcdir:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$srcdir" "$PROFILE"; then
            log "PATH 已包含 $srcdir，跳过写入 $PROFILE"
        else
            { echo ""; echo "# trinity (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 Trinity 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$srcdir:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "trinity $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        platform_ok_source || die "--method source 在 ${OS}/${ARCH} 不受支持（官方 FULL 归档支持 Linux / macOS）"
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_source; then
            install_source
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无法源码编译，无法自动安装"
        fi ;;
esac
log "安装成功"
