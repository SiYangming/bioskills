#!/usr/bin/env bash
# =============================================================================
# install.sh — biom-format（BIOM 特征表工具集）宿主机本地安装脚本
#
# 归属    ：bioskills modules/biom-format/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   biom-format 提供 CLI（命令 biom），无官方预编译二进制；官方镜像由 bioconda 自动构建
#   （quay.io/biocontainers/biom-format）；宿主机安装两条包管理器路线：
#     - conda 路线（默认优先）：建独立 env，pin biom-format=2.1.17（conda-forge 频道）
#     - pip 路线（无 conda 兜底）：建用户级 venv 到 --prefix，pip install biom-format
#   - 版本默认 2.1.17，与 modules/biom-format/meta.yaml software_versions.native 对齐。
#     ⚠️ bioconda 频道 biom-format 仅发布到 2.1.7；2.1.17 取自 conda-forge（quay/depot 镜像为 2.1.17）。
#
# 官方来源：
#  官网     : https://biom-format.org
#   GitHub   : https://github.com/biocore/biom-format
#   conda    : https://anaconda.org/conda-forge/biom-format
#   容器     : quay.io/biocontainers/biom-format（官方镜像，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                       # auto：有 conda 走 conda-forge，否则 pip venv
#   bash install.sh --method conda                        # 强制 conda 路线（建独立 env: biom-format）
#   bash install.sh --method pip --prefix ~/opt/biom      # 强制 pip（用户级 venv）
#   bash install.sh --conda-env biom-format --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --version 2.1.17                      # 覆盖版本
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="2.1.17"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="biom-format"
PREFIX="${PREFIX:-$HOME/software/biom-format-$DEFAULT_VERSION}"
METHOD="auto"          # auto | conda | pip
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)   VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --method)    METHOD="${2:?--method 需要 auto|conda|pip}"; shift 2 ;;
        --conda-env) CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --prefix)    PREFIX="${2:?--prefix 需要路径}"; shift 2 ;;
        --force)     FORCE=1; shift ;;
        --help|-h)   usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|pip) ;; *) die "--method 仅支持 auto|conda|pip（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（安装后运行 biom --version） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1)" || die "版本断言失败：无法运行 $bin --version"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" \
        || warn "版本校验提示：期望 ${VERSION}，实际输出见上（可能为 conda/pip 解析到的版本）"
    log "版本校验通过：biom-format ${VERSION}"
}

# ---------------- 路线 A：conda（conda-forge） ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists env_bin
    log "使用 conda 安装 biom-format=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "biom-format=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "biom-format=$VERSION"
    fi
    env_bin="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/biom"
    [[ -x "$env_bin" ]] || die "环境 biom 不存在: $env_bin"
    assert_version "$env_bin"
    log "完成：conda activate $CONDA_ENV 后运行 python native/main.py convert ..."
}

# ---------------- 路线 B：pip（用户级 venv） ----------------
install_pip() {
    command -v python3 >/dev/null 2>&1 || die "--method pip 但 PATH 中无 python3"
    if [[ -e "$PREFIX" && "$FORCE" == 1 ]]; then
        log "删除已存在前缀（--force）：$PREFIX"
        rm -rf "$PREFIX"
    fi
    [[ -e "$PREFIX" ]] && die "前缀已存在：$PREFIX（加 --force 重建，或改 --prefix）"
    log "创建用户级 venv: $PREFIX"
    python3 -m venv "$PREFIX"
    "$PREFIX/bin/python" -m pip install --quiet --upgrade pip
    log "pip 安装 biom-format==$VERSION"
    "$PREFIX/bin/python" -m pip install --quiet "biom-format==$VERSION"
    assert_version "$PREFIX/bin/biom"
    log "完成：export PATH=\"$PREFIX/bin:\$PATH\" 后运行 biom / python native/main.py ..."
}

# ---------------- 主流程 ----------------
log "biom-format $VERSION 安装开始"
case "$METHOD" in
    conda)
        install_conda ;;
    pip)
        install_pip ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v python3 >/dev/null 2>&1; then
            warn "未检测到 mamba/conda，改走 pip 路线（用户级 venv）"
            install_pip
        else
            die "未检测到 mamba/conda 与 python3；请先安装其一后再运行本脚本"
        fi ;;
esac
log "安装成功"
