#!/usr/bin/env bash
# =============================================================================
# install.sh — QIIME 2 宿主机本地安装脚本
#
# 归属    ：bioskills modules/qiime2/native/install.sh（native 实现安装方式）
# 路线    ：QIIME 2 官方只以 **Conda 发行版**（amplicon conda.yml）分发，无预编译二进制、
#           无 apt 包；故本脚本仅 conda 路线（自动下载官方 2026.1 amplicon 环境文件建环境）。
#   - conda（唯一路线）：mamba/conda env create -f <官方 qiime2-amplicon-*-conda.yml>
#     官方发行文件：https://raw.githubusercontent.com/qiime2/distributions/refs/heads/dev/<ver>/amplicon/released/qiime2-amplicon-ubuntu-latest-conda.yml
#   - 版本默认 2026.1，与 modules/qiime2/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://qiime2.org/
#   docs     : https://docs.qiime2.org/
#   quickstart: https://library.qiime2.org/quickstart/amplicon
#   distributions: https://github.com/qiime2/distributions （分支 dev）
#   (官方 Quay 镜像：quay.io/qiime2/amplicon:2026.1 —— 容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                              # 建官方 2026.1 amplicon 环境（默认名 qiime2-amplicon-2026.1）
#   bash install.sh --conda-env qiime2           # 指定环境名
#   bash install.sh --version 2025.10            # 覆盖版本（环境名自动跟随，仅当未显式 --conda-env）
#   bash install.sh --force                       # 环境已存在时删除重建
#   bash install.sh --no-path-update              # 不改 shell profile
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2026.1"
VERSION="$DEFAULT_VERSION"
CONDA_ENV=""            # 空 -> 解析后默认 qiime2-amplicon-${VERSION}
FORCE=0
UPDATE_PATH=1
PROFILE="${HOME}/.bashrc"

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
        --version)        VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --conda-env)      CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --method)         METHOD="${2:?--method 需要 conda}"; shift 2 ;;
        --profile)        PROFILE="${2:?--profile 需要路径}"; shift 2 ;;
        --force)          FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)        usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

if [[ -n "${METHOD:-}" && "$METHOD" != "conda" ]]; then
    die "QIIME 2 官方仅 Conda 发行版（无预编译二进制/apt 包），--method 仅支持 conda（收到: ${METHOD}）"
fi
[[ -n "$CONDA_ENV" ]] || CONDA_ENV="qiime2-amplicon-${VERSION}"

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi
[[ -n "$CONDA_BIN" ]] || die "未检测到 mamba/conda（PATH 中）；QIIME 2 官方仅 Conda 发行版，请先装 Miniconda/Mambaforge 后重试"

ENV_YML_URL="https://raw.githubusercontent.com/qiime2/distributions/refs/heads/dev/${VERSION}/amplicon/released/qiime2-amplicon-ubuntu-latest-conda.yml"

# ---------------- 安装 ----------------
log "QIIME 2 ${VERSION} 安装开始（本机 $(uname -s)/$(uname -m)）"
log "使用 $CONDA_BIN 创建环境: $CONDA_ENV"
log "官方发行文件: $ENV_YML_URL"

env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
if [[ -n "$env_exists" ]]; then
    if [[ "$FORCE" == 1 ]]; then
        log "环境 $CONDA_ENV 已存在（--force），删除重建"
        "$CONDA_BIN" env remove -y -n "$CONDA_ENV" || true
    else
        die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
    fi
fi

tmp=""
tmp="$(mktemp -d)"
cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
trap cleanup_tmp EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$tmp/qiime2-env.yml" "$ENV_YML_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp/qiime2-env.yml" "$ENV_YML_URL"
else
    die "需要 curl 或 wget 下载官方发行文件"
fi
[[ -s "$tmp/qiime2-env.yml" ]] || die "官方发行文件下载失败或为空：$ENV_YML_URL"

if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
    mamba env create -y -n "$CONDA_ENV" -f "$tmp/qiime2-env.yml"
else
    conda env create -y -n "$CONDA_ENV" -f "$tmp/qiime2-env.yml"
fi
rm -rf "$tmp"; tmp=""; trap - EXIT

# ---------------- 版本断言 ----------------
log "验证：$CONDA_BIN run -n $CONDA_ENV qiime --version"
out="$("$CONDA_BIN" run -n "$CONDA_ENV" qiime --version 2>&1 || true)"
printf '  %s\n' "$out" | head -n 3
grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"

if [[ "$UPDATE_PATH" == 1 ]]; then
    if [[ -f "$PROFILE" ]] && grep -qF "conda activate $CONDA_ENV" "$PROFILE"; then
        log "PATH 已包含 conda activate $CONDA_ENV，跳过写入 $PROFILE"
    else
        { echo ""; echo "# qiime2 (bioskills install.sh)"; echo "conda activate $CONDA_ENV"; } >> "$PROFILE"
        log "已追加 'conda activate $CONDA_ENV' 到 $PROFILE（需自行 source，或重新登录）"
    fi
fi

log "安装成功：conda activate $CONDA_ENV 后即可使用 qiime（qiime info 自检）"
