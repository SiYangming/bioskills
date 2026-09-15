#!/usr/bin/env bash
# =============================================================================
# install.sh — ANNOVAR 宿主机本地安装脚本
#
# 归属    ：bioskills modules/annovar/native/install.sh（native 实现安装方式）
# 迁移形态：ANNOVAR 官方渠道无镜像/无 conda（2026-09 核实：bioconda 404 /
#          quay.io/biocontainers 无仓库 / depot.galaxyproject.org 404），
#          且需在官网注册才能获取下载链接（许可受限）→ 本脚本走「用户提供
#          tarball / 注册邮件里的个人下载 URL」部署到用户级前缀。
#
#   - tarball 路线：--tarball /path/to/annovar.latest.tar.gz（已注册下载的文件）
#   - url     路线：--url "<注册邮件里的个人下载链接>"（curl/wget 拉取）
#   - 默认 $PREFIX=~/software/annovar-<ver>，无需 root、不写 /opt
#   - 因个人下载链接为注册专属、版本以 latest 分发，本脚本不内嵌 sha256
#
# 官方来源：
#   homepage  : https://annovar.openbioinformatics.org/
#   注册下载   : https://www.openbioinformatics.org/annovar/annovar_download_form.php
#
# 用法示例：
#   bash install.sh --tarball ~/Downloads/annovar.latest.tar.gz
#   bash install.sh --url "http://www.openbioinformatics.org/annovar/download/<token>/annovar.latest.tar.gz"
#   bash install.sh --prefix ~/opt/annovar --force
#   bash install.sh --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值 ----------------
DEFAULT_VERSION="latest"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/annovar-$DEFAULT_VERSION}"
TARBALL=""
URL=""
METHOD="auto"          # auto | tarball | url
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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
        --tarball)     TARBALL="${2:?--tarball 需要文件路径}"; METHOD="tarball"; shift 2 ;;
        --url)         URL="${2:?--url 需要下载链接}";         METHOD="url"; shift 2 ;;
        --version)     VERSION="${2:?--version 需要版本号}";   shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";        shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";       shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|tarball|url) ;; *) die "未知安装方式: ${METHOD}" ;; esac

OS="$(uname -s)"; ARCH="$(uname -m)"

registration_help() {
    cat >&2 <<'MSG'
ANNOVAR 需在官网注册后获取下载链接（许可受限；学术/非营利免费，商用需授权）：
  1. 打开注册表单 https://www.openbioinformatics.org/annovar/annovar_download_form.php
  2. 用机构邮箱注册，收到含个人下载链接的邮件（annovar.latest.tar.gz）
  3. 重新执行：bash install.sh --tarball ~/Downloads/annovar.latest.tar.gz
     或：      bash install.sh --url "<邮件中的个人下载链接>"

说明：ANNOVAR 不在 bioconda / quay.io/biocontainers / depot.galaxyproject.org 分发
（2026-09 已核实 404），故无法通过 conda / 官方镜像安装，只能走上述注册路线。
MSG
}

# ---------------- 部署（解压 tar.gz 到前缀） ----------------
deploy_tarball() {
    local tarball="$1"
    command -v perl >/dev/null 2>&1 || die "未检测到 perl（ANNOVAR 为 Perl 脚本集，需 Perl 5 >= 5.8.8）"
    [[ -f "$tarball" ]] || die "找不到 tarball: $tarball"
    log "解压 $tarball -> $PREFIX"
    if [[ -d "$PREFIX" && "$FORCE" != 1 ]]; then
        if [[ -f "$PREFIX/table_annovar.pl" ]]; then
            die "$PREFIX 已存在 ANNOVAR；加 --force 覆盖，或改用 --prefix 指定其它目录"
        fi
    fi
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    tar -xzf "$tarball" -C "$tmp"

    # 归档通常含顶层 annovar/ 目录；定位含 table_annovar.pl 的目录
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 2 -type f -name table_annovar.pl | head -1)"
    [[ -n "$srcdir" ]] || die "tar 包内未找到 table_annovar.pl（文件是否为 annovar.latest.tar.gz？）"
    srcdir="$(dirname "$srcdir")"
    log "检测到 ANNOVAR 目录: $srcdir"

    rm -rf "$PREFIX"
    mkdir -p "$PREFIX"
    cp -R "$srcdir/." "$PREFIX/"
    chmod +x "$PREFIX"/*.pl 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -f "$PREFIX/table_annovar.pl" ]] || die "部署后未找到 $PREFIX/table_annovar.pl"
    log "验证：perl $PREFIX/table_annovar.pl --help"
    perl "$PREFIX/table_annovar.pl" --help 2>&1 | head -n 2 | sed 's/^/  /' || true

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export ANNOVAR_HOME=\"$PREFIX\""
        local line2="export PATH=\"\$ANNOVAR_HOME:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "ANNOVAR_HOME 已包含，跳过写入 $PROFILE"
        else
            { echo ""; echo "# annovar (bioskills install.sh)"; echo "$line"; echo "$line2"; } >> "$PROFILE"
            log "已追加 ANNOVAR_HOME / PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 table_annovar.pl 即可"
    else
        log "完成（未改环境）：使用时请执行 export ANNOVAR_HOME=\"$PREFIX\""
    fi
}

# ---------------- 主流程 ----------------
log "ANNOVAR（$VERSION）安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    tarball)
        deploy_tarball "$TARBALL" ;;
    url)
        [[ -n "$URL" ]] || die "--url 需要下载链接"
        mkdir -p "$(dirname "$PREFIX")" 2>/dev/null || true
        tmpdl="$(mktemp -d)"
        trap 'rm -rf "$tmpdl"' EXIT
        log "下载注册链接: $URL"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$tmpdl/annovar.latest.tar.gz" "$URL" || die "下载失败（链接过期？请重新注册/登录获取）"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$tmpdl/annovar.latest.tar.gz" "$URL" || die "下载失败（链接过期？请重新注册/登录获取）"
        else
            die "需要 curl 或 wget 下载"
        fi
        warn "注册链接为个人专属、latest 分发，跳过 sha256 校验（可自行核对邮件/官网摘要）"
        deploy_tarball "$tmpdl/annovar.latest.tar.gz"
        rm -rf "$tmpdl"; trap - EXIT ;;
    auto)
        registration_help
        die "auto 模式无法自动获取 ANNOVAR（需注册）；请按上方提示提供 --tarball 或 --url" ;;
esac
log "安装成功"
