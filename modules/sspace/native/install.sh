#!/usr/bin/env bash
# =============================================================================
# install.sh — SSPACE STANDARD v3.0 宿主机本地安装脚本（说明型 + binary 路线）
#
# 归属    ：bioskills modules/sspace/native/install.sh（native 实现安装方式）
# 渠道现状（2026-09 核实）：**无官方 conda 包 / 官方镜像** —— bioconda `sspace` 404
#   （仅 `sspace_basic`=2.1.1，为另一工具 SSPACE-Basic），quay.io/biocontainers/sspace
#   与 depot.galaxyproject.org 均无；官方 BaseClear 下载 URL 已 404。故本脚本：
#   - conda 路线：不可用（--method conda 会明确报错并说明原因）
#   - binary 路线（唯一可用）：官方发行 tar（BaseClear 原 URL 已 404，取自社区归档
#     github.com/yexianingyue/SSPACE-STANDARD-3.0，内嵌 sha256 校验），解压到
#     --prefix（默认 ~/software/sspace-<ver>），无需 root、不写 /opt
#   - 仅支持 linux-x64（tar 内捆绑 bowtie 0.12.5 / bwa 均为 linux-x86_64 ELF）；
#     其它平台请改用本模块自建容器（native/Dockerfile / native/Apptainer.def）
#   - 运行依赖：perl + Debian 包 libperl4-corelibs-perl（提供 SSPACE require 的 getopts.pl）
#   - 版本默认 3.0，与 modules/sspace/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://www.baseclear.com/services/bioinformatics/basetools/sspace-standard（页面 404）
#   发行 tar 社区归档 : https://github.com/yexianingyue/SSPACE-STANDARD-3.0
#
# 用法示例：
#   bash install.sh                                   # auto → binary（无 conda 路线，直接走 tar）
#   bash install.sh --method binary                   # 明确走官方发行 tar（仅 linux-x64）
#   bash install.sh --prefix ~/opt/sspace-3.0         # 自定义前缀
#   bash install.sh --version 3.0                     # 覆盖版本（跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="3.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/sspace-$DEFAULT_VERSION}"
CONDA_ENV="sspace"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方发行 tar（社区归档镜像；仅 linux-x64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
TARBALL_NAME="SSPACE-STANDARD-v.-3.0-linux-x86_64.tar.gz"
SHA256_LINUX_X86_64="4a5064103921e196ad66f80c7ff4373ddc6be9d830b8f30b8cd5c6785693645a"

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

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"

# binary 模式仅官方发行 tar 覆盖的平台（linux-x64；捆绑 bowtie/bwa 为 linux ELF）可用
platform_ok_binary() {
    [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]
}

# ---------------- 版本断言（SSPACE 无 --version，用脚本内版本串断言） ----------------
assert_version() {
    local script="$1"
    grep -q "SSPACE_Standard_v3.0_linux" "$script" \
        || die "版本校验失败：未在脚本中找到 [SSPACE_Standard_v3.0_linux] 版本串"
    # getopts.pl（libperl4-corelibs-perl）存在时做编译校验（更严格）
    if perl -e 'require "getopts.pl"' 2>/dev/null; then
        perl -c "$script" >/dev/null 2>&1 || die "perl -c 编译校验失败（依赖缺失？）"
        log "版本校验通过：SSPACE STANDARD v${VERSION}（perl -c 通过）"
    else
        warn "未检测到 getopts.pl（建议安装 libperl4-corelibs-perl）→ 跳过 perl -c，仅做版本串断言"
        log "版本校验通过：SSPACE STANDARD v${VERSION}"
    fi
}

# ---------------- 路线 A：conda（无官方包，明确报错） ----------------
install_conda() {
    die "无官方 conda 包：bioconda \`sspace\` 404（仅 \`sspace_basic\`=2.1.1，为另一工具 SSPACE-Basic）；请改用 --method binary 或本模块自建容器（native/Dockerfile / native/Apptainer.def）"
}

# ---------------- 路线 B：官方发行 tar（社区归档；仅 linux-x64） ----------------
install_binary() {
    local url sha srcdir share_dir
    sha="$SHA256_LINUX_X86_64"
    url="https://raw.githubusercontent.com/yexianingyue/SSPACE-STANDARD-3.0/main/${TARBALL_NAME}"

    log "下载官方发行 tar（社区归档）: $url"
    log "安装前缀: $PREFIX"
    share_dir="$PREFIX/share/SSPACE-STANDARD-3.0_linux-x86_64"
    mkdir -p "$PREFIX/bin" "$PREFIX/share"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/sspace.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/sspace.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载发行 tar"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/sspace.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/sspace.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对归档文件）"
    fi

    rm -rf "$share_dir"
    tar -xzf "$tmp/sspace.tar.gz" -C "$PREFIX/share"
    [[ -f "$share_dir/SSPACE_Standard_v3.0.pl" ]] \
        || die "发行 tar 内未找到 SSPACE_Standard_v3.0.pl（版本号或 URL 有误？）"

    # 用包装脚本调用，保证 Perl FindBin 解析到真实安装目录（$Bin/bowtie、$Bin/bwa）
    printf '#!/bin/sh\nexec perl %s/SSPACE_Standard_v3.0.pl "$@"\n' "$share_dir" > "$PREFIX/bin/SSPACE_Standard_v3.0.pl"
    printf '#!/bin/sh\nexec perl %s/tools/sam_bam2tab.pl "$@"\n' "$share_dir" > "$PREFIX/bin/sam_bam2tab.pl"
    chmod +x "$PREFIX/bin/SSPACE_Standard_v3.0.pl" "$PREFIX/bin/sam_bam2tab.pl"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$share_dir/SSPACE_Standard_v3.0.pl"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# sspace (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 SSPACE_Standard_v3.0.pl 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "SSPACE STANDARD $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无可用发行 tar（仅 linux-x64）；请改用自建容器（native/Dockerfile / native/Apptainer.def）"
        install_binary ;;
    auto)
        if platform_ok_binary; then
            install_binary
        else
            die "本平台（${OS}/${ARCH}）无可用发行 tar（仅 linux-x64）且无官方 conda 路线；请改用自建容器（native/Dockerfile / native/Apptainer.def）"
        fi ;;
esac
log "安装成功"
