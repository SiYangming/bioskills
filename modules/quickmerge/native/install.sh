#!/usr/bin/env bash
# =============================================================================
# install.sh — quickmerge 宿主机本地安装脚本
#
# 归属    ：bioskills modules/quickmerge/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::quickmerge=0.3
#     （官方 conda 包自动包含 MUMmer 依赖）
#   - source 路线（无 conda 兜底）：官方 GitHub 源码 tag v0.3 → bash make_merger.sh
#     到用户级前缀（默认 ~/software/quickmerge-0.3，免 root、不写 /opt）；需自行安装 MUMmer
#   - 版本默认 0.3，与 modules/quickmerge/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/mahulchak/quickmerge
#   bioconda : https://anaconda.org/bioconda/quickmerge
#   release  : https://github.com/mahulchak/quickmerge/archive/refs/tags/v0.3.tar.gz
#   容器     : quay.io/biocontainers/quickmerge:0.3--pl5321h503566f_6（本脚本为宿主机安装）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: quickmerge）
#   bash install.sh --method source                   # 强制官方源码编译（需本机 MUMmer）
#   bash install.sh --prefix ~/opt/quickmerge         # source 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="0.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/quickmerge-$DEFAULT_VERSION}"
CONDA_ENV="quickmerge"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
REPO_URL="https://github.com/mahulchak/quickmerge.git"

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

# quickmerge 无 --version：退化为 -h 可调用 + 非空输出
assert_binary() {
    local bin="$1" out
    [[ -x "$bin" ]] || die "未找到可执行文件: $bin"
    out="$("$bin" -h 2>&1 | head -n 3 || true)"
    [[ -n "$out" ]] || warn "quickmerge 无参数运行无输出（无 --version，以存在性为准）"
    printf '  %s\n' "$out"
    log "可执行文件就绪：$bin"
}

write_path() {
    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# quickmerge (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    else
        log "未改 PATH：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 quickmerge=$VERSION 到环境: $CONDA_ENV（自动含 MUMmer 依赖）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "quickmerge=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "quickmerge=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV quickmerge -h（无 --version）"
    "$CONDA_BIN" run -n "$CONDA_ENV" bash -lc 'command -v quickmerge && command -v nucmer && command -v delta-filter' | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 quickmerge / nucmer / delta-filter"
}

# ---------------- 路线 B：官方源码编译（make_merger.sh） ----------------
install_source() {
    command -v git >/dev/null 2>&1 || die "--method source 需要 git（或改用 --method conda）"
    command -v g++ >/dev/null 2>&1 || die "--method source 需要 g++"
    log "下载官方源码 tag v$VERSION 并执行 make_merger.sh"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    git clone --depth 1 --branch "v${VERSION}" "$REPO_URL" "$tmp/quickmerge" \
        || die "git clone tag v${VERSION} 失败"
    ( cd "$tmp/quickmerge" && bash make_merger.sh ) || die "make_merger.sh 编译失败（见上方报错）"
    [[ -x "$tmp/quickmerge/merger/quickmerge" ]] || die "编译后未找到 merger/quickmerge"
    mkdir -p "$PREFIX/bin"
    install -m 0755 "$tmp/quickmerge/merger/quickmerge" "$PREFIX/bin/quickmerge"
    # 附带的 merge_wrapper.py（官方 wrapper，安装为 quickmerge_wrapper.py）
    [[ -f "$tmp/quickmerge/merge_wrapper.py" ]] && install -m 0755 "$tmp/quickmerge/merge_wrapper.py" "$PREFIX/bin/quickmerge_wrapper.py"
    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_binary "$PREFIX/bin/quickmerge"
    warn "源码路线需自行安装 MUMmer（nucmer / delta-filter）；可直接用 modules/mummer/native/install.sh"
    write_path
}

# ---------------- 主流程 ----------------
log "quickmerge $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source) install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_source
        fi ;;
esac
log "安装成功"
