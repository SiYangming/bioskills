#!/usr/bin/env bash
# =============================================================================
# install.sh — DBG2OLC 宿主机本地安装脚本
#
# 归属    ：bioskills modules/dbg2olc/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::dbg2olc=20200723
#   - binary 路线（无 conda 兜底，官方预编译）：git clone 官方仓库，取仓库内 compiled/
#     预编译二进制（DBG2OLC / SparseAssembler / Sparc / SelectLongestReads / AssemblyStatistics）
#   - source 路线：git clone 官方仓库 + g++ -O3 编译（无预编译或需自编译时）
#   - 版本：上游 GitHub 无 tag/版本号，官方 bioconda/quay pin 为日期式 20200723
#
# 官方来源：
#   homepage : https://github.com/yechengxi/DBG2OLC
#   bioconda : https://anaconda.org/bioconda/dbg2olc
#   容器     : quay.io/biocontainers/dbg2olc:20200723--h077b44d_4（本脚本为宿主机安装，容器用法见 README）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方预编译二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: dbg2olc）
#   bash install.sh --method binary                   # 强制官方仓库内预编译二进制（无需 conda）
#   bash install.sh --method source                   # git clone + g++ 源码编译
#   bash install.sh --conda-env dbg --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/DBG2OLC            # binary/source 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="20200723"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/DBG2OLC}"
CONDA_ENV="dbg2olc"
METHOD="auto"          # auto | conda | binary | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
REPO_URL="https://github.com/yechengxi/DBG2OLC.git"

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
[[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "上游 GitHub 无 tag；--version 覆盖仅影响 conda pin，binary/source 一律 clone 官方仓库最新 master"

# ---------------- 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（DBG2OLC 无 --version：退化为可执行存在 + 非空输出） ----------------
assert_binary() {
    local bin="$1"
    [[ -x "$bin" ]] || die "未找到可执行文件: $bin"
    local out
    out="$("$bin" 2>&1 | head -n 3 || true)"
    [[ -n "$out" ]] || warn "可执行文件 $bin 无参数运行无输出（DBG2OLC 无 --version，请以存在性为准）"
    log "可执行文件就绪：$bin"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 dbg2olc=$VERSION（日期式官方 pin）到环境: $CONDA_ENV"
    local env_exists
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "dbg2olc=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "dbg2olc=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV DBG2OLC（无 --version，仅确认可调用）"
    "$CONDA_BIN" run -n "$CONDA_ENV" bash -lc 'command -v DBG2OLC && command -v SparseAssembler' | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 DBG2OLC / SparseAssembler / Sparc"
}

# ---------------- binary / source 公共：clone 官方仓库 ----------------
clone_repo() {
    local tmp="$1"
    if command -v git >/dev/null 2>&1; then
        git clone --depth 1 "$REPO_URL" "$tmp/DBG2OLC"
    else
        die "需要 git（或改用 --method conda）"
    fi
}

write_path() {
    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# dbg2olc (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    else
        log "未改 PATH：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 路线 B：官方仓库内预编译二进制 ----------------
install_binary() {
    log "安装官方仓库内预编译二进制（compiled/）到前缀: $PREFIX"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    clone_repo "$tmp"
    mkdir -p "$PREFIX/bin"
    local n=0 f
    for f in DBG2OLC SparseAssembler Sparc SelectLongestReads AssemblyStatistics; do
        if [[ -f "$tmp/DBG2OLC/compiled/$f" ]]; then
            install -m 0755 "$tmp/DBG2OLC/compiled/$f" "$PREFIX/bin/$f"; n=$((n + 1))
        fi
    done
    [[ "$n" -gt 0 ]] || die "官方仓库 compiled/ 未找到预编译二进制（改用 --method source）"
    # Sparc consensus 依赖 utility/ 下的 shell/python 脚本
    mkdir -p "$PREFIX/utility"
    cp -f "$tmp/DBG2OLC/utility/"* "$PREFIX/utility/" 2>/dev/null || true
    chmod 755 "$PREFIX/utility/"* 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_binary "$PREFIX/bin/DBG2OLC"
    [[ -x "$PREFIX/bin/SparseAssembler" ]] || die "SparseAssembler 缺失"
    log "已安装：$PREFIX/bin/{DBG2OLC,SparseAssembler,Sparc,...}；utility 脚本在 $PREFIX/utility"
    write_path
}

# ---------------- 路线 C：源码编译（g++ -O3） ----------------
install_source() {
    log "git clone 官方仓库 + g++ -O3 源码编译到前缀: $PREFIX"
    command -v g++ >/dev/null 2>&1 || die "--method source 需要 g++"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    clone_repo "$tmp"
    mkdir -p "$PREFIX/bin"
    ( cd "$tmp/DBG2OLC" \
        && g++ -O3 -o DBG2OLC *.cpp \
        && g++ -O3 -o SparseAssembler DBG2OLC.cpp \
        && g++ -O3 -o Sparc *.cpp ) || die "源码编译失败（见上方 g++ 报错；SParc 可改用 compiled/ 预编译）"
    local f
    for f in DBG2OLC SparseAssembler Sparc; do
        [[ -x "$tmp/DBG2OLC/$f" ]] && install -m 0755 "$tmp/DBG2OLC/$f" "$PREFIX/bin/$f"
    done
    for f in SelectLongestReads AssemblyStatistics; do
        [[ -f "$tmp/DBG2OLC/compiled/$f" ]] && install -m 0755 "$tmp/DBG2OLC/compiled/$f" "$PREFIX/bin/$f"
    done
    mkdir -p "$PREFIX/utility"
    cp -f "$tmp/DBG2OLC/utility/"* "$PREFIX/utility/" 2>/dev/null || true
    chmod 755 "$PREFIX/utility/"* 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_binary "$PREFIX/bin/DBG2OLC"
    log "已安装：$PREFIX/bin/DBG2OLC（源码编译）；utility 脚本在 $PREFIX/utility"
    write_path
}

# ---------------- 主流程 ----------------
log "DBG2OLC 安装开始（本机 ${OS}/${ARCH}；上游无版本号，官方 pin 20200723）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_binary
        fi ;;
esac
log "安装成功"
