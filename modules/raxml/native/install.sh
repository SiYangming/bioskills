#!/usr/bin/env bash
# =============================================================================
# install.sh — RAxML（standard-RAxML）宿主机本地安装脚本
#
# 归属    ：bioskills modules/raxml/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::raxml=8.2.12
#   - binary 路线（无 conda 兜底）：RAxML 官方**仅以源码分发**（无预编译包），
#     故本路线为「官方源码编译」：下载 v8.2.12 源码归档 → make 编译 → 安装到用户前缀
#     （默认 ~/software/raxml-8.2.12），无需 root、不写 /opt
#   - 版本默认 8.2.12，与 modules/raxml/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://cme.h-its.org/exelixis/web/software/raxml/index.html
#   source   : https://github.com/stamatak/standard-RAxML
#   bioconda : https://anaconda.org/bioconda/raxml
#   (容器：quay.io/biocontainers/raxml —— 本脚本为宿主机安装，容器用法见模块 README)
#
# ⚠️ HYBRID（MPI）版本需 MPICH：本脚本默认编译 SSE3.PTHREADS 版（免 MPI）。
#    如需 HYBRID 版，请参见 README「官方源码编译」小节手动配置：
#    export C_INCLUDE_PATH=/usr/include/mpich-x86_64:$C_INCLUDE_PATH
#    export LD_LIBRARY_PATH=/usr/lib64/mpich/lib:$LD_LIBRARY_PATH && make -f Makefile.SSE3.HYBRID.gcc
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: raxml）
#   bash install.sh --method binary                   # 强制官方源码编译（无需 conda）
#   bash install.sh --conda-env raxml --force         # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/raxml              # binary 模式自定义前缀
#   bash install.sh --version 8.2.13                  # 覆盖版本（源码归档 URL 模板）
#   bash install.sh --makefile Makefile.AVX.PTHREADS.gcc
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="8.2.12"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/raxml-$DEFAULT_VERSION}"
CONDA_ENV="raxml"
METHOD="auto"          # auto | conda | binary（binary = 官方源码编译）
MAKEFILE="Makefile.SSE3.PTHREADS.gcc"
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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
        --makefile)    MAKEFILE="${2:?--makefile 需要 Makefile 名}"; shift 2 ;;
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
NPROC="$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 4 )"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# 源码编译需 C 编译器（gcc / clang）
need_cc() {
    command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1
}

# ---------------- 版本断言（raxmlHPC-PTHREADS-SSE3 -v，版本横幅） ----------------
assert_version() {
    local bindir="$1" bin out
    bin="$(find "$bindir" -maxdepth 1 -type f -name 'raxmlHPC-PTHREADS*' | head -1)"
    [[ -n "$bin" ]] || die "未在 $bindir 找到 raxmlHPC-PTHREADS* 可执行文件"
    out="$("$bin" -v 2>&1 || true)"
    printf '  %s\n' "$out" | head -n 3
    grep -q "${VERSION//./\.}" <<<"$out" || die "版本校验失败：输出未含 ${VERSION}（见上）"
    log "版本校验通过：$VERSION（$bin）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 raxml=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "raxml=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "raxml=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV raxmlHPC-PTHREADS-SSE3 -v"
    "$CONDA_BIN" run -n "$CONDA_ENV" bash -lc 'raxmlHPC-PTHREADS-SSE3 -v' 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 raxmlHPC-PTHREADS-SSE3"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_binary() {
    need_cc || die "源码编译需要 C 编译器（gcc / cc / clang）"
    local url tarball
    url="https://github.com/stamatak/standard-RAxML/archive/v${VERSION}.tar.gz"

    log "下载官方源码归档: $url"
    log "编译 Makefile: $MAKEFILE（-j $NPROC）"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    tarball="$tmp/raxml-src.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tarball" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tarball" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    tar zxf "$tarball" -C "$tmp"
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'standard-RAxML-*' | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档解压目录异常（未找到 standard-RAxML-*）"

    ( cd "$srcdir" && make -f "$MAKEFILE" -j "$NPROC" )

    local installed=0
    local bin
    while IFS= read -r bin; do
        [[ -n "$bin" ]] || continue
        install -m 0755 "$bin" "$PREFIX/bin/$(basename "$bin")"
        installed=$((installed + 1))
    done < <(find "$srcdir" -maxdepth 1 -type f -name 'raxmlHPC*' -perm -111)
    [[ "$installed" -ge 1 ]] || die "编译未产出 raxmlHPC* 可执行文件（Makefile/编译器问题？）"
    log "已安装 $installed 个可执行文件到 $PREFIX/bin"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# raxml (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 raxmlHPC-PTHREADS-SSE3 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "raxml $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif need_cc; then
            install_binary
        else
            die "未检测到 mamba/conda 且无 C 编译器，无法自动安装（可装 conda 或 gcc/MPICH 后重试）"
        fi ;;
esac
log "安装成功"
