#!/usr/bin/env bash
# =============================================================================
# install.sh — Blast2GO（客户端 3.3 + b2g4pipe v2.5 命令行）宿主机本地安装脚本
#
# 归属    ：bioskills modules/blast2go/native/install.sh（native 实现安装方式）
# 迁移形态：Blast2GO 许可受限（需在官网注册/订阅获取发行包），官方渠道无镜像/无 conda
#          （2026-09 核实：bioconda 404 / quay.io/biocontainers 无仓库 /
#          depot.galaxyproject.org 404），故本脚本走「用户自备发行包」部署到用户级前缀：
#   - 命令行 b2g4pipe_v2.5.zip  → $PREFIX/b2g4pipe
#   - 图形客户端 Blast2GO_unix_3_3_x64.zip → $PREFIX/Blast2GO（best-effort 静默安装）
#   - 本地注释库 local_b2g_db.tar.gz → $PREFIX/blast2go-db（可选；依赖 MySQL/Perl）
#   - 默认 $PREFIX=~/software/blast2go-<ver>，无需 root、不写 /opt
#   - 因发行包为注册/订阅专属、无公开直链，本脚本不内嵌 sha256
#
# 官方来源：
#   homepage  : https://www.blast2go.com/
#   下载/许可  : https://www.biobam.com/download-blast2go/
#
# 用法示例：
#   bash install.sh --b2g4pipe-zip ~/software/b2g4pipe_v2.5.zip
#   bash install.sh --b2g4pipe-zip ~/software/b2g4pipe_v2.5.zip --client-zip ~/software/Blast2GO_unix_3_3_x64.zip
#   bash install.sh --b2g4pipe-zip ... --db-tarball ~/software/local_b2g_db.tar.gz
#   bash install.sh --prefix ~/opt/blast2go --db-name b2gdb --db-host localhost --force
# =============================================================================
set -euo pipefail

# ---------------- 默认值 ----------------
DEFAULT_VERSION="3.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/blast2go-$DEFAULT_VERSION}"
CLIENT_ZIP=""
B2G_ZIP=""
DB_TARBALL=""
DB_NAME="b2gdb"
DB_HOST="localhost"
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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
        --client-zip)   CLIENT_ZIP="${2:?--client-zip 需要文件路径}"; shift 2 ;;
        --b2g4pipe-zip) B2G_ZIP="${2:?--b2g4pipe-zip 需要文件路径}";   shift 2 ;;
        --db-tarball)   DB_TARBALL="${2:?--db-tarball 需要文件路径}"; shift 2 ;;
        --version)      VERSION="${2:?--version 需要版本号}";         shift 2 ;;
        --prefix)       PREFIX="${2:?--prefix 需要路径}";              shift 2 ;;
        --db-name)      DB_NAME="${2:?--db-name 需要数据库名}";        shift 2 ;;
        --db-host)      DB_HOST="${2:?--db-host 需要主机名}";          shift 2 ;;
        --profile)      PROFILE="${2:?--profile 需要路径}";             shift 2 ;;
        --force)        FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)      usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

[[ -n "$CLIENT_ZIP$B2G_ZIP$DB_TARBALL" ]] || {
    cat >&2 <<'MSG'
Blast2GO 许可受限（需在官网注册/订阅获取发行包），官方渠道无镜像/无 conda（2026-09 核实
bioconda 404 / quay 无仓库 / depot 404），故需自备发行包后执行，例如：
  bash install.sh --b2g4pipe-zip ~/software/b2g4pipe_v2.5.zip \
                  --client-zip   ~/software/Blast2GO_unix_3_3_x64.zip
下载/许可：https://www.biobam.com/download-blast2go/
MSG
    die "至少需要 --b2g4pipe-zip / --client-zip / --db-tarball 之一"
}

OS="$(uname -s)"; ARCH="$(uname -m)"

# ---------------- Java 断言 ----------------
assert_java() {
    command -v java >/dev/null 2>&1 || die "未找到 java：Blast2GO / b2g4pipe 依赖 Java（推荐 JDK/JRE 11/17）"
    log "验证 Java："
    java -version 2>&1 | sed 's/^/  /'
}

# ---------------- 部署 b2g4pipe（命令行） ----------------
deploy_b2g4pipe() {
    local zip="$1"
    [[ -f "$zip" ]] || die "找不到 b2g4pipe zip: $zip"
    command -v unzip >/dev/null 2>&1 || die "需要 unzip"
    log "解压 b2g4pipe -> $PREFIX/b2g4pipe"
    rm -rf "$PREFIX/b2g4pipe"
    mkdir -p "$PREFIX/b2g4pipe"
    unzip -q "$zip" -d "$PREFIX/b2g4pipe"
    # 归档可能含顶层 b2g4pipe/ 目录，压平到 $PREFIX/b2g4pipe
    if [[ ! -f "$PREFIX/b2g4pipe/b2gPipe.properties" ]]; then
        local inner
        inner="$(find "$PREFIX/b2g4pipe" -maxdepth 2 -type f -name b2gPipe.properties | head -1)"
        if [[ -n "$inner" ]]; then
            local d; d="$(dirname "$inner")"
            shopt -s dotglob
            mv "$d"/* "$PREFIX/b2g4pipe/"
            shopt -u dotglob
        fi
    fi
    [[ -f "$PREFIX/b2g4pipe/b2gPipe.properties" ]] || warn "未找到 b2gPipe.properties（发行包布局可能不同）"
    # 设置数据库连接（文档：Dbacces.dbname / Dbacces.dbhost）
    if [[ -f "$PREFIX/b2g4pipe/b2gPipe.properties" ]]; then
        perl -p -i -e "s/^Dbacces.dbname=.*/Dbacces.dbname=${DB_NAME}/" "$PREFIX/b2g4pipe/b2gPipe.properties"
        perl -p -i -e "s/^Dbacces.dbhost=.*/Dbacces.dbhost=${DB_HOST}/" "$PREFIX/b2g4pipe/b2gPipe.properties"
        log "已设置 b2gPipe.properties：Dbacces.dbname=${DB_NAME} Dbacces.dbhost=${DB_HOST}"
    fi
}

