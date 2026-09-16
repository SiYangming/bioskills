#!/usr/bin/env bash
# =============================================================================
# install.sh — Ontologizer 宿主机本地安装脚本（官方公开 jar 直装）
#
# 归属    ：bioskills modules/ontologizer/native/install.sh（native 实现安装方式）
# 路线    ：官方无 conda/容器渠道（bioconda 404 / quay 无 / depot 404，2026-09 核实）；
#           官方以公开 GPL jar 分发（非许可受限）→ 本脚本直接下载官方 jar 到用户前缀：
#             - 命令行 jar ：http://ontologizer.de/cmdline/Ontologizer.jar
#             - 图形界面 jar：http://ontologizer.de/gui/OntologizerGui.jar
#           部署到用户前缀（默认 ~/software/ontologizer-2.1），无需 root、不写 /opt。
#
# 依赖：JRE（早期做法用 JRE 1.7；jar 亦可跑在更新版 JVM 上，实测 OpenJDK 21 可用）。
#   Java WebStart（javaws）或独立 jar；本脚本用独立 jar（javaws 已被现代 JRE 移除）。
#
# 官方来源：
#   homepage : http://ontologizer.de/
#   jar      : http://ontologizer.de/cmdline/Ontologizer.jar（2.1，公开 GPL）
#
# 用法示例：
#   bash install.sh                       # 下载官方 jar 到 ~/software/ontologizer-2.1
#   bash install.sh --prefix ~/opt/onto --force
#   bash install.sh --no-path-update
#   bash install.sh --help
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/ontologizer-$DEFAULT_VERSION}"
CMD_JAR_URL="http://ontologizer.de/cmdline/Ontologizer.jar"
GUI_JAR_URL="http://ontologizer.de/gui/OntologizerGui.jar"
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)      VERSION="${2:?--version 需要版本号}";                 shift 2 ;;
        --prefix)       PREFIX="${2:?--prefix 需要路径}";                     shift 2 ;;
        --jar-url)      CMD_JAR_URL="${2:?--jar-url 需要地址}";               shift 2 ;;
        --gui-jar-url)  GUI_JAR_URL="${2:?--gui-jar-url 需要地址}";           shift 2 ;;
        --profile)      PROFILE="${2:?--profile 需要路径}";                   shift 2 ;;
        --force)        FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)      usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

# ---------------- 前置检查 ----------------
command -v java >/dev/null 2>&1 || die "未检测到 java，请先安装 JRE（如 openjdk-17-jre-headless）"
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
    || die "需要 curl 或 wget 下载官方 jar"

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

TMP="$(mktemp -d)"
cleanup_tmp() { [[ -n "${TMP:-}" ]] && rm -rf "$TMP"; }
trap cleanup_tmp EXIT

fetch() {
    local url="$1" out="$2"
    log "下载 $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$out" "$url"
    else
        wget -qO "$out" "$url"
    fi
}

# ---------------- 下载官方 jar ----------------
fetch "$CMD_JAR_URL" "$TMP/Ontologizer.jar"
fetch "$GUI_JAR_URL" "$PREFIX/OntologizerGui.jar"
install -m 0644 "$TMP/Ontologizer.jar" "$PREFIX/Ontologizer.jar"

# 版本断言：java -jar Ontologizer.jar -v（输出形如 "Ontologizer 2.1 (Build ...)"）
OUT="$(java -jar "$PREFIX/Ontologizer.jar" -v 2>&1 || true)"
printf '  %s\n' "$OUT"
grep -qE "${VERSION//./\.}" <<<"$OUT" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
log "版本校验通过：$VERSION"

rm -rf "$TMP"; TMP=""; trap - EXIT

# ---------------- PATH / ONTOLOGIZER_HOME ----------------
if [[ "$UPDATE_PATH" == 1 ]]; then
    if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
        log "profile 已包含 $PREFIX，跳过写入 $PROFILE"
    else
        {
            echo ""
            echo "# ontologizer (bioskills install.sh)"
            echo "export ONTOLOGIZER_HOME=\"$PREFIX\""
            echo "export PATH=\"$PREFIX:\$PATH\""
        } >> "$PROFILE"
        log "已追加 ONTOLOGIZER_HOME 与 PATH 到 $PROFILE"
    fi
    log "完成：source $PROFILE 后可执行 java -jar \"$PREFIX/Ontologizer.jar\""
else
    log "完成（未改 PATH）：请执行 export ONTOLOGIZER_HOME=\"$PREFIX\""
fi
