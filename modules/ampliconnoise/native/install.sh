#!/usr/bin/env bash
# =============================================================================
# install.sh — AmpliconNoise V1.27 宿主机本地安装脚本（历史 454 去噪工具）
#
# 归属    ：bioskills modules/ampliconnoise/native/install.sh（native 实现安装方式）
# 路线    ：AmpliconNoise 无 conda/apt/预编译二进制；官方渠道全无，原 Google Code 站已死，
#           仅 Google Code 归档发布包可达 → 唯一路线 = 官方归档源码 make && make install（依赖 MPI）。
#   - source（默认，唯一）：下载 Google Code 归档 AmpliconNoiseV<ver>.tar.gz -> make && make install
#     -> 部署到用户前缀（默认 ~/software/ampliconnoise-<ver>，含 bin/ 与 Data/）
#   - 版本默认 1.27，与 modules/ampliconnoise/meta.yaml software_versions.native 对齐
#
# 官方来源（如实登记）：
#   homepage（已死）: https://code.google.com/p/ampliconnoise/  （2026-09 探测 curl 000）
#   归档发布包      : https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/ampliconnoise/AmpliconNoiseV1.27.tar.gz
#   依赖            : mpicc / mpirun（apt: mpich 或 openmpi）；gcc / make
#
# 用法示例：
#   bash install.sh                                   # 从官方归档源码编译安装到 ~/software/ampliconnoise-1.27
#   bash install.sh --prefix ~/opt/ampliconnoise       # 自定义前缀
#   bash install.sh --source-url <tarball_or_git_url>  # 指向自备归档（原站失效时的替代）
#   bash install.sh --no-path-update                   # 不改 shell profile
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="1.27"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/ampliconnoise-$DEFAULT_VERSION}"
METHOD="auto"           # auto | source（conda 不支持，传入即 die）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
SOURCE_URL="https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/ampliconnoise/AmpliconNoiseV${DEFAULT_VERSION}.tar.gz"
CUSTOM_SOURCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)        VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)         PREFIX="${2:?--prefix 需要路径}"; shift 2 ;;
        --method)         METHOD="${2:?--method 需要 auto|source}"; shift 2 ;;
        --source-url)     SOURCE_URL="${2:?--source-url 需要 URL}"; CUSTOM_SOURCE=1; shift 2 ;;
        --profile)        PROFILE="${2:?--profile 需要路径}"; shift 2 ;;
        --force)          FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)        usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done
case "$METHOD" in
    auto|source) ;;
    conda) die "AmpliconNoise 无 conda 包（bioconda 404）；请用默认源码路线" ;;
    *) die "--method 仅支持 auto|source（收到: ${METHOD}）" ;;
esac

if [[ "$CUSTOM_SOURCE" == 0 && "$VERSION" != "$DEFAULT_VERSION" ]]; then
    SOURCE_URL="https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/ampliconnoise/AmpliconNoiseV${VERSION}.tar.gz"
fi
# 非默认版本 或 自定义 URL：跳过内嵌说明，提示自行核对
if [[ "$VERSION" != "$DEFAULT_VERSION" || "$CUSTOM_SOURCE" == 1 ]]; then
    warn "非默认来源/版本（${VERSION}），请自行核对归档完整性"
fi

if [[ -d "$PREFIX" && "$FORCE" != 1 ]]; then
    die "前缀已存在: $PREFIX（加 --force 覆盖，或改用 --prefix 指定其它路径）"
fi

# 构建依赖探测
command -v make >/dev/null 2>&1 || die "缺少 make（apt: build-essential / brew: xcode-select --install）"
MPICC="$(command -v mpicc || true)"
[[ -n "$MPICC" ]] || die "缺少 mpicc（AmpliconNoise 依赖 MPI：apt-get install -y mpich 或 openmpi）"

log "AmpliconNoise ${VERSION} 安装开始（本机 $(uname -s)/$(uname -m)）"
log "来源: $SOURCE_URL"
log "前缀: $PREFIX"

tmp=""
tmp="$(mktemp -d)"
cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
trap cleanup_tmp EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$tmp/an.tar.gz" "$SOURCE_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp/an.tar.gz" "$SOURCE_URL"
else
    die "需要 curl 或 wget 下载归档"
fi

tar -xzf "$tmp/an.tar.gz" -C "$tmp"
srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
[[ -n "$srcdir" ]] || die "归档中未找到源码目录（URL 或版本号有误？）"

log "编译: (cd $srcdir && make && make install)"
( cd "$srcdir" && make && make install )

[[ -x "$srcdir/bin/PyroNoise" ]] || die "编译未产出 bin/PyroNoise（检查 mpicc/make 环境）"

mkdir -p "$PREFIX/bin" "$PREFIX/Data"
cp -a "$srcdir/bin/." "$PREFIX/bin/"
if [[ -d "$srcdir/Data" ]]; then cp -a "$srcdir/Data/." "$PREFIX/Data/"; fi
[[ -x "$PREFIX/bin/PyroNoise" ]] || die "部署失败：$PREFIX/bin/PyroNoise 不可执行"

# 断言：程序可执行 + Data 资源就位（AmpliconNoise 无 --version 旗标，按产物与版本目录校验）
log "断言：$PREFIX/bin/{PyroNoise,PerseusD} 可执行 + Data/LookUp.dat 存在"
test -x "$PREFIX/bin/PyroNoise"
test -x "$PREFIX/bin/PerseusD"
test -f "$PREFIX/Data/LookUp.dat"

rm -rf "$tmp"; tmp=""; trap - EXIT

if [[ "$UPDATE_PATH" == 1 ]]; then
    if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
        log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
    else
        { echo ""; echo "# ampliconnoise (bioskills install.sh)"; echo "export PATH=\"$PREFIX/bin:\$PATH\""; } >> "$PROFILE"
        log "已追加 PATH 到 $PROFILE"
    fi
fi

log "安装成功：export PATH=\"$PREFIX/bin:\$PATH\" 后可用（Data 目录：$PREFIX/Data）"
