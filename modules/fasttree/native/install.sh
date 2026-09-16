#!/usr/bin/env bash
# =============================================================================
# install.sh — FastTree 宿主机本地安装脚本
#
# 归属    ：bioskills modules/fasttree/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5；官方镜像优先语境）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::fasttree=2.1.11
#   - source 路线（无 conda 兜底）：官方源码 FastTree-2.1.11.c，gcc -O3 编译
#     FastTree（单精度）与 FastTree_d（-DUSE_DOUBLE，双精度）两版本到用户级前缀
#     --prefix（默认 ~/software/FastTree-2.1.11），无需 root、不写 /opt
#   - 版本默认 2.1.11，与 modules/fasttree/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://www.microbesonline.org/fasttree/
#   source   : http://www.microbesonline.org/fasttree/FastTree-2.1.11.c（官方无预编译二进制）
#   (容器：quay.io/biocontainers/fasttree:2.1.11--h7b50bb2_5 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                               # auto：有 conda/mamba 走 bioconda，否则源码编译
#   bash install.sh --method conda                # 强制 conda（默认建独立 env: fasttree）
#   bash install.sh --method source               # 强制官方源码 gcc 编译
#   bash install.sh --conda-env ft --force        # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/FastTree       # source 模式自定义前缀
#   bash install.sh --version 2.1.11 --force      # 覆盖版本（跳过内嵌 sha256 校验并提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.1.11"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/FastTree-$DEFAULT_VERSION}"
CONDA_ENV="fasttree"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码 FastTree-2.1.11.c 内嵌 sha256（跨平台同一份源码）
SHA256_SOURCE="9026ae550307374be92913d3098f8d44187d30bea07902b9dcbfb123eaa2050f"

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

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi
CC_BIN="${CC:-gcc}"
have_cc() { command -v "$CC_BIN" >/dev/null 2>&1; }

# ---------------- 版本断言（安装后运行 FastTree -help 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -help 2>&1 | head -n 1)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 fasttree=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "fasttree=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "fasttree=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV FastTree -help"
    "$CONDA_BIN" run -n "$CONDA_ENV" FastTree -help 2>&1 | grep -q "${VERSION//./\.}" \
        || die "版本校验失败：期望输出含 ${VERSION}"
    log "完成：conda activate $CONDA_ENV 后即可使用 FastTree"
}

# ---------------- 路线 B：官方源码 gcc 编译（FastTree + FastTree_d） ----------------
install_source() {
    local url src
    src="FastTree-${VERSION}.c"
    url="http://www.microbesonline.org/fasttree/${src}"

    have_cc || die "未检测到 C 编译器（${CC_BIN}）；请安装 gcc/clang 或改用 --method conda"
    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"
    [[ "$FORCE" == 1 || ! -e "$PREFIX" ]] || die "前缀已存在：${PREFIX}（加 --force 覆盖，或 --prefix 指定其它目录）"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/$src" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/$src" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SOURCE  $tmp/$src" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_SOURCE  $tmp/$src" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官方源码摘要）"
    fi

    # 官方编译命令：FastTree（单精度）/ FastTree_d（-DUSE_DOUBLE，双精度）
    ( cd "$tmp" && "$CC_BIN" -O3 -finline-functions -funroll-loops -Wall -o FastTree "$src" -lm )
    ( cd "$tmp" && "$CC_BIN" -O3 -finline-functions -funroll-loops -Wall -DUSE_DOUBLE -o FastTree_d "$src" -lm )
    install -m 0755 "$tmp/FastTree" "$PREFIX/bin/FastTree"
    install -m 0755 "$tmp/FastTree_d" "$PREFIX/bin/FastTree_d"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/FastTree"
    "$PREFIX/bin/FastTree_d" -help >/dev/null 2>&1 || true

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# fasttree (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 FastTree 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "fasttree $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif have_cc; then
            install_source
        else
            die "未检测到 mamba/conda 且无 C 编译器（${CC_BIN}），无法自动安装"
        fi ;;
esac
log "安装成功"
