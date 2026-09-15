#!/usr/bin/env bash
# =============================================================================
# install.sh — ProtHint（prothint）宿主机本地安装脚本
#
# 归属    ：bioskills modules/prothint/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」对齐）
#   - source 路线（唯一官方路线）：官方 GitHub release tarball 解压部署到用户前缀
#     （默认 ~/software/ProtHint-2.4.0），并检查 Perl 运行依赖
#   - 说明：官方渠道全无 —— bioconda（prothint 404）、quay.io/biocontainers（无仓库）、
#     depot.galaxyproject.org（404）2026-09 核实，且无 prebuilt 平台二进制包
#     → 无 conda/镜像路线；容器请用 native/Dockerfile 或 native/Apptainer.def
#   - 版本默认 2.4.0，与 modules/prothint/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/gatech-genemark/ProtHint
#   release  : https://github.com/gatech-genemark/ProtHint/releases/tag/v2.4.0
#
# 用法示例：
#   bash install.sh                                  # 部署到 ~/software/ProtHint-2.4.0 并写 PATH
#   bash install.sh --prefix ~/opt/ProtHint          # 自定义前缀
#   bash install.sh --version 2.3.0                  # 覆盖版本（跳过内嵌 sha256 校验并提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
#   bash install.sh --method conda                   # 该软件无 conda 包，会给出明确提示并退出
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.4.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/ProtHint-$DEFAULT_VERSION}"
METHOD="auto"          # auto | source（conda 路线不适用）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release tarball（官方唯一分发资产，平台无关）内嵌 sha256；改 --version 后不匹配 → 跳过并提示
SHA256_TARBALL="bcdba61ff1624e2af46497b68bfac89690c295f09a59841e3faa90b6be4eef98"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|source|conda}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in
    auto|source) ;;
    conda) die "protint 未收录 bioconda（api.anaconda.org/bioconda/prothint 404，2026-09 核实），无 conda 路线；请用 --method source 或自建容器" ;;
    *) die "--method 仅支持 auto|source|conda（收到: ${METHOD}）" ;;
esac

OS="$(uname -s)"; ARCH="$(uname -m)"

# ---------------- 依赖检查（Perl 模块；diamond/spaln 已内附于 tarball） ----------------
check_perl_modules() {
    command -v perl >/dev/null 2>&1 || { warn "未检测到 perl（ProtHint 剪接比对脚本需要 Perl）"; return 0; }
    local missing=""
    for m in MCE::Mutex YAML Math::Utils Thread::Queue threads; do
        perl -M"$m" -e1 2>/dev/null || missing="$missing $m"
    done
    if [[ -n "$missing" ]]; then
        warn "缺少 Perl 模块:${missing}（Debian/Ubuntu 可 apt-get install libmce-perl libyaml-perl libmath-utils-perl libthread-queue-perl）"
    else
        log "Perl 模块检查通过（MCE::Mutex / YAML / Math::Utils / Thread::Queue / threads）"
    fi
}

# ---------------- 版本断言（python3 prothint.py --version 输出含版本号） ----------------
assert_version() {
    local script="$1" out
    out="$(python3 "$script" --version 2>&1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- source 路线（官方 release tarball） ----------------
install_source() {
    command -v python3 >/dev/null 2>&1 || die "source 路线需要 python3（ProtHint 脚本为 Python 3）"
    local url="https://github.com/gatech-genemark/ProtHint/releases/download/v${VERSION}/ProtHint-${VERSION}.tar.gz"
    log "下载官方 release: $url"
    log "安装前缀: $PREFIX"

    if [[ -e "$PREFIX/bin/prothint.py" && "$FORCE" != 1 ]]; then
        die "$PREFIX 已存在 ProtHint；加 --force 覆盖，或改用 --prefix"
    fi

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/ProtHint.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/ProtHint.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${SHA256_TARBALL:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_TARBALL  $tmp/ProtHint.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_TARBALL  $tmp/ProtHint.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 release 摘要）"
    fi

    mkdir -p "$tmp/unpack"
    tar -xzf "$tmp/ProtHint.tar.gz" -C "$tmp/unpack"
    local srcdir
    srcdir="$(find "$tmp/unpack" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -n "$srcdir" && -f "$srcdir/bin/prothint.py" ]] || die "release 包内未找到 bin/prothint.py（URL 或版本号有误？）"

    mkdir -p "$PREFIX"
    cp -R "$srcdir"/. "$PREFIX"/
    chmod 0755 "$PREFIX"/bin/*.py "$PREFIX"/bin/*.pl 2>/dev/null || true
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/prothint.py"
    check_perl_modules

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PROTHINT_HOME=\"$PREFIX\"; export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# ProtHint (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PROTHINT_HOME/PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 prothint.py 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PROTHINT_HOME=\"$PREFIX\" PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "ProtHint ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
if [[ "$OS" != "Linux" ]]; then
    warn "官方 release 内附的 diamond/spaln 依赖为 Linux 二进制；在 ${OS} 上需自行提供可用的 diamond/spaln"
fi
install_source
log "安装成功"
