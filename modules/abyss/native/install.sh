#!/usr/bin/env bash
# =============================================================================
# install.sh — ABySS 宿主机本地安装脚本
#
# 归属    ：bioskills modules/abyss/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方镜像优先，宿主机走 conda / 官方资产）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::abyss=1.9.0
#   - source 路线（无 conda 兜底）：官方 GitHub 源码归档编译（1.9.0），
#     用户级前缀安装到 --prefix（默认 ~/software/abyss-1.9.0），无需 root、不写 /opt
#   - 容器（官方镜像优先，本脚本不含）：quay.io/biocontainers/abyss:1.9.0--0 /
#     depot.galaxyproject.org sif —— 官方渠道已覆盖 bioconda → quay → depot，
#     故本模块不维护 Dockerfile/Apptainer.def（见模块 README「环境安装」）
#
# 版本说明（2026-09 核实）：
#   - 本模块登记教学版本 1.9.0（bioconda abyss=1.9.0，linux-64）；
#   - 上游仍在维护，GitHub tag / bioconda 最新为 2.3.10，nf-core abyss/abysspe pin 2.3.10；
#   - 官方 GitHub release 仅提供源码归档（如 abyss-2.3.10.tar.gz），无预编译二进制资产；
#   - 两个版本 abyss-pe 的 k= / np= / j= key=value 用法一致。
#
# 官方来源：
#   homepage : https://github.com/bcgsc/abyss
#   bioconda : https://anaconda.org/bioconda/abyss
#   source   : https://github.com/bcgsc/abyss/archive/refs/tags/1.9.0.tar.gz
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: abyss）
#   bash install.sh --method source                   # 强制官方源码编译
#   bash install.sh --conda-env abyss-native --force  # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/abyss-1.9.0        # source 模式自定义前缀
#   bash install.sh --version 2.3.10 --method conda   # 覆盖版本（conda pin）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.9.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/abyss-$DEFAULT_VERSION}"
CONDA_ENV="abyss"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
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
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（abyss-pe version） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" version </dev/null 2>&1 | head -n 5 || true)"
    printf '  %s\n' "$out"
    if [[ -z "$out" ]]; then
        warn "abyss-pe version 无输出（该版本可能不支持 version 子命令），已按可执行性判定"
        return 0
    fi
    grep -qE "${VERSION//./\\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：${VERSION}"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 abyss=${VERSION} 到环境: ${CONDA_ENV}"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "abyss=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "abyss=$VERSION"
    fi
    log "验证：conda run -n ${CONDA_ENV} abyss-pe version"
    "$CONDA_BIN" run -n "$CONDA_ENV" abyss-pe version </dev/null 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate ${CONDA_ENV} 后即可使用 abyss-pe / abyss-map / DistanceEst 等"
}

# ---------------- 路线 B：官方源码编译（无官方预编译二进制） ----------------
install_source() {
    log "源码编译 ABySS ${VERSION}（官方 GitHub 源码归档）"
    command -v make >/dev/null 2>&1 || die "源码编译需要 make"
    command -v g++  >/dev/null 2>&1 || die "源码编译需要 g++"
    [[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}），请自行核对官方 tag 是否存在"

    local url="https://github.com/bcgsc/abyss/archive/refs/tags/${VERSION}.tar.gz"
    local tmp; tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    log "下载官方源码: ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/abyss.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/abyss.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    tar -xzf "$tmp/abyss.tar.gz" -C "$tmp"
    local srcdir; srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "abyss-*" | head -1)"
    [[ -n "$srcdir" ]] || die "源码包解压目录异常（URL 或版本号有误？）"

    # MPI 为 np= 并行组装所需（历史依赖 openmpi + sparsehash）；无 mpicxx 时退化为串行构建
    local cfg_args=(--prefix="$PREFIX")
    if command -v mpicxx >/dev/null 2>&1; then
        cfg_args+=(--with-mpi)
        log "检测到 mpicxx：启用 --with-mpi（支持 abyss-pe np= 并行）"
    else
        warn "未检测到 mpicxx：按串行构建（np= 并行不可用）；如需并行请先安装 openmpi"
    fi
    warn "1.9.0 源码编译依赖 google-sparsehash（configure 阶段会检查）"

    log "configure + make（-j 4）..."
    ( cd "$srcdir" && ./configure "${cfg_args[@]}" && make -j 4 )
    ( cd "$srcdir" && make install )

    local bin="$PREFIX/bin/abyss-pe"
    [[ -x "$bin" ]] || die "安装后未找到 ${bin}（编译是否失败？）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$bin"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# abyss (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 abyss-pe 即可"
    else
        warn "未改 PATH：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "ABySS ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_source
        fi ;;
esac
log "安装成功"
