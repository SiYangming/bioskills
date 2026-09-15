#!/usr/bin/env bash
# =============================================================================
# install.sh — ClustalW 宿主机本地安装脚本
#
# 归属    ：bioskills modules/clustalw/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda 路线（默认优先，跨平台）：mamba/conda 创建独立环境，pin bioconda::clustalw=2.1
#   - binary 路线（官方预编译静态二进制，仅 linux-x64）：clustalw-2.1-linux-x86_64-libcppstatic.tar.gz
#     （EBI 官方镜像站；包内为 clustalw2，脚本自动补 clustalw 软链）
#   - source 路线（官方源码）：clustalw-2.1.tar.gz → ./configure && make && make install
#   - 版本默认 2.1，与 modules/clustalw/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://www.clustal.org/clustal2/
#   download : http://www.clustal.org/download/ （EBI 镜像 https://ftp.ebi.ac.uk/pub/software/clustalw2/2.1/）
#   bioconda : https://anaconda.org/bioconda/clustalw
#   (容器：quay.io/biocontainers/clustalw —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 说明：ClustalW 无 --version 旗标；断言用 `clustalw -help` 抓 "CLUSTAL 2.1" 版本串。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda；否则 linux-x64 用官方预编译，其余源码
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: clustalw）
#   bash install.sh --method binary                   # 强制官方预编译静态二进制（仅 linux-x64）
#   bash install.sh --method source                   # 强制官方源码编译
#   bash install.sh --conda-env clustalw --force
#   bash install.sh --prefix ~/software/clustalw-2.1 --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/clustalw-$DEFAULT_VERSION}"
CONDA_ENV="clustalw"
METHOD="auto"          # auto | conda | binary | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方资产内嵌 sha256（EBI 官方镜像站 clustalw2/2.1/）
SHA256_BINARY_LINUX_X86_64="e8d488db819789642b44945d238a50847f2505a1a0dd43d374fa7f29f9defcac"   # clustalw-2.1-linux-x86_64-libcppstatic.tar.gz
SHA256_SOURCE="e052059b87abfd8c9e695c280bfba86a65899138c82abccd5b00478a80f49486"                 # clustalw-2.1.tar.gz

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
        --method)      METHOD="${2:?--method 需要 auto|conda|binary|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done
case "$METHOD" in auto|conda|binary|source) ;; *) die "--method 仅支持 auto|conda|binary|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# 官方预编译二进制仅 linux-x86_64（静态 libcppstatic 包）
platform_ok_binary() { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }

# ---------------- 版本断言（clustalw -help 含 "CLUSTAL 2.1"） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -help 2>&1 || true)"
    printf '  %s\n' "$(grep -m1 -i 'CLUSTAL' <<<"$out" || echo "$out" | head -n1)"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

download() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$out" "$url"
    else
        die "需要 curl 或 wget 下载"
    fi
}

check_sha256() {
    local file="$1" sha="$2"
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$sha  $file" | sha256sum -c - >/dev/null 2>&1 || die "sha256 校验失败：下载文件不完整或被篡改"
    else
        echo "$sha  $file" | shasum -a 256 -c - >/dev/null 2>&1 || die "sha256 校验失败：下载文件不完整或被篡改"
    fi
    log "sha256 校验通过"
}

write_path() {
    local bindir="$1" line="export PATH=\"$1:\$PATH\""
    if [[ "$UPDATE_PATH" == 1 ]]; then
        if [[ -f "$PROFILE" ]] && grep -qF "$bindir" "$PROFILE"; then
            log "PATH 已包含 $bindir，跳过写入 $PROFILE"
        else
            { echo ""; echo "# clustalw (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 clustalw 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$bindir:\$PATH\""
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 clustalw=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "clustalw=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "clustalw=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV clustalw -help"
    "$CONDA_BIN" run -n "$CONDA_ENV" clustalw -help 2>&1 | grep -m1 -i "CLUSTAL" | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 clustalw"
}

# ---------------- 路线 B：官方预编译静态二进制（仅 linux-x64） ----------------
install_binary() {
    local url tmp="" srcdir
    url="https://ftp.ebi.ac.uk/pub/software/clustalw2/${VERSION}/clustalw-${VERSION}-linux-x86_64-libcppstatic.tar.gz"

    log "下载官方预编译静态二进制: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    download "$url" "$tmp/clustalw.tar.gz"
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        check_sha256 "$tmp/clustalw.tar.gz" "$SHA256_BINARY_LINUX_X86_64"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi
    tar xzf "$tmp/clustalw.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'clustalw-*' | head -1)"
    [[ -n "$srcdir" ]] || die "解压后未找到 clustalw-* 目录"
    [[ -x "$srcdir/clustalw2" ]] || die "预编译包内未找到可执行文件 clustalw2"
    install -m 0755 "$srcdir/clustalw2" "$PREFIX/bin/clustalw2"
    ln -sf "$PREFIX/bin/clustalw2" "$PREFIX/bin/clustalw"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/clustalw"
    write_path "$PREFIX/bin"
}

# ---------------- 路线 C：官方源码编译 ----------------
install_source() {
    local url tmp="" srcdir
    url="https://ftp.ebi.ac.uk/pub/software/clustalw2/${VERSION}/clustalw-${VERSION}.tar.gz"

    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"
    command -v make >/dev/null 2>&1 || die "源码编译需要 make 与 C++ 编译器（当前 PATH 中未找到 make）"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    download "$url" "$tmp/clustalw-src.tar.gz"
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        check_sha256 "$tmp/clustalw-src.tar.gz" "$SHA256_SOURCE"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi
    tar xzf "$tmp/clustalw-src.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'clustalw-*' | head -1)"
    [[ -n "$srcdir" ]] || die "解压后未找到 clustalw-* 源码目录"

    # 官方源码 configure 位于 src/ 子目录（见 14.md §4 安装ClustalW）
    local build_dir="$srcdir"
    [[ -x "$srcdir/src/configure" ]] && build_dir="$srcdir/src"
    log "编译安装中：cd $build_dir && ./configure --prefix=$PREFIX && make && make install"
    ( cd "$build_dir" && ./configure --prefix="$PREFIX" >/dev/null && make >/dev/null && make install >/dev/null )
    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -x "$PREFIX/bin/clustalw" ]] || [[ -x "$PREFIX/bin/clustalw2" ]] || die "编译后未在 $PREFIX/bin 找到 clustalw/clustalw2"
    [[ -x "$PREFIX/bin/clustalw" ]] || ln -sf "$PREFIX/bin/clustalw2" "$PREFIX/bin/clustalw"
    assert_version "$PREFIX/bin/clustalw"
    write_path "$PREFIX/bin"
}

# ---------------- 主流程 ----------------
log "clustalw $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译二进制（仅 linux-x86_64）；请改用 conda / brew / --method source"
        install_binary ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            install_source
        fi ;;
esac
log "安装成功"
