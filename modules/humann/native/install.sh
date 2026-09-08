#!/usr/bin/env bash
# =============================================================================
# install.sh — HUMAnN 宿主机本地安装脚本
#
# 归属    ：bioskills modules/humann/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / §4.5 安装脚本契约）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::humann=3.9 + python=3.12
#     （bioconda 自动携带 bowtie2 / diamond / glpk / metaphlan 依赖）
#     注意：humann-3.9-py312hdfd78af_0 包内文件硬编码 lib/python3.12/site-packages，
#     conda 环境必须 pin python=3.12，否则模块会装进与解释器不匹配的 site-packages 而无法 import
#   - pip/源码路线（无 conda 或 --version 指定 4.0.0a1 时）：官方 PyPI sdist
#     安装到独立 python venv（默认 ~/software/humann-<ver>），免 root、不写 /opt
#   - 版本默认 3.9（bioconda 稳定版），与 meta.yaml software_versions.native 对齐；
#     --version 4.0.0a1 覆盖走作者 v4 alpha 路线（meta software_versions.author_v4_alpha）
#
# 版本说明（2026-09 核实，禁止编造）：
#   - bioconda humann 最新稳定版 3.9（build py312hdfd78af_0，官方镜像
#     quay.io/biocontainers/humann:3.9--py312hdfd78af_0 / depot.galaxyproject.org）
#   - 作者 biobakery/humann master 已推进到 4.0.0.alpha.2；PyPI 上 4.0.0a1 存在
#     （2024-10-28 sdist）；humann --version 输出 "humann v3.9" / "humann v4.0.0.alpha.1"
#   - humann 无官方预编译二进制（纯 Python 包 + 数据库），故本脚本的
#     binary 语义 = PyPI sdist pip 安装（走 pip 自带 TLS/摘要校验，不另内嵌 sha256）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda 3.9，否则 pip/源码
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: humann）
#   bash install.sh --method pip                      # 强制 pip/源码（PyPI sdist）
#   bash install.sh --method binary                   # 同 pip（官方无二进制；binary 为兼容别名）
#   bash install.sh --conda-env hn --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/humann             # pip 模式自定义前缀
#   bash install.sh --version 4.0.0a1                 # 作者 v4 alpha 路线（pip/源码，PyPI sdist）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="3.9"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/humann-$DEFAULT_VERSION}"
CONDA_ENV="humann"
METHOD="auto"          # auto | conda | pip | binary(binary 同 pip)
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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
        --method)      METHOD="${2:?--method 需要 auto|conda|pip|binary}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in
    auto|conda|pip|binary) ;;
    *) die "--method 仅支持 auto|conda|pip|binary（收到: ${METHOD}）" ;;
esac

# binary 为兼容别名：humann 无官方预编译二进制，binary = PyPI sdist pip 路线
if [[ "$METHOD" == "binary" ]]; then
    METHOD="pip"
    warn "--method binary 已映射为 pip 路线（humann 无官方二进制，PyPI sdist 为准）"
fi

# 版本路线判定：默认 3.9 优先 conda；显式 --version 4.0.0a1（作者 v4 alpha）走 pip/源码
PIP_ROUTE=0
if [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
    PIP_ROUTE=1
    warn "非默认版本（${VERSION}）→ 走 pip/源码路线（PyPI sdist；作者 v4 alpha 4.0.0a1 请确保本机有 bowtie2 / diamond / glpk）"
fi

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（输出 "humann v<版本>"） ----------------
# 注意 PEP440：PyPI 4.0.0a1 安装后 humann --version 输出 "humann v4.0.0.alpha.1"，
# 因此匹配段取版本号主段（4.0.0a1 -> 4.0.0）做正则，避免尾部格式差异误判。
assert_version() {
    local bin="$1" out match
    out="$("$bin" --version 2>&1)"
    printf '  %s\n' "$out"
    match="${VERSION%%[a-zA-Z]*}"          # 去尾部 alpha 后缀：4.0.0a1 -> 4.0.0
    grep -qE "${match//./\.}" <<<"$out" || die "版本校验失败：期望输出含 ${match}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda（稳定版 3.9 主路线） ----------------
install_conda() {
    log "使用 conda 安装 humann=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "python=3.12" "humann=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "python=3.12" "humann=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV humann --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" humann --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 humann（含 humann_renorm_table / humann_databases 等）"
}

# ---------------- 路线 B：pip / 官方 PyPI sdist（作者 v4 alpha / 无 conda 兜底） ----------------
install_pip() {
    command -v python3 >/dev/null 2>&1 || die "pip 路线需要 python3（未在 PATH 中找到）"
    log "使用 pip 安装 humann=$VERSION（PyPI sdist）到前缀: $PREFIX"
    log "提示：humann 运行需外部 bowtie2 / diamond / glpk（conda 路线自动携带）；若缺失请自行安装（如 apt install bowtie2 diamond-aligner libglpk40 或 brew install bowtie2 diamond-aligner glpk）"

    if [[ -d "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀 $PREFIX 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 $PREFIX 已存在；加 --force 重建，或改用 --prefix 指定其它路径"
        fi
    fi
    mkdir -p "$PREFIX"

    python3 -m venv "$PREFIX/venv"
    # humann 主流程为纯 Python；工具脚本（barplot/associate）延迟依赖 numpy/scipy，
    # 一并装入避免运行期缺失（numpy 为 humann 生态常见依赖）
    "$PREFIX/venv/bin/pip" install --upgrade pip >/dev/null
    "$PREFIX/venv/bin/pip" install --no-cache-dir "humann==${VERSION}" numpy

    mkdir -p "$PREFIX/bin"
    for s in humann humann_databases humann_join_tables humann_renorm_table \
             humann_regroup_table humann_split_stratified_table humann_unpack_pathways \
             humann_barplot humann_config; do
        if [[ -x "$PREFIX/venv/bin/$s" ]]; then
            ln -sfn "$PREFIX/venv/bin/$s" "$PREFIX/bin/$s"
        fi
    done
    assert_version "$PREFIX/bin/humann"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# humann (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 humann 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
    warn "提示：4.0.0a1 完整 prescreen 需 MetaPhlAn（pip install MetaPhlAn）并下载数据库（humann_databases）；本脚本未自动安装。"
}

# ---------------- 主流程 ----------------
log "humann $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    pip)
        install_pip ;;
    auto)
        if [[ -n "$CONDA_BIN" && "$PIP_ROUTE" == 0 ]]; then
            install_conda
        else
            install_pip
        fi ;;
esac
log "安装成功"
