#!/usr/bin/env bash
# =============================================================================
# install.sh — jcvi 宿主机本地安装脚本
#
# 归属    ：bioskills modules/jcvi/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::jcvi=1.6.7
#   - pip   路线（无 conda 兜底）：pip install jcvi==1.6.7（当前解释器）
#   - 版本默认 1.6.7，与 modules/jcvi/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/tanghaibao/jcvi
#   bioconda : https://anaconda.org/bioconda/jcvi
#   PyPI     : https://pypi.org/project/jcvi/
#   (容器：quay.io/biocontainers/jcvi —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则 pip
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: jcvi）
#   bash install.sh --method pip                      # 强制 pip 安装到当前解释器
#   bash install.sh --conda-env jcvi --force          # 指定环境名 / 已存在时强制重建
#   bash install.sh --python /usr/bin/python3         # pip 模式指定解释器
#   bash install.sh --version 1.6.7                    # 覆盖版本
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.6.7"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="jcvi"
METHOD="auto"          # auto | conda | pip
PYTHON_BIN=""          # pip 模式解释器（默认探测 python3/python）
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|pip}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --python)      PYTHON_BIN="${2:?--python 需要解释器路径}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|pip) ;; *) die "--method 仅支持 auto|conda|pip（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi
if [[ -z "$PYTHON_BIN" ]]; then
    if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    elif command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"; fi
fi

# ---------------- 安装后校验：python -m jcvi -h ----------------
assert_jcvi() {
    local py="$1"
    "$py" -m jcvi -h >/dev/null 2>&1 || die "校验失败：$py -m jcvi -h 未通过"
    local ver
    ver="$("$py" -c 'import jcvi; print(jcvi.__version__)' 2>/dev/null || echo "unknown")"
    log "校验通过：jcvi $ver（解释器 $py）"
    [[ "$ver" == "unknown" || "$ver" == "$VERSION" ]] \
        || warn "实装 jcvi $ver 与目标 $VERSION 不一致（pip 依赖解析可能略漂移）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists env_py
    log "使用 conda 安装 jcvi=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "jcvi=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "jcvi=$VERSION"
    fi
    env_py="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')/bin/python"
    [[ -x "$env_py" ]] || die "环境 python 不存在: $env_py"
    assert_jcvi "$env_py"
    log "完成：conda activate $CONDA_ENV 后运行 python native/main.py ortholog ..."
}

# ---------------- 路线 B：pip ----------------
install_pip() {
    [[ -n "$PYTHON_BIN" ]] || die "--method pip 但未检测到 python3/python（或用 --python 指定）"
    log "使用 pip 安装 jcvi==$VERSION 到 ${PYTHON_BIN}"
    "$PYTHON_BIN" -m pip install "jcvi==$VERSION"
    assert_jcvi "$PYTHON_BIN"
    log "完成：使用 ${PYTHON_BIN} native/main.py ortholog ... 即可"
}

# ---------------- 主流程 ----------------
log "jcvi $VERSION 安装开始"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    pip)
        install_pip ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif [[ -n "$PYTHON_BIN" ]]; then
            warn "未检测到 mamba/conda，改走 pip 路线"
            install_pip
        else
            die "未检测到 mamba/conda 且无 python，无法自动安装"
        fi ;;
esac
log "安装成功"
