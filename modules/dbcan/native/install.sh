#!/usr/bin/env bash
# =============================================================================
# install.sh — dbCAN V9（经典 CAZy 数据库 + 脚本）宿主机本地安装脚本
#
# 归属    ：bioskills modules/dbcan/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「安装方式（本地）」对齐）
#   - db    路线（默认）：从 bcb.unl.edu/dbCAN2 下载经典 V9 数据库 + 脚本，本地建库
#     （hmmpress / makeblastdb / diamond makedb），部署到用户级前缀
#     默认 ~/software/dbCAN_v9.0（无需 root、不写 /opt/biosoft）
#   - conda 路线（备选）：安装 dbCAN2 下游封装 run_dbcan（bioconda::dbcan=5.2.9）
#   - 版本默认 9.0（数据库包），与 modules/dbcan/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://bcb.unl.edu/dbCAN2/index.php
#   download : http://bcb.unl.edu/dbCAN2/download/
#   bioconda : https://anaconda.org/bioconda/dbcan （=run_dbcan，与经典 V9 非同一代）
#
# 数据体积提示：dbCAN-HMMdb-V9 + CAZyDB.07312020.fa 合计约数百 MB（解压后更大），
#              建库产物（hmmpress / blastdb / .dmnd）再增数百 MB。
#
# 用法示例：
#   bash install.sh                                   # auto：走 db 路线（下载 + 建库）
#   bash install.sh --method db                        # 强制下载 + 建库（等价 binary 别名）
#   bash install.sh --method conda --conda-env dbc     # 安装 run_dbcan（bioconda::dbcan=5.2.9）
#   bash install.sh --prefix ~/opt/dbCAN_v9.0          # 自定义数据库前缀
#   bash install.sh --no-build                        # 仅下载，不执行建库工具
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="9.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/dbCAN_v$DEFAULT_VERSION}"
CONDA_ENV="dbcan"
METHOD="auto"          # auto | db（binary 别名）| conda
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
DO_BUILD=1

BASE_URL="http://bcb.unl.edu/dbCAN2/download"
HMM_URL="$BASE_URL/dbCAN-HMMdb-V9.txt"
FASTA_URL="$BASE_URL/CAZyDB.07312020.fa"
PARSER_URL="$BASE_URL/Databases/V9/hmmscan-parser.sh"
README_URL="$BASE_URL/Databases/V9/readme.txt"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|db|conda}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-build)    DO_BUILD=0; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

[[ "$METHOD" == "binary" ]] && METHOD="db"   # 兼容 --method binary（dbCAN V9 无单一二进制）
case "$METHOD" in auto|db|conda) ;; *) die "--method 仅支持 auto|db|conda（收到: ${METHOD}）" ;; esac
[[ "$VERSION" == "$DEFAULT_VERSION" ]] || die "本脚本仅内置 dbCAN V${DEFAULT_VERSION} 的官方下载 URL；如需其它版本请手动下载建库"

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

need() { command -v "$1" >/dev/null 2>&1 || die "缺少依赖工具 $1（建库需要 hmmer / ncbi-blast+ / diamond）"; }

# ---------------- 路线 A：下载经典 V9 数据库 + 脚本并建库 ----------------
install_db() {
    log "下载 dbCAN V9 数据库 + 脚本 -> ${PREFIX}（版本 ${VERSION}）"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    { command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; } || die "需要 curl 或 wget 下载数据库"
    # 统一用函数封装下载，兼容 curl / wget
    fetch() {  # fetch <url> <dest>
        if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"; else wget -qO "$2" "$1"; fi
    }

    fetch "$HMM_URL"    "$tmp/dbCAN-HMMdb-V9.txt"
    fetch "$FASTA_URL"  "$tmp/CAZyDB.07312020.fa"
    fetch "$PARSER_URL" "$tmp/hmmscan-parser.sh"
    fetch "$README_URL" "$tmp/readme.txt" 2>/dev/null || warn "readme.txt 下载失败（非必需，继续）"

    # 官方未发布校验和（bcb.unl.edu 无 .md5/.sha256）→ 跳过校验
    warn "官方未发布数据库校验和（bcb.unl.edu/dbCAN2 无 md5/sha256），跳过完整性校验，仅做建库与文件断言"

    install -m 0644 "$tmp/dbCAN-HMMdb-V9.txt"   "$PREFIX/dbCAN-HMMdb-V9.txt"
    install -m 0644 "$tmp/CAZyDB.07312020.fa"   "$PREFIX/CAZyDB.07312020.fa"
    install -m 0755 "$tmp/hmmscan-parser.sh"    "$PREFIX/hmmscan-parser.sh"
    [[ -f "$tmp/readme.txt" ]] && install -m 0644 "$tmp/readme.txt" "$PREFIX/readme.txt" || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 官方脚本约定：dbCAN-fam-HMMs.txt 为 HMM 库文件名（软链）
    ln -sf dbCAN-HMMdb-V9.txt "$PREFIX/dbCAN-fam-HMMs.txt"
    # CAZyDB FASTA 头部结尾 " |" 需修复为换行（13.md 步骤）
    perl -p -i -e 's/\|\s*$/\n/ if m/^>/' "$PREFIX/CAZyDB.07312020.fa"

    if [[ "$DO_BUILD" == 1 ]]; then
        need hmmpress; need makeblastdb; need diamond
        log "hmmpress 建立 HMM 数据库"
        hmmpress -f "$PREFIX/dbCAN-fam-HMMs.txt"
        log "makeblastdb 建立 BLAST 库"
        makeblastdb -in "$PREFIX/CAZyDB.07312020.fa" -dbtype prot -title CAZyDB.07312020 \
            -parse_seqids -out "$PREFIX/CAZyDB.07312020" -logfile "$PREFIX/CAZyDB.07312020.makeblastdb.log"
        log "diamond makedb 建立 DIAMOND 库"
        diamond makedb --in "$PREFIX/CAZyDB.07312020.fa" --db "$PREFIX/CAZyDB.07312020"
    else
        log "已跳过建库（--no-build）；稍后请手动执行 hmmpress / makeblastdb / diamond makedb"
    fi

    # 文件断言
    [[ -f "$PREFIX/dbCAN-HMMdb-V9.txt" ]] || die "HMM 数据库缺失"
    [[ -f "$PREFIX/CAZyDB.07312020.fa" ]] || die "CAZy FASTA 缺失"
    [[ -x "$PREFIX/hmmscan-parser.sh" ]] || die "hmmscan-parser.sh 缺失或不可执行"
    log "dbCAN V${VERSION} 部署完成：$PREFIX"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# dbCAN V${VERSION} (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}（hmmscan-parser.sh 可直接调用）"
        fi
    fi
}

# ---------------- 路线 B：conda（run_dbcan 下游封装） ----------------
install_conda() {
    local env_exists
    warn "conda 路线的 bioconda::dbcan 为 run_dbcan（dbCAN2 下游封装，当前 5.2.9），与经典 V9 脚本非同一代"
    log "使用 conda 安装 dbcan（run_dbcan）到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda dbcan=5.2.9
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda dbcan=5.2.9
    fi
    log "验证：conda run -n $CONDA_ENV run_dbcan --help"
    "$CONDA_BIN" run -n "$CONDA_ENV" run_dbcan --help | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 run_dbcan（经典 V9 建库请用 --method db）"
}

# ---------------- 主流程 ----------------
log "dbCAN V$VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    db)    install_db ;;
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    auto)
        # 经典 V9 数据库路线为本模块主路线；conda 的 dbcan 为另一代 run_dbcan，仅在显式 --method conda 时安装
        install_db ;;
esac
log "安装成功"
