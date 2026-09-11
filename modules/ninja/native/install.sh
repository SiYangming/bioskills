#!/usr/bin/env bash
# =============================================================================
# install.sh — NINJA（Nearly Infinite Neighbor Joining Application）宿主机本地安装脚本
#
# 归属    ：bioskills modules/ninja/native/install.sh（native 实现安装方式）
# 迁移形态：官方镜像优先（bioconda → quay.io/biocontainers → depot.galaxyproject.org
#   均已维护），宿主机工具走本脚本；双路线：
#     - conda  路线（默认优先）：mamba/conda 创建独立环境，装官方包 ninja-nj=<版本>
#       （bioconda；可执行文件为 Ninja。注意包名是 ninja-nj，不是同名构建系统 ninja）
#     - source 路线（无 conda 兜底）：下载 cluster_only C++ 源码归档（由 GitHub 仓库
#       TravisWheelerLab/ninja-old 提供；原 TravisWheelerLab/NINJA 于 2026 年改版为
#       Rust 实现后，C++ 版归档至 ninja-old），本地 make 编译出 Ninja，安装到用户前缀
#       --prefix（默认 ~/software/NINJA-<ver>），用户级前缀、无需 root
#   - 版本默认 1.00，与 modules/ninja/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/TravisWheelerLab/NINJA
#   bioconda : https://anaconda.org/bioconda/ninja-nj（包名 ninja-nj）
#   legacy C++ 源码归档：https://github.com/TravisWheelerLab/ninja-old
#     源码归档 URL 模板：https://github.com/TravisWheelerLab/ninja-old/archive/${ver}-cluster_only.tar.gz
#   （容器：quay.io/biocontainers/ninja-nj —— bioconda 自动构建，本脚本为宿主机安装，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                            # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                             # 强制 conda（默认建独立 env: ninja）
#   bash install.sh --method source                            # 强制源码编译（无需 conda）
#   bash install.sh --method source --source-tarball ~/Downloads/1.00-cluster_only.tar.gz
#   bash install.sh --conda-env ninja-nj --force               # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/software/NINJA-1.00
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.00"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/NINJA-$DEFAULT_VERSION}"
CONDA_ENV="ninja"
METHOD="auto"          # auto | conda | source（binary 为 source 的别名）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
SOURCE_TARBALL=""

# 官方源码归档（cluster_only C++）sha256：默认版本 1.00 的 1.00-cluster_only 归档
#   https://github.com/TravisWheelerLab/ninja-old/archive/1.00-cluster_only.tar.gz
#   （平台无关的源码归档；GitHub 生成的归档字节若日后被重新打包，sha256 可能变化——
#     此时可用 --version 覆盖为非默认版本（跳过内嵌校验）或 --no-verify 跳过校验）
DEFAULT_SHA256="a0500478ab67a46ae60440a11217892053677771ad97f77cfca896e869f276d5"
VERIFY_SHA=1

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
        --version)         VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)          PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)          METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)       CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --source-tarball)  SOURCE_TARBALL="${2:?--source-tarball 需要 tarball 路径}"; shift 2 ;;
        --profile)         PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)           FORCE=1; shift ;;
        --no-path-update)  UPDATE_PATH=0; shift ;;
        --no-verify)       VERIFY_SHA=0; shift ;;
        --help|-h)         usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

# 允许 binary 作为 source 的别名（AGENT.md §4.5 参数面）
if [[ "$METHOD" == "binary" ]]; then METHOD="source"; fi
case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（Ninja -v 输出形如 "Version 1.00-cluster_only"） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -v 2>&1)"
    printf '  %s\n' "$out"
    grep -qF "$VERSION" <<<"$out" || die "版本校验失败：期望输出含 ${VERSION}，实际见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda（官方包 ninja-nj） ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists
    log "使用 conda 安装 ninja-nj=$VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 官方 bioconda 包名为 ninja-nj（勿用同名构建系统 conda-forge/ninja）
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "ninja-nj=$VERSION"
    log "验证：conda run -n $CONDA_ENV Ninja -v"
    "$CONDA_BIN" run -n "$CONDA_ENV" Ninja -v | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 Ninja"
}

