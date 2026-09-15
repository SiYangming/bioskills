#!/usr/bin/env bash
# =============================================================================
# install.sh — BEAGLE（beagle-lib）宿主机本地安装脚本
#
# 归属    ：bioskills modules/beagle-lib/native/install.sh（native 实现安装方式）
# 路线    ：官方镜像优先（bioconda/quay/depot 已覆盖）→ 本脚本只管宿主机安装
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::beagle-lib=3.1.2
#   - source 路线（无 conda 兜底）：下载官方源码 v3.1.2.tar.gz，./autogen.sh + ./configure
#      --prefix + make + make install，装到 --prefix（默认 ~/software/beagle-lib-3.1.2）
#   - 版本默认 3.1.2，与 modules/beagle-lib/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/beagle-dev/beagle-lib
#   source   : https://github.com/beagle-dev/beagle-lib/archive/v3.1.2.tar.gz
#   bioconda : https://anaconda.org/bioconda/beagle-lib
#   (容器：quay.io/biocontainers/beagle-lib —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 说明：BEAGLE 是库（libhmsbeagle），通过 pkg-config（hmsbeagle-1）供 BEAST2 等链接；
#       source 路线需 autoconf/automake/libtool/pkg-config + C/C++ 编译器。
#
# 用法示例：
#   bash install.sh                                    # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                     # 强制 conda（默认建独立 env: beagle-lib）
#   bash install.sh --method source                    # 强制官方源码编译
#   bash install.sh --prefix ~/opt/beagle-lib          # 自定义安装前缀
#   bash install.sh --no-path-update                   # 不写 shell profile
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="3.1.2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/beagle-lib-$DEFAULT_VERSION}"
CONDA_ENV="beagle-lib"
METHOD="auto"              # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
JOBS="$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 4 )"

SHA256_SOURCE="dd872b484a3a9f0bce369465e60ccf4e4c0cd7bd5ce41499415366019f236275"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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
        --jobs)        JOBS="${2:?--jobs 需要线程数}";         shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（pkg-config --modversion hmsbeagle-1） ----------------
assert_version() {
    local prefix="$1" out ver
    command -v pkg-config >/dev/null 2>&1 || { warn "未安装 pkg-config，跳过版本断言"; return 0; }
    out="$(PKG_CONFIG_PATH="$prefix/lib/pkgconfig" pkg-config --modversion hmsbeagle-1 2>&1 || true)"
    ver="$(awk -v want="$VERSION" '
        $1 ~ /^[0-9]/ { if ($1 == want) found=1; print $1 }
        END { exit found ? 0 : 1 }' <<<"$out" | head -n1 || true)"
    printf '  hmsbeagle-1 = %s\n' "${out:-<未找到>}"
    [[ -n "$ver" ]] || die "版本校验失败：期望 hmsbeagle-1 = ${VERSION}，实际见上"
    log "版本校验通过：$VERSION"
}

# 写出供上层工具（BEAST2 等）链接 BEAGLE 的三个搜索路径
write_env_exports() {
    local prefix="$1"
    [[ "$UPDATE_PATH" == 1 ]] || { log "完成（未改 profile）：请手动 export PKG_CONFIG_PATH/LD_LIBRARY_PATH/C_INCLUDE_PATH"; return 0; }
    local marker="beagle-lib (bioskills install.sh)"
    if [[ -f "$PROFILE" ]] && grep -qF "$prefix/lib/pkgconfig" "$PROFILE"; then
        log "profile 已包含 $prefix 相关路径，跳过写入 $PROFILE"
    else
        {
            echo ""
            echo "# $marker"
            echo "export PKG_CONFIG_PATH=\"$prefix/lib/pkgconfig:\$PKG_CONFIG_PATH\""
            echo "export LD_LIBRARY_PATH=\"$prefix/lib:\$LD_LIBRARY_PATH\""
            echo "export C_INCLUDE_PATH=\"$prefix/include:\$C_INCLUDE_PATH\""
        } >> "$PROFILE"
        log "已追加 PKG_CONFIG_PATH / LD_LIBRARY_PATH / C_INCLUDE_PATH 到 $PROFILE"
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 beagle-lib=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "beagle-lib=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "beagle-lib=$VERSION"
    fi
    local env_prefix
    env_prefix="$("$CONDA_BIN" run -n "$CONDA_ENV" bash -c 'echo "$CONDA_PREFIX"')"
    if command -v pkg-config >/dev/null 2>&1 && [[ -n "$env_prefix" ]]; then
        log "验证：PKG_CONFIG_PATH=$env_prefix/lib/pkgconfig pkg-config --modversion hmsbeagle-1"
        PKG_CONFIG_PATH="$env_prefix/lib/pkgconfig" pkg-config --modversion hmsbeagle-1 2>&1 | sed 's/^/  /' || true
    fi
    log "完成：conda activate $CONDA_ENV 后用其 PKG_CONFIG_PATH/LD_LIBRARY_PATH 链接 BEAGLE"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_source() {
    local url tmp="" srcdir
    url="https://github.com/beagle-dev/beagle-lib/archive/v${VERSION}.tar.gz"

    { command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; } || die "源码编译需要 C 编译器（cc/gcc）"
    command -v make >/dev/null 2>&1 || die "源码编译需要 make"
    command -v autoconf >/dev/null 2>&1 || die "autogen.sh 需要 autoconf/automake/libtool（Debian: apt install autoconf automake libtool）"
    command -v pkg-config >/dev/null 2>&1 || warn "未安装 pkg-config：安装仍可完成，但无法做版本断言/供上层链接"

    log "下载官方源码: $url"
    log "安装前缀: $PREFIX（并行 -j ${JOBS}）"
    mkdir -p "$PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/beagle.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/beagle.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载官方源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SOURCE  $tmp/beagle.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_SOURCE  $tmp/beagle.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官方 release 摘要）"
    fi

    tar -xzf "$tmp/beagle.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "beagle-lib-*" | head -1)"
    [[ -n "$srcdir" ]] || die "解压后未找到源码目录 beagle-lib-*（版本号有误？）"

    ( cd "$srcdir" && ./autogen.sh && ./configure --prefix="$PREFIX" && make -j "$JOBS" && make install ) \
        || die "BEAGLE 源码编译失败（检查 autotools/pkg-config 与工具链）"

    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX"
    write_env_exports "$PREFIX"
    log "安装成功：库位于 $PREFIX/lib，头文件位于 $PREFIX/include"
}

# ---------------- 主流程 ----------------
log "beagle-lib $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
