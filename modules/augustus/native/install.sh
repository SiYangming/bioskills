#!/usr/bin/env bash
# =============================================================================
# install.sh — AUGUSTUS 宿主机本地安装脚本
#
# 归属    ：bioskills modules/augustus/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方镜像优先，宿主机走 conda / 官方源码编译）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::augustus=3.4.0
#     （跨平台，含编译好的 bam2hints）
#   - source 路线（无 conda 兜底）：官方源码 augustus-3.4.0.tar.gz（官方仅源码，无预编译二进制），
#     解压到用户前缀（默认 ~/software/augustus-3.4.0）并 make 编译，无需 root、不写 /opt
#   - 版本默认 3.4.0，与 modules/augustus/meta.yaml software_versions.native 对齐
#
# 依赖说明：源码编译需 htslib 1.10 / boost_1_64_0 / bamtools（编译 bam2hints）；
#   sudo 非必需；AUGUSTUS_CONFIG_PATH 指向 config/ 目录。
#
# 官方来源：
#   homepage : https://bioinf.uni-greifswald.de/augustus/
#   source   : https://github.com/Gaius-Augustus/Augustus/releases/download/v3.4.0/augustus-3.4.0.tar.gz
#              （等价官网 http://bioinf.uni-greifswald.de/augustus/binaries/augustus-3.4.0.tar.gz）
#   bioconda : https://anaconda.org/bioconda/augustus
#   （容器：quay.io/biocontainers/augustus —— 本脚本为宿主机安装，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: augustus）
#   bash install.sh --method binary                   # 强制官方源码编译
#   bash install.sh --conda-env augustus --force      # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/augustus --no-build
#   bash install.sh --version 3.4.0
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="3.4.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/augustus-$DEFAULT_VERSION}"
CONDA_ENV="augustus"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
BUILD=1

# 官方源码归档（GitHub release v3.4.0，与官网 binaries/augustus-3.4.0.tar.gz 同源）内嵌 sha256
SHA256_SOURCE="246772737862d16755ab0197bb1d4656cafb31db9b38c2cd991a8e8db6f116c8"

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
        --no-build)    BUILD=0; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 augustus=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "augustus=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "augustus=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV augustus --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" augustus --version 2>&1 | head -n 2 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 augustus 及配套脚本"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_binary() {
    local url tar sha tmp srcdir builddir
    url="https://github.com/Gaius-Augustus/Augustus/releases/download/v${VERSION}/augustus-${VERSION}.tar.gz"
    sha="$SHA256_SOURCE"

    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"

    tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/augustus.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/augustus.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载官方源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/augustus.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/augustus.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官方发布摘要）"
    fi

    tar -xzf "$tmp/augustus.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "augustus-*" | head -1)"
    [[ -n "$srcdir" ]] || die "源码包解压目录异常（URL 或版本号有误？）"
    mkdir -p "$(dirname "$PREFIX")"
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀已存在（--force），删除重建: $PREFIX"
            rm -rf "$PREFIX"
        else
            die "前缀已存在: $PREFIX（加 --force 覆盖重建，或改用 --prefix）"
        fi
    fi
    cp -a "$srcdir" "$PREFIX"

    if [[ "$BUILD" == 1 ]]; then
        warn "编译需 htslib 1.10 / boost_1_64_0 / bamtools（bam2hints）；构建失败可加 --no-build 仅解压源码后手动编译"
        log "开始编译（make -j 4）..."
        if ( cd "$PREFIX" && make clean >/dev/null 2>&1 || true ) \
           && ( cd "$PREFIX" && make -j 4 ); then
            log "编译完成"
        else
            warn "make 编译未成功（可能缺少 htslib/boost/bamtools）；源码已解压到 $PREFIX，可手动编译"
        fi
    else
        log "--no-build：仅解压源码到 $PREFIX"
    fi
    chmod 777 "$PREFIX/config/species" 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    if [[ -x "$PREFIX/bin/augustus" ]]; then
        "$PREFIX/bin/augustus" --version 2>&1 | head -n 1 | sed 's/^/  /' | grep -qE "${VERSION//./\.}" \
            && log "版本校验通过：$VERSION" || warn "augustus --version 未输出 ${VERSION}，请人工确认"
    else
        warn "未找到 $PREFIX/bin/augustus（编译未完成），请完成编译后再用"
    fi

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local binline="export PATH=\"$PREFIX/bin:$PREFIX/scripts:\$PATH\""
        local cfgline="export AUGUSTUS_CONFIG_PATH=\"$PREFIX/config/\""
        if [[ -f "$PROFILE" ]] && grep -qF "AUGUSTUS_CONFIG_PATH=\"$PREFIX/config/\"" "$PROFILE"; then
            log "$PROFILE 已包含 AUGUSTUS_CONFIG_PATH，跳过写入"
        else
            { echo ""; echo "# augustus (bioskills install.sh)"; echo "$binline"; echo "$cfgline"; } >> "$PROFILE"
            log "已追加 PATH / AUGUSTUS_CONFIG_PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 augustus 即可"
    else
        log "完成（未改 profile）：使用时请 export PATH=\"$PREFIX/bin:$PREFIX/scripts:\$PATH\" 与 AUGUSTUS_CONFIG_PATH=\"$PREFIX/config/\""
    fi
}

# ---------------- 主流程 ----------------
log "augustus $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_binary
        fi ;;
esac
log "安装成功"
