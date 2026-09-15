#!/usr/bin/env bash
# =============================================================================
# install.sh — Mauve 宿主机本地安装脚本
#
# 归属    ：bioskills modules/mauve/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::mauve=<版本>
#     （mauve 依赖 mauvealigner，后者提供 progressiveMauve / mauveAligner）
#   - binary 路线（无 conda 兜底）：官方预编译 mauve_linux_2.4.0.tar.gz 解压到用户级前缀
#     （默认 ~/software/mauve-2.4.0），无需 root、不写 /opt；仅 Linux x86_64 可用
#   - 版本默认 2.4.0，与 modules/mauve/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://darlinglab.org/mauve/mauve.html
#   bioconda : https://anaconda.org/bioconda/mauve
#   release  : https://darlinglab.org/mauve/downloads/mauve_linux_2.4.0.tar.gz
#   容器     : quay.io/biocontainers/mauve:2.4.0.r4736--h43d4aaa_3（本脚本为宿主机安装）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: mauve）
#   bash install.sh --method binary                   # 强制官方预编译 tarball（无需 conda）
#   bash install.sh --prefix ~/opt/mauve              # binary 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.4.0"
VERSION="$DEFAULT_VERSION"
CONDA_VERSION="2.4.0.r4736"      # bioconda 包版本（GUI 包；依赖 mauvealigner 提供 progressiveMauve）
PREFIX="${PREFIX:-$HOME/software/mauve-$DEFAULT_VERSION}"
CONDA_ENV="mauve"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
# 官方预编译 tarball（mauve_linux_2.4.0.tar.gz）sha256：取自官方下载实测（2026-09）——
# 如官方重新打包会校验失败，届时请更新本值。
SHA256_BIN="66ba3c359b6534ca8498dab079b5e582acfece036067478a289fe363a74fd27b"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
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
[[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}）；官方仅提供 2.4.0 tarball，binary 模式 URL/校验和可能不适用"

OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

platform_ok_binary() { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }

# progressiveMauve 静态二进制：--version 输出格式随构建而异（官方 2.4.0 tarball 内未内嵌
# 版本字面量），故断言「可执行 + 能输出 usage/版本」；命中 2.4 则视为版本匹配。
assert_progressiveMauve() {
    local bin="$1" out rc=0
    [[ -x "$bin" ]] || die "未找到可执行文件: $bin"
    out="$("$bin" --version 2>&1 || "$bin" -version 2>&1 || "$bin" 2>&1 || true)"
    printf '  %s\n' "$out"
    if grep -qE '2\.4' <<<"$out"; then
        log "版本校验通过：命中 2.4"
    elif grep -qiE 'progressiveMauve usage|Display software version' <<<"$out"; then
        warn "progressiveMauve --version 未回显 2.4 版本号；二进制可执行（usage 正常）→ 按官方渠道版本 ${VERSION} 计"
    else
        die "progressiveMauve 未能执行（输出见上）"
    fi
}

write_path() {
    local dirs=("$@")
    if [[ "$UPDATE_PATH" == 1 ]]; then
        local d line
        for d in "${dirs[@]}"; do
            line="export PATH=\"$d:\$PATH\""
            if [[ -f "$PROFILE" ]] && grep -qF "$d" "$PROFILE"; then
                log "PATH 已包含 $d，跳过写入 $PROFILE"
            else
                { echo ""; echo "# mauve (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
                log "已追加 PATH 到 $PROFILE（$d）"
            fi
        done
    else
        log "未改 PATH：使用时请执行 export PATH=\"${dirs[*]// /:}:\$PATH\""
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 mauve=$CONDA_VERSION（含 mauvealigner → progressiveMauve）到环境: $CONDA_ENV"
    local env_exists
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mauve=$CONDA_VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mauve=$CONDA_VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV progressiveMauve --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" progressiveMauve --version 2>&1 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 progressiveMauve / mauveAligner / Mauve"
}

# ---------------- 路线 B：官方预编译 tarball ----------------
install_binary() {
    command -v tar >/dev/null 2>&1 || die "--method binary 需要 tar"
    local url="https://darlinglab.org/mauve/downloads/mauve_linux_${VERSION}.tar.gz"
    log "下载官方预编译: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/mauve.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/mauve.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载 tarball"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "$SHA256_BIN" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "${SHA256_BIN}  $tmp/mauve.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "${SHA256_BIN}  $tmp/mauve.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "跳过内嵌 sha256 校验（非默认版本）"
    fi

    tar -xzf "$tmp/mauve.tar.gz" -C "$PREFIX"
    local bin_cli="$PREFIX/mauve_${VERSION}/linux-x64"
    local bin_gui="$PREFIX/mauve_${VERSION}"
    [[ -x "$bin_cli/progressiveMauve" ]] || die "tarball 内未找到 linux-x64/progressiveMauve（版本号有误？）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_progressiveMauve "$bin_cli/progressiveMauve"
    write_path "$bin_cli" "$bin_gui"
    log "完成：progressiveMauve/mauveAligner 位于 $bin_cli；GUI 启动脚本 Mauve 位于 $bin_gui"
}

# ---------------- 主流程 ----------------
log "Mauve $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 官方预编译仅 Linux x86_64；本机 ${OS}/${ARCH} 请改用 conda 路线"
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
