#!/usr/bin/env bash
# =============================================================================
# install.sh — r8s 宿主机本地安装脚本
#
# 归属    ：bioskills modules/r8s/native/install.sh（native 实现安装方式）
# 路线    ：官方渠道全无（bioconda/quay/depot 2026-09 核实均无 r8s）→ 源码编译
#   - source 路线（默认唯一路线）：下载官方源码 r8s1.81.tar.gz（SourceForge），
#     补丁旧 makefile（去系统头依赖）+ make 编译，安装 r8s 到 --prefix/bin，无需 root
#   - 无 conda 路线：bioconda/bioconda-recipes recipes/r8s 返回 404，无包可装
#   - 版本默认 1.81，与 modules/r8s/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://sourceforge.net/projects/r8s/
#   source   : https://downloads.sourceforge.net/project/r8s/r8s1.81.tar.gz
#   (容器：官方无；本模块提供 native/Dockerfile 自建配方，用法见模块 README)
#
# 依赖：gfortran（Fortran 编译器）+ gcc/cc + make
# 用法示例：
#   bash install.sh                       # auto：源码编译 r8s 1.81
#   bash install.sh --method source       # 显式源码编译
#   bash install.sh --prefix ~/opt/r8s    # 自定义安装前缀
#   bash install.sh --no-path-update    # 不写 shell profile
#   bash install.sh --force               # 前缀已存在时强制覆盖
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.81"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/r8s-$DEFAULT_VERSION}"
METHOD="auto"              # auto | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
JOBS="$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 4 )"

SHA256_SOURCE="9e89d7851d74d74487d147b77177a717e6c659b485c9b67f516340a6ed595080"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|source}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --jobs)        JOBS="${2:?--jobs 需要线程数}";         shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|source) ;; *) die "--method 仅支持 auto|source（收到: ${METHOD}）；官方无 conda/二进制包" ;; esac

# ---------------- 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"

# ---------------- 版本断言（r8s -v -b 打印 "r8s version 1.81"，且以退出码 1 结束） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -v -b 2>&1 || true)"
    printf '  %s\n' "$(head -n 1 <<<"$out")"
    grep -qE "r8s version[[:space:]]+${VERSION//./\.}" <<<"$out" \
        || die "版本校验失败：期望输出含 'r8s version ${VERSION}'，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 源码编译 ----------------
install_source() {
    local url tmp="" srcdir
    url="https://downloads.sourceforge.net/project/r8s/r8s${VERSION}.tar.gz"

    command -v gfortran >/dev/null 2>&1 || die "r8s 为 Fortran 程序，编译需要 gfortran（Debian: apt install gfortran；macOS: brew install gcc）"
    { command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; } || die "编译需要 C 编译器（cc/gcc）"

    log "下载官方源码: $url"
    log "安装前缀: $PREFIX（并行 -j ${JOBS}）"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/r8s.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/r8s.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载官方源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SOURCE  $tmp/r8s.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_SOURCE  $tmp/r8s.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官方 release 摘要）"
    fi

    tar -xzf "$tmp/r8s.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "r8s${VERSION}" | head -1)"
    [[ -n "$srcdir" ]] || die "解压后未找到源码目录 r8s${VERSION}（版本号有误？）"

    # 旧 makefile 依赖 /usr/include/*.h（macOS 无此路径）→ 去除系统头依赖
    ( cd "$srcdir/src" && sed -e 's#/usr/include/[^ ]*##g' makefile > makefile.new && mv makefile.new makefile )
    # gfortran 10+ 对旧 Fortran 实参不匹配报错 → -fallow-argument-mismatch；旧 C 用 -fcommon
    ( cd "$srcdir/src" && make CC="${CC:-gcc}" FC=gfortran LPATH= \
        CFLAGS="-O2 -w -fcommon" FFLAGS="-fallow-argument-mismatch -w" -j "$JOBS" r8s ) \
        || die "r8s 编译失败（检查 gfortran 版本与系统头）"
    [[ -x "$srcdir/src/r8s" ]] || die "编译未产出可执行文件 src/r8s"
    install -m 0755 "$srcdir/src/r8s" "$PREFIX/bin/r8s"

    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/r8s"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# r8s (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 r8s 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "r8s $VERSION 安装开始（本机 ${OS}/${ARCH}）"
if [[ -n "${CONDA_PREFIX:-}" ]] || command -v conda >/dev/null 2>&1; then
    warn "检测到 conda，但官方渠道无 r8s 包（bioconda recipes/r8s 404）——仍走官方源码编译"
fi
case "$METHOD" in
    source|auto) install_source ;;
esac
log "安装成功"
