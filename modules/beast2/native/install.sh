#!/usr/bin/env bash
# =============================================================================
# install.sh — BEAST2 宿主机本地安装脚本
#
# 归属    ：bioskills modules/beast2/native/install.sh（native 实现安装方式）
# 路线    ：官方镜像优先（bioconda/quay/depot 已覆盖）→ 本脚本只管宿主机安装
#   - binary 路线（默认，Linux x86_64）：官方 GitHub release 预编译包
#       BEAST.v2.5.2.Linux.tgz（可精确到 2.5.2），解压到 --prefix（默认 ~/software/beast2-2.5.2）
#   - conda  路线（备选）：mamba/conda 创建独立环境，pin bioconda::beast2=2.5.0
#       （bioconda 无 beast2=2.5.2；2.5.0 为最接近的 2.5 系列构建）
#   - 版本默认 2.5.2，与 modules/beast2/meta.yaml software_versions.native 对齐
#   - 需要 Java 8/11：官方 Linux 包不自带 JRE；Java ≥20 会因移除 Thread.stop 报错
#
# 官方来源：
#   homepage : https://www.beast2.org/
#   release  : https://github.com/CompEvol/beast2/releases
#   bioconda : https://anaconda.org/bioconda/beast2
#   (容器：quay.io/biocontainers/beast2 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                       # auto：Linux x64 用官方预编译包，否则走 conda
#   bash install.sh --method binary       # 强制官方预编译包（仅 linux-x64）
#   bash install.sh --method conda        # 强制 conda（装 beast2=2.5.0）
#   bash install.sh --prefix ~/opt/beast2 # 自定义安装前缀
#   bash install.sh --no-path-update      # 不写 shell profile
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.5.2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/beast2-$DEFAULT_VERSION}"
CONDA_ENV="beast2"
CONDA_BEAST_VERSION="2.5.0"   # bioconda 无 beast2=2.5.2，最接近的 2.5 系列构建
METHOD="auto"                 # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方预编译 Linux x86_64 包内嵌 sha256（2.5.2）
SHA256_LINUX_X86_64="2feb2281b4f7cf8f7de1a62de50f52a8678ed0767fc72f2322e77dde9b8cd45f"

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

platform_ok_binary() { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }

# ---------------- 版本断言（beast -version 打印 v2.5.2；Java≥20 末尾可能报错，用 || true 兜住） ----------------
assert_version() {
    local bin="$1" want="$2" out
    out="$("$bin" -version 2>&1 || true)"
    printf '  %s\n' "$(grep -m1 -E "v?${want}" <<<"$out" || head -n 1 <<<"$out")"
    grep -qF "$want" <<<"$out" || die "版本校验失败：期望输出含 '${want}'，实际输出见上"
    log "版本校验通过：$want"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    warn "bioconda 无 beast2=${VERSION}（仅 2.4.5/2.5.0/2.6.x/2.7.7），conda 路线将安装 beast2=${CONDA_BEAST_VERSION}"
    log "使用 conda 安装 beast2=${CONDA_BEAST_VERSION} 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "beast2=${CONDA_BEAST_VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "beast2=${CONDA_BEAST_VERSION}"
    fi
    log "验证：conda run -n $CONDA_ENV beast -version"
    "$CONDA_BIN" run -n "$CONDA_ENV" beast -version 2>&1 | grep -m1 -E "v?${CONDA_BEAST_VERSION}" || true
    log "完成：conda activate $CONDA_ENV 后即可使用 beast/beauti/treeannotator 等"
}

# ---------------- 路线 B：官方 GitHub release 预编译包 ----------------
install_binary() {
    local url sha tmp="" srcdir bindir
    url="https://github.com/CompEvol/beast2/releases/download/v${VERSION}/BEAST.v${VERSION}.Linux.tgz"
    sha="$SHA256_LINUX_X86_64"

    # 官方 Linux 包不自带 JRE；需要宿主 Java
    if ! command -v java >/dev/null 2>&1 && [[ -z "${JAVA_HOME:-}" ]]; then
        warn "未检测到 java；BEAST2 运行需 Java 8/11（mamba install -c conda-forge openjdk=11 或系统 JDK）"
    fi

    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/beast.tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/beast.tgz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/beast.tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/beast.tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    tar -xzf "$tmp/beast.tgz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name beast | head -1)"
    [[ -n "$srcdir" && -x "$srcdir/bin/beast" ]] || die "release 包结构异常（未找到 beast/bin/beast）"
    rm -rf "$PREFIX/beast"
    cp -R "$srcdir" "$PREFIX/beast"
    bindir="$PREFIX/beast/bin"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$bindir/beast" "$VERSION"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$bindir:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$bindir" "$PROFILE"; then
            log "PATH 已包含 $bindir，跳过写入 $PROFILE"
        else
            { echo ""; echo "# beast2 (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 beast/beauti/treeannotator 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$bindir:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "beast2 $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方包（仅 Linux x86_64；macOS 请用 conda/brew）"
        install_binary ;;
    auto)
        if platform_ok_binary; then
            install_binary
        elif [[ -n "$CONDA_BIN" ]]; then
            warn "本平台（${OS}/${ARCH}）无官方 2.5.2 预编译包，回落 conda 路线"
            install_conda
        else
            die "本平台（${OS}/${ARCH}）无官方 2.5.2 预编译包且无 conda；请用 brew tap brewsci/bio && brew install beast2"
        fi ;;
esac
log "安装成功"
