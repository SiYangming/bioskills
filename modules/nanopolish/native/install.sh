#!/usr/bin/env bash
# =============================================================================
# install.sh — nanopolish 宿主机本地安装脚本
#
# 归属    ：bioskills modules/nanopolish/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::nanopolish=0.14.0
#   - source 路线（无 conda 兜底）：官方 GitHub 源码 git clone --recursive + make
#     （需 htslib/eigen/hdf5 + g++/make），部署到 --prefix（默认 ~/software/nanopolish-0.14.0）
#   - 版本默认 0.14.0，与 modules/nanopolish/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/jts/nanopolish
#   bioconda : https://anaconda.org/bioconda/nanopolish
#   source   : https://github.com/jts/nanopolish（git clone --recursive; make）
#   (容器：quay.io/biocontainers/nanopolish —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: nanopolish）
#   bash install.sh --method source                   # 强制源码编译（需构建依赖）
#   bash install.sh --conda-env np --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/nanopolish         # source 模式自定义前缀
#   bash install.sh --version 0.13.2                  # 覆盖版本（source 模式 checkout tag）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="0.14.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/nanopolish-$DEFAULT_VERSION}"
CONDA_ENV="nanopolish"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
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

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言 ----------------
assert_version() {
    local out
    out="$("$1" --version 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 nanopolish=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "nanopolish=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "nanopolish=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV nanopolish --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" nanopolish --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 nanopolish"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_source() {
    command -v git >/dev/null 2>&1 || die "source 路线需要 git"
    command -v make >/dev/null 2>&1 || die "source 路线需要 make 与 C++ 编译器"
    warn "源码编译需 htslib / eigen / hdf5 开发库（官方依赖）；缺失时报错请先安装后重试"
    log "编译 nanopolish $VERSION 到前缀: $PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    git clone --recursive --branch "v${VERSION}" --depth 1 \
        https://github.com/jts/nanopolish.git "$tmp/nanopolish" \
        || die "git clone 失败（tag v${VERSION} 是否存在？）"
    make -C "$tmp/nanopolish" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

    mkdir -p "$PREFIX/bin"
    install -m 0755 "$tmp/nanopolish/nanopolish" "$PREFIX/bin/nanopolish"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/nanopolish"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# nanopolish (bioskills install.sh)"; echo "export PATH=\"$PREFIX/bin:\$PATH\""; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 nanopolish 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "nanopolish $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
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
            warn "未检测到 mamba/conda，回退到官方源码编译路线"
            install_source
        fi ;;
esac
log "安装成功"
