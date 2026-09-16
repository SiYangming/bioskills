#!/usr/bin/env bash
# =============================================================================
# install.sh — GO class 宿主机本地安装脚本（⚠️ 无官方渠道：需自备 go_class.tar.gz）
#
# 归属    ：bioskills modules/go_class/native/install.sh（native 实现安装方式）
# 路线    ：官方无 conda/容器渠道（bioconda 404 / quay 无 / depot 404，2026-09 核实）；
#           分发介质为本地 tar 包（go_class.tar.gz）、无官方下载页 → 本脚本仅消费
#           「用户自备」的 tar 包：
#             - --archive <go_class.tar.gz>   使用本地 tar 包（推荐）
#             - --url <mirror-url>             使用用户自行托管的可用副本
#           部署到用户前缀（默认 ~/software/go_class），无需 root、不写 /opt。
#           可选：--obo <go.obo> 安装后立即运行 make_go_class_config.pl 初始化配置。
#
# ⚠️ 依赖 Perl（go_class 全为 Perl 脚本）。
#    tar zxf go_class.tar.gz -C /opt/biosoft/ && cd bin/ && ./make_go_class_config.pl go.obo
#
# 用法示例：
#   bash install.sh --archive ~/software/go_class.tar.gz
#   bash install.sh --archive go_class.tar.gz --obo ~/data/go.obo
#   bash install.sh --url https://<your-mirror>/go_class.tar.gz --prefix ~/software/go_class --force
#   bash install.sh --help
# =============================================================================
set -euo pipefail

# ---------------- 默认值（版本与 meta.yaml software_versions.native 对齐：未标注） ----------------
PREFIX="${PREFIX:-$HOME/software/go_class}"
ARCHIVE=""
URL=""
OBO=""
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)     ARCHIVE="${2:?--archive 需要本地 tar 包路径}"; shift 2 ;;
        --url)         URL="${2:?--url 需要下载地址}";                shift 2 ;;
        --obo)         OBO="${2:?--obo 需要 go.obo 路径}";            shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";               shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";             shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

[[ -n "$ARCHIVE" || -n "$URL" ]] || die "需提供 --archive <go_class.tar.gz> 或 --url <可下载地址>。
  go_class 无官方下载页（本地 tar 包分发），请自备该 tar 包。"

# ---------------- Perl 守卫 ----------------
command -v perl >/dev/null 2>&1 || die "未检测到 perl，请先安装 Perl（go_class 全为 Perl 脚本）"

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

# ---------------- 获取 tar 包 ----------------
LOCAL_TARBALL=""
TMP=""
cleanup_tmp() { [[ -n "${TMP:-}" ]] && rm -rf "$TMP"; }
trap cleanup_tmp EXIT

if [[ -n "$ARCHIVE" ]]; then
    [[ -f "$ARCHIVE" ]] || die "--archive 指定的文件不存在: $ARCHIVE"
    LOCAL_TARBALL="$ARCHIVE"
    log "使用本地 tar 包: $ARCHIVE"
else
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
        || die "需要 curl 或 wget 下载 --url 指定的 tar 包"
    TMP="$(mktemp -d)"
    LOCAL_TARBALL="$TMP/go_class.tar.gz"
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
[[ -x "$PREFIX/bin/make_go_class_config.pl" ]] || [[ -f "$PREFIX/bin/make_go_class_config.pl" ]] \
    || die "解压后未找到 bin/make_go_class_config.pl（tar 包结构有误？）"
chmod +x "$PREFIX"/bin/*.pl 2>/dev/null || true
chmod +x "$PREFIX"/svg/*.pl 2>/dev/null || true

log "脚本清单："
ls -1 "$PREFIX"/bin/*.pl 2>/dev/null | sed 's/^/  /' || true
ls -1 "$PREFIX"/svg/*.pl 2>/dev/null | sed 's/^/  /' || true

# ---------------- 可选：初始化 GO 配置 ----------------
if [[ -n "$OBO" ]]; then
    [[ -f "$OBO" ]] || die "--obo 指定的文件不存在: $OBO"
    log "初始化 GO 配置：make_go_class_config.pl $OBO"
    ( cd "$PREFIX/bin" && perl ./make_go_class_config.pl "$OBO" )
    log "已生成 go_class 配置文件"
fi

if [[ -n "$TMP" ]]; then rm -rf "$TMP"; TMP=""; trap - EXIT; fi

# ---------------- PATH（bin 与 svg 两个目录） ----------------
if [[ "$UPDATE_PATH" == 1 ]]; then
    if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
        log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
    else
        {
            echo ""
            echo "# go_class (bioskills install.sh)"
            echo "export GO_CLASS_HOME=\"$PREFIX\""
            echo "export PATH=\"$PREFIX/bin:$PREFIX/svg:\$PATH\""
        } >> "$PROFILE"
        log "已追加 PATH（bin+svg）与 GO_CLASS_HOME 到 $PROFILE"
    fi
    log "完成：source $PROFILE 后即可使用 annot2wego.pl / go_svg.pl 等"
else
    log "完成（未改 PATH）：请执行 export GO_CLASS_HOME=\"$PREFIX\" && export PATH=\"$PREFIX/bin:$PREFIX/svg:\$PATH\""
fi
