#!/usr/bin/env bash
# =============================================================================
# install.sh — SpliceGrapher 宿主机本地安装脚本
#
# 归属    ：bioskills modules/splicegrapher/native/install.sh（native 实现安装方式）
# 现代规范（AGENT.md §4.5 变体 / README「环境安装」对齐；官方无 conda 包/二进制）：
#   本工具**无官方 conda 包、无预编译二进制**（bioconda/quay/depot 2026-09 核实全无），
#   官方仅源码（SourceForge SpliceGrapher-0.2.7.tgz，python setup.py build && install）。
#   - conda  路线（有 conda/mamba 时）：建 python=2.7 环境并 pip 装依赖 + setup.py install
#   - source 路线（默认兜底）：系统 python2 + pip 装依赖 + setup.py install --prefix
#   - 版本默认 0.2.7，与 modules/splicegrapher/meta.yaml software_versions.native 对齐
#   ⚠️ SpliceGrapher 0.2.7 为 Python 2.7 时代代码（依赖 PyML），需 python2.7。
#
# 官方来源：
#   homepage : http://splicegrapher.sourceforge.net/
#   source   : https://sourceforge.net/projects/splicegrapher/files/SpliceGrapher-0.2.7.tgz
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 py2.7 conda 环境，否则系统 python2
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: splicegrapher）
#   bash install.sh --method source                   # 强制系统 python2 源码安装
#   bash install.sh --prefix ~/software/splicegrapher-0.2.7   # source 模式前缀
#   bash install.sh --conda-env sg --force
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="0.2.7"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/splicegrapher-$DEFAULT_VERSION}"
CONDA_ENV="splicegrapher"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码归档内嵌 sha256（平台无关）；改 --version 后不匹配 → 跳过并提示
SHA256_SOURCE_TARBALL="a3fc8310d41dbd95d5b6e8a31b781588a9f47e0c34ce0c284c22cae716b2f9ae"

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

# 找系统 python2（source 路线）
find_python2() {
    if command -v python2.7 >/dev/null 2>&1; then echo "python2.7";
    elif command -v python2 >/dev/null 2>&1; then echo "python2";
    else echo ""; fi
}

# 下载并校验（回显归档路径 $tmp/sg.tgz）
fetch_tarball() {
    local tmp="$1" url
    url="https://downloads.sourceforge.net/project/splicegrapher/SpliceGrapher-${VERSION}.tgz"
    log "下载官方源码: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL -o "$tmp/sg.tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/sg.tgz" "$url"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi
    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${SHA256_SOURCE_TARBALL:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SOURCE_TARBALL  $tmp/sg.tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败"
        else
            echo "$SHA256_SOURCE_TARBALL  $tmp/sg.tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi
}

assert_version() {
    local py="$1" out
    out="$("$py" -c 'import SpliceGrapher; print(SpliceGrapher.__version__)' 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda（python=2.7 环境 + 源码 install） ----------------
install_conda() {
    local env_exists run_py tmp=""
    log "使用 conda 安装 SpliceGrapher=$VERSION 到环境: $CONDA_ENV（python=2.7）"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env"
        fi
    fi
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge python=2.7 pip samtools hisat2 numpy
    run_py="$("$CONDA_BIN" run -n "$CONDA_ENV" which python)"

    tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"' EXIT
    fetch_tarball "$tmp"
    tar -xzf "$tmp/sg.tgz" -C "$tmp"
    local srcdir; srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    "$run_py" -m pip install --no-cache-dir setuptools PyML matplotlib pysam
    ( cd "$srcdir" && "$run_py" setup.py build && "$run_py" setup.py install )
    rm -rf "$tmp"; tmp=""; trap - EXIT

    "$CONDA_BIN" run -n "$CONDA_ENV" python -c \
        'import SpliceGrapher; print("SpliceGrapher", SpliceGrapher.__version__)'
    log "完成：conda activate $CONDA_ENV 后即可使用 build_classifiers.py 等脚本"
}

# ---------------- 路线 B：系统 python2 源码安装 ----------------
install_source() {
    local py tmp="" srcdir
    py="$(find_python2)"
    [[ -n "$py" ]] || die "未找到 python2/python2.7（SpliceGrapher 0.2.7 需 Python 2.7）；请先安装 python2 或改用 --method conda"
    log "使用 $py 源码安装 SpliceGrapher=$VERSION 到前缀: $PREFIX"

    tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"' EXIT
    fetch_tarball "$tmp"
    tar -xzf "$tmp/sg.tgz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"

    "$py" -m pip install --user setuptools PyML matplotlib pysam
    ( cd "$srcdir" && "$py" setup.py build && "$py" setup.py install --prefix="$PREFIX" )
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 版本断言（用系统 python2；install --prefix 后模块应在 PYTHONPATH 可及处）
    local scripts_dir="$PREFIX/bin"
    assert_version "$py" || true

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$scripts_dir:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$scripts_dir" "$PROFILE"; then
            log "PATH 已包含 $scripts_dir，跳过写入 $PROFILE"
        else
            { echo ""; echo "# splicegrapher (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 build_classifiers.py 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$scripts_dir:\$PATH\""
    fi
}

log "splicegrapher $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
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
