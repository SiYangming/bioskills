#!/usr/bin/env bash
# =============================================================================
# install.sh — SOAPfuse 宿主机本地安装脚本（自建兜底路线）
#
# 归属    ：bioskills modules/soapfuse/native/install.sh（native 实现安装方式）
# 迁移形态：AGENT.md §7「查无官方维护 → 自建兜底」
#   - 官方渠道 bioconda → quay.io/biocontainers → depot.galaxyproject.org 均无 SOAPfuse
#     （2026-09 核实），故无 conda / 官方镜像路线。
#   - 官方发布：SourceForge 预编译包 SOAPfuse-v1.27.tar.gz，解压部署到用户前缀
#     （默认 ~/software/soapfuse-<ver>，免 root、不写 /opt/biosoft）。
#   - 运行依赖：perl（>=5.8.5）+ samtools + bedtools；v1.27 起需把 SOAPfuse perl 模块目录
#     加入 PERL5LIB（launcher 已自动设置）。
#
# 官方来源：
#   SourceForge: https://sourceforge.net/projects/soapfuse/files/SOAPfuse_Package/
#   wiki       : https://sourceforge.net/p/soapfuse/wiki/
#
# 用法示例：
#   bash install.sh                                   # auto：从官方 SourceForge 下载 v1.27 并部署
#   bash install.sh --tarball ~/Downloads/SOAPfuse-v1.27.tar.gz   # 用本地包部署
#   bash install.sh --prefix ~/opt/soapfuse --force
#   bash install.sh --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.27"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/soapfuse-$DEFAULT_VERSION}"
METHOD="auto"          # auto | binary | local
TARBALL=""
SHA256=""              # 可选：显式提供时校验下载包（默认不内嵌，避免编造摘要）
UPDATE_PATH=1
FORCE=0
URL="https://downloads.sourceforge.net/project/soapfuse/SOAPfuse_Package/SOAPfuse-v${VERSION}.tar.gz"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; URL="https://downloads.sourceforge.net/project/soapfuse/SOAPfuse_Package/SOAPfuse-v${VERSION}.tar.gz"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|binary|local}"; shift 2 ;;
        --tarball)     TARBALL="${2:?--tarball 需要本地包路径}"; shift 2 ;;
        --sha256)      SHA256="${2:?--sha256 需要 64 位摘要}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|binary|local) ;; *) die "--method 仅支持 auto|binary|local（收到: ${METHOD}）" ;; esac

# ---------------- 依赖探测（perl / samtools / bedtools） ----------------
check_deps() {
    command -v perl >/dev/null 2>&1 || warn "未检测到 perl（SOAPfuse 需 perl >= 5.8.5）"
    command -v samtools >/dev/null 2>&1 || warn "未检测到 samtools（SOAPfuse 流程依赖）"
    command -v bedtools >/dev/null 2>&1 || warn "未检测到 bedtools（SOAPfuse 流程依赖）"
    log "依赖提示：samtools/bedtools 可用 conda 安装（mamba create -n sofa -c bioconda -c conda-forge samtools bedtools perl）"
}

# ---------------- 部署 ----------------
deploy() {
    local src="$1"
    log "部署 SOAPfuse $VERSION 到: $PREFIX"
    [[ "$FORCE" == 1 ]] && rm -rf "$PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if [[ "$src" == "-" ]]; then
        log "下载官方预编译包: $URL"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$tmp/soapfuse.tar.gz" "$URL" || die "下载失败（URL 或网络问题）"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$tmp/soapfuse.tar.gz" "$URL" || die "下载失败（URL 或网络问题）"
        else
            die "需要 curl 或 wget 下载"
        fi
        src="$tmp/soapfuse.tar.gz"
    else
        [[ -f "$src" ]] || die "本地包不存在: $src"
    fi

    # 未内嵌 sha256（按录入规范禁真实下载核对）；--sha256 显式提供时才校验
    if [[ -n "$SHA256" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256  $src" | sha256sum -c - >/dev/null 2>&1 || die "sha256 校验失败"
        else
            echo "$SHA256  $src" | shasum -a 256 -c - >/dev/null 2>&1 || die "sha256 校验失败"
        fi
        log "sha256 校验通过"
    fi

    tar -xzf "$src" -C "$PREFIX" --strip-components=1
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 定位主脚本（SOAPfuse-RUN.pl）
    local main_pl
    main_pl="$(find "$PREFIX" -maxdepth 2 -type f -name 'SOAPfuse-RUN.pl' | head -1)"
    [[ -n "$main_pl" ]] || die "包内未找到 SOAPfuse-RUN.pl（版本号或 URL 有误？）"
    chmod +x "$main_pl" 2>/dev/null || true

    # 暴露 SOAPfuse-RUN.pl 到 bin/（驱动按 `perl SOAPfuse-RUN.pl ...` 解析）
    mkdir -p "$PREFIX/bin"
    ln -sf "$main_pl" "$PREFIX/bin/SOAPfuse-RUN.pl"

    # v1.27+ 需把 SOAPfuse perl 模块目录加入 PERL5LIB（官方 wiki 要求）
    local perl_lib=""
    local d
    for d in "$PREFIX/source" "$PREFIX/source/bin" "$PREFIX"; do
        [[ -d "$d" ]] && perl_lib="${perl_lib:+$perl_lib:}$d"
    done

    check_deps

    local path_line="export PATH=\"$PREFIX/bin:\$PATH\""
    local perl_line="export PERL5LIB=\"${perl_lib}:\${PERL5LIB:-}\""
    if [[ "$UPDATE_PATH" == 1 ]]; then
        local profile="${HOME}/.bashrc"
        if [[ -f "$profile" ]] && grep -qF "$PREFIX/bin" "$profile"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $profile"
        else
            { echo ""; echo "# soapfuse (bioskills install.sh)"; echo "$path_line"; echo "$perl_line"; } >> "$profile"
            log "已追加 PATH / PERL5LIB 到 $profile"
        fi
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\" 与 export PERL5LIB=\"${perl_lib}:\${PERL5LIB:-}\""
    fi
    log "完成：SOAPfuse 部署于 $PREFIX（用法：perl SOAPfuse-RUN.pl -c config.txt -fd raw_data -l sample.list -o out/）"
}

# ---------------- 主流程 ----------------
log "SOAPfuse $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
log "说明：官方渠道 bioconda/quay/depot 均无 SOAPfuse（2026-09 核实）→ 走官方 SourceForge 预编译包本地部署"
case "$METHOD" in
    local)
        [[ -n "$TARBALL" ]] || die "--method local 需要 --tarball <本地 SOAPfuse 包>"
        deploy "$TARBALL" ;;
    binary)
        deploy "-" ;;
    auto)
        if [[ -n "$TARBALL" ]]; then deploy "$TARBALL"; else deploy "-"; fi ;;
esac
log "安装成功"
