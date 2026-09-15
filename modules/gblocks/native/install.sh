#!/usr/bin/env bash
# =============================================================================
# install.sh — Gblocks 宿主机本地安装脚本
#
# 归属    ：bioskills modules/gblocks/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::gblocks=0.91b
#   - binary 路线（无 conda 兜底）：官方预编译二进制（Linux64 / OSX，.tar.Z），
#     用户级前缀安装到 --prefix（默认 ~/software/gblocks-0.91b），无需 root、不写 /opt
#   - 版本默认 0.91b，与 modules/gblocks/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://molevol.cmima.csic.es/castresana/Gblocks.html
#   bioconda : https://anaconda.org/bioconda/gblocks
#   binary   : http://molevol.cmima.csic.es/castresana/Gblocks/Gblocks_{Linux64,OSX}_0.91b.tar.Z
#              （.tar.Z = tar + compress，需 ncompress/compress 或 GNU tar -Z / bsdtar）
#   (容器：quay.io/biocontainers/gblocks —— 本脚本为宿主机安装，容器用法见模块 README)
#   注：官方下载页为老式 http 站点，2026-09 从测试环境不可达（curl 连接失败）；
#       上述二进制 URL 与 sha256 依据 brewsci/homebrew-bio 公式核实（2026-09）。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: gblocks）
#   bash install.sh --method binary                   # 强制官方预编译二进制（无需 conda）
#   bash install.sh --conda-env gb --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/gblocks            # binary 模式自定义前缀
#   bash install.sh --version 1.0                     # 覆盖版本（binary 模式跳过内嵌 sha256 校验）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="0.91b"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/gblocks-$DEFAULT_VERSION}"
CONDA_ENV="gblocks"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方预编译二进制（仅 linux-x64 / osx-x64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_LINUX_X86_64="563658f03cc5e76234a8aa705bdc149398defec813d3a0c172b5f94c06c880dc"
SHA256_OSX_X86_64="e5b9e1ae2a227ca0b78ca65741e44f460c7968dea4b01ea45150b1231f391473"

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

# binary 模式仅官方预编译覆盖的平台（linux-x64 / macos-x64）
platform_ok_binary() {
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 版本断言（安装后 echo q | Gblocks 会打印版本并退出） ----------------
assert_version() {
    local bin="$1" out
    out="$(echo q | "$bin" 2>&1 || true)"
    printf '  %s\n' "$out" | head -n 3
    grep -qi "gblocks" <<<"$out" || die "版本校验失败：输出未含 Gblocks 标识（见上）"
    grep -q "${VERSION//./\.}" <<<"$out" || die "版本校验失败：输出未含 ${VERSION}（见上）"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 gblocks=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "gblocks=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "gblocks=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV Gblocks --help"
    "$CONDA_BIN" run -n "$CONDA_ENV" bash -lc 'echo q | Gblocks --help' | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 Gblocks"
}

# ---------------- 路线 B：官方预编译二进制（.tar.Z） ----------------
install_binary() {
    local plat url sha
    case "$OS" in
        Linux)  plat="Linux64"; sha="$SHA256_LINUX_X86_64" ;;
        Darwin) plat="OSX";     sha="$SHA256_OSX_X86_64" ;;
    esac
    url="http://molevol.cmima.csic.es/castresana/Gblocks/Gblocks_${plat}_${VERSION}.tar.Z"

    log "下载官方预编译二进制: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp="" archive=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    archive="$tmp/gblocks.tar.Z"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$archive" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$archive" "$url"
    else
        die "需要 curl 或 wget 下载官方二进制"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $archive" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $archive" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官方摘要）"
    fi

    # .tar.Z（tar + compress）解压：优先 GNU/bsdtar 的 -Z，否则回退 uncompress
    if tar -tZf "$archive" >/dev/null 2>&1; then
        tar -xZf "$archive" -C "$tmp"
    elif command -v uncompress >/dev/null 2>&1; then
        uncompress -c "$archive" > "$tmp/gblocks.tar"
        tar -xf "$tmp/gblocks.tar" -C "$tmp"
    else
        die "解压 .tar.Z 需要 compress/uncompress（Linux 可装 ncompress）或支持 -Z 的 tar；或改用 --method conda"
    fi

    local bin_src
    bin_src="$(find "$tmp" -maxdepth 2 -type f -name Gblocks -perm -111 | head -1)"
    [[ -n "$bin_src" ]] || bin_src="$(find "$tmp" -maxdepth 2 -type f -name Gblocks | head -1)"
    [[ -n "$bin_src" ]] || die "压缩包内未找到可执行文件 Gblocks（URL 或版本号有误？）"
    install -m 0755 "$bin_src" "$PREFIX/bin/Gblocks"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/Gblocks"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# gblocks (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 Gblocks 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "gblocks $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译二进制（仅 linux-x64 / macos-x64）；请改用 conda 路线"
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