# ---------------- 部署 Blast2GO 客户端（GUI） ----------------
deploy_client() {
    local zip="$1"
    [[ -f "$zip" ]] || die "找不到 Blast2GO 客户端 zip: $zip"
    command -v unzip >/dev/null 2>&1 || die "需要 unzip"
    local tmp; tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log "解压 Blast2GO 客户端发行包 -> $tmp"
    unzip -q "$zip" -d "$tmp"
    local installer
    installer="$(find "$tmp" -maxdepth 2 -type f -name 'Blast2GO*installer*.sh' -o -maxdepth 2 -type f -name 'Blast2GO_unix*.sh' | head -1)"
    rm -rf "$PREFIX/Blast2GO"
    if [[ -n "$installer" ]]; then
        log "静默安装客户端（install4j -q -dir）：$installer"
        if sh "$installer" -q -dir "$PREFIX/Blast2GO" >/dev/null 2>&1; then
            log "客户端已安装到 $PREFIX/Blast2GO"
        else
            warn "静默安装失败（可能需要图形界面/交互）；请手动运行：sh $installer -dir $PREFIX/Blast2GO"
        fi
    else
        mkdir -p "$PREFIX/Blast2GO"
        cp -R "$tmp/." "$PREFIX/Blast2GO/"
        warn "未找到自动安装脚本，已解压到 $PREFIX/Blast2GO（GUI 客户端请在有桌面环境处运行）"
    fi
    rm -rf "$tmp"; trap - EXIT
}

# ---------------- 部署本地注释库（可选） ----------------
deploy_db() {
    local tarball="$1"
    [[ -f "$tarball" ]] || die "找不到注释库 tarball: $tarball"
    log "解压 local_b2g_db -> $PREFIX/blast2go-db"
    rm -rf "$PREFIX/blast2go-db"
    mkdir -p "$PREFIX/blast2go-db"
    tar -xzf "$tarball" -C "$PREFIX/blast2go-db"
    if [[ ! -f "$PREFIX/blast2go-db/install_blast2goDB.sh" ]]; then
        local inner
        inner="$(find "$PREFIX/blast2go-db" -maxdepth 2 -type f -name install_blast2goDB.sh | head -1)"
        [[ -n "$inner" ]] && mv "$(dirname "$inner")"/* "$PREFIX/blast2go-db/" 2>/dev/null || true
    fi
    log "注释库脚本就绪：perl $PREFIX/blast2go-db/install_blast2goDB.sh（依赖 MySQL + Perl DBI/DBD::mysql）"
    command -v mysql >/dev/null 2>&1 || warn "未检测到 mysql 客户端（安装本地注释库需 MySQL）"
}

# ---------------- 主流程 ----------------
log "Blast2GO（$VERSION）安装开始（本机 ${OS}/${ARCH}）"
assert_java
mkdir -p "$PREFIX"
[[ -n "$B2G_ZIP" ]]   && deploy_b2g4pipe "$B2G_ZIP"
[[ -n "$CLIENT_ZIP" ]] && deploy_client "$CLIENT_ZIP"
[[ -n "$DB_TARBALL" ]] && deploy_db "$DB_TARBALL"

if [[ "$UPDATE_PATH" == 1 ]]; then
    lines=()
    [[ -d "$PREFIX/b2g4pipe" ]]    && lines+=("export B2G4PIPE_HOME=\"$PREFIX/b2g4pipe\"")
    [[ -d "$PREFIX/Blast2GO" ]]    && lines+=("export BLAST2GO_HOME=\"$PREFIX/Blast2GO\"")
    [[ ${#lines[@]} -gt 0 ]] || warn "无可写入的环境变量（未部署 b2g4pipe / 客户端）"
    if [[ ${#lines[@]} -gt 0 ]]; then
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "环境变量已包含，跳过写入 $PROFILE"
        else
            { echo ""; echo "# blast2go (bioskills install.sh)"; printf '%s\n' "${lines[@]}"; } >> "$PROFILE"
            log "已追加 B2G4PIPE_HOME / BLAST2GO_HOME 到 $PROFILE"
        fi
    fi
    log "完成：重新登录或 source $PROFILE 后执行 python main.py annot/install_db/client 即可"
else
    log "完成（未改环境）：使用时请手动 export B2G4PIPE_HOME / BLAST2GO_HOME"
fi
log "安装成功"
