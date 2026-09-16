#!/usr/bin/env bash
# =============================================================================
# install.sh — LASTZ 宿主机本地安装脚本
#
# 归属    ：bioskills modules/lastz/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::lastz=<版本>
#   - source 路线（无 conda 兜底）：官方 GitHub 源码 make 编译，用户级前缀安装
#     到 --prefix（默认 ~/software/lastz-1.04.22），无需 root、不写 /opt
#   - 版本默认 1.04.22，与 modules/lastz/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/lastz/lastz
#   文档     : https://lastz.github.io/lastz/
#   bioconda : https://anaconda.org/bioconda/lastz
#   release  : https://github.com/lastz/lastz/archive/refs/tags/1.04.22.tar.gz
#   容器     : quay.io/biocontainers/lastz:1.04.22--h7b50bb2_2（本脚本为宿主机安装）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: lastz）
#   bash install.sh --method source                   # 强制官方源码 make 编译（无需 conda）
#   bash install.sh --prefix ~/opt/lastz              # source 模式自定义前缀
#   bash install.sh --version 1.04.52                 # 覆盖版本（源码 URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.04.22"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/lastz-$DEFAULT_VERSION}"
CONDA_ENV="lastz"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
# 官方 GitHub tag 源码 tar.gz：官方未发布摘要，本仓库未核实 → 留空，安装时跳过校验并提示
# （禁止编造 sha256）。
SHA256_SRC=""

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
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
[[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}）；内嵌 sha256 校验已跳过，请自行核对 release 摘要"

OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

assert_version() {
    local bin="$1" out
    [[ -x "$bin" ]] || die "未找到可执行文件: $bin"
    out="$("$bin" --version 2>&1 | head -n 1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

write_path() {
    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# lastz (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    else
        log "未改 PATH：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 lastz=$VERSION 到环境: $CONDA_ENV"
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
    # 顺序固定 conda-forge 在前，避免依赖冲突
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "lastz=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "lastz=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV lastz --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" lastz --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 lastz"
}

# ---------------- 路线 B：官方源码 make 编译 ----------------
install_source() {
    command -v make >/dev/null 2>&1 || die "--method source 需要 make（及 C 编译器 gcc/clang）"
    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 \
        || die "--method source 需要 C 编译器（gcc/clang）"
    local url="https://github.com/lastz/lastz/archive/refs/tags/${VERSION}.tar.gz"
    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/lastz.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/lastz.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "$SHA256_SRC" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "${SHA256_SRC}  $tmp/lastz.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "${SHA256_SRC}  $tmp/lastz.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "未内嵌 sha256（官方 release 未提供摘要，本仓库未核实）→ 跳过校验；请自行核对 release 摘要"
    fi

    tar -xzf "$tmp/lastz.tar.gz" -C "$tmp"
    local srcdir; srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "源码解压失败"
    # LASTZ 官方构建：make 产出 src/lastz
    ( cd "$srcdir" && make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" ) \
        || die "make 编译失败（见上方报错）"
    [[ -x "$srcdir/src/lastz" ]] || die "未找到编译产物 src/lastz"
    install -m 0755 "$srcdir/src/lastz" "$PREFIX/bin/lastz"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/lastz"
    write_path
}

# ---------------- 主流程 ----------------
log "LASTZ $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
