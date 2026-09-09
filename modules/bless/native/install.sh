#!/usr/bin/env bash
# =============================================================================
# install.sh — BLESS / BLESS 2 宿主机本地安装脚本
#
# 归属    ：bioskills modules/bless/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / 自建兜底对齐）
#   - source 路线（唯一可用路线）：官方 SourceForge 源码归档下载 → make（g++ + MPI 开发库）
#     安装到用户前缀 --prefix（默认 ~/software/bless-<ver>），无需 root、不写 /opt/biosoft
#   - conda 路线：**不可用**。2026-09 核实 bioconda 无 bless 包（api.anaconda.org 404、
#     bioconda-recipes recipes/bless 404）；conda-forge/bless 是同名异义的 Python CLI
#     日志包（v0.4.0），与 NGS BLESS 无关，**禁止**当作本软件安装。--method conda 直接报错。
#   - binary 路线：官方仅分发源码归档（bless.v1p02.tgz 内为源码，需 make），无预编译二进制。
#   - 版本默认 v1p02（即 BLESS 1.02 / BLESS 2 最新发布，2015-06-10），与
#     modules/bless/meta.yaml software_versions.native bless=1.02 对齐
#
# 官方来源：
#   homepage : https://sourceforge.net/projects/bless-ec/
#   wiki     : https://sourceforge.net/p/bless-ec/wiki/Home/（用法/参数/编译依赖）
#   下载     : https://sourceforge.net/projects/bless-ec/files/bless.v1p02.tgz/download
#             （直链 https://downloads.sourceforge.net/project/bless-ec/bless.v1p02.tgz；
#              顶层解压目录名 v1p02 —— 用户文档 `mv /opt/biosoft/v1p02/ ...` 佐证）
#   (容器：官方 bioconda/quay biocontainers/depot 全无 → native/Dockerfile 自建，见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto（=source）：源码编译到 ~/software/bless-1.02
#   bash install.sh --method source                   # 同上，显式指定
#   bash install.sh --method conda                    # 报错退出（bioconda 无 bless；conda-forge/bless 同名异义）
#   bash install.sh --prefix ~/opt/bless              # 自定义前缀
#   bash install.sh --version v1p01                   # 覆盖版本（SourceForge 归档 token：v1p01/v1p00/v0p24…）
#   bash install.sh --sha256 <64hex>                  # 提供官方 sha256（默认跳过：未核实）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="v1p02"          # SourceForge 归档 token（BLESS 1.02 / BLESS 2 最新发布）
DISPLAY_VERSION="1.02"           # meta.yaml software_versions.native.bless
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/bless-$DISPLAY_VERSION}"
METHOD="auto"                    # auto | source（conda 显式拒绝）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
SHA256=""                        # 未核实 → 默认跳过校验；可 --sha256 显式提供

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号（SourceForge 归档 token，如 v1p02/v0p24）}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|source}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --sha256)      SHA256="${2:?--sha256 需要 64 位十六进制摘要}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|source) ;; *)
    die "--method 仅支持 auto|source（收到: ${METHOD}）；conda/binary 路线不可用：bioconda 无 bless 包、官方无预编译二进制（2026-09 核实）" ;;
esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"

# ---------------- 版本断言（bless 无 --version/-v：无参运行打印全部选项，grep 关键选项名） ----------------
assert_ready() {
    local bin="$1" tmpdir="$2" out
    out="$(cd "$tmpdir" && "$bin" 2>&1 || true)"
    grep -q "\-kmerlength" <<<"$out" || die "校验失败：bless 无参输出未见 -kmerlength（期望打印全部选项）"
    grep -q "\-prefix" <<<"$out" || die "校验失败：bless 无参输出未见 -prefix"
    log "bless 可用（版本目标 ${VERSION} ≈ BLESS ${DISPLAY_VERSION}）"
}

# ---------------- 源码编译依赖检查 ----------------
source_platform_deps_ok() {
    # 需要 make + g++（C++）+ MPI 编译驱动 mpicxx/mpic++（官方测试 GCC 4.9.2 + MPICH 3.1.3 / OpenMPI 1.8.2）
    for t in make g++; do
        command -v "$t" >/dev/null 2>&1 || return 1
    done
    command -v mpicxx >/dev/null 2>&1 || command -v mpic++ >/dev/null 2>&1
}

