#!/usr/bin/env bash
# =============================================================================
# install.sh — eggNOG-mapper 宿主机本地安装脚本
#
# 归属    ：bioskills modules/eggnog-mapper/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「安装方式（本地）」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::eggnog-mapper
#   - source 路线（无 conda 兜底）：官方 GitHub archive 源码，用户级前缀
#     安装到 --prefix（默认 ~/software/eggnog-mapper-<ver>），无需 root、不写 /opt
#   - 版本默认 1.0.3，与 modules/eggnog-mapper/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://eggnogdb.embl.de （GitHub: https://github.com/eggnogdb/eggnog-mapper）
#   bioconda : https://anaconda.org/bioconda/eggnog-mapper
#   source   : https://github.com/eggnogdb/eggnog-mapper/archive/refs/tags/1.0.3.tar.gz
#   (容器：quay.io/biocontainers/eggnog-mapper —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 注意：官方未发布预编译二进制资产（仅源码 + conda），source 路线为源码归档；
#       数据库 emapperdb 需另行下载（download_eggnog_data.py，体积大）。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: eggnog-mapper）
#   bash install.sh --method source                   # 强制源码安装（--method binary 为其别名）
#   bash install.sh --conda-env em --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/eggnog-mapper      # source 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.0.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/eggnog-mapper-$DEFAULT_VERSION}"
CONDA_ENV="eggnog-mapper"
METHOD="auto"          # auto | conda | source（binary 为 source 别名）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

[[ "$METHOD" == "binary" ]] && METHOD="source"   # 兼容 --method binary（官方无预编译二进制，等价源码）
case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（安装后运行 emapper.py 校验） ----------------
assert_version() {
    local bin="$1" out=""
    out="$("$bin" --version 2>&1 || "$bin" -v 2>&1 || true)"
    printf '  %s\n' "$(head -n 1 <<<"$out")"
    if grep -qE "${VERSION//./\.}" <<<"$out"; then
        log "版本校验通过：$VERSION"
    elif "$bin" --help >/dev/null 2>&1; then
        warn "emapper.py 未直接输出版本号（1.0.3 的 --version 行为随版本而异）；二进制可用，已通过 --help 冒烟"
    else
        die "emapper.py 无法执行（--version 与 --help 均失败）"
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 eggnog-mapper=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "eggnog-mapper=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "eggnog-mapper=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV emapper.py --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" emapper.py --version | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 emapper.py"
}

# ---------------- 路线 B：官方源码归档（GitHub archive） ----------------
install_source() {
    local url tmp=""
    url="https://github.com/eggnogdb/eggnog-mapper/archive/refs/tags/${VERSION}.tar.gz"

    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/eggnog-mapper.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/eggnog-mapper.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi

    # 官方未发布源码归档校验和（GitHub archive 由服务端即时打包，非字节稳定）→ 跳过 sha256 校验
    warn "官方未发布源码归档校验和（GitHub archive 非字节稳定），跳过 sha256，仅做版本断言"

    tar -xzf "$tmp/eggnog-mapper.tar.gz" -C "$PREFIX" --strip-components=1
    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -f "$PREFIX/emapper.py" ]] || die "源码包内未找到 emapper.py（URL 或版本号有误？）"
    chmod +x "$PREFIX/emapper.py" "$PREFIX/download_eggnog_data.py" 2>/dev/null || true

    assert_version "$PREFIX/emapper.py"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# eggnog-mapper (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 emapper.py 即可（数据库需另行 download_eggnog_data.py）"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "eggnog-mapper $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
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
