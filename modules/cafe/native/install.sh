#!/usr/bin/env bash
# =============================================================================
# install.sh — CAFE v4.2.1 宿主机本地安装脚本
#
# 归属    ：bioskills modules/cafe/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::cafe=4.2.1
#   - source 路线（无 conda 兜底）：官方源码归档 v4.2.1，./configure && make，
#     把 cafe/caferror.py 与 release/cafe 安装到 --prefix/bin（用户级，无需 root）
#   - 版本默认 4.2.1，与 modules/cafe/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/hahnlab/CAFE
#   bioconda : https://anaconda.org/bioconda/cafe
#   source   : https://github.com/hahnlab/CAFE/archive/v4.2.1.tar.gz
#   (容器：quay.io/biocontainers/cafe —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: cafe）
#   bash install.sh --method source                   # 强制源码编译（需 g++/make）
#   bash install.sh --conda-env cafe --force          # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/CAFE-4.2.1         # 自定义安装前缀（source 模式）
#   bash install.sh --version 4.2.1                    # 覆盖版本
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="4.2.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/CAFE-$DEFAULT_VERSION}"
CONDA_ENV="cafe"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码归档 v4.2.1 sha256（GitHub tag 归档可能被上游重新生成，故为软校验；不匹配仅 warn）
SHA256_SRC="c9f0bdb9071105c1d23162f355632cab1a017e5798b95042b86c04bae86ff4aa"

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
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 安装后校验 ----------------
assert_cafe() {
    local bin_cafe="$1" out
    [[ -x "$bin_cafe" ]] || die "缺少可执行文件: $bin_cafe"
    out="$("$bin_cafe" --help 2>&1 || true)"
    if grep -qiE "CAFE|usage" <<<"$out"; then
        log "校验通过：$("$bin_cafe" --version 2>/dev/null || echo "cafe v${VERSION}")"
    else
        warn "cafe --help 输出未命中 CAFE/usage（仅提示，可执行文件已就位）"
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 cafe=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "cafe=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "cafe=$VERSION"
    fi
    log "校验：conda run -n $CONDA_ENV cafe --help"
    "$CONDA_BIN" run -n "$CONDA_ENV" cafe --help >/dev/null 2>&1 \
        && log "cafe 已就位（环境 $CONDA_ENV）" \
        || warn "cafe --help 非零退出（仅提示；请 conda activate $CONDA_ENV 后手工确认）"
    log "完成：conda activate $CONDA_ENV 后即可使用 cafe / caferror.py"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_source() {
    local tarball url tmp srcdir
    command -v make >/dev/null 2>&1 || die "--method source 需要 make（及 g++/autoconf 工具链）"
    url="https://github.com/hahnlab/CAFE/archive/v${VERSION}.tar.gz"

    log "下载官方源码: $url"
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/cafe.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/cafe.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${SHA256_SRC:-}" ]]; then
        tarball="$tmp/cafe.tar.gz"
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SRC  $tarball" | sha256sum -c - >/dev/null 2>&1 \
                && log "sha256 校验通过" \
                || warn "sha256 与内嵌值不一致（GitHub tag 归档可能被上游重新生成，继续安装）"
        else
            echo "$SHA256_SRC  $tarball" | shasum -a 256 -c - >/dev/null 2>&1 \
                && log "sha256 校验通过" \
                || warn "sha256 与内嵌值不一致（GitHub tag 归档可能被上游重新生成，继续安装）"
        fi
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi

    tar -xzf "$tmp/cafe.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'CAFE-*' | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档结构异常：未找到 CAFE-* 目录"

    (
        cd "$srcdir"
        ./configure
        make -j "${CAFE_MAKE_JOBS:-4}"
    )
    [[ -x "$srcdir/release/cafe" ]] || die "编译失败：未生成 release/cafe"

    mkdir -p "$PREFIX/bin"
    install -m 0755 "$srcdir/release/cafe" "$PREFIX/bin/cafe"
    install -m 0755 "$srcdir/cafe/caferror.py" "$PREFIX/bin/caferror.py"
    # 修正 caferror.py 的 python 解释器路径（对齐 14.md 的 perl 替换步骤）
    if command -v perl >/dev/null 2>&1; then
        perl -p -i -e 's#/usr/bin/python#/usr/bin/env python#' "$PREFIX/bin/caferror.py"
    fi
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_cafe "$PREFIX/bin/cafe"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# cafe (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 cafe / caferror.py 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "cafe $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v make >/dev/null 2>&1; then
            warn "未检测到 mamba/conda，改走官方源码编译"
            install_source
        else
            die "未检测到 mamba/conda 且无 make 工具链，无法自动安装；请先安装 mamba 或 g++/make"
        fi ;;
esac
log "安装成功"
