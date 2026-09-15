#!/usr/bin/env bash
# =============================================================================
# install.sh — EVidenceModeler (EVM) 宿主机本地安装脚本
#
# 归属    ：bioskills modules/evidencemodeler/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::evidencemodeler
#   - source 路线（无 conda 兜底）：官方 GitHub 源码归档部署到用户前缀
#     （默认 ~/software/EVidenceModeler-1.1.1），无需 root、不写 /opt/biosoft
#   - 版本默认 1.1.1，与 modules/evidencemodeler/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/EVidenceModeler/EVidenceModeler
#   bioconda : https://anaconda.org/bioconda/evidencemodeler
#   (容器：quay.io/biocontainers/evidencemodeler —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方源码
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: evidencemodeler）
#   bash install.sh --method source                   # 强制官方源码归档（无需 conda）
#   bash install.sh --conda-env evm --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/EVidenceModeler    # source 模式自定义前缀
#   bash install.sh --version 2.1.0                   # 覆盖版本（source 模式 URL 模板；跳过内嵌校验提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.1.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/EVidenceModeler-$DEFAULT_VERSION}"
CONDA_ENV="evidencemodeler"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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

OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 evidencemodeler=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "evidencemodeler=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "evidencemodeler=$VERSION"
    fi
    # 版本断言：EVM 无统一 --version（1.1.1 主脚本为 evidence_modeler.pl，2.x 为 EVidenceModeler）
    local hit
    hit="$("$CONDA_BIN" run -n "$CONDA_ENV" bash -lc 'command -v EVidenceModeler || command -v evidence_modeler.pl || command -v partition_EVM_inputs.pl || true')"
    [[ -n "$hit" ]] || die "版本校验失败：conda 环境 $CONDA_ENV 内未找到 EVM 可执行脚本"
    log "版本校验通过（结构化）：$hit"
    log "完成：conda activate $CONDA_ENV 后即可使用（EVM_HOME 由激活脚本设置）"
}

# ---------------- 路线 B：官方 GitHub 源码归档 ----------------
install_source() {
    local url="https://github.com/EVidenceModeler/EVidenceModeler/archive/v${VERSION}.tar.gz"
    log "下载官方源码归档: $url"
    log "安装前缀: $PREFIX"

    if [[ -e "$PREFIX/EvmUtils/evidence_modeler.pl" && "$FORCE" != 1 ]]; then
        die "$PREFIX 已存在 EVM；加 --force 覆盖，或改用 --prefix"
    fi

    local tmp="" srcdir=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/evm.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/evm.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi
    # sha256 未内嵌：GitHub 动态打包 tarball（archive/vX.tar.gz）摘要不稳定，无法稳定校验
    mkdir -p "$tmp/unpack"
    tar -xzf "$tmp/evm.tar.gz" -C "$tmp/unpack"
    srcdir="$(find "$tmp/unpack" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -n "$srcdir" && -f "$srcdir/EvmUtils/evidence_modeler.pl" ]] \
        || die "源码归档内未找到 EvmUtils/evidence_modeler.pl（URL 或版本号有误？）"

    mkdir -p "$PREFIX"
    cp -R "$srcdir"/. "$PREFIX"/
    chmod 0755 "$PREFIX"/EvmUtils/*.pl 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 版本/结构断言：主脚本就位
    if [[ -f "$PREFIX/evidence_modeler.pl" || -f "$PREFIX/EvmUtils/evidence_modeler.pl" ]]; then
        warn "EVM ${VERSION} 主脚本为 perl 脚本（无 --version）；已按登记版本部署，结构化断言通过"
        log "版本校验通过（结构化）：${VERSION}"
    else
        die "版本校验失败：EVM 主脚本未就位"
    fi

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export EVM_HOME=\"$PREFIX\"; export PATH=\"$PREFIX/EvmUtils:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/EvmUtils" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/EvmUtils，跳过写入 $PROFILE"
        else
            { echo ""; echo "# EVidenceModeler (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 EVM_HOME/PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 partition_EVM_inputs.pl 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export EVM_HOME=\"$PREFIX\" PATH=\"$PREFIX/EvmUtils:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "EVidenceModeler ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_source
        fi ;;
esac
log "安装成功"
