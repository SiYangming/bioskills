#!/usr/bin/env bash
# =============================================================================
# install.sh — GapCloser (SOAPdenovo2) 宿主机本地安装脚本
#
# 归属    ：bioskills modules/gapcloser/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「安装方式（本地）」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin
#     bioconda::soapdenovo2-gapcloser（GapCloser 的 bioconda 包名）
#   - binary 路线（无 conda 兜底）：官方 SourceForge 预编译 tgz
#     GapCloser-bin-v1.12-r6.tgz（仅 linux-x64），用户级前缀安装到
#     --prefix（默认 ~/software/gapcloser-<ver>），无需 root、不写 /opt
#   - 版本默认 1.12，与 modules/gapcloser/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://sourceforge.net/projects/soapdenovo2/files/GapCloser
#   bioconda : https://anaconda.org/bioconda/soapdenovo2-gapcloser
#   prebuilt : https://sourceforge.net/projects/soapdenovo2/files/GapCloser/bin/r6/GapCloser-bin-v1.12-r6.tgz
#   (容器：quay.io/biocontainers/soapdenovo2-gapcloser —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方预编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: gapcloser）
#   bash install.sh --method binary                   # 强制官方预编译 tgz（仅 linux-x64）
#   bash install.sh --conda-env gc --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/gapcloser          # binary 模式自定义前缀
#   bash install.sh --version 1.12                    # 覆盖版本（binary 模式跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.12"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/gapcloser-$DEFAULT_VERSION}"
CONDA_ENV="gapcloser"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 SourceForge 预编译 tgz（仅 linux-x64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_LINUX_X86_64="8ca1a7e521dabc551ab4436d2b6e32536df670fae1c0e0fcb9242ae3a53db579"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
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

# binary 模式仅官方 SourceForge 预编译覆盖的平台（linux-x64）可用
platform_ok_binary() {
    [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]
}

# ---------------- 版本断言（GapCloser 无 --version，用内建 help 关键字断言） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" 2>&1 || true)"
    printf '%s\n' "$out" | grep -q "input scaffold file name" \
        || die "版本/可用性校验失败：GapCloser help 未输出预期关键字，实际输出见上"
    log "可用性校验通过：GapCloser（GapCloser v${VERSION}-r6；二进制无标准 --version）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 soapdenovo2-gapcloser=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "soapdenovo2-gapcloser=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "soapdenovo2-gapcloser=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV GapCloser"
    "$CONDA_BIN" run -n "$CONDA_ENV" GapCloser 2>&1 | grep -q "input scaffold file name" \
        || die "conda 安装后 GapCloser 校验失败"
    log "完成：conda activate $CONDA_ENV 后即可使用 GapCloser"
}

# ---------------- 路线 B：官方 SourceForge 预编译 tgz ----------------
install_binary() {
    local url sha
    sha="$SHA256_LINUX_X86_64"
    url="https://downloads.sourceforge.net/project/soapdenovo2/GapCloser/bin/r6/GapCloser-bin-v${VERSION}-r6.tgz"

    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/gapcloser.tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/gapcloser.tgz" "$url"
    else
        die "需要 curl 或 wget 下载预编译包"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/gapcloser.tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/gapcloser.tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 SourceForge 摘要）"
    fi

    tar -xzf "$tmp/gapcloser.tgz" -C "$tmp"
    [[ -f "$tmp/GapCloser" ]] || die "预编译包内未找到可执行文件 GapCloser（版本号或 URL 有误？）"
    install -m 0755 "$tmp/GapCloser" "$PREFIX/bin/GapCloser"
    [[ -f "$tmp/GapCloser_Manual.pdf" ]] && cp "$tmp/GapCloser_Manual.pdf" "$PREFIX/" || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/GapCloser"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# gapcloser (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 GapCloser 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "GapCloser $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译包（仅 linux-x64）；请改用 conda 路线"
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
