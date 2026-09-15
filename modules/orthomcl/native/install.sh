#!/usr/bin/env bash
# =============================================================================
# install.sh — OrthoMCL 宿主机本地安装脚本
#
# 归属    ：bioskills modules/orthomcl/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7；软件 deprecated → 不自建容器，仅宿主机安装）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::orthomcl=2.0.9
#   - tarball 路线（无 conda 兜底）：下载官方 tarball orthomclSoftware-v2.0.9.tar.gz，
#     解压到用户级 --prefix（默认 ~/software/orthomclSoftware-v2.0.9），无需 root、不写 /opt
#   - 版本默认 2.0.9，与 modules/orthomcl/meta.yaml software_versions.native 对齐
#
# ⚠️ OrthoMCL 已停止维护（推荐 OrthoFinder 替代），且流程依赖 MySQL；本脚本仅安装
#    OrthoMCL 脚本本体，MySQL 需另行安装/配置（见模块 README）。
#
# 官方来源：
#   homepage : http://orthomcl.org/orthomcl/
#   tarball  : http://orthomcl.org/common/downloads/software/v2.0/orthomclSoftware-v2.0.9.tar.gz
#   bioconda : https://anaconda.org/bioconda/orthomcl
#   (历史容器：quay.io/biocontainers/orthomcl —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 说明：OrthoMCL 由一组 Perl 脚本组成，无统一 --version；binary 是 tarball 的别名。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 tarball
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: orthomcl）
#   bash install.sh --method tarball                  # 强制官方 tarball（无需 conda）
#   bash install.sh --conda-env orthomcl-native --force
#   bash install.sh --prefix ~/software/orthomclSoftware-v2.0.9 --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.0.9"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/orthomclSoftware-v$DEFAULT_VERSION}"
CONDA_ENV="orthomcl"
METHOD="auto"          # auto | conda | tarball（binary = tarball 别名）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 tarball 内嵌 md5（官方仅公开 md5；取自 bioconda-recipes orthomcl 配方）
MD5_TARBALL="2e0202ed4e36a753752c3567edb9bba9"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|tarball|binary}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

if [[ "$METHOD" == "binary" ]]; then
    warn "OrthoMCL 官方以 tarball 分发脚本；--method binary 按 tarball 处理"
    METHOD="tarball"
fi
case "$METHOD" in auto|conda|tarball) ;; *) die "--method 仅支持 auto|conda|tarball|binary（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 断言（OrthoMCL 无 --version，改断言脚本可达且打印用法） ----------------
# 各脚本无参数运行会打印用法（含 EXAMPLE），据此判定安装成功
assert_scripts() {
    local bindir="$1" out
    [[ -x "$bindir/orthomclAdjustFasta" ]] || die "未找到 $bindir/orthomclAdjustFasta"
    out="$(PATH="$bindir:$PATH" orthomclAdjustFasta 2>&1 || true)"
    grep -q "EXAMPLE" <<<"$out" || die "orthomclAdjustFasta 用法输出校验失败（未含 EXAMPLE）"
    log "脚本可达性校验通过：$bindir/orthomclAdjustFasta"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 orthomcl=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "orthomcl=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "orthomcl=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV orthomclAdjustFasta（应打印含 EXAMPLE 的用法）"
    "$CONDA_BIN" run -n "$CONDA_ENV" orthomclAdjustFasta 2>&1 | grep -m1 EXAMPLE | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 orthomcl* 脚本（MySQL 需另行配置）"
}

# ---------------- 路线 B：官方 tarball ----------------
install_tarball() {
    local url tarball="orthomclSoftware-v${VERSION}.tar.gz" tmp="" findir
    url="http://orthomcl.org/common/downloads/software/v2.0/${tarball}"

    log "下载官方 tarball: $url"
    log "安装前缀: $PREFIX"
    [[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}），URL 模板可能不适用"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/$tarball" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/$tarball" "$url"
    else
        die "需要 curl 或 wget 下载 tarball"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${MD5_TARBALL:-}" ]]; then
        if command -v md5sum >/dev/null 2>&1; then
            echo "$MD5_TARBALL  $tmp/$tarball" | md5sum -c - >/dev/null 2>&1 \
                || die "md5 校验失败：下载文件不完整或被篡改"
        else
            echo "$MD5_TARBALL  $tmp/$tarball" | md5 -r >/dev/null 2>&1 || true
            got="$(md5 -q "$tmp/$tarball" 2>/dev/null || true)"
            [[ "$got" == "$MD5_TARBALL" ]] || die "md5 校验失败：期望 $MD5_TARBALL，实际 ${got:-未知}"
        fi
        log "md5 校验通过"
    fi

    mkdir -p "$PREFIX"
    tar xzf "$tmp/$tarball" -C "$PREFIX"
    findir="$(find "$PREFIX" -maxdepth 1 -mindepth 1 -type d -name 'orthomclSoftware-*' | head -1)"
    [[ -n "$findir" ]] || die "解压后未找到 orthomclSoftware-* 目录"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_scripts "$findir/bin"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$findir/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$findir/bin" "$PROFILE"; then
            log "PATH 已包含 $findir/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# orthomcl (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 orthomclAdjustFasta 即可（MySQL 需另行配置）"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$findir/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "orthomcl $VERSION 安装开始（本机 ${OS}/${ARCH}）"
warn "⚠️ OrthoMCL 已停止维护，推荐 OrthoFinder 替代（见 modules/orthofinder/）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    tarball)
        install_tarball ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_tarball
        fi ;;
esac
log "安装成功"
