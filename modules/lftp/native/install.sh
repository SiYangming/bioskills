#!/usr/bin/env bash
# =============================================================================
# install.sh — lftp 宿主机本地安装脚本
#
# 归属    ：bioskills modules/lftp/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」）
#   - conda  路线（默认优先）：lftp 在 conda-forge（bioconda 无 lftp，2026-09-08 核实 404）→
#     mamba/conda 创建独立环境（仅 -c conda-forge），pin lftp=4.9.3（与 meta software_versions.native
#     对齐）+ python=3.11 + pyyaml（驱动 main.py 用）。
#   - binary 路线（无 conda 兜底）：官方**源码**归档编译（lftp 官方无预编译二进制资产；v4.9.3
#     GitHub release 仅 lftp-4.9.3.tar.gz 一个资产）：
#       Linux  ：https://lftp.yar.ru/ftp/lftp-<ver>.tar.xz（官方 ftp 归档；官方仅发布 .md5sum +
#                GPG .asc，无 sha256 → 用官方 .md5sum 文件做 md5sum -c 校验，sha256 未核实）
#       macOS  ：https://github.com/lavv17/lftp/releases/download/v<ver>/lftp-<ver>.tar.gz
#                （GitHub release 官方归档；默认版本内嵌 sha256=68116cc1…e0a29 —— homebrew-core
#                formula JSON 校验值，2026-09-08 核实）
#     编译到用户前缀 --prefix（默认 ~/software/lftp-<ver>），无需 root、不写 /opt/biosoft、
#     不写 /home/train；./configure --prefix=$PREFIX && make -j && make install。
#   - 版本默认 4.9.3，与 modules/lftp/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://lftp.yar.ru/（get.html 下载页滞后仍列 4.9.2；首页 events + ftp 归档已有 4.9.3）
#   源码归档 : https://lftp.yar.ru/ftp/lftp-4.9.3.tar.xz（2026-09-08 核实 HTTP 200）
#   GitHub   : https://github.com/lavv17/lftp/releases（lavv17/lftp；v4.9.3 资产 lftp-4.9.3.tar.gz）
#   conda    : https://anaconda.org/conda-forge/lftp（latest 4.9.3）
#   brew     : https://formulae.brew.sh/api/formula/lftp.json（stable 4.9.3）
#   (容器自建：native/Dockerfile + Apptainer.def —— debian:bookworm-slim + apt lftp=4.9.2-2，
#    官方生物渠道 bioconda/quay/depot 全无，见模块 README；本脚本为宿主机安装)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 conda-forge，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: lftp-native）
#   bash install.sh --method binary                   # 强制官方源码编译（无需 conda，需 gcc/make）
#   bash install.sh --conda-env lftp --force          # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/lftp                # binary 模式自定义前缀
#   bash install.sh --version 4.9.2                    # 覆盖版本（非默认 → 跳过内嵌校验并提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="4.9.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/lftp-$DEFAULT_VERSION}"
CONDA_ENV="lftp-native"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 GitHub release 源码归档（lftp-<ver>.tar.gz）——默认版本内嵌 sha256：
# homebrew-core formula JSON（https://formulae.brew.sh/api/formula/lftp.json）校验值，2026-09-08 核实；
# lftp.yar.ru 官方对源码归档仅发布 .md5sum + GPG .asc（sha256 未核实）→ Linux 走官方 .md5sum 校验
SHA256_GITHUB_TAR_GZ="68116cc184ab660a78a4cef323491e89909e5643b59c7b5f0a14f7c2b20e0a29"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    awk 'NR>1 && /^#/{ sub(/^# ?/,""); print; next } /^#/{ next } { exit }' "$0"
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

# 源码编译路线：Linux / macOS 均可（需 make + cc + 开发库）；其余平台（如 Windows 等）不适用
platform_ok_binary() {
    { [[ "$OS" == "Linux" ]] || [[ "$OS" == "Darwin" ]]; }
}

have_toolchain() {
    command -v make >/dev/null 2>&1 && command -v cc >/dev/null 2>&1
}

# ---------------- 版本断言（安装后运行 lftp --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 || true)"
    printf '  %s\n' "$(printf '%s\n' "$out" | head -n 1)"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：lftp --version 输出未包含 ${VERSION}（实际输出见上）"
    log "版本校验通过：lftp ${VERSION}"
}

# ---------------- 路线 A：conda / conda-forge（bioconda 无 lftp，只用 conda-forge） ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 lftp=${VERSION} 到环境: ${CONDA_ENV}（channel: conda-forge；bioconda 无 lftp，2026-09-08 核实 404）"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge python=3.11 "lftp=${VERSION}" pyyaml
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge python=3.11 "lftp=${VERSION}" pyyaml
    fi
    log "验证：conda run -n ${CONDA_ENV} lftp --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" lftp --version | sed 's/^/  /' | head -n 1
    grep -qE "${VERSION//./\.}" <<<"$("$CONDA_BIN" run -n "$CONDA_ENV" lftp --version 2>&1)" \
        || die "conda 路线版本校验失败（期望 ${VERSION}）"
    log "完成：conda activate ${CONDA_ENV} 后即可使用 lftp / python main.py"
}