install_source() {
    local tmp="" url tgz topdir bin_src kmc_src
    log "使用源码编译 bless=${VERSION}（≈BLESS ${DISPLAY_VERSION}）到前缀: ${PREFIX}"

    if ! source_platform_deps_ok; then
        die "源码编译缺少依赖：需要 make + g++ + MPI 开发库（mpicxx/mpic++）。请先安装：
Debian/Ubuntu：sudo apt-get install -y --no-install-recommends build-essential g++ make mpich libmpich-dev
            （OpenMPI 亦可：libopenmpi-dev openmpi-bin）
macOS（Homebrew）：brew install mpich gcc
（官方测试环境 GCC 4.9.2 + MPICH 3.1.3 / OpenMPI 1.8.2；用户文档同样要求高版本 GCC + MPICH）"
    fi

    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀 ${PREFIX} 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 重建，或改用 --prefix 指定其它前缀"
        fi
    fi
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    # 1) 下载官方源码归档（SourceForge 直链；镜像重定向 → curl -L / wget 跟随）
    url="https://downloads.sourceforge.net/project/bless-ec/bless.${VERSION}.tgz"
    log "下载官方源码归档: ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL -o "$tmp/bless.tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/bless.tgz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    if [[ -n "$SHA256" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "${SHA256}  $tmp/bless.tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "${SHA256}  $tmp/bless.tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "未提供 --sha256（官方 sha256 未核实，bioskills 录入规范禁真实下载核对），已跳过校验；请自行核对 SourceForge 发布"
    fi

    tar -xzf "$tmp/bless.tgz" -C "$tmp"
    # 顶层目录名 = v1p02（用户文档 `mv /opt/biosoft/v1p02/ /opt/biosoft/BLESS/` 佐证）
    topdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$topdir" ]] || die "源码解压失败（未找到顶层目录）"
    log "源码顶层目录: $(basename "${topdir}")"

    # 2) make（tgz 自 V1.01 起内含全部依赖库：Boost/sparsehash/klib/KMC/murmurhash3/zlib/pigz）
    log "make（默认并行 4，可用 make -j N 自行调节）"
    ( cd "$topdir" && make -j 4 )
    bin_src="$topdir/bless"
    kmc_src="$topdir/kmc/bin/kmc"
    [[ -f "$bin_src" ]] || die "make 后未找到可执行文件 ${bin_src}（编译失败？）"
    [[ -f "$kmc_src" ]] || warn "未找到 ${kmc_src}（用户文档要求运行时把 kmc/bin/kmc 拷到当前目录；若不存在请检查 make 输出）"

    # 3) 部署到用户前缀：真实二进制 + kmc + launcher（runtime 保证 CWD 下 kmc/bin/kmc + MPI hostname 兜底）
    install -m 0755 "$bin_src" "$PREFIX/bless"
    if [[ -f "$kmc_src" ]]; then
        mkdir -p "$PREFIX/kmc/bin"
        install -m 0755 "$kmc_src" "$PREFIX/kmc/bin/kmc"
    fi
    cat > "$PREFIX/bin/bless" <<EOF
#!/usr/bin/env bash
# BLESS 运行时要求 CWD 下存在 kmc/bin/kmc（用户文档 alias 依据）；launcher 保证之
if [[ ! -x kmc/bin/kmc ]]; then
    if mkdir -p kmc/bin 2>/dev/null; then
        cp "${PREFIX}/kmc/bin/kmc" kmc/bin/ 2>/dev/null || true
    fi
fi
# MPI hostname 解析问题兜底（用户文档：`hostname localhost` 还原后再运行）
if ! getent hosts "\$(hostname 2>/dev/null)" >/dev/null 2>&1; then
    echo "127.0.0.1 \$(hostname 2>/dev/null)" >> /etc/hosts 2>/dev/null || true
fi
exec "${PREFIX}/bless" "\$@"
EOF
    chmod 0755 "$PREFIX/bin/bless"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 4) 断言：launcher 无参运行应打印全部选项（含 -kmerlength/-prefix）
    local assert_tmp
    assert_tmp="$(mktemp -d)"
    if ! assert_ready "$PREFIX/bin/bless" "$assert_tmp"; then rm -rf "$assert_tmp"; exit 1; fi
    rm -rf "$assert_tmp"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# bless (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 bless 即可（在 reads 所在目录运行，launcher 会自动放置 kmc/bin/kmc）"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "bless ${VERSION}（≈BLESS ${DISPLAY_VERSION}）安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    source)
        install_source ;;
    auto)
        log "auto = source（bioconda 无 bless 包；conda-forge/bless 为同名异义 Python 日志包，禁止使用）"
        install_source ;;
esac
log "安装成功"
