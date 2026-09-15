#!/usr/bin/env bash
# =============================================================================
# install.sh — MCL 宿主机本地安装脚本
#
# 归属    ：bioskills modules/mcl/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::mcl=14.137
#   - source 路线（无 conda 兜底）：下载官方源码 tarball mcl-14-137.tar.gz，
#     ./configure && make && make install 到用户级 --prefix（默认 ~/software/mcl-14-137），
#     无需 root、不写 /opt
#   - 版本默认 14-137（bioconda 版本号 14.137），与 modules/mcl/meta.yaml
#     software_versions.native 对齐
#
# 官方来源：
#   homepage : https://www.micans.org/mcl/
#   bioconda : https://anaconda.org/bioconda/mcl
#   source   : http://micans.org/mcl/src/mcl-14-137.tar.gz
#   (容器：quay.io/biocontainers/mcl —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 说明：MCL 官方仅分发源码，无预编译二进制；故 binary 方法是 source（源码编译）的别名，
#      保留 --method binary 以对齐参数契约（收到 binary 时打印提示并按 source 处理）。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: mcl）
#   bash install.sh --method source                   # 强制官方源码编译（无需 conda）
#   bash install.sh --conda-env mcl14 --force         # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/mcl                # source 模式自定义前缀
#   bash install.sh --version 22-282                  # 覆盖版本（source 模式 URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="14-137"          # 上游发布号（tarball mcl-14-137.tar.gz）
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/mcl-$DEFAULT_VERSION}"
CONDA_ENV="mcl"
METHOD="auto"          # auto | conda | source（binary = source 别名）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码 tarball（平台无关，Linux / OSX 同一份）内嵌 sha256（取自 bioconda-recipes mcl 14.137 配方）；
# 改 --version 后不匹配 → 自动跳过并提示
SHA256_SOURCE="b5786897a8a8ca119eb355a5630806a4da72ea84243dba85b19a86f14757b497"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|source|binary}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

# binary 是 source 的别名（MCL 官方无预编译二进制）
if [[ "$METHOD" == "binary" ]]; then
    warn "MCL 官方仅分发源码、无预编译二进制；--method binary 按 source（源码编译）处理"
    METHOD="source"
fi
case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source|binary（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# MCL 版本号（bioconda 14.137）与上游发布号（14-137）互转
conda_version() { printf '%s' "${VERSION//-/.}"; }
tarball_version() { printf '%s' "${VERSION//./-}"; }

# ---------------- 版本断言（安装后运行 mcl --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//-/.}|${VERSION}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local cv env_exists
    cv="$(conda_version)"
    log "使用 conda 安装 mcl=$cv 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mcl=$cv"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mcl=$cv"
    fi
    log "验证：conda run -n $CONDA_ENV mcl --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" mcl --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 mcl"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_source() {
    local tv url srcdir tmp=""
    tv="$(tarball_version)"
    url="https://www.micans.org/mcl/src/mcl-${tv}.tar.gz"

    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"
    command -v make >/dev/null 2>&1 || die "源码编译需要 make（当前 PATH 中未找到）"

    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/mcl.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/mcl.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${SHA256_SOURCE:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SOURCE  $tmp/mcl.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_SOURCE  $tmp/mcl.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对上游摘要）"
    fi

    tar -xzf "$tmp/mcl.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'mcl-*' | head -1)"
    [[ -n "$srcdir" ]] || die "解压后未找到 mcl-* 源码目录（URL 或版本号有误？）"

    log "编译安装中：./configure --prefix=$PREFIX && make && make install"
    ( cd "$srcdir" && ./configure --prefix="$PREFIX" >/dev/null && make -j 4 >/dev/null && make install >/dev/null )
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/mcl"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# mcl (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 mcl 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "mcl $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
            install_source
        fi ;;
esac
log "安装成功"
