#!/usr/bin/env bash
# =============================================================================
# install.sh — TMHMM 2.0c 宿主机本地安装脚本（⚠️ 许可受限：需自备官方授权 tarball）
#
# 归属    ：bioskills modules/tmhmm/native/install.sh（native 实现安装方式）
# 路线    ：官方无 conda/容器渠道（bioconda 404 / quay 无 / depot 404，2026-09 核实），
#           且官方 tarball 需以 edu 邮箱向 DTU 申请 → 本脚本仅消费「用户自备」的授权包：
#             - --archive <tmhmm-2.0c.Linux.tar.gz>    直接使用本地授权 tarball（推荐）
#             - --url <mirror-url>                      使用用户自行托管的可用副本
#           部署到用户前缀（默认 ~/software/tmhmm-<ver>），无需 root、不写 /opt。
#           安装后自动修正 Perl 解释器路径（13.md：s#/usr/local/bin/perl#/usr/bin/perl#）。
#
# ⚠️ 许可限制：TMHMM 由 DTU 授权，需用 edu 邮箱在官方软件页申请下载链接，禁止商用。
#    官方申请入口：https://services.healthtech.dtu.dk/services/software.php
#    本脚本不提供、也不伪造任何官方直链。
#
# 官方来源：
#   homepage : https://services.healthtech.dtu.dk/services/TMHMM-2.0/
#   申请入口 : https://services.healthtech.dtu.dk/services/software.php
#
# 用法示例：
#   bash install.sh --archive ~/software/tmhmm-2.0c.Linux.tar.gz
#   bash install.sh --url https://<your-mirror>/tmhmm-2.0c.Linux.tar.gz
#   bash install.sh --archive tmhmm-2.0c.Linux.tar.gz --prefix ~/software/tmhmm --force
#   bash install.sh --help
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.0c"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/tmhmm-$DEFAULT_VERSION}"
ARCHIVE=""
URL=""
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
APPLY_URL_PAGE="https://services.healthtech.dtu.dk/services/software.php"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)     ARCHIVE="${2:?--archive 需要本地 tarball 路径}"; shift 2 ;;
        --url)         URL="${2:?--url 需要下载地址}";                  shift 2 ;;
        --version)     VERSION="${2:?--version 需要版本号}";             shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";                 shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";               shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

[[ -n "$ARCHIVE" || -n "$URL" ]] || die "需提供 --archive <tmhmm-${VERSION}.Linux.tar.gz> 或 --url <可下载地址>。
  官方 tarball 为许可受限资产，请先用 edu 邮箱在 ${APPLY_URL_PAGE} 申请，本脚本不提供官方直链。"

# ---------------- 目标位置准备 ----------------
if [[ -e "$PREFIX" ]]; then
    if [[ "$FORCE" == 1 ]]; then
        warn "前缀 $PREFIX 已存在（--force），删除重建"
        rm -rf "$PREFIX"
    else
        die "前缀 $PREFIX 已存在；加 --force 重建，或改用 --prefix 指定其它目录"
    fi
fi
mkdir -p "$PREFIX"

# ---------------- Perl 守卫（TMHMM 为 Perl 脚本） ----------------
command -v perl >/dev/null 2>&1 || die "未检测到 perl，请先安装 Perl（TMHMM 为 Perl 脚本）"

# ---------------- 获取 tarball ----------------
LOCAL_TARBALL=""
TMP=""
cleanup_tmp() { [[ -n "${TMP:-}" ]] && rm -rf "$TMP"; }
trap cleanup_tmp EXIT

if [[ -n "$ARCHIVE" ]]; then
    [[ -f "$ARCHIVE" ]] || die "--archive 指定的文件不存在: $ARCHIVE"
    LOCAL_TARBALL="$ARCHIVE"
    log "使用本地授权 tarball: $ARCHIVE"
else
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
        || die "需要 curl 或 wget 下载 --url 指定的 tarball"
    TMP="$(mktemp -d)"
    LOCAL_TARBALL="$TMP/tmhmm.tar.gz"
    log "下载用户自托管副本: $URL"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$LOCAL_TARBALL" "$URL"
    else
        wget -qO "$LOCAL_TARBALL" "$URL"
    fi
fi

# ---------------- 解压部署 ----------------
log "解压到前缀: $PREFIX"
tar -xzf "$LOCAL_TARBALL" -C "$PREFIX" --strip-components=1

# 修正 Perl 解释器路径（13.md 关键步骤：bin/tmhmm* 里 /usr/local/bin/perl -> /usr/bin/perl）
log "修正 Perl 解释器路径（/usr/local/bin/perl -> /usr/bin/perl）"
perl -p -i -e 's#/usr/local/bin/perl#/usr/bin/perl#' "$PREFIX"/bin/tmhmm* 2>/dev/null || true

BIN="$PREFIX/bin/tmhmm"
[[ -x "$BIN" ]] || die "解压后未找到可执行文件 bin/tmhmm（tarball 结构或版本号有误？）"

# 版本断言：tmhmm -version（输出形如 "TMHMM 2.0c"）
OUT="$("$BIN" -version 2>&1 || true)"
printf '  %s\n' "$OUT"
grep -qE "${VERSION//./\.}" <<<"$OUT" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
log "版本校验通过：$VERSION"

if [[ -n "$TMP" ]]; then rm -rf "$TMP"; TMP=""; trap - EXIT; fi

# ---------------- PATH ----------------
if [[ "$UPDATE_PATH" == 1 ]]; then
    LINE="export PATH=\"$PREFIX/bin:\$PATH\""
    if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
        log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
    else
        { echo ""; echo "# tmhmm (bioskills install.sh)"; echo "$LINE"; } >> "$PROFILE"
        log "已追加 PATH 到 $PROFILE"
    fi
    log "完成：source $PROFILE 后执行 tmhmm 即可"
else
    log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
fi