# ---------------- 路线 B：cluster_only C++ 源码编译（无 conda 兜底） ----------------
install_source() {
    command -v make >/dev/null 2>&1 || die "--method source 需要 make（未找到）；或改用 --method conda"
    if ! command -v c++ >/dev/null 2>&1 && ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
        die "--method source 需要 C++ 编译器（c++/g++/clang++）；或改用 --method conda"
    fi
    local CXX_BIN=""
    CXX_BIN="$(command -v c++ || command -v g++ || command -v clang++)"

    local tmp="" src_dir="" archive=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if [[ -n "$SOURCE_TARBALL" ]]; then
        [[ -f "$SOURCE_TARBALL" ]] || die "未找到 --source-tarball: ${SOURCE_TARBALL}"
        archive="$SOURCE_TARBALL"
        log "使用本地源码归档：${archive}"
    else
        local url="https://github.com/TravisWheelerLab/ninja-old/archive/${VERSION}-cluster_only.tar.gz"
        archive="$tmp/ninja-src.tar.gz"
        log "下载官方 cluster_only 源码归档：${url}"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$archive" "$url" || die "下载失败：${url}（版本号是否有效？cluster_only 标签形如 1.00-cluster_only）"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$archive" "$url" || die "下载失败：${url}"
        else
            die "--method source 需要 curl 或 wget 下载源码归档"
        fi
    fi

    # sha256 校验（仅对默认版本内嵌值；非默认版本或 --no-verify 时跳过并提示）
    if [[ "$VERIFY_SHA" == 1 && "$VERSION" == "$DEFAULT_VERSION" && -z "$SOURCE_TARBALL" ]]; then
        if command -v shasum >/dev/null 2>&1; then
            local got
            got="$(shasum -a 256 "$archive" | awk '{print $1}')"
        elif command -v sha256sum >/dev/null 2>&1; then
            local got
            got="$(sha256sum "$archive" | awk '{print $1}')"
        else
            warn "未找到 shasum/sha256sum，跳过校验"
            got=""
        fi
        if [[ -n "${got:-}" ]]; then
            [[ "$got" == "$DEFAULT_SHA256" ]] \
                && log "sha256 校验通过" \
                || die "sha256 校验失败：期望 ${DEFAULT_SHA256}，实际 ${got}（GitHub 归档可能被重新打包；确认无误后可加 --no-verify）"
        fi
    else
        [[ "$VERIFY_SHA" == 1 ]] && warn "非默认版本或本地归档，跳过内嵌 sha256 校验；请自行核对归档摘要"
    fi

    log "解压源码归档"
    tar -xzf "$archive" -C "$tmp"
    src_dir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "ninja-old-*" | head -1)"
    [[ -n "$src_dir" ]] || die "归档内未找到 ninja-old-* 顶层目录（归档结构异常？）"
    [[ -d "$src_dir/NINJA" ]] || die "源码目录内未找到 NINJA/（确认是 cluster_only 归档？）"

    local CXXFLAGS="-std=gnu++14 -Wall -O3"
    if [[ "$ARCH" == "x86_64" ]]; then CXXFLAGS="$CXXFLAGS -mssse3"; fi

    log "编译 Ninja（CXX=${CXX_BIN}，CXXFLAGS=\"${CXXFLAGS}\"）"
    ( cd "$src_dir/NINJA" && make all CXX="$CXX_BIN" CXXFLAGS="$CXXFLAGS" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" ) \
        || die "编译失败（需要支持 C++14 的编译器与 make）"

    [[ -x "$src_dir/NINJA/Ninja" ]] || die "编译产物 NINJA/Ninja 未生成"
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            case "$PREFIX" in
                ""|"/"|"$HOME") die "拒绝删除危险前缀: ${PREFIX}" ;;
            esac
            log "前缀 ${PREFIX} 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 重建，或改用 --prefix 指定其它目录"
        fi
    fi
    mkdir -p "$PREFIX/bin"
    install -m 0755 "$src_dir/NINJA/Ninja" "$PREFIX/bin/Ninja"
    log "已安装 Ninja -> $PREFIX/bin/Ninja"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/Ninja"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# ninja (bioskills install.sh)"; echo "export PATH=\"$PREFIX/bin:\$PATH\""; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 Ninja 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "NINJA ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            warn "未检测到 mamba/conda，改走 source 路线（源码编译）"
            install_source
        fi ;;
esac
log "安装成功"
