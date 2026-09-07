#!/usr/bin/env bash
# =============================================================================
# install.sh — riboss（RiboSS 0.46）宿主机本地安装脚本
#
# 归属    ：bioskills modules/riboss/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」对齐）
#   RiboSS 是无官方二进制 / 无官方 biocontainer 的重依赖 Python 包（numpy/pandas/scipy/
#   pysam/pyranges/bedtools/bowtie2/star/salmon 等），官方维护渠道即 conda env
#   （上游 environment.yml）+ YangmingSi 频道 riboss 包 + bioinfortools 社区镜像。
#   因此本脚本只有 conda 路线（无官方 release 二进制可下载，source=git 仍需 conda 解依赖）。
#   - 版本默认 0.46，与 modules/riboss/meta.yaml software_versions.native 对齐。
#
# 官方来源：
#   github  : https://github.com/lcscs12345/riboss
#   conda   : https://anaconda.org/channels/YangmingSi/packages/riboss/overview
#   容器    : quay.io/bioinfortools/riboss:0.46（社区；无官方 biocontainer）
#
# 用法示例：
#   bash install.sh                                   # auto：检测 mamba/conda 后建 env: riboss
#   bash install.sh --method conda                    # 同上（显式 conda）
#   bash install.sh --conda-env riboss2 --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --version 0.46                    # 覆盖版本
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="0.46"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="riboss"
METHOD="auto"          # auto | conda
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)   VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --method)    METHOD="${2:?--method 需要 auto|conda}"; shift 2 ;;
        --conda-env) CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --force)     FORCE=1; shift ;;
        --help|-h)   usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda) ;; *) die "--method 仅支持 auto|conda（收到: ${METHOD}）" ;; esac

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（riboss 无 CLI --version；以 python 模块断言为准） ----------------
assert_version() {
    local out
    out="$("$CONDA_BIN" run -n "$CONDA_ENV" python -c \
        'from riboss import __version__; from riboss.orfs import translate; assert translate("ATGGTCTGA")=="MV"; print(__version__)' 2>/dev/null)" \
        || die "riboss 断言失败：translate('ATGGTCTGA')!=MV 或模块不可导入"
    printf '  riboss %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || warn "版本提示：期望 ${VERSION}，实装 ${out}（以模块为准）"
    log "版本断言通过（translate 自检 MV）"
}

# ---------------- conda 路线（唯一路线，重依赖需 conda 解析） ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 riboss=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda -c YangmingSi "riboss=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda -c YangmingSi "riboss=${VERSION}"
    fi
    assert_version
    log "完成：conda activate $CONDA_ENV 后即可运行 python native/main.py <subcommand>"
}

# ---------------- 主流程 ----------------
log "riboss $VERSION 安装开始"
case "$METHOD" in
    conda|auto)
        [[ -n "$CONDA_BIN" ]] || die "需要 mamba/conda（RiboSS 依赖链重且无官方二进制；请先安装 Miniforge：\
https://github.com/conda-forge/miniforge），再运行本脚本"
        install_conda ;;
esac
log "安装成功"
