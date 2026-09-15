#!/usr/bin/env bash
# =============================================================================
# install.sh — FusionMap 宿主机本地安装脚本（自建兜底路线）
#
# 归属    ：bioskills modules/fusionmap/native/install.sh（native 实现安装方式）
# 迁移形态：AGENT.md §7「查无官方维护 → 自建兜底」
#   - 官方渠道 bioconda → quay.io/biocontainers → depot.galaxyproject.org 均无 FusionMap
#     （2026-09 核实），故无 conda / 官方镜像路线。
#   - 官方发布：OmicSoft 预编译 tar.gz（FusionMap_2015-03-31.tar.gz），部署到用户前缀
#     （默认 ~/software/fusionmap-<ver>，免 root、不写 /opt/biosoft）。
#
# ⚠️ 商业/许可受限：FusionMap 官方声明 free for noncommercial use（非商业免费），商业用途需向
#    OmicSoft 获取授权；官方下载经 Cloudflare/许可页（自动化 curl 通常返回 403），请从官方下载页
#    https://www.omicsoft.com/download/fusionmap/ 获取并接受许可后，用 --tarball 指定本地包。
#    本脚本不内嵌官方包、不再分发软件本体。
#
# Windows 版为 FusionMap.exe（Linux/macOS 下用 mono 运行，需自备 mono）；官方另有 Linux 直接
# 可执行的构建。launcher 会优先使用原生 FusionMap，缺失时用 mono 运行 FusionMap.exe。
#
# 用法示例：
#   bash install.sh --tarball ~/Downloads/FusionMap_2015-03-31.tar.gz   # 从官方下载页取包后本地部署
#   bash install.sh                                                     # 尝试从官方 URL 直接下载（多会 403）
#   bash install.sh --method binary --url <镜像URL>                     # 指定可访问的官方/镜像 URL
#   bash install.sh --prefix ~/opt/fusionmap --force
#   bash install.sh --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2015-03-31"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/fusionmap-$DEFAULT_VERSION}"
METHOD="auto"          # auto | binary | local
URL=""
TARBALL=""
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|binary|local}"; shift 2 ;;
        --url)         URL="${2:?--url 需要下载地址}";        shift 2 ;;
        --tarball)     TARBALL="${2:?--tarball 需要本地包路径}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|binary|local) ;; *) die "--method 仅支持 auto|binary|local（收到: ${METHOD}）" ;; esac
[[ -n "$URL" ]] || URL="http://www.omicsoft.com/downloads/fusionmap/FusionMap_${VERSION}.tar.gz"

# ---------------- 部署融合包 ----------------
deploy() {
    local src="$1"
    log "部署 FusionMap 到: $PREFIX"
    [[ "$FORCE" == 1 ]] && rm -rf "$PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if [[ "$src" == "-" ]]; then
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$tmp/fusionmap.tar.gz" "$URL" \
                || die "官方 URL 下载失败（Cloudflare/许可限制，多为 403）；请从官方下载页获取后改用 --tarball"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$tmp/fusionmap.tar.gz" "$URL" \
                || die "官方 URL 下载失败（Cloudflare/许可限制，多为 403）；请从官方下载页获取后改用 --tarball"
        else
            die "需要 curl 或 wget 下载"
        fi
        src="$tmp/fusionmap.tar.gz"
    else
        [[ -f "$src" ]] || die "本地包不存在: $src"
    fi

    tar -xzf "$src" -C "$PREFIX"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 定位可执行文件（原生 FusionMap 优先，其次 FusionMap.exe）
    local bin_native bin_exe
    bin_native="$(find "$PREFIX" -maxdepth 3 -type f -name FusionMap -perm -111 2>/dev/null | head -1)"
    bin_exe="$(find "$PREFIX" -maxdepth 3 -type f -name 'FusionMap.exe' 2>/dev/null | head -1)"
    [[ -n "$bin_native$bin_exe" ]] || die "包内未找到 FusionMap / FusionMap.exe（URL 或版本号有误？）"

    # 生成 launcher：原生优先，否则 mono 运行 .exe
    mkdir -p "$PREFIX/bin"
    {
      echo '#!/usr/bin/env bash'
      echo '# FusionMap launcher（原生优先；否则 mono FusionMap.exe）'
      if [[ -n "$bin_native" ]]; then echo "if [[ -x \"$bin_native\" ]]; then exec \"$bin_native\" \"\$@\"; fi"; fi
      if [[ -n "$bin_exe" ]]; then
        echo "if [[ -f \"$bin_exe\" ]]; then"
        echo "    command -v mono >/dev/null 2>&1 || { echo 'FusionMap.exe 需 mono（apt install mono-runtime / brew install mono）' >&2; exit 127; }"
        echo "    exec mono \"$bin_exe\" \"\$@\""
        echo "fi"
      fi
      echo 'echo "FusionMap 可执行文件未找到" >&2; exit 127'
    } > "$PREFIX/bin/FusionMap"
    chmod 0755 "$PREFIX/bin/FusionMap"

    if [[ -n "$bin_native" ]]; then
        log "使用原生 FusionMap: $bin_native"
    else
        log "仅发现 Windows 版 FusionMap.exe：$bin_exe（运行时需 mono）"
        command -v mono >/dev/null 2>&1 || warn "未检测到 mono，请安装（Debian/Ubuntu: apt install mono-runtime；macOS: brew install mono）"
    fi

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        local profile="${HOME}/.bashrc"
        if [[ -f "$profile" ]] && grep -qF "$PREFIX/bin" "$profile"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $profile"
        else
            { echo ""; echo "# fusionmap (bioskills install.sh)"; echo "$line"; } >> "$profile"
            log "已追加 PATH 到 $profile"
        fi
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
    log "完成：FusionMap 部署于 $PREFIX（⚠️ 商业/许可受限，仅限非商业用途）"
}

# ---------------- 主流程 ----------------
log "FusionMap $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
log "说明：官方渠道 bioconda/quay/depot 均无 FusionMap（2026-09 核实）→ 走官方预编译包本地部署"
case "$METHOD" in
    local)
        [[ -n "$TARBALL" ]] || die "--method local 需要 --tarball <本地 fusionmap 包>"
        deploy "$TARBALL" ;;
    binary)
        deploy "-" ;;
    auto)
        if [[ -n "$TARBALL" ]]; then
            deploy "$TARBALL"
        else
            deploy "-"
        fi ;;
esac
log "安装成功"
