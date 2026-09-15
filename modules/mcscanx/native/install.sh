#!/usr/bin/env bash
# =============================================================================
# install.sh — MCScanX 宿主机本地安装脚本
#
# 归属    ：bioskills modules/mcscanx/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::mcscanx=1.0.0
#   - source 路线（无 conda 兜底）：官方 GitHub 源码 zip，make 编译主程序到 --prefix/bin
#   - 版本默认 1.0.0（bioconda 版本号），与 modules/mcscanx/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://chibba.pgml.uga.edu/mcscan2/（2026-09 curl 连接失败，下载页暂不可达）
#   github   : https://github.com/wyp1125/MCScanX
#   bioconda : https://anaconda.org/bioconda/mcscanx
#   (容器：quay.io/biocontainers/mcscanx —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: mcscanx）
#   bash install.sh --method source                   # 强制源码编译（需 g++/make；绘图组件需 JDK）
#   bash install.sh --conda-env mcscanx --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/MCScanX            # 自定义安装前缀（source 模式）
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.0.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/MCScanX-$DEFAULT_VERSION}"
CONDA_ENV="mcscanx"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
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
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 安装后校验 ----------------
assert_mcscanx() {
    local bin="$1"
    [[ -x "$bin" ]] || die "缺少可执行文件: $bin"
    # MCScanX 无 --version，无参运行会打印 usage（退出码非零属正常）
    if "$bin" 2>&1 | grep -qiE "usage|MCScanX|parameter"; then
        log "校验通过：$bin 可执行（usage 正常输出）"
    else
        warn "MCScanX 无参运行未输出 usage（仅提示，可执行文件已就位）"
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 mcscanx=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mcscanx=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mcscanx=$VERSION"
    fi
    "$CONDA_BIN" run -n "$CONDA_ENV" MCScanX >/dev/null 2>&1 || true
    log "完成：conda activate $CONDA_ENV 后即可使用 MCScanX / duplicate_gene_classifier"
}

# ---------------- 路线 B：官方 GitHub 源码编译 ----------------
install_source() {
    local url tmp srcdir
    command -v make >/dev/null 2>&1 || die "--method source 需要 make（及 g++ 工具链；绘图组件需 JDK）"
    url="https://github.com/wyp1125/MCScanX/archive/refs/heads/master.tar.gz"

    log "下载官方源码: $url"
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/mcscanx.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/mcscanx.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    tar -xzf "$tmp/mcscanx.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'MCScanX-*' | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档结构异常：未找到 MCScanX-* 目录"

    (
        cd "$srcdir"
        export PATH=/usr/bin/:$PATH
        make
    )
    [[ -x "$srcdir/MCScanX" ]] || die "编译失败：未生成 MCScanX"

    mkdir -p "$PREFIX/bin" "$PREFIX/downstream_analyses"
    install -m 0755 "$srcdir/MCScanX" "$PREFIX/bin/MCScanX"
    [[ -x "$srcdir/duplicate_gene_classifier" ]] && \
        install -m 0755 "$srcdir/duplicate_gene_classifier" "$PREFIX/bin/duplicate_gene_classifier"
    # 绘图组件（Java）随 downstream_analyses 一并保留
    cp -f "$srcdir/downstream_analyses/"* "$PREFIX/downstream_analyses/" 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_mcscanx "$PREFIX/bin/MCScanX"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# mcscanx (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 MCScanX 即可（绘图组件在 $PREFIX/downstream_analyses）"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "mcscanx $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v make >/dev/null 2>&1; then
            warn "未检测到 mamba/conda，改走官方源码编译"
            install_source
        else
            die "未检测到 mamba/conda 且无 make 工具链，无法自动安装；请先安装 mamba 或 g++/make"
        fi ;;
esac
log "安装成功"
