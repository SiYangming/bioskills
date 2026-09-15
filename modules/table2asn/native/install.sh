#!/usr/bin/env bash
# =============================================================================
# install.sh — table2asn 宿主机本地安装脚本
#
# 归属    ：bioskills modules/table2asn/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方镜像优先，宿主机走 conda / 官方资产）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::table2asn
#   - binary 路线（无 conda 兜底）：NCBI 官方 FTP 预编译二进制（linux64 / mac），
#     解压部署到用户前缀（默认 ~/software/table2asn-<ver>），无需 root、不写 /opt
#   - 版本默认 1.28.1179，与 modules/table2asn/meta.yaml software_versions 对齐
#
# 说明：table2asn 是 tbl2asn 的现役后继（NCBI 官方原文："table2asn is the replacement
#   of the older now-obsolete tool tbl2asn"）；tbl2asn 官方二进制已下架（Obsolete）。
#
# 官方来源：
#   homepage : https://www.ncbi.nlm.nih.gov/genbank/table2asn/
#   bioconda : https://anaconda.org/bioconda/table2asn
#   release  : https://ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/table2asn/
#              （linux64.table2asn.gz / mac.table2asn.gz / win64.table2asn.zip；官方未提供源码）
#   （容器：quay.io/biocontainers/table2asn —— 本脚本为宿主机安装，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方二进制
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: table2asn）
#   bash install.sh --method binary                   # 强制官方预编译二进制（无需 conda）
#   bash install.sh --conda-env t2a --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/table2asn          # binary 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.28.1179"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/table2asn-$DEFAULT_VERSION}"
CONDA_ENV="table2asn"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 FTP 二进制为固定文件名（不含版本号），且官方未提供源码归档：
#   https://ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/table2asn/linux64.table2asn.gz
#   https://ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/table2asn/mac.table2asn.gz
# 因此不内嵌 sha256（文件随官方更新而变，哈希不稳定）；如需校验请自行 shasum 并与官方核对。

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
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
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（table2asn 无 --version，用 -help 打印用法横幅） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -help </dev/null 2>&1 | head -n 5 || true)"
    printf '  %s\n' "$out"
    grep -q "table2asn" <<<"$out" || die "版本校验失败：table2asn -help 输出异常（见上）"
    if grep -qE "${VERSION//./\\.}" <<<"$out"; then
        log "版本校验通过：${VERSION}"
    else
        warn "table2asn -help 未直接打印版本号（官方 FTP 为固定文件名二进制）；已确认可执行文件可用，版本以 bioconda/meta 登记 ${VERSION} 为准"
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 table2asn=${VERSION} 到环境: ${CONDA_ENV}"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "table2asn=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "table2asn=${VERSION}"
    fi
    log "验证：conda run -n ${CONDA_ENV} table2asn -help"
    "$CONDA_BIN" run -n "$CONDA_ENV" table2asn -help 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate ${CONDA_ENV} 后即可使用 table2asn"
}

# ---------------- 路线 B：官方 FTP 预编译二进制 ----------------
install_binary() {
    local tmp fname url
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    mkdir -p "$PREFIX/bin"

    if [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; then
        fname="linux64.table2asn.gz"
    elif [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]]; then
        fname="mac.table2asn.gz"
    elif [[ "$OS" == "Darwin" && "$ARCH" == "arm64" ]]; then
        die "官方 mac 二进制为 x86_64（Apple Silicon 走 Rosetta 或改用 --method conda）"
    else
        die "官方预编译二进制仅覆盖 linux-x64 / macos-x64（当前 ${OS}/${ARCH}）；请改用 --method conda"
    fi

    [[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "官方 FTP 二进制为固定文件名（不含版本号），--version ${VERSION} 无法改变下载内容"
    url="https://ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/table2asn/${fname}"
    log "下载官方预编译二进制: ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/${fname}" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/${fname}" "$url"
    else
        die "需要 curl 或 wget 下载官方二进制"
    fi
    gunzip -c "$tmp/${fname}" > "$PREFIX/bin/table2asn"
    chmod 0755 "$PREFIX/bin/table2asn"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/table2asn"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# table2asn (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 table2asn 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "table2asn ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_binary
        fi ;;
esac
log "安装成功"
