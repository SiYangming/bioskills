#!/usr/bin/env bash
# =============================================================================
# install.sh — FALCON (pb-falcon / pb-assembly) 宿主机本地安装脚本
#
# 归属    ：bioskills modules/falcon/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「安装方式（本地）」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境
#       · 默认装 pb-assembly（PacBio 官方 meta-package：FALCON + Unzip 整套三代工具链，
#         即文档方法二所述；最后更新 2019–2020）
#       · 或用 --pkg pb-falcon 只装 FALCON/Unzip 本体（当前维护，版本更新）
#   - source 路线（无 conda 兜底）：官方 GitHub release 源码 tar（pb-falcon.tar.gz）
#     pip 安装到用户前缀（需 meson/ninja/C 编译器；较重，仅备用）
#   - 默认 pin 2.2.4（pb-falcon，与 modules/falcon/meta.yaml software_versions.native 对齐）；
#     --pkg pb-assembly 时版本为 0.0.8
#
# 官方来源：
#   homepage : https://github.com/PacificBiosciences/FALCON
#   bioconda : https://anaconda.org/bioconda/pb-falcon（本体）
#              https://anaconda.org/bioconda/pb-assembly（文档所述 meta-package）
#   release  : https://github.com/PacificBiosciences/pb-falcon/releases
#   (容器：quay.io/biocontainers/pb-falcon —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda（pb-assembly）
#   bash install.sh --pkg pb-falcon                   # 只装 FALCON/Unzip 本体（2.2.4）
#   bash install.sh --method conda --conda-env pb-assembly --force
#   bash install.sh --method source                   # 无 conda 兜底：官方源码 pip 安装
#   bash install.sh --prefix ~/opt/falcon-2.2.4
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.2.4"          # pb-falcon 本体版本（--pkg pb-falcon）
META_VERSION="0.0.8"             # pb-assembly meta-package 版本
PKG="pb-assembly"                # 默认装文档所述 meta-package；--pkg pb-falcon 改本体
CONDA_ENV="${PKG}"               # 默认环境名与包名一致
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/falcon-$DEFAULT_VERSION}"
METHOD="auto"                    # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 GitHub release 源码 tar（pb-falcon 2.2.4）内嵌 sha256（来源：bioconda recipe）
SOURCE_URL="https://github.com/PacificBiosciences/pb-falcon/releases/download/v${DEFAULT_VERSION}/pb-falcon.tar.gz"
SOURCE_SHA256="ae5743a16e0aadbfcbd7f3a54732a693e355a19e5533959cfe1a0dfb1b759e4a"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --pkg)         PKG="${2:?--pkg 需要 pb-assembly|pb-falcon}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac
case "$PKG" in pb-assembly|pb-falcon) ;; *) die "--pkg 仅支持 pb-assembly|pb-falcon（收到: ${PKG}）" ;; esac
# 环境名若未显式指定，跟随包名
[[ "$CONDA_ENV" == "pb-assembly" && "$PKG" != "pb-assembly" ]] && CONDA_ENV="$PKG"
if [[ "$PKG" == "pb-assembly" ]]; then PIN_VER="$META_VERSION"; else PIN_VER="$DEFAULT_VERSION"; fi

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本/可用性断言（FALCON 无 --version，用 fc_run.py --help 断言） ----------------
assert_version() {
    local fc_run="$1" out
    out="$("$fc_run" --help 2>&1 || true)"
    printf '%s\n' "$out" | grep -qiE "usage|config|fc_run" \
        || die "可用性校验失败：fc_run.py --help 输出未见预期关键字，实际输出见上"
    log "可用性校验通过：FALCON（fc_run.py；pb-falcon ${DEFAULT_VERSION} / pb-assembly ${META_VERSION}）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 ${PKG}=${PIN_VER} 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "${PKG}=${PIN_VER}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "${PKG}=${PIN_VER}"
    fi
    log "验证：conda run -n $CONDA_ENV fc_run.py --help"
    assert_version "$CONDA_BIN run -n $CONDA_ENV fc_run.py"
    log "完成：conda activate $CONDA_ENV 后即可使用 fc_run.py"
}

# ---------------- 路线 B：官方 GitHub release 源码（pip 安装，仅 pb-falcon 本体） ----------------
install_source() {
    [[ "$PKG" == "pb-falcon" || "$VERSION" == "$DEFAULT_VERSION" ]] || true
    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    log "下载官方 release 源码: $SOURCE_URL"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/pb-falcon.tar.gz" "$SOURCE_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/pb-falcon.tar.gz" "$SOURCE_URL"
    else
        die "需要 curl 或 wget 下载 release 源码"
    fi
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SOURCE_SHA256  $tmp/pb-falcon.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败"
        else
            echo "$SOURCE_SHA256  $tmp/pb-falcon.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi

    command -v pip3 >/dev/null 2>&1 || die "source 路线需要 pip3（并需 meson/ninja/C 编译器，较重；建议优先 conda 路线）"
    mkdir -p "$PREFIX"
    log "pip 安装到前缀: $PREFIX（需编译，耗时较长）"
    pip3 install --prefix "$PREFIX" "$tmp/pb-falcon.tar.gz"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/fc_run.py"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# falcon (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 fc_run.py 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "FALCON 安装开始（包 ${PKG}；本机 ${OS}/${ARCH}）"
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
            warn "未检测到 mamba/conda → 退回 source 路线（pip 源码安装，较重）"
            install_source
        fi ;;
esac
log "安装成功"
