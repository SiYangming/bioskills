#!/usr/bin/env bash
# =============================================================================
# install.sh — HTSeq / htseq-count 宿主机本地安装脚本
#
# 归属    ：bioskills modules/htseq/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::htseq
#   - pip   路线（无 conda 兜底）：官方 PyPI 发行（HTSeq，含 manylinux/macos wheel），
#     安装到 --prefix 下的独立 venv（用户级前缀，免 root、不写 /opt/biosoft）
#   - 版本默认 2.1.2，与 modules/htseq/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://htseq.readthedocs.io/
#   PyPI     : https://pypi.org/project/HTSeq/
#   bioconda : https://anaconda.org/bioconda/htseq
#   (容器：quay.io/biocontainers/htseq:2.1.2--py311h0e292b2_3 / depot.galaxyproject.org)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则 pip
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: htseq）
#   bash install.sh --method pip                      # 强制 pip（独立 venv）
#   bash install.sh --conda-env ht --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/htseq              # pip 模式自定义前缀
#   bash install.sh --version 2.0.3                   # 覆盖版本
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.1.2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/htseq-$DEFAULT_VERSION}"
CONDA_ENV="htseq"
METHOD="auto"          # auto | conda | pip
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|pip}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|pip) ;; *) die "--method 仅支持 auto|conda|pip（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 htseq=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "htseq=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "htseq=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV htseq-count --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" htseq-count --version 2>&1 | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 htseq-count"
}

# ---------------- 路线 B：官方 PyPI 发行（独立 venv） ----------------
install_pip() {
    local py pip_bin
    if command -v python3 >/dev/null 2>&1; then py="$(command -v python3)"; else die "需要 python3"; fi

    if [[ -d "$PREFIX" && "$FORCE" != 1 && -x "$PREFIX/bin/htseq-count" ]]; then
        die "前缀 $PREFIX 已存在（含 htseq-count）；加 --force 重建，或改用 --prefix 指定其它路径"
    fi
    [[ "$FORCE" == 1 ]] && rm -rf "$PREFIX"

    log "创建 venv: $PREFIX（官方 PyPI HTSeq==$VERSION）"
    "$py" -m venv "$PREFIX"
    pip_bin="$PREFIX/bin/pip"
    "$pip_bin" install --upgrade pip >/dev/null
    "$pip_bin" install "HTSeq==$VERSION"

    log "验证：$PREFIX/bin/htseq-count --version"
    "$PREFIX/bin/htseq-count" --version 2>&1 | sed 's/^/  /'

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        local profile="${HOME}/.bashrc"
        if [[ -f "$profile" ]] && grep -qF "$PREFIX/bin" "$profile"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $profile"
        else
            { echo ""; echo "# htseq (bioskills install.sh)"; echo "$line"; } >> "$profile"
            log "已追加 PATH 到 $profile"
        fi
        log "完成：重新登录或 source $profile 后执行 htseq-count 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "htseq $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    pip)
        install_pip ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_pip
        fi ;;
esac
log "安装成功"
