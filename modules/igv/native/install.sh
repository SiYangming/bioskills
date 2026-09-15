#!/usr/bin/env bash
# =============================================================================
# install.sh — IGV 宿主机本地安装脚本
#
# 归属    ：bioskills modules/igv/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方预编译二进制优先 / README「安装方式（本地）」对齐）
#   - conda  路线：mamba/conda 创建独立环境（bioconda 的 igv 2.5.x 仅收录 2.5.2 → conda 路线
#     pin 2.5.2；2.5.3 请走 binary 路线）
#   - binary 路线（默认首选）：官方 Broad 预编译 zip（IGV_Linux_2.5.3.zip / IGV_Mac_2.5.3.zip），
#     用户级前缀（默认 ~/software/igv-<ver>），无需 root、不写 /opt
#   - 版本默认 2.5.3，与 modules/igv/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://software.broadinstitute.org/software/igv/
#   下载页   : https://software.broadinstitute.org/software/igv/download
#   bioconda : https://anaconda.org/bioconda/igv
#   (容器：quay.io/biocontainers/igv —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                        # auto：有 conda/mamba 走 bioconda(2.5.2)，否则官方预编译(2.5.3)
#   bash install.sh --method binary        # 强制官方预编译 zip（2.5.3，推荐）
#   bash install.sh --method conda         # 强制 conda（igv 2.5.2）
#   bash install.sh --prefix ~/opt/igv     # binary 模式自定义前缀
#   bash install.sh --version 2.5.3        # 覆盖版本（非默认版本跳过内嵌 sha256 校验）
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.5.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/igv-$DEFAULT_VERSION}"
CONDA_ENV="igv"
CONDA_VERSION="2.5.2"    # bioconda 的 igv 2.5.x 仅收录 2.5.2（2.5.3 未收录，见 meta software_versions）
METHOD="auto"            # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 Broad 预编译 zip（2.5.3）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_LINUX_X86_64="bc71fa385c87941e32fde4cc4cc786f809fc95b10e5febd3abe1ee6dadef2b55"   # IGV_Linux_2.5.3.zip
SHA256_MACOS="3fc84201f95a06fa1c8adda2110484dfacbcbebaf83b59f4a932669ee8192539"          # IGV_Mac_2.5.3.zip

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
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

platform_ok_binary() {
    { [[ "$OS" == "Linux"  ]] || [[ "$OS" == "Darwin" ]]; }
}

# ---------------- 版本断言（安装后运行 igv.sh 校验，Java GUI 无标准 --version，容错） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 || "$bin" 2>&1 || true)"
    printf '  %s\n' "${out%%$'\n'*}"
    grep -qE "igv|${VERSION//./\.}" <<<"$out" || warn "未能从输出确认版本（期望 ${VERSION}），请人工核对"
    log "版本检查完成（期望 ${VERSION}）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 igv=$CONDA_VERSION 到环境: $CONDA_ENV"
    [[ "$CONDA_VERSION" == "$VERSION" ]] || \
        warn "bioconda 的 igv 2.5.x 仅收录 2.5.2（无 ${VERSION}），conda 路线 pin ${CONDA_VERSION}；如需 ${VERSION} 请走 --method binary"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "igv=$CONDA_VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "igv=$CONDA_VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV igv.sh --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" igv.sh --version 2>&1 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 igv.sh"
}

# ---------------- 路线 B：官方 Broad 预编译 zip ----------------
install_binary() {
    local plat url sha tmp srcdir
    case "$OS" in
        Linux)  plat="Linux"; sha="$SHA256_LINUX_X86_64" ;;
        Darwin) plat="Mac";   sha="$SHA256_MACOS" ;;
        *) die "官方预编译包仅覆盖 Linux / macOS（当前 ${OS}）；请改用 conda 或源码编译" ;;
    esac
    url="http://data.broadinstitute.org/igv/projects/downloads/2.5/IGV_${plat}_${VERSION}.zip"

    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --http1.1 -o "$tmp/IGV.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/IGV.zip" "$url"
    else
        die "需要 curl 或 wget 下载预编译包"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "$sha" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/IGV.zip" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/IGV.zip" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 Broad 下载页）"
    fi

    command -v unzip >/dev/null 2>&1 || die "需要 unzip 解压预编译包"
    unzip -q "$tmp/IGV.zip" -d "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'IGV*' | head -1)"
    [[ -n "$srcdir" ]] || die "预编译包内未找到 IGV* 目录（URL 或版本号有误？）"
    cp -a "$srcdir"/. "$PREFIX"/
    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -x "$PREFIX/igv.sh" ]] || die "预编译包内未找到 igv.sh"

    assert_version "$PREFIX/igv.sh"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "PATH 已包含 $PREFIX，跳过写入 $PROFILE"
        else
            { echo ""; echo "# igv (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 igv.sh 即可（需 Java + 显示环境）"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "igv $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS} 无官方预编译包（仅 Linux/macOS）；请改用 conda"
        install_binary ;;
    auto)
        if platform_ok_binary; then
            install_binary
        elif [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            die "未检测到 mamba/conda 且本平台（${OS}）无官方预编译包，无法自动安装"
        fi ;;
esac
log "安装成功"
