#!/usr/bin/env bash
# =============================================================================
# install.sh — QIIME 1.9.1 宿主机本地安装脚本（⚠️ deprecated / 历史参考）
#
# 归属    ：bioskills modules/qiime1/native/install.sh（native 实现安装方式）
# 状态    ：QIIME 1.9.1 已淘汰（2018 停止维护、Python 2.7 EOL）——本脚本仅供历史复现。
# 路线    ：QIIME 1 无现代预编译二进制；宿主机安装两条历史路线：
#   - conda（默认优先）：mamba/conda 建独立环境，pin bioconda::qiime=1.9.1
#   - pip2.7（历史路线）：Python 2.7 下 `pip2.7 install qiime`（需自备 Py2.7，本脚本不代装）
#   - qiime-deploy（历史官方部署工具）：见 README「环境安装」，本脚本不自动执行
#   - 版本默认 1.9.1，与 modules/qiime1/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://qiime.org/（历史官网）
#   bioconda : https://anaconda.org/bioconda/qiime（qiime=1.9.1）
#   (历史容器：quay.io/biocontainers/qiime:1.9.1--py27_0 / depot.galaxyproject.org sif，见 README)
#
# 用法示例：
#   bash install.sh                         # 有 conda/mamba -> 建 bioconda 环境 qiime1-native
#   bash install.sh --conda-env qiime1      # 指定环境名
#   bash install.sh --force                 # 环境已存在时删除重建
#   bash install.sh --method pip2.7         # 走历史 pip2.7 路线（需自备 Python 2.7）
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="1.9.1"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="qiime1-native"
METHOD="auto"           # auto | conda | pip2.7
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)    VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --conda-env)  CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --method)     METHOD="${2:?--method 需要 auto|conda|pip2.7}"; shift 2 ;;
        --force)      FORCE=1; shift ;;
        --help|-h)    usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done
case "$METHOD" in auto|conda|pip2.7) ;; *) die "--method 仅支持 auto|conda|pip2.7（收到: ${METHOD}）" ;; esac

warn "QIIME 1.9.1 已淘汰（2018 停止维护、Python 2.7 EOL）；本安装仅供历史复现，新项目请用 qiime2。"

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

assert_version() {
    local out
    out="$("$1" run -n "$CONDA_ENV" python -c "import qiime; print(qiime.__version__)" 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    log "使用 $CONDA_BIN 安装 qiime=$VERSION 到环境: $CONDA_ENV"
    if "$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}' | grep -q .; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV" || true
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "qiime=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "qiime=$VERSION"
    fi
    assert_version "$CONDA_BIN"
    log "完成：conda activate $CONDA_ENV 后即可使用（print_qiime_config.py -tf 自检）"
}

install_pip27() {
    local py=""
    for c in python2.7 py2.7 python2; do
        if command -v "$c" >/dev/null 2>&1; then py="$c"; break; fi
    done
    [[ -n "$py" ]] || die "--method pip2.7 需要 Python 2.7（PATH 中未找到 python2.7）；请参考 01.md 先装 Py2.7"
    log "使用历史路线：$py -m pip install qiime==$VERSION"
    "$py" -m pip install "qiime==$VERSION"
    "$py" -c "import qiime; print('qiime', qiime.__version__)"
    log "完成（注意：Py2.7 环境需自行维护；不写 PATH）"
}

log "QIIME 1 $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    conda)  install_conda ;;
    pip2.7) install_pip27 ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then install_conda
        else warn "未检测到 mamba/conda，回退历史 pip2.7 路线"; install_pip27
        fi ;;
esac
log "安装成功（⚠️ 仅供历史复现）"
