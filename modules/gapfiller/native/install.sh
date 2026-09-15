#!/usr/bin/env bash
# =============================================================================
# install.sh — GapFiller（Perl GapFiller.pl v1.11，三代修改版）宿主机本地安装脚本
#
# 归属    ：bioskills modules/gapfiller/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」对齐）
#   - source 路线（唯一路线）：从官方 lufuhao/gapfiller 仓库取单文件 GapFiller.pl，
#     部署到 --prefix（默认 ~/software/GapFiller_v1-11），并校验依赖比对器 bowtie/bwa
#   - 说明：官方渠道 bioconda/quay/depot 的同名 gapfiller 为 C++ v2.1.2 系列（CLI 为
#     `GapFiller --seed1 …`），与本文档目标 Perl GapFiller.pl（-l/-s/-T）不是同一工具，
#     故本脚本不提供 conda 路线；请用 native/Dockerfile 或本脚本部署 Perl v1.11
#   - 版本默认 v1.11，与 modules/gapfiller/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   source : https://github.com/lufuhao/gapfiller（GapFiller.pl，三代修改版 v1.11）
#   manual : docs/F132-05-GapFiller_User_Manual_v1.10.pdf（仓库内）
#
# 用法示例：
#   bash install.sh                          # 取 GapFiller.pl 到 ~/software/GapFiller_v1-11 并写 PATH
#   bash install.sh --prefix ~/opt/gapfiller # 自定义前缀
#   bash install.sh --ref master             # 指定 git ref（tag/分支）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_REF="master"                 # 仓库无 release tag；默认跟踪 master（脚本内 my $version = "v1.11"）
REF="$DEFAULT_REF"
PREFIX="${PREFIX:-$HOME/software/GapFiller_v1-11}"
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ref)         REF="${2:?--ref 需要 git ref}";    shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";  shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

# ---------------- 依赖比对器检查（GapFiller.pl 按 $Bin/bowtie、$Bin/bwa 查找） ----------------
check_aligners() {
    local missing=0
    command -v bowtie >/dev/null 2>&1 || { warn "未检测到 bowtie（文库表用 bowtie 比对时需要）"; missing=1; }
    command -v bwa >/dev/null 2>&1 || { warn "未检测到 bwa（文库表用 bwa/bwasw 比对时需要）"; missing=1; }
    if [[ "$missing" == 1 ]]; then
        warn "请安装比对器（Debian/Ubuntu: apt-get install -y --no-install-recommends bowtie bwa；或 mamba install -c bioconda bowtie bwa）"
        warn "GapFiller.pl 期望在自身目录的 bowtie/ 与 bwa/ 子目录找到二进制（本脚本会据 PATH 自动建软链接）"
    fi
}

# ---------------- 主流程：source 部署 ----------------
install_source() {
    log "部署 GapFiller.pl（ref=${REF}）到前缀: $PREFIX"
    if [[ -e "$PREFIX/GapFiller.pl" && "$FORCE" != 1 ]]; then
        die "$PREFIX/GapFiller.pl 已存在；加 --force 覆盖，或改用 --prefix"
    fi
    mkdir -p "$PREFIX/bowtie" "$PREFIX/bwa"

    local url="https://raw.githubusercontent.com/lufuhao/gapfiller/${REF}/GapFiller.pl"
    log "下载官方脚本: $url"
    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/GapFiller.pl" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/GapFiller.pl" "$url"
    else
        die "需要 curl 或 wget 下载 GapFiller.pl"
    fi
    # sha256 未核实（上游无 release 资产、仓库 master 滚动更新）
    install -m 0755 "$tmp/GapFiller.pl" "$PREFIX/GapFiller.pl"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # $Bin 相对查找：建 bowtie/ bwa/ 软链接指向 PATH 中的二进制
    local bt bw
    bt="$(command -v bowtie || true)"; bw="$(command -v bwa || true)"
    [[ -n "$bt" ]] && ln -sf "$bt" "$PREFIX/bowtie/bowtie"
    [[ -n "$bt" ]] && { command -v bowtie-build >/dev/null 2>&1 && ln -sf "$(command -v bowtie-build)" "$PREFIX/bowtie/bowtie-build"; }
    [[ -n "$bw" ]] && ln -sf "$bw" "$PREFIX/bwa/bwa"

    # 版本断言（GapFiller.pl 无 --version：脚本内 my $version = "v1.11"）
    grep -qE 'version *= *"v1\.11"' "$PREFIX/GapFiller.pl" || die "版本校验失败：脚本内未找到 v1.11 标记"
    log "版本校验通过：v1.11"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "PATH 已包含 $PREFIX，跳过写入 $PROFILE"
        else
            { echo ""; echo "# GapFiller.pl (bioskills install.sh)"; echo "export PATH=\"$PREFIX:\$PATH\""; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 GapFiller.pl 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX:\$PATH\""
    fi
}

log "GapFiller.pl v1.11 安装开始（本机 $(uname -s)/$(uname -m)）"
check_aligners
install_source
log "安装成功"
