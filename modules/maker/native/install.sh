#!/usr/bin/env bash
# =============================================================================
# install.sh — MAKER 宿主机本地安装脚本
#
# 归属    ：bioskills modules/maker/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方镜像优先，宿主机走 conda）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::maker
#     （自动带入 AUGUSTUS/SNAP/RepeatMasker 等大部分依赖）
#   - binary 路线：不支持 —— MAKER 上游不提供预编译二进制，官方源码发行包需在官网注册后
#     获取（旧分发主机 yandell.topaz.genetics.utah.edu / weatherby.genetics.utah.edu 当前均不可达，
#     2026-09 核实）；无公开可下载的官方资产，故 --method binary 直接报错并指引 conda / 官网注册。
#   - 版本默认 3.01.03，与 modules/maker/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://yandell-lab.org/software/maker/
#   下载      : http://yandell.topaz.genetics.utah.edu/cgi-bin/maker_license.cgi（需注册）
#   GitHub   : https://github.com/Yandell-Lab/maker
#   bioconda : https://anaconda.org/bioconda/maker
#   （容器：quay.io/biocontainers/maker —— 本脚本为宿主机安装，容器用法见模块 README）
#
# 依赖说明：MAKER 为 Perl 驱动（perl Build.PL && ./Build install），运行依赖
#   AUGUSTUS / SNAP / GeneMark-ES/ET / RepeatMasker / RepeatModeler / tRNAscan-SE /
#   exonerate / MPI；conda 安装会自动处理大部分依赖，GeneMark 需另配密钥。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: maker）
#   bash install.sh --conda-env maker-gp --force      # 指定环境名 / 已存在时强制重建
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="3.01.03"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="maker"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      shift 2 ;;   # 兼容接口：conda 路线不使用 prefix
        --method)      METHOD="${2:?--method 需要 auto|conda|binary}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 maker=$VERSION 到环境: $CONDA_ENV（自动带入 AUGUSTUS/SNAP/RepeatMasker 等依赖）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "maker=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "maker=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV maker --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" maker --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 maker / gff3_merge / fasta_merge"
}

# ---------------- 路线 B：官方二进制（MAKER 无）
install_binary() {
    die "MAKER 上游不提供预编译二进制，且官方源码发行包需官网注册获取（旧分发主机已不可达，2026-09 核实）；请改用 --method conda，或按 README「官方源码编译」小节到官网注册后手动获取 maker-${VERSION}.tgz"
}

# ---------------- 主流程 ----------------
log "maker $VERSION 安装开始"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            die "未检测到 mamba/conda；MAKER 无官方预编译二进制，请先安装 conda/mamba 后重试（--method conda）"
        fi ;;
esac
log "安装成功"
