#!/usr/bin/env bash
# =============================================================================
# install.sh — Bowtie（v1）宿主机本地安装脚本
#
# 归属    ：bioskills modules/bowtie/native/install.sh（native 实现安装方式）
#   （原教程为 sourceforge 二进制 zip 手工部署：
#     wget https://sourceforge.net/projects/bowtie-bio/files/bowtie/1.3.1/bowtie-1.3.1-linux-x86_64.zip
#     unzip ... -d /opt/biosoft + echo 'PATH=...' >> ~/.bashrc；
#     下载链接已迁移到 GitHub release，仅保留「解压即用 + PATH」思路供参考）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::bowtie
#   - binary 路线（无 conda 兜底）：官方 GitHub release zip（linux-x86_64 / linux-aarch64 /
#     macos-x86_64），用户级前缀安装到 --prefix（默认 ~/software/bowtie-<ver>），无需 root、不写 /opt
#   - 版本默认 1.3.1，与 modules/bowtie/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://bowtie-bio.sourceforge.net/index.shtml
#   bioconda : https://anaconda.org/bioconda/bowtie
#   release  : https://github.com/BenLangmead/bowtie/releases（v1.3.1 资产：bowtie-1.3.1-{linux-x86_64,
#              linux-aarch64,macos-x86_64}.zip；zip 解压目录内含 bowtie / bowtie-build / bowtie-inspect）
#   （容器：quay.io/biocontainers/bowtie —— bowtie v1 上游无官方 Dockerfile，由 biocontainer
#     自动构建覆盖；本脚本为宿主机安装，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: bowtie）
#   bash install.sh --method binary                   # 强制官方 release 二进制（无需 conda）
#   bash install.sh --conda-env bt --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/bowtie             # binary 模式自定义前缀
#   bash install.sh --version 1.3.0                   # 覆盖版本（binary 模式 URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.3.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/bowtie-$DEFAULT_VERSION}"
CONDA_ENV="bowtie"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release 资产后缀（已在线核实 v1.3.1 GitHub release 实际资产名）
#   https://github.com/BenLangmead/bowtie/releases/download/v1.3.1/bowtie-1.3.1-linux-x86_64.zip
#   https://github.com/BenLangmead/bowtie/releases/download/v1.3.1/bowtie-1.3.1-linux-aarch64.zip
#   https://github.com/BenLangmead/bowtie/releases/download/v1.3.1/bowtie-1.3.1-macos-x86_64.zip
# 说明：zip 体积较大（linux ≈52MB / macos ≈11MB），未内嵌 sha256；如需校验请对照 GitHub
#   release 页面自行 sha256sum（非默认版本或平台资产名变化时 URL 模板可能失效，脚本会报错提示）。

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
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

# binary 模式：官方 release 覆盖 linux-x86_64 / linux-aarch64 / macos-x86_64
plat_for_binary() {
    case "$OS:$ARCH" in
        Linux:x86_64)  echo "linux-x86_64" ;;
        Linux:aarch64) echo "linux-aarch64" ;;
        Darwin:x86_64) echo "macos-x86_64" ;;
        *) echo "" ;;
    esac
}

# ---------------- 版本断言（安装后运行 bowtie --version 校验，输出形如 "bowtie-align-s version 1.3.1"） ----------------
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
    log "使用 conda 安装 bowtie=$VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 用 mamba 时回退 conda；顺序固定 conda-forge 在前，避免依赖冲突
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "bowtie=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "bowtie=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV bowtie --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" bowtie --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 bowtie"
}

# ---------------- 路线 B：官方 GitHub release 二进制（zip，解压即用） ----------------
install_binary() {
    local plat url tmp srcdir
    plat="$(plat_for_binary)"
    [[ -n "$plat" ]] || die "--method binary 在 ${OS}/${ARCH} 无官方 release 资产（v1.3.1 仅 linux-x86_64 / linux-aarch64 / macos-x86_64）；请改用 conda 路线"
    command -v unzip >/dev/null 2>&1 || die "--method binary 需要 unzip 解压官方 zip（未在 PATH 中找到）"
    url="https://github.com/BenLangmead/bowtie/releases/download/v${VERSION}/bowtie-${VERSION}-${plat}.zip"

    log "下载官方 release: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/bowtie.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/bowtie.zip" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），URL 资产名可能与 release 页不一致；请自行核对 GitHub release 摘要"
    fi
    # zip 较大未内嵌 sha256（见文件头注释）；如需强校验可在下载后对照 release 页 sha256sum

    unzip -q "$tmp/bowtie.zip" -d "$tmp"
    # 解压出顶层目录 bowtie-<ver>-<plat>/，可执行文件在其根下
    srcdir="$(find "$tmp" -maxdepth 2 -mindepth 1 -type d -name "bowtie-*" | head -1)"
    [[ -n "$srcdir" ]] || srcdir="$tmp"
    for exe in bowtie bowtie-build bowtie-inspect; do
        [[ -f "$srcdir/$exe" ]] || die "release 包内未找到可执行文件 $exe（URL 或版本号有误？）"
        install -m 0755 "$srcdir/$exe" "$PREFIX/bin/$exe"
    done
    log "已安装 bowtie / bowtie-build / bowtie-inspect -> $PREFIX/bin"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/bowtie"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# bowtie (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 bowtie 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "bowtie $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif [[ -n "$(plat_for_binary)" ]]; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方二进制，无法自动安装"
        fi ;;
esac
log "安装成功"
