#!/usr/bin/env bash
# =============================================================================
# install.sh — FastUniq 宿主机本地安装脚本
#
# 归属    ：bioskills modules/fastuniq/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / 安装方式登记对齐）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，bioconda 频道 fastuniq
#     （-c conda-forge -c bioconda fastuniq=1.1；2026-09 核实 bioconda 有 1.1，
#     linux-64 / osx-64 / linux-aarch64 / osx-arm64 全平台）
#   - source 路线（无 conda 兜底）：官方 sourceforge 源码包 FastUniq-<ver>.tar.gz
#     （官方仅有源码包、无预编译二进制 release）→ make -C source 编译 →
#     fastuniq 部署到用户前缀 --prefix（默认 ~/software/fastuniq-<ver>），免 root、
#     不写 /opt/biosoft、/home/train
#   - 版本默认 1.1，与 modules/fastuniq/meta.yaml software_versions.native 对齐
#
# 官方来源（2026-09 逐渠道核实）：
#   homepage : https://sourceforge.net/projects/fastuniq/
#   source   : https://downloads.sourceforge.net/project/fastuniq/FastUniq-1.1.tar.gz
#              sha256 9ebf251566d097226393fb5aa9db30a827e60c7a4bd9f6e06022b4af4cee0eae
#              （bioconda recipe 与 brewsci/bio brew formula 双源一致）
#   bioconda : https://anaconda.org/bioconda/fastuniq（fastuniq=1.1）
#   brew     : brewsci/bio tap 有公式（brew tap brewsci/bio && brew install fastuniq）
#   (容器：官方镜像 quay.io/biocontainers/fastuniq:1.1--h7b50bb2_2 /
#    depot.galaxyproject.org sif，见模块 README「环境安装」)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 conda（bioconda），否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: fastuniq）
#   bash install.sh --method source                   # 强制源码编译（无需 conda）
#   bash install.sh --conda-env fastuniq11 --force    # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/fastuniq           # source 模式自定义前缀
#   bash install.sh --version 1.0                     # 覆盖版本（非默认版本跳过内嵌 sha256 校验并提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.1"
EXPECTED_SHA256="9ebf251566d097226393fb5aa9db30a827e60c7a4bd9f6e06022b4af4cee0eae"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/fastuniq-$DEFAULT_VERSION}"
CONDA_ENV="fastuniq"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    # 打印文件头注释（两个 ==== 装饰行之间），自动截断，不粘连脚本正文
    awk 'NR==1 {next} /^# ===/{n++; if(n==2) exit} {sub(/^# ?/,""); print}' "$0"
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

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（fastuniq 无 --version/--help；无参运行即打印用法并返回非 0） ----------------
# 官方/bioconda 的可用性判据：输出含用法首行 "The input file list of paired"
assert_ready() {
    local bin="$1" out
    out="$("$bin" 2>&1 || true)"
    grep -q "The input file list of paired" <<<"$out" \
        || die "fastuniq 未就绪：无参运行输出未命中用法文本（The input file list of paired）"
    log "fastuniq 可用（版本目标 ${VERSION}）"
}

# ---------------- 路线 A：conda（bioconda 官方频道，含 1.1） ----------------
install_conda() {
    local env_exists out
    log "使用 conda 安装 fastuniq=${VERSION}（-c conda-forge -c bioconda）到环境: ${CONDA_ENV}"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "fastuniq=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "fastuniq=${VERSION}"
    fi
    log "验证：conda run -n ${CONDA_ENV} fastuniq（无参运行打印用法）"
    out="$("$CONDA_BIN" run -n "$CONDA_ENV" fastuniq 2>&1 || true)"
    grep -q "The input file list of paired" <<<"$out" \
        || die "conda 安装后 fastuniq 用法文本校验失败"
    "$CONDA_BIN" list -n "$CONDA_ENV" fastuniq | sed 's/^/  /'
    log "完成：conda activate ${CONDA_ENV} 后即可使用 fastuniq"
}

# ---------------- 路线 B：官方源码包编译（C 程序，用户级前缀，免 conda） ----------------
source_platform_deps_ok() {
    # FastUniq 为纯 C 工程：只需 make + C 编译器（gcc/clang）
    command -v make >/dev/null 2>&1 || return 1
    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || return 1
    return 0
}

install_source() {
    local tmp="" url mkf src_dir actual_sha hasher
    if ! source_platform_deps_ok; then
        die "源码编译缺少依赖：需要 make + C 编译器（gcc/clang）。macOS 请装 Xcode Command Line
  Tools（xcode-select --install）；Debian/Ubuntu: sudo apt-get install -y --no-install-recommends
  build-essential make；再重跑本脚本。"
    fi
    log "使用官方源码包编译 fastuniq=${VERSION} 到前缀: ${PREFIX}"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    # 1) 下载官方源码包（sourceforge 直链；官方无预编译二进制 release）
    url="https://downloads.sourceforge.net/project/fastuniq/FastUniq-${VERSION}.tar.gz"
    log "下载源码包: ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/fastuniq.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/fastuniq.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码包"
    fi

    # 2) sha256 校验（仅默认版本内嵌官方摘要；非默认版本提示自行核对）
    if command -v shasum >/dev/null 2>&1; then hasher="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then hasher="sha256sum"; fi
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if [[ -n "$hasher" ]]; then
            actual_sha="$($hasher "$tmp/fastuniq.tar.gz" | awk '{print $1}')"
            [[ "$actual_sha" == "$EXPECTED_SHA256" ]] \
                || die "sha256 校验失败：期望 ${EXPECTED_SHA256}，实际 ${actual_sha}（下载可能不完整或被篡改）"
            log "sha256 校验通过（${EXPECTED_SHA256}）"
        else
            warn "未找到 shasum/sha256sum，跳过内嵌 sha256 校验（建议手工核对下载摘要）"
        fi
    else
        warn "--version ${VERSION} 为非默认版本（默认 ${DEFAULT_VERSION}），跳过内嵌 sha256 校验，请自行核对 sourceforge release 摘要"
    fi

    # 3) 解压并定位 source/Makefile（官方包结构：<root>/source/Makefile）
    tar -xzf "$tmp/fastuniq.tar.gz" -C "$tmp"
    mkf="$(find "$tmp" -maxdepth 3 -type f -path '*/source/Makefile' | head -n 1 || true)"
    [[ -n "$mkf" ]] || die "源码包内未找到 source/Makefile（FastUniq-${VERSION}.tar.gz 结构异常）"
    src_dir="$(dirname "$mkf")"   # .../FastUniq-1.1/source
    log "源码目录: ${src_dir}"

    # 4) make 编译并部署二进制（生成 source/fastuniq；官方 README 步骤）
    make -C "$src_dir"
    [[ -f "$src_dir/fastuniq" ]] || die "make 未生成 fastuniq（查看 ${src_dir}/Makefile 的 GCC_OPTION）"
    install -m 0755 "$src_dir/fastuniq" "$PREFIX/bin/fastuniq"

    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_ready "$PREFIX/bin/fastuniq"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# fastuniq (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 fastuniq 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "fastuniq ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            log "未检测到 mamba/conda，转官方源码编译路线（需 make + C 编译器）"
            install_source
        fi ;;
esac
log "安装成功"
