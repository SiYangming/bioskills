#!/usr/bin/env bash
# =============================================================================
# install.sh — STAR-Fusion 宿主机本地安装脚本
#
# 归属    ：bioskills modules/star-fusion/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::star-fusion
#   - source 路线（无 conda 兜底）：官方 GitHub 仓库 clone + make，部署到用户前缀
#     （默认 ~/software/star-fusion-<ver>，免 root、不写 /opt/biosoft）
#   - 版本默认 1.15.1，与 modules/star-fusion/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   GitHub   : https://github.com/STAR-Fusion/STAR-Fusion
#   bioconda : https://anaconda.org/bioconda/star-fusion
#   CTAT lib : https://github.com/NCIP/CTAT_genome_lib_build_DIR（资源库下载/构建）
#   (容器：quay.io/biocontainers/star-fusion:1.15.1--hdfd78af_1 / depot.galaxyproject.org)
#
# ⚠️ STAR-Fusion 运行前必须准备 CTAT_resource_lib（--genome_lib_dir），本脚本不下载资源库。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则 GitHub 源码
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: star-fusion）
#   bash install.sh --method source                   # 强制 GitHub 源码 clone + make
#   bash install.sh --conda-env sf --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/star-fusion        # source 模式自定义前缀
#   bash install.sh --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.15.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/star-fusion-$DEFAULT_VERSION}"
CONDA_ENV="star-fusion"
METHOD="auto"          # auto | conda | source
REPO="https://github.com/STAR-Fusion/STAR-Fusion.git"
REF=""                 # source 模式可选：指定分支/标签
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
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --repo)        REPO="${2:?--repo 需要 Git 地址}";      shift 2 ;;
        --ref)         REF="${2:?--ref 需要分支/标签}";        shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 star-fusion=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "star-fusion=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "star-fusion=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV STAR-Fusion --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" STAR-Fusion --version 2>&1 | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 STAR-Fusion（记得准备 CTAT_resource_lib）"
}

# ---------------- 路线 B：官方 GitHub 源码（clone + make） ----------------
install_source() {
    command -v git >/dev/null 2>&1 || die "--method source 需要 git（PATH 中）"
    if [[ -d "$PREFIX/STAR-Fusion" && "$FORCE" != 1 ]]; then
        die "前缀已存在 $PREFIX/STAR-Fusion；加 --force 重建，或改用 --prefix 指定其它路径"
    fi
    [[ "$FORCE" == 1 ]] && rm -rf "$PREFIX"
    mkdir -p "$PREFIX"

    log "clone 官方仓库: $REPO"
    if [[ -n "$REF" ]]; then
        git clone --depth 1 --branch "$REF" "$REPO" "$PREFIX/STAR-Fusion"
    else
        git clone --depth 1 "$REPO" "$PREFIX/STAR-Fusion"
    fi

    log "构建（make）：$PREFIX/STAR-Fusion"
    ( cd "$PREFIX/STAR-Fusion" && make )

    [[ -x "$PREFIX/STAR-Fusion/STAR-Fusion" ]] || die "构建后未找到可执行 STAR-Fusion"
    mkdir -p "$PREFIX/bin"
    ln -sf "$PREFIX/STAR-Fusion/STAR-Fusion" "$PREFIX/bin/STAR-Fusion"

    log "验证：$PREFIX/bin/STAR-Fusion --version"
    "$PREFIX/bin/STAR-Fusion" --version 2>&1 | sed 's/^/  /' || warn "版本输出非零退出（缺 Perl 模块时可用 conda 备齐依赖）"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        local profile="${HOME}/.bashrc"
        if [[ -f "$profile" ]] && grep -qF "$PREFIX/bin" "$profile"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $profile"
        else
            { echo ""; echo "# star-fusion (bioskills install.sh)"; echo "$line"; } >> "$profile"
            log "已追加 PATH 到 $profile"
        fi
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
    log "完成：STAR-Fusion 部署于 $PREFIX（⚠️ 运行前须准备 CTAT_resource_lib）"
}

# ---------------- 主流程 ----------------
log "STAR-Fusion $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then install_conda; else install_source; fi ;;
esac
log "安装成功"
