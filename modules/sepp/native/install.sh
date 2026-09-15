#!/usr/bin/env bash
# =============================================================================
# install.sh — SEPP 宿主机本地安装脚本
#
# 归属    ：bioskills modules/sepp/native/install.sh（native 实现安装方式）
# 现代规范（AGENT.md §4.5 / README「环境安装」对齐）：
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::sepp
#   - source 路线（无 conda 兜底）：官方 GitHub 源码归档 4.3.10.tar.gz，
#     pip 装 dendropy 后 `python setup.py config && python setup.py install --prefix`
#     部署到用户级前缀（默认 ~/software/sepp-<ver>），无需 root、不写 /opt
#   - 版本默认 4.3.10，与 modules/sepp/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/smirarab/sepp
#   bioconda : https://anaconda.org/bioconda/sepp
#   source   : https://github.com/smirarab/sepp/archive/refs/tags/4.3.10.tar.gz
#   (容器：quay.io/biocontainers/sepp —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码安装
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: sepp）
#   bash install.sh --method source                   # 强制官方源码安装（python setup.py config && install）
#   bash install.sh --conda-env sepp --force          # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/sepp               # source 模式自定义前缀
#   bash install.sh --version 4.3.10                  # 覆盖版本（source 模式 URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="4.3.10"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/sepp-$DEFAULT_VERSION}"
CONDA_ENV="sepp"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码归档（GitHub tag archive）内嵌 sha256（平台无关）；改 --version 后不匹配 → 跳过并提示
SHA256_SOURCE_TARBALL="daea1469f5ef33268300fbe946fae3b04d41cd740a763bc42efcf1e3a5d2b837"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
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
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"; fi

# ---------------- 版本断言（安装后运行 run_sepp.py -v 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -v 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 sepp=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "sepp=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "sepp=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV run_sepp.py -v"
    "$CONDA_BIN" run -n "$CONDA_ENV" run_sepp.py -v 2>&1 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 run_sepp.py / run_upp.py"
}

# ---------------- 路线 B：官方源码安装（python setup.py config && install） ----------------
install_source() {
    local url tar srcdir tmp=""
    url="https://github.com/smirarab/sepp/archive/refs/tags/${VERSION}.tar.gz"
    log "下载官方源码: $url"
    log "安装前缀: $PREFIX"

    [[ -n "$PYTHON_BIN" ]] || die "源码安装需要 python/py3（未在 PATH 中检测到）"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fSL -o "$tmp/sepp.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/sepp.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${SHA256_SOURCE_TARBALL:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SOURCE_TARBALL  $tmp/sepp.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_SOURCE_TARBALL  $tmp/sepp.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    tar -xzf "$tmp/sepp.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    cd "$srcdir"

    # 依赖 dendropy（官方要求）；无 root 时用 --user 装到用户 site-packages
    log "安装依赖 dendropy"
    "$PYTHON_BIN" -m pip install --user dendropy

    log "构建与安装（python setup.py config && python setup.py install --prefix）"
    "$PYTHON_BIN" setup.py config
    "$PYTHON_BIN" setup.py install --prefix="$PREFIX"

    # 收集 console scripts（SEPP 的 run_sepp.py / run_upp.py 通常落在 <prefix>/bin）
    local bin_dir="$PREFIX/bin"
    [[ -d "$bin_dir" ]] || bin_dir="$(find "$PREFIX" -maxdepth 3 -type f -name run_sepp.py | head -1 | xargs -r dirname)"
    [[ -n "$bin_dir" && -f "$bin_dir/run_sepp.py" ]] || die "未找到安装后的 run_sepp.py（前缀：$PREFIX）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$bin_dir/run_sepp.py"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$bin_dir:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$bin_dir" "$PROFILE"; then
            log "PATH 已包含 $bin_dir，跳过写入 $PROFILE"
        else
            { echo ""; echo "# sepp (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 run_sepp.py 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$bin_dir:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "sepp $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
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
