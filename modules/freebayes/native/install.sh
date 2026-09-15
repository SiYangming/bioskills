#!/usr/bin/env bash
# =============================================================================
# install.sh — freebayes 宿主机本地安装脚本
#
# 归属    ：bioskills modules/freebayes/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::freebayes
#   - binary 路线（无 conda 兜底）：官方 GitHub release 预编译静态二进制
#     freebayes-1.3.10-linux-amd64-static.gz（仅 linux-amd64），部署到用户级前缀
#     --prefix（默认 ~/software/freebayes-<ver>），无需 root、不写 /opt
#   - 版本默认 1.3.10，与 modules/freebayes/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   GitHub   : https://github.com/freebayes/freebayes
#   release  : https://github.com/freebayes/freebayes/releases/download/v1.3.10/
#   bioconda : https://anaconda.org/bioconda/freebayes
#   (容器：quay.io/biocontainers/freebayes —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 说明：官方静态二进制仅 linux-amd64；freebayes-parallel 及其配套脚本（vcffirstheader /
#      vcfstreamsort / vcfuniq / fasta_generate_regions.py）不在静态二进制内，需走 conda
#      或官方源码 release。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方静态二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: freebayes）
#   bash install.sh --method binary                   # 强制官方静态二进制（仅 linux-amd64）
#   bash install.sh --conda-env fb --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/freebayes          # binary 模式自定义前缀
#   bash install.sh --version 1.3.9                   # 覆盖版本（跳过内嵌 sha256 校验）
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.3.10"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/freebayes-$DEFAULT_VERSION}"
CONDA_ENV="freebayes"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release 预编译静态二进制（仅 linux-amd64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_LINUX_X86_64="680b6ff224d057f35e3a0e4f7d357506df3815db9690a43410d50928ea36ab64"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
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

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# 官方静态二进制仅 linux-x64
platform_ok_binary() { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }

# ---------------- 版本断言 ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1)"
    printf '  %s\n' "$out"
    grep -qF "$VERSION" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 freebayes=$VERSION 到环境: $CONDA_ENV"
    if "$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {found=1} END {exit found?0:1}'; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "freebayes=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "freebayes=$VERSION"
    fi
    log "验证：$CONDA_BIN run -n $CONDA_ENV freebayes --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" freebayes --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 freebayes / freebayes-parallel"
}

# ---------------- 路线 B：官方 GitHub release 静态二进制 ----------------
install_binary() {
    local url sha
    sha="$SHA256_LINUX_X86_64"
    url="https://github.com/freebayes/freebayes/releases/download/v${VERSION}/freebayes-${VERSION}-linux-amd64-static.gz"

    log "下载官方静态二进制: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/freebayes.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/freebayes.gz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/freebayes.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/freebayes.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    if command -v gunzip >/dev/null 2>&1; then
        gunzip -c "$tmp/freebayes.gz" > "$tmp/freebayes"
    else
        die "需要 gunzip 解压静态二进制"
    fi
    [[ -s "$tmp/freebayes" ]] || die "解压后二进制为空（URL 或版本号有误？）"
    install -m 0755 "$tmp/freebayes" "$PREFIX/bin/freebayes"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/freebayes"
    warn "静态二进制仅含 freebayes 本体；freebayes-parallel 及配套脚本请走 conda 或官方源码 release"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# freebayes (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 freebayes 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "freebayes $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方静态二进制（仅 linux-x64）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方静态二进制，无法自动安装"
        fi ;;
esac
log "安装成功"