# ---------------- 路线 B：官方源码编译（Linux: yar.ru tar.xz + md5sum；macOS: GitHub tar.gz + sha256） ----------------
install_binary() {
    log "使用官方源码编译安装 lftp=${VERSION}（官方无预编译二进制资产；仅源码归档）"
    log "安装前缀: ${PREFIX}"
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀 ${PREFIX} 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 重建，或改用 --prefix 指定其它前缀"
        fi
    fi
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    local src_archive=""  # 解压后的源码目录
    if [[ "$OS" == "Linux" ]]; then
        local url_xz="https://lftp.yar.ru/ftp/lftp-${VERSION}.tar.xz"
        log "下载官方源码归档: ${url_xz}"
        curl -fsSL -o "$tmp/lftp-${VERSION}.tar.xz" "$url_xz" 2>/dev/null \
            || wget -qO "$tmp/lftp-${VERSION}.tar.xz" "$url_xz" \
            || die "需要 curl 或 wget 下载官方源码归档"
        # 官方只发布 .md5sum + GPG .asc（sha256 未核实）→ 下载官方 .md5sum 做 md5sum -c
        if [[ "$VERSION" == "$DEFAULT_VERSION" ]] \
           && curl -fsSL -o "$tmp/lftp-${VERSION}.md5sum" "https://lftp.yar.ru/ftp/lftp-${VERSION}.md5sum" 2>/dev/null; then
            # 官方 md5sum 文件同时含 tar.gz/bz2/xz 多条 → 只取本机下载的 .tar.xz 条目校验
            ( cd "$tmp" && grep -F "lftp-${VERSION}.tar.xz" "lftp-${VERSION}.md5sum" | md5sum -c - >/dev/null 2>&1 ) \
                || die "md5 校验失败：下载文件不完整或被篡改（官方 lftp-${VERSION}.md5sum）"
            log "md5 校验通过（官方 lftp-${VERSION}.md5sum；官方无 sha256 发布 → sha256 未核实）"
        else
            warn "非默认版本（${VERSION}）或官方 md5sum 不可用 → 跳过完整性校验，请自行核对官网 .asc 签名/摘要"
        fi
        tar -Jxf "$tmp/lftp-${VERSION}.tar.xz" -C "$tmp"
    else  # Darwin
        local url_gz="https://github.com/lavv17/lftp/releases/download/v${VERSION}/lftp-${VERSION}.tar.gz"
        log "下载官方源码归档: ${url_gz}"
        curl -fsSL -o "$tmp/lftp-${VERSION}.tar.gz" "$url_gz" \
            || die "需要 curl 下载官方源码归档"
        if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
            echo "${SHA256_GITHUB_TAR_GZ}  $tmp/lftp-${VERSION}.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
            log "sha256 校验通过（homebrew-core formula 同源校验值，2026-09-08 核实）"
        else
            warn "非默认版本（${VERSION}）→ 跳过内嵌 sha256 校验，请自行核对 GitHub release 摘要"
        fi
        tar -xzf "$tmp/lftp-${VERSION}.tar.gz" -C "$tmp"
    fi

    src_archive="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "lftp-*" | head -n 1)"
    [[ -n "$src_archive" && -f "$src_archive/configure" ]] \
        || die "源码归档内未找到 configure（URL 或版本号有误？）"

    # 编译：./configure --prefix=$PREFIX && make -j && make install
    log "configure: ./configure --prefix=${PREFIX}"
    ( cd "$src_archive" && ./configure --prefix="$PREFIX" ) \
        || die "configure 失败。请先安装编译依赖：Debian/Ubuntu 需 build-essential libssl-dev \
libidn2-dev libreadline-dev zlib1g-dev（sudo apt-get install -y ...）；macOS 可 brew install openssl \
libidn2 readline（必要时按 configure 报错设置 CPPFLAGS/LDFLAGS）"
    local njobs=4
    if command -v nproc >/dev/null 2>&1; then njobs="$(nproc)"; elif command -v sysctl >/dev/null 2>&1; then
        njobs="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"; fi
    log "make -j${njobs} && make install"
    ( cd "$src_archive" && make -j"$njobs" && make install ) \
        || die "make 失败（见上方编译日志；依赖缺失提示同 configure 失败信息）"
    test -x "$PREFIX/bin/lftp" || die "编译产物缺失：${PREFIX}/bin/lftp"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/lftp"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"${PREFIX}/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# lftp (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 lftp 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"${PREFIX}/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "lftp ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 不支持源码编译（仅 Linux / macOS）"
        have_toolchain || die "--method binary 需要 gcc/make（make 与 cc 未在 PATH）；请先安装编译工具链（见 README §4 依赖提示）"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary && have_toolchain; then
            install_binary
        else
            die "未检测到 mamba/conda 且本机（${OS}/${ARCH}）无编译工具链；请先装 conda/mamba 或用 README §4 安装编译依赖"
        fi ;;
esac
log "安装成功"
