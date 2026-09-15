#!/usr/bin/env bash
# =============================================================================
# install.sh — Salmon 宿主机本地安装脚本
#
# 归属    ：bioskills modules/salmon/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::salmon
#   - binary 路线（无 conda 兜底）：官方 GitHub release 预编译二进制（仅 linux-x64；
#     v1.3.0 官方未发布 macOS 预编译资产，macOS 请走 conda），用户级前缀安装到
#     --prefix（默认 ~/software/salmon-<ver>），无需 root、不写 /opt
#   - 版本默认 1.3.0，与 modules/salmon/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://combine-lab.github.io/salmon/
#   bioconda : https://anaconda.org/bioconda/salmon
#   release  : https://github.com/COMBINE-lab/salmon/releases
#   (容器：quay.io/biocontainers/salmon —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: salmon）
#   bash install.sh --method binary                   # 强制官方 release 二进制（无需 conda）
#   bash install.sh --conda-env sm --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/salmon             # binary 模式自定义前缀
#   bash install.sh --version 1.10.3 --sha256 <hex>   # 覆盖版本并显式校验收据（非默认版本需自备 sha256）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.3.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/salmon-$DEFAULT_VERSION}"
CONDA_ENV="salmon"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
USER_SHA256=""

# 官方 release 预编译二进制（仅 linux-x64）内嵌 sha256（2026-09 实测官方 asset）；
# 非默认版本或未提供 --sha256 时会打印实际下载文件摘要供与 release 页核对。
SHA256_LINUX_X86_64="c7218622cc6b7ef10400a8cbdcb244225cece77f11794694b9f49204f5ee8c78"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
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
        --sha256)      USER_SHA256="${2:?--sha256 需要 64 位十六进制}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# binary 模式仅官方 release 覆盖的平台（仅 linux-x64）可用；macOS 无官方预编译资产 → 走 conda
platform_ok_binary() {
    [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]
}

# ---------------- 版本断言（安装后运行 salmon --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 salmon=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "salmon=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "salmon=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV salmon --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" salmon --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 salmon"
}

# ---------------- 路线 B：官方 GitHub release 二进制 ----------------
install_binary() {
    local sha url
    sha="${USER_SHA256:-$SHA256_LINUX_X86_64}"
    url="https://github.com/COMBINE-lab/salmon/releases/download/v${VERSION}/salmon-${VERSION}_linux_x86_64.tar.gz"

    log "下载官方二进制: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/salmon.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/salmon.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/salmon.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/salmon.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}）且未提供 --sha256，跳过校验（请自行核对 GitHub release 摘要）"
    else
        warn "本模块未内嵌 salmon ${VERSION} 官方 sha256（未编造）；实际下载文件摘要如下，请与 release 页核对："
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$tmp/salmon.tar.gz" | sed 's/^/    /'
        else
            shasum -a 256 "$tmp/salmon.tar.gz" | sed 's/^/    /'
        fi
    fi

    tar -xzf "$tmp/salmon.tar.gz" -C "$tmp"
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "release 包结构异常（未找到解压目录）"
    cp -a "$srcdir"/. "$PREFIX"/
    rm -rf "$tmp"; tmp=""; trap - EXIT
    [[ -x "$PREFIX/bin/salmon" ]] || die "release 包内未找到可执行文件 bin/salmon"

    assert_version "$PREFIX/bin/salmon"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# salmon (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 salmon 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "salmon $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 仅在 linux-x64 有官方预编译资产（v${VERSION} 无 macOS 版）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方二进制，无法自动安装"
        fi ;;
esac
log "安装成功"
