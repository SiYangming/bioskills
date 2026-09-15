#!/usr/bin/env bash
# =============================================================================
# install.sh — UCSC kent（jksrc）宿主机本地安装脚本
#
# 归属    ：bioskills modules/kent/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先；本软件无整体官方包/镜像 → 自建/官方资产）
#   - 无 kent 整体 conda 包/镜像；官方按工具提供预编译二进制与源码树
#   - binary 路线（默认）：官方预编译二进制
#       https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/<tool>
#     布署到 --prefix/bin（默认 ~/software/kent-<ver>），无需 root、不写 /opt
#   - conda  路线：安装 bioconda 的 ucsc-* 单工具包（ucsc-fatotwobit 等）到独立环境
#   - source 路线：编译官方源码树 jksrc.v330.zip（文档用于 GBrowse 的 jkweb.a）
#   - 版本默认 v330（jksrc v330），与 modules/kent/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://hgdownload.gi.ucsc.edu/admin/
#   source   : http://hgdownload.cse.ucsc.edu/admin/jksrc.archive/jksrc.v330.zip
#   prebuilt : https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda 走 ucsc-* 包，否则官方预编译二进制
#   bash install.sh --method binary                   # 官方预编译二进制到 ~/software/kent-v330
#   bash install.sh --method conda --conda-env kent   # bioconda ucsc-* 单工具包
#   bash install.sh --method source                   # 编译 jksrc v330（较慢）
#   bash install.sh --help
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="v330"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/kent-$DEFAULT_VERSION}"
CONDA_ENV="kent"
METHOD="auto"          # auto | binary | conda | source
FORCE=0

# 代表性工具（与 native/main.py 子命令一致）
TOOLS=(faToTwoBit twoBitToFa twoBitInfo blat bedToBigBed bigWigToBedGraph)
# bioconda 单工具包（conda 路线）
CONDA_PKGS=(ucsc-fatotwobit ucsc-twobittofa ucsc-twobitinfo ucsc-blat ucsc-bedtobigbed ucsc-bigwigtobedgraph)

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本（如 v330）}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";  shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|binary|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) NO_PATH_UPDATE=1; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done
NO_PATH_UPDATE="${NO_PATH_UPDATE:-0}"

case "$METHOD" in auto|binary|conda|source) ;; *) die "--method 仅支持 auto|binary|conda|source（收到: ${METHOD}）" ;; esac

OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi
PROFILE="${HOME}/.bashrc"

# ---------------- 功能断言：FASTA -> 2bit -> FASTA 往返 ----------------
assert_functional() {
    local bindir="$1"
    local tmp; tmp="$(mktemp -d)"
    printf '>chr_test\nACGTACGTACGT\n' > "$tmp/t.fa"
    "$bindir/faToTwoBit" "$tmp/t.fa" "$tmp/t.2bit"
    "$bindir/twoBitToFa" "$tmp/t.2bit" "$tmp/back.fa"
    grep -q 'ACGTACGTACGT' "$tmp/back.fa" || { rm -rf "$tmp"; die "功能校验失败：FASTA↔2bit 往返不一致"; }
    rm -rf "$tmp"
    log "功能校验通过：faToTwoBit/twoBitToFa 往返一致"
}

# ---------------- 路线 A：官方预编译二进制 ----------------
install_binary() {
    [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]] \
        || die "官方预编译二进制仅覆盖 linux-x64；本机 ${OS}/${ARCH} 请改用 --method source（源码编译）"
    log "下载官方预编译二进制到 $PREFIX/bin"
    mkdir -p "$PREFIX/bin"
    local t
    for t in "${TOOLS[@]}"; do
        log "  fetch $t"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$PREFIX/bin/$t" "https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/$t"
        else
            wget -qO "$PREFIX/bin/$t" "https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/$t"
        fi
        chmod 0755 "$PREFIX/bin/$t"
    done
    # 官方预编译二进制随上游更新，无固定 sha256 可内嵌；功能断言代替
    assert_functional "$PREFIX/bin"
    update_path "$PREFIX/bin"
}

# ---------------- 路线 B：bioconda ucsc-* 单工具包 ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 ucsc-* 单工具包到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "${CONDA_PKGS[@]}"
    log "完成：conda activate $CONDA_ENV 后即可使用 ${TOOLS[*]}"
}

# ---------------- 路线 C：源码编译 jksrc ----------------
install_source() {
    log "编译官方源码树 jksrc.$VERSION（较慢）"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    local url="http://hgdownload.cse.ucsc.edu/admin/jksrc.archive/jksrc.$VERSION.zip"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/jksrc.zip" "$url"
    else
        wget -qO "$tmp/jksrc.zip" "$url"
    fi
    local actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual="$(sha256sum "$tmp/jksrc.zip" | awk '{print $1}')"
    else
        actual="$(shasum -a 256 "$tmp/jksrc.zip" | awk '{print $1}')"
    fi
    warn "未内嵌上游 sha256（UCSC 未发布校验和）；下载文件 sha256=$actual，请自行核对"

    ( cd "$tmp" && unzip -q jksrc.zip )
    local srcdir="$tmp/kent"
    [[ -d "$srcdir/src" ]] || die "源码树结构异常：未找到 $srcdir/src"
    mkdir -p "$PREFIX/bin"
    export MACHTYPE="${MACHTYPE:-x86_64}"
    ( cd "$srcdir/src" && make -j"$( (command -v nproc >/dev/null 2>&1 && nproc) || echo 4)" \
        CXXFLAGS=-fPIC CFLAGS=-fPIC CPPFLAGS=-fPIC BINDIR="$PREFIX/bin" ) \
        || warn "make 退出非零（部分工具可能失败），尝试继续收集已构建二进制"
    # kent 默认输出到 $HOME/bin/$MACHTYPE；合并到前缀
    if [[ -d "$HOME/bin/$MACHTYPE" ]]; then
        cp -f "$HOME/bin/$MACHTYPE"/. "$PREFIX/bin"/ 2>/dev/null || true
    fi
    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_functional "$PREFIX/bin"
    update_path "$PREFIX/bin"
}

update_path() {
    local bindir="$1"
    if [[ "$NO_PATH_UPDATE" == 1 ]]; then
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$bindir:\$PATH\""
        return 0
    fi
    local line="export PATH=\"$bindir:\$PATH\""
    if [[ -f "$PROFILE" ]] && grep -qF "$bindir" "$PROFILE"; then
        log "PATH 已包含 $bindir，跳过写入 $PROFILE"
    else
        { echo ""; echo "# kent (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
        log "已追加 PATH 到 $PROFILE"
    fi
}

# ---------------- 主流程 ----------------
log "kent $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    binary) install_binary ;;
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source) install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_binary
        fi ;;
esac
log "安装成功"
