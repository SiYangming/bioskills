#!/usr/bin/env bash
# =============================================================================
# install.sh — seqkit 宿主机本地安装脚本
#
# 归属    ：bioskills modules/seqkit/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装（官方镜像优先）」）
#   - conda  路线（默认优先，auto）：mamba/conda 创建独立环境，pin bioconda::seqkit
#   - binary 路线（无 conda 兜底）：官方 GitHub release 预编译 tar.gz（Go 单二进制），
#     用户级前缀安装到 --prefix（默认 ~/software/seqkit-<ver>），无需 root、不写 /opt/biosoft
#   - 版本默认 2.13.0，与 modules/seqkit/meta.yaml software_versions.native 对齐
#     （GitHub latest release v2.13.0，2026-02-27；bioconda/homebrew-core/nf-core/
#      snakemake-wrappers 五源均 2.13.0，2026-09-08 核实）
#
# 官方来源：
#   homepage : https://bioinf.shenwei.me/seqkit/
#   bioconda : https://anaconda.org/bioconda/seqkit
#   release  : https://github.com/shenwei356/seqkit/releases
#   (容器：quay.io/biocontainers/seqkit —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: seqkit）
#   bash install.sh --method binary                   # 强制官方 release 二进制（无需 conda）
#   bash install.sh --conda-env sk --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/seqkit             # binary 模式自定义前缀
#   bash install.sh --version 2.12.0                  # 覆盖版本（binary URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.13.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/seqkit-$DEFAULT_VERSION}"
CONDA_ENV="seqkit"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release 二进制（linux-x64 / macos-x64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
# 来源：GitHub release v2.13.0 资产 digest（seqkit_linux_amd64.tar.gz / seqkit_darwin_amd64.tar.gz，
#       2026-09-08 API 核实；官方资产另附 *.md5.txt，本脚本用 release API 提供的 sha256）
SHA256_LINUX_X86_64="7d686de448464fada1b1988e2e07d693bec68768312da62846bc0e2b502bfc46"
SHA256_OSX_X86_64="7db4264a1a49d9ad7cc6d02f572c8573469d6f91881da2a2420b7f5426d63951"

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
        *) die "未知参数: ${1}（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# binary 模式仅官方 release 覆盖的平台（linux-x64 / macos-x64；arm64 亦有官方包，脚本保守只走两平台，
# 其余平台提示改用 conda 或官方 arm64 资产手动安装）
platform_ok_binary() {
    { [[ "$OS" == "Linux"  && "$ARCH" == "x86_64" ]] ||
      [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 版本断言（安装后运行 seqkit version 校验，输出形如 "seqkit v2.13.0"） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" version 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "v${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 v${VERSION}，实际输出见上"
    log "版本校验通过：${VERSION}"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 seqkit=${VERSION} 到环境: ${CONDA_ENV}"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 用 mamba 时回退 conda；顺序固定 conda-forge 在前，避免依赖冲突
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "seqkit=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "seqkit=${VERSION}"
    fi
    log "验证：conda run -n ${CONDA_ENV} seqkit version"
    "$CONDA_BIN" run -n "$CONDA_ENV" seqkit version | sed 's/^/  /'
    log "完成：conda activate ${CONDA_ENV} 后即可使用 seqkit"
}

# ---------------- 路线 B：官方 GitHub release 二进制 ----------------
install_binary() {
    local plat url tar sha bin_src
    case "$OS" in
        Linux)  plat="linux_amd64"; sha="$SHA256_LINUX_X86_64" ;;
        Darwin) plat="darwin_amd64"; sha="$SHA256_OSX_X86_64" ;;
    esac
    url="https://github.com/shenwei356/seqkit/releases/download/v${VERSION}/seqkit_${plat}.tar.gz"

    log "下载官方二进制: ${url}"
    log "安装前缀: ${PREFIX}"
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀 ${PREFIX} 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 重建，或改用 --prefix 指定其它前缀"
        fi
    fi
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/seqkit.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/seqkit.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/seqkit.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/seqkit.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    tar -xzf "$tmp/seqkit.tar.gz" -C "$tmp"
    bin_src="$(find "$tmp" -maxdepth 2 -type f -name seqkit -perm -111 | head -1)"
    [[ -n "$bin_src" ]] || die "release 包内未找到可执行文件 seqkit（URL 或版本号有误？）"

    install -m 0755 "$bin_src" "$PREFIX/bin/seqkit"
    # tar 包内附 LICENSE / README 等（如有）一并放置到前缀根
    if [[ -f "$(dirname "$bin_src")/LICENSE" ]]; then
        install -m 0644 "$(dirname "$bin_src")/LICENSE" "$PREFIX/LICENSE"
    fi
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/seqkit"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# seqkit (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 seqkit 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "seqkit ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方二进制（本脚本仅覆盖 linux-x64 / macos-x64）；请改用 conda 路线或官方 arm64 资产"
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
