#!/usr/bin/env bash
# =============================================================================
# install.sh — Emperor 宿主机本地安装脚本
#
# 归属    ：bioskills modules/emperor/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   Emperor 为 Python 库（无 CLI 二进制；`python -m emperor` 非有效入口），宿主机安装路线：
#     - pip   路线（默认优先）：python3 -m pip install emperor==<ver>
#     - conda 路线（无 pip 兜底 / 隔离环境）：建独立 env（conda-forge emperor==<ver>）
#   - 版本默认 1.0.5，与 modules/emperor/meta.yaml software_versions.native 对齐
#     （bioconda 仅旧版 0.9.51--py27；conda-forge / PyPI 为现代 1.0.5）
#
# 官方来源：
#   homepage : http://emperor.microbio.me/
#   code     : https://github.com/biocore/emperor
#   conda    : https://anaconda.org/conda-forge/emperor
#   PyPI     : https://pypi.org/project/emperor/
#   (容器：quay.io/biocontainers/emperor —— 官方仅旧版 py27，现代用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 python3+pip 走 pip，否则 conda
#   bash install.sh --method pip                      # 强制 pip
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: emperor）
#   bash install.sh --conda-env emp --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --version 1.0.5                   # 覆盖版本（安装后版本断言对齐）
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="1.0.5"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="emperor"
METHOD="auto"          # auto | pip | conda
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)   VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --method)    METHOD="${2:?--method 需要 auto|pip|conda}"; shift 2 ;;
        --conda-env) CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --force)     FORCE=1; shift ;;
        --help|-h)   usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|pip|conda) ;; *) die "--method 仅支持 auto|pip|conda（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（读取 emperor.__version__） ----------------
assert_version() {
    local py="$1" out
    out="$("$py" -c 'import emperor; print(emperor.__version__)' 2>/dev/null)" \
        || die "版本断言失败：无法 import emperor"
    printf '  emperor %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || warn "版本校验提示：期望 ${VERSION}，实装 ${out}（以实际安装版本为准）"
    log "emperor 可用（python: ${py}）"
}

# ---------------- 路线 pip：PyPI 直装 ----------------
install_pip() {
    local py="$1"
    log "使用 ${py} 从 PyPI 安装 emperor==${VERSION}"
    "$py" -m pip install --upgrade "emperor==${VERSION}"
    assert_version "$py"
    log "完成：python native/main.py plot ... 即可使用（或 from emperor import Emperor）"
}

# ---------------- 路线 conda：独立 env ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists env_py
    log "使用 conda 创建环境 $CONDA_ENV（emperor=$VERSION）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge "emperor=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge "emperor=$VERSION"
    fi
    env_py="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/python"
    [[ -x "$env_py" ]] || die "环境 python 不存在: $env_py"
    assert_version "$env_py"
    log "完成：conda activate $CONDA_ENV 后运行 python native/main.py plot ..."
}

# ---------------- 主流程 ----------------
log "emperor $VERSION 安装开始"
case "$METHOD" in
    pip)
        command -v python3 >/dev/null 2>&1 || die "--method pip 但 PATH 中无 python3"
        install_pip "$(command -v python3)" ;;
    conda)
        install_conda ;;
    auto)
        if command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
            install_pip "$(command -v python3)"
        elif [[ -n "$CONDA_BIN" ]]; then
            warn "未检测到可用 pip，改走 conda 路线"
            install_conda
        else
            die "未检测到 python3+pip 且无 mamba/conda；请先安装 python3（或 mamba），再运行本脚本"
        fi ;;
esac
log "安装成功"
