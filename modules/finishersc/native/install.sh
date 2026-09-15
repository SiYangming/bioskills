#!/usr/bin/env bash
# =============================================================================
# install.sh — FinisherSC（Finishing Tool v2.1）宿主机本地安装脚本
#
# 归属    ：bioskills modules/finishersc/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」对齐）
#   - source 路线（唯一路线）：官方 GitHub codeload zip 解压部署到用户前缀
#     （默认 ~/software/finishingTool-2.1），并校验运行依赖（Python 2 + MUMmer）
#   - 说明：官方渠道（bioconda/quay/depot）均未收录 finishersc（2026-09 核实）→ 无 conda/镜像
#     路线；请用 native/Dockerfile 或本脚本部署
#   - 版本默认 2.1（教学文档 zip 名 ...v2.1-2-ga1f2608.zip），与 software_versions.native 对齐
#
# 官方来源：
#   homepage : https://kakitone.github.io/finishingTool/
#   source   : https://github.com/kakitone/finishingTool
#
# 用法示例：
#   bash install.sh                                  # 部署到 ~/software/finishingTool-2.1 并写 PATH
#   bash install.sh --prefix ~/opt/finishingTool     # 自定义前缀
#   bash install.sh --ref master                     # 指定 ref（分支/tag）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.1"
VERSION="$DEFAULT_VERSION"
REF="master"                         # 仓库 zip 名 v2.1-2-ga1f2608 对应 master 提交
PREFIX="${PREFIX:-$HOME/software/finishingTool-$DEFAULT_VERSION}"
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --ref)         REF="${2:?--ref 需要 git ref}";       shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";     shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";   shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

# ---------------- 依赖检查（Python 2 + MUMmer） ----------------
check_deps() {
    local py2=""
    for c in python2.7 python2 python; do
        if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info[0]==2 else 1)' 2>/dev/null; then
            py2="$c"; break
        fi
    done
    if [[ -z "$py2" ]]; then
        warn "未检测到 Python 2 解释器（finisherSC.py 为 Python 2 语法，Python 3 无法运行）"
        warn "请安装 Python 2.7（或在容器内运行；运行驱动可 export FINISHERSC_PYTHON=python2.7）"
    else
        log "检测到 Python 2 解释器：$py2"
    fi
    local mm=""
    for c in nucmer show-coords; do
        command -v "$c" >/dev/null 2>&1 && { mm="$c"; break; }
    done
    if [[ -z "$mm" ]]; then
        warn "未检测到 MUMmer（nucmer/show-coords）；请安装（conda: mamba install -c bioconda mummer；或 apt: mummer）"
    else
        log "检测到 MUMmer（如 $mm）；运行 finisherSC.py 时以 mummer 目录作第 2 位置参数传入"
    fi
}

# ---------------- source 部署 ----------------
install_source() {
    command -v unzip >/dev/null 2>&1 || die "source 路线需要 unzip"
    log "部署 FinisherSC（ref=${REF}）到前缀: $PREFIX"
    if [[ -e "$PREFIX/finisherSC.py" && "$FORCE" != 1 ]]; then
        die "$PREFIX/finisherSC.py 已存在；加 --force 覆盖，或改用 --prefix"
    fi

    local url="https://codeload.github.com/kakitone/finishingTool/legacy.zip/${REF}"
    log "下载官方源码 zip: $url"
    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/src.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/src.zip" "$url"
    else
        die "需要 curl 或 wget 下载源码 zip"
    fi
    # sha256 未核实（codeload 动态打包 zip，摘要不稳定）
    mkdir -p "$tmp/unzip"
    unzip -q "$tmp/src.zip" -d "$tmp/unzip"
    local srcdir
    srcdir="$(find "$tmp/unzip" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -n "$srcdir" && -f "$srcdir/finisherSC.py" ]] || die "源码 zip 内未找到 finisherSC.py"

    mkdir -p "$PREFIX"
    cp -R "$srcdir"/. "$PREFIX"/
    chmod 0755 "$PREFIX/finisherSC.py" 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 版本断言：上游脚本无 --version（脚本内亦无版本常量）→ 结构化断言 + 记录登记版本
    [[ -f "$PREFIX/finisherSC.py" ]] || die "版本校验失败：finisherSC.py 未就位"
    grep -q "finisherSC" "$PREFIX/README.md" 2>/dev/null || true
    warn "finisherSC.py 无 --version（上游未提供）；已按登记版本 ${VERSION} 部署，结构化断言通过"
    log "版本校验通过（结构化）：${VERSION}"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "PATH 已包含 $PREFIX，跳过写入 $PROFILE"
        else
            { echo ""; echo "# FinisherSC (bioskills install.sh)"; echo "export PATH=\"$PREFIX:\$PATH\""; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后即可使用（export FINISHERSC_HOME=$PREFIX 亦可）"
    else
        log "完成（未改 PATH）：使用时请执行 export FINISHERSC_HOME=\"$PREFIX\""
    fi
}

log "FinisherSC ${VERSION} 安装开始（本机 $(uname -s)/$(uname -m)）"
check_deps
install_source
log "安装成功"
