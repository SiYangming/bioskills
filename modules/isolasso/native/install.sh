#!/usr/bin/env bash
# =============================================================================
# install.sh — IsoLasso 宿主机本地安装脚本
#
# 归属    ：bioskills modules/isolasso/native/install.sh（native 实现安装方式）
# 现代规范（AGENT.md §4.5 变体 / README「环境安装」对齐；官方无 conda 包/二进制）：
#   IsoLasso **无官方 conda 包、无预编译二进制**（bioconda/quay/depot 2026-09 核实全无），
#   官方仅源码（alumni.cs.ucr.edu/~liw/isolasso-2.6.1.tar.gz），安装 = src 目录 make。
#   - conda  路线（有 conda/mamba 时）：用 conda-forge 编译器 + CGAL/GSL/GLPK/GMP 编译源码
#   - source 路线（默认兜底）：依赖系统 g++ 与系统 CGAL/GSL/GLPK/GMP 编译源码
#   - 版本默认 2.6.1，与 modules/isolasso/meta.yaml software_versions.native 对齐
#   ⚠️ 编译依赖（务必先满足）：CGAL / GSL / GLPK / GMP（+ g++/make）；历史 CentOS 6 文档另提及 boost_thread。
#
# 官方来源：
#   homepage : http://alumni.cs.ucr.edu/~liw/isolasso.html
#   source   : http://alumni.cs.ucr.edu/~liw/isolasso-2.6.1.tar.gz
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 conda 编译，否则系统编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: isolasso）
#   bash install.sh --method source                   # 强制系统编译
#   bash install.sh --prefix ~/software/isolasso-2.6.1
#   bash install.sh --conda-env iso --force
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="2.6.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/isolasso-$DEFAULT_VERSION}"
CONDA_ENV="isolasso"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码归档内嵌 sha256（平台无关）；改 --version 后不匹配 → 跳过并提示
SHA256_SOURCE_TARBALL="7f1005f229e6e4aa904e99afeeb5b2ebf4923c9b0e04f6e83745e7c2fa9fe502"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

fetch_tarball() {
    local tmp="$1" url
    url="http://alumni.cs.ucr.edu/~liw/isolasso-${VERSION}.tar.gz"
    log "下载官方源码: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL -o "$tmp/isolasso.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/isolasso.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi
    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${SHA256_SOURCE_TARBALL:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SOURCE_TARBALL  $tmp/isolasso.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败"
        else
            echo "$SHA256_SOURCE_TARBALL  $tmp/isolasso.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi
}

# 编译并部署：在源码 src 内 make（可用 run_prefix 指定 conda run 包装）
build_and_deploy() {
    local tarfile_srcdir="$1" runwrap="$2"
    mkdir -p "$PREFIX/bin"
    ( cd "$tarfile_srcdir/src" && $runwrap make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" )
    [[ -x "$tarfile_srcdir/bin/isolasso" ]] || die "编译未产出 bin/isolasso（请检查 CGAL/GSL/GLPK/GMP 依赖）"
    cp -a "$tarfile_srcdir/bin/." "$PREFIX/bin/"
    chmod +x "$PREFIX/bin/runlasso.py"
    # 版本断言：编译产物存在（IsoLasso 无 --version 输出）
    test -x "$PREFIX/bin/isolasso" || die "未找到 $PREFIX/bin/isolasso"
    log "版本自检通过：bin/isolasso 已就绪（$VERSION）"
}

install_conda() {
    local run_py tmp="" srcdir
    log "使用 conda 编译 IsoLasso=$VERSION 到前缀: $PREFIX（env: $CONDA_ENV）"
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge \
        cxx-compiler make cgal gsl glpk gmp python=3 || die "conda 建环境失败"
    local runwrap="$CONDA_BIN run -n $CONDA_ENV"

    tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"' EXIT
    fetch_tarball "$tmp"
    tar -xzf "$tmp/isolasso.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    build_and_deploy "$srcdir" "$runwrap"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    log "完成：PATH 加入 $PREFIX/bin 后使用 runlasso.py / isolasso / processsam"
}

install_source() {
    local tmp="" srcdir
    command -v g++ >/dev/null 2>&1 || die "未找到 g++（--method source 需系统编译器与 CGAL/GSL/GLPK/GMP dev 库）"
    log "使用系统编译器编译 IsoLasso=$VERSION 到前缀: $PREFIX"

    tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"' EXIT
    fetch_tarball "$tmp"
    tar -xzf "$tmp/isolasso.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    build_and_deploy "$srcdir" ""
    rm -rf "$tmp"; tmp=""; trap - EXIT

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# isolasso (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 runlasso.py 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

log "isolasso $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then install_conda; else install_source; fi ;;
esac
log "安装成功"
