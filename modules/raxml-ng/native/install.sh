#!/usr/bin/env bash
# =============================================================================
# install.sh — RAxML-NG 宿主机本地安装脚本
#
# 归属    ：bioskills modules/raxml-ng/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::raxml-ng=2.0.3
#   - binary 路线（无 conda 兜底）：官方 GitHub release 预编译 zip（自带 raxml-ng 可执行文件），
#     用户级前缀安装到 --prefix（默认 ~/software/raxml-ng-2.0.3），无需 root、不写 /opt
#   - 版本默认 2.0.3，与 modules/raxml-ng/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://cme.h-its.org/exelixis/web/software/raxml/index.html
#   bioconda : https://anaconda.org/bioconda/raxml-ng
#   release  : https://github.com/amkozlov/raxml-ng/releases/tag/2.0.3
#              （raxml-ng_v2.0.3_linux_x86_64.zip / raxml-ng_v2.0.3_macos.zip / ..._source.zip）
#   (容器：quay.io/biocontainers/raxml-ng —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 zip
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: raxml-ng）
#   bash install.sh --method binary                   # 强制官方预编译 zip（无需 conda）
#   bash install.sh --conda-env raxml-ng --force      # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/raxml-ng           # binary 模式自定义前缀
#   bash install.sh --version 2.0.2                   # 覆盖版本（binary 模式跳过内嵌 sha256 校验）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.0.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/raxml-ng-$DEFAULT_VERSION}"
CONDA_ENV="raxml-ng"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方预编译 zip（仅 linux-x64 / macos-x64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_LINUX_X86_64="d660cebe2a083de6c20d9354968803b8fd10be206f625be2393997d0abe98105"
SHA256_OSX_X86_64="6dc678ba0202da10dfeb8a7e4718dec583b68339fdc912391fbe349c69a1c99e"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
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
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 版本断言（安装后 raxml-ng --version，版本横幅含 v. <ver>） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 || true)"
    printf '  %s\n' "$out" | head -n 3
    grep -q "${VERSION//./\.}" <<<"$out" || die "版本校验失败：输出未含 ${VERSION}（见上）"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 raxml-ng=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "raxml-ng=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "raxml-ng=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV raxml-ng --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" bash -lc 'raxml-ng --version' 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 raxml-ng"
}

# ---------------- 路线 B：官方 GitHub release 预编译 zip ----------------
install_binary() {
    local asset url sha
    case "$OS" in
        Linux)  asset="raxml-ng_v${VERSION}_linux_x86_64.zip"; sha="$SHA256_LINUX_X86_64" ;;
        Darwin) asset="raxml-ng_v${VERSION}_macos.zip";        sha="$SHA256_OSX_X86_64" ;;
    esac
    url="https://github.com/amkozlov/raxml-ng/releases/download/${VERSION}/${asset}"

    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/raxml-ng.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/raxml-ng.zip" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/raxml-ng.zip" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/raxml-ng.zip" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    command -v unzip >/dev/null 2>&1 || die "需要 unzip 解压 release 包"
    unzip -q "$tmp/raxml-ng.zip" -d "$tmp"

    local bin_src
    bin_src="$(find "$tmp" -maxdepth 2 -type f -name 'raxml-ng' | head -1)"
    [[ -n "$bin_src" ]] || die "release 包内未找到可执行文件 raxml-ng（URL 或版本号有误？）"
    install -m 0755 "$bin_src" "$PREFIX/bin/raxml-ng"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/raxml-ng"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# raxml-ng (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 raxml-ng 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "raxml-ng $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译包（仅 linux-x64 / macos-x64）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方预编译包，无法自动安装"
        fi ;;
esac
log "安装成功"
