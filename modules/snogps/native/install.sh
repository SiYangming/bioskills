#!/usr/bin/env bash
# =============================================================================
# install.sh — snogps 宿主机本地安装脚本
#
# 归属    ：bioskills modules/snogps/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7；官方渠道全无 → 自建兜底，源码编译）
#   - 官方渠道核实（2026-09）：bioconda snogps 未找到 / quay.io/biocontainers/snogps
#     401（不存在）/ depot.galaxyproject.org 404 —— 无 conda 包、无官方镜像
#   - 故本脚本以「官方源码编译」为主路线：https://trna.ucsc.edu/software/snoGPS-0.2.tar.gz
#     编译 `cd src && make`，产物 pseudoU_test（软链 snoGPS），用户级前缀安装到
#     --prefix（默认 ~/software/snogps-<ver>），无需 root、不写 /opt
#   - --method conda 会明确报错（bioconda 无 snogps）；--method auto 走源码编译
#   - 版本默认 0.2，与 modules/snogps/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://lowelab.ucsc.edu/snoGPS/
#   source   : https://trna.ucsc.edu/software/snoGPS-0.2.tar.gz
#
# 用法示例：
#   bash install.sh                                   # auto：源码编译（官方无 conda/镜像）
#   bash install.sh --method binary                   # 显式源码编译
#   bash install.sh --prefix ~/opt/snogps             # 自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="0.2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/snogps-$DEFAULT_VERSION}"
CONDA_ENV="snogps"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码归档内嵌 sha256（0.2 beta）
SRC_URL="https://trna.ucsc.edu/software/snoGPS-0.2.tar.gz"
SHA256_SRC="184abd9ca6ce24b34c65ddb24ee445c8d5ecfef1a1315d75055b80a284845027"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|binary}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"

platform_ok_binary() {
    { [[ "$OS" == "Linux"  ]] || [[ "$OS" == "Darwin" ]]; }
}

# ---------------- 版本断言（安装后运行 snoGPS -h 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -h 2>&1 || true)"
    printf '%s\n' "$out" | sed 's/^/  /'
    grep -qi "usage" <<<"$out" || die "版本校验失败：snoGPS -h 未输出预期 usage"
    log "版本校验通过（snoGPS -h 正常）"
}

# ---------------- 官方源码编译（主路线） ----------------
install_binary() {
    local tmp srcdir
    log "官方渠道（bioconda/quay/depot）全无 snoGPS，走官方源码编译"
    log "下载官方源码归档: $SRC_URL"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/snogps.tar.gz" "$SRC_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/snogps.tar.gz" "$SRC_URL"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        echo "$SHA256_SRC  $tmp/snogps.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
            || die "sha256 校验失败：下载的源码归档不完整或被篡改"
    else
        echo "$SHA256_SRC  $tmp/snogps.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
            || die "sha256 校验失败：下载的源码归档不完整或被篡改"
    fi
    log "sha256 校验通过"

    tar -xzf "$tmp/snogps.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'snoGPS-*' | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档内未找到 snoGPS-* 目录"

    command -v make >/dev/null 2>&1 || die "源码编译需要 make"
    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || die "源码编译需要 C 编译器（cc/gcc）"

    # makefile 位于 src/，产物 pseudoU_test 并软链为 snoGPS（BINDIR 覆盖默认的 $(HOME)/bin）
    ( cd "$srcdir/src" && { make clean >/dev/null 2>&1 || true; } && make BINDIR="$PREFIX/bin" )

    [[ -x "$PREFIX/bin/snoGPS" ]] || [[ -x "$PREFIX/bin/pseudoU_test" ]] \
        || die "源码编译后未找到 snoGPS/pseudoU_test 可执行文件"

    # 运行期数据与辅助脚本（descriptor/target/scoretable + Perl 脚本）
    local share="$PREFIX/share/snogps"
    mkdir -p "$share"
    for d in data desc targs scoretables perlModules; do
        [[ -d "$srcdir/$d" ]] && cp -R "$srcdir/$d" "$share/" || true
    done
    if [[ -d "$srcdir/scripts" ]]; then
        cp -R "$srcdir/scripts" "$share/"
        # 辅助 Perl 脚本放入 bin（sortHits.pl 等），首行 shebang 归一为 env perl
        local sc
        for sc in "$share"/scripts/*.pl; do
            [[ -f "$sc" ]] || continue
            install -m 0755 "$sc" "$PREFIX/bin/"
        done
        if [[ -f "$PREFIX/bin/sortHits.pl" ]]; then
            perl -i -pe 's{^#! ?.*perl.*$}{#!/usr/bin/env perl}' "$PREFIX/bin/sortHits.pl" 2>/dev/null || true
        fi
    fi
    log "运行期数据已安装到 $share（Perl 脚本请设 MYPERLMODULEDIR=$share/perlModules/）"

    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/snoGPS"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# snogps (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 snoGPS 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "snogps $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        die "--method conda 不可用：bioconda 无 snogps 包（2026-09 核实 api.anaconda.org 未找到）；请用 --method binary 源码编译" ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 不受支持（源码编译仅 linux/macos）"
        install_binary ;;
    auto)
        platform_ok_binary || die "官方渠道全无且本平台（${OS}/${ARCH}）无法源码编译，无法自动安装"
        install_binary ;;
esac
log "安装成功"
