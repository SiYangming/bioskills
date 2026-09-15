#!/usr/bin/env bash
# =============================================================================
# install.sh — USEARCH（usearch）宿主机本地安装脚本
#
# ⚠️⚠️ 许可限制（务必阅读）⚠️⚠️
#   USEARCH 由 Robert C. Edgar / drive5 开发，是**商业软件**：学术使用免费但需在官网
#   注册后下载，并遵守 USEARCH 许可协议（drive5.com/usearch/）。请勿用于未获授权的商业用途。
#   本模块登记的 8.1.1861 属「历史版本二进制」：现由 rcedgar/usearch_old_binaries 以
#   CC0-1.0（public domain）重发布，bioconda/quay 亦据此打包（bioconda 标注 license=CC0）；
#   但 drive5 当前在售版本（usearch11/usearch12 商业版）仍为专有许可。
#   ★ 本脚本**不内置任何需注册的下载链接**；binary 路线仅提示用户自行获取授权副本。
#
# 归属    ：bioskills modules/usearch/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先）
#   - conda 路线（推荐/默认）：mamba/conda 创建独立环境，pin bioconda::usearch=8.1.1861
#   - binary 路线（无 conda 兜底）：因许可限制，**不自动下载**；仅检测 PATH 中是否已有
#     用户自行获取的 usearch 二进制并校验版本（用户须自行从 drive5 获取授权副本）
#   - 版本默认 8.1.1861，与 meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://www.drive5.com/usearch/
#   bioconda : https://anaconda.org/bioconda/usearch
#   (容器：quay.io/biocontainers/usearch:8.1.1861--h9ee0642_0 / depot.galaxyproject.org)
#
# 用法示例：
#   bash install.sh                                # auto：有 conda/mamba 走 bioconda，否则提示自行获取
#   bash install.sh --method conda                 # 强制 conda（默认建独立 env: usearch）
#   bash install.sh --method binary --bin /path/usearch   # 校验用户自备二进制
#   bash install.sh --conda-env usearch8 --force
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="8.1.1861"
VERSION="$DEFAULT_VERSION"
CONDA_ENV="usearch"
METHOD="auto"          # auto | conda | binary
BIN_PATH=""            # binary 模式下用户指定的 usearch 路径
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

license_notice() {
    cat >&2 <<'EOF'
--------------------------------------------------------------------------------
⚠️  USEARCH 许可提示：USEARCH 为 drive5 商业软件；学术免费但需注册下载并遵守其许可协议。
    本脚本不内置任何需注册的下载链接。若用于商业用途，请先获得 drive5 授权。
    8.1.1861 历史二进制经 rcedgar/usearch_old_binaries 以 CC0-1.0 重发布（bioconda 亦据此打包）。
--------------------------------------------------------------------------------
EOF
}

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|binary}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --bin)         BIN_PATH="${2:?--bin 需要 usearch 路径}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（USEARCH 8 无 --version；运行 banner 含版本号） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" 2>&1 || true)"
    grep -q "${VERSION}" <<<"$out" || die "版本校验失败：期望输出包含 ${VERSION}，实际见上（也可能该二进制版本不符）"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    license_notice
    log "使用 conda 安装 usearch=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "usearch=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "usearch=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV usearch（输出 banner 含版本）"
    "$CONDA_BIN" run -n "$CONDA_ENV" usearch 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 usearch"
}

# ---------------- 路线 B：用户自备二进制（不下载，仅校验） ----------------
install_binary() {
    local bin
    license_notice
    if [[ -n "$BIN_PATH" ]]; then
        bin="$BIN_PATH"
    else
        bin="$(command -v usearch || true)"
    fi
    if [[ -z "$bin" || ! -x "$bin" ]]; then
        cat >&2 <<EOF
[install] 未找到可执行的 usearch（binary 路线不自动下载，需你自行获取授权副本）。
  获取方式：前往 drive5 官网注册并下载，或使用已安装 usearch 的环境；随后可用：
      bash install.sh --method binary --bin /path/to/usearch
  推荐直接用 conda 路线（无需注册，bioconda 已打包 8.1.1861）：
      bash install.sh --method conda
  或直接用官方容器：
      docker run --rm -u \$(id -u):\$(id -g) quay.io/biocontainers/usearch:8.1.1861--h9ee0642_0 usearch -cluster_otus ...
EOF
        exit 1
    fi
    log "校验用户自备二进制: $bin"
    assert_version "$bin"
    log "完成：已将 $bin 作为 usearch（如不在 PATH，请自行建立软链接）"
}

# ---------------- 主流程 ----------------
log "usearch $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
            warn "未检测到 mamba/conda；binary 路线因许可限制不自动下载"
            install_binary
        fi ;;
esac
log "安装成功"
