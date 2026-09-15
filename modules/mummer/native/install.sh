#!/usr/bin/env bash
# =============================================================================
# install.sh — MUMmer v4 宿主机本地安装脚本
#
# 归属    ：bioskills modules/mummer/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::mummer4=<版本>
#     ⚠️ MUMmer4 的 bioconda 包名是 mummer4；mummer 包是旧版 MUMmer3.23
#   - source 路线（无 conda 兜底）：官方 GitHub release 源码 ./configure && make && make install
#     到用户级前缀（默认 ~/software/mummer-4.0.0beta2，免 root、不写 /opt）
#   - 版本默认 4.0.0beta2，与 modules/mummer/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/mummer4/mummer
#   bioconda : https://anaconda.org/bioconda/mummer4
#   release  : https://github.com/mummer4/mummer/releases/download/v4.0.0beta2/mummer-4.0.0beta2.tar.gz
#   容器     : quay.io/biocontainers/mummer4:4.0.0beta2--pl526he1b5a44_5（本脚本为宿主机安装）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: mummer）
#   bash install.sh --method source                   # 强制官方源码编译（无需 conda）
#   bash install.sh --prefix ~/opt/mummer             # source 模式自定义前缀
#   bash install.sh --version 4.0.1                   # 覆盖版本（跳过内嵌 sha256 校验并提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="4.0.0beta2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/mummer-$DEFAULT_VERSION}"
CONDA_ENV="mummer"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
# 官方 release 源码 tar.gz 的 sha256：官方 release 页未提供摘要，本仓库未核实 → 留空，
# 安装时跳过校验并提示用户自行核对（禁止编造 sha256）。
SHA256_SRC=""

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
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac
[[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}）；官方仅 v$DEFAULT_VERSION 内嵌 sha256 校验已跳过，请自行核对 release 摘要"

OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

assert_binary() {
    local bin="$1" out
    [[ -x "$bin" ]] || die "未找到可执行文件: $bin"
    out="$("$bin" --version 2>&1 | head -n 1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

write_path() {
    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# mummer (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
    else
        log "未改 PATH：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 路线 A：conda / bioconda（包名 mummer4） ----------------
install_conda() {
    log "使用 conda 安装 mummer4=$VERSION（MUMmer4；bioconda 包名 mummer4）到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mummer4=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "mummer4=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV nucmer --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" nucmer --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 nucmer / show-coords / delta-filter / mummerplot"
}

# ---------------- 路线 B：官方源码编译 ----------------
install_source() {
    command -v g++ >/dev/null 2>&1 || die "--method source 需要 g++/build-essential"
    command -v make >/dev/null 2>&1 || die "--method source 需要 make"
    local url="https://github.com/mummer4/mummer/releases/download/v${VERSION}/mummer-${VERSION}.tar.gz"
    log "下载官方源码: $url"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/mummer.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/mummer.tar.gz" "$url"
    else
        die "需要 curl 或 wget"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "$SHA256_SRC" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "${SHA256_SRC}  $tmp/mummer.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "${SHA256_SRC}  $tmp/mummer.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "未内嵌 sha256（官方 release 未提供摘要，本仓库未核实）→ 跳过校验；请自行核对 release 摘要"
    fi

    tar -xzf "$tmp/mummer.tar.gz" -C "$tmp"
    local srcdir; srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "源码解压失败"
    ( cd "$srcdir" \
        && ./configure --prefix="$PREFIX" \
        && make -j"$(nproc 2>/dev/null || echo 4)" \
        && make install ) || die "configure/make/make install 失败（见上方报错）"
    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_binary "$PREFIX/bin/nucmer"
    write_path
}

# ---------------- 主流程 ----------------
log "MUMmer v$VERSION 安装开始（本机 ${OS}/${ARCH}；bioconda 包名 mummer4）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source) install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_source
        fi ;;
esac
log "安装成功"
