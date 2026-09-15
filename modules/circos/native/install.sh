#!/usr/bin/env bash
# =============================================================================
# install.sh — Circos 宿主机本地安装脚本
#
# 归属    ：bioskills modules/circos/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::circos
#   - binary 路线（无 conda 兜底）：官方 Perl tarball（circos-0.69-6.tgz）
#     解压到 --prefix（默认 ~/software/circos-<ver>），无需 root、不写 /opt
#   - 版本默认 0.69.6，与 modules/circos/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://circos.ca/
#   download : http://circos.ca/distribution/circos-0.69-6.tgz
#   bioconda : https://anaconda.org/bioconda/circos
#   (容器：quay.io/biocontainers/circos —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 tarball
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: circos）
#   bash install.sh --method binary                   # 强制官方 tarball（无需 conda）
#   bash install.sh --conda-env cs --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/circos             # binary 模式自定义前缀
#   bash install.sh --version 0.69-6                  # 覆盖版本（tarball 版本号形如 0.69-6）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="0.69.6"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/circos-$DEFAULT_VERSION}"
CONDA_ENV="circos"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 tarball（circos-0.69-6.tgz，平台无关 Perl 源码）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_TARBALL="52d29bfd294992199f738a8d546a49754b0125319a1685a28daca71348291566"

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

# ---------------- 版本号格式：conda 用 0.69.6，tarball 用 0.69-6 ----------------
TARBALL_VERSION="${VERSION%.*}-${VERSION##*.}"

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# circos 为平台无关 Perl 脚本，任意平台有 perl 即可
platform_ok_binary() { command -v perl >/dev/null 2>&1; }

# ---------------- 版本断言（安装后运行 circos -v 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -v 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE '0\.69' <<<"$out" || die "版本校验失败：期望包含 0.69，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 circos=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "circos=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "circos=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV circos -v"
    "$CONDA_BIN" run -n "$CONDA_ENV" circos -v | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 circos"
}

# ---------------- 路线 B：官方 Perl tarball ----------------
install_binary() {
    local url tgz sha
    url="http://circos.ca/distribution/circos-${TARBALL_VERSION}.tgz"
    sha="$SHA256_TARBALL"

    log "下载官方 tarball: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/circos.tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/circos.tgz" "$url"
    else
        die "需要 curl 或 wget 下载 tarball"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && "$sha" != *"PLACEHOLDER"* ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/circos.tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/circos.tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官方 tarball 摘要）"
    fi

    tar -xzf "$tmp/circos.tgz" -C "$tmp"
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'circos-*' | head -1)"
    [[ -n "$srcdir" ]] || die "tarball 内未找到 circos-* 目录（URL 或版本号有误？）"
    rm -rf "$PREFIX"; mkdir -p "$PREFIX"
    cp -R "$srcdir"/. "$PREFIX"/
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/circos"
    warn "Circos 依赖大量 Perl 模块，请执行 '$PREFIX/bin/circos -modules' 检查并按缺失项 cpan 补装"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# circos (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 circos 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "circos $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 需要 perl（本机 ${OS}/${ARCH} 未检测到）"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本机无 perl，无法自动安装"
        fi ;;
esac
log "安装成功"
