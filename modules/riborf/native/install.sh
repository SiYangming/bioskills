#!/usr/bin/env bash
# =============================================================================
# install.sh — riborf（RibORF 2.0）宿主机本地安装脚本
#
# 归属    ：bioskills modules/riborf/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」对齐）
#   RibORF 无官方 biocontainer，社区渠道有 quay.io/bioinfortools/riborf（补充），
#   conda 包维护在 YangmingSi 频道。宿主机安装双路线：
#     - conda  路线（默认优先）：mamba/conda 建独立 env（-c conda-forge -c bioconda -c YangmingSi）
#     - source 路线（无 conda 兜底）：git clone zhejilab/RibORF，把 RibORF.2.0/*.pl 部署到
#       --prefix（默认 ~/software/riborf-2.0），无需 root
#   - 版本默认 2.0，与 modules/riborf/meta.yaml software_versions.native 对齐。
#   - 注意：完整 Ribo-seq 流程仍需 bowtie2/tophat/R(r-e1071)/samtools/bedtools —— conda 路线由
#     riborf 包依赖自动带入；source 路线只装 perl 脚本本体，流程工具请另装 conda 环境。
#
# 官方来源：
#   github  : https://github.com/zhejilab/RibORF
#   conda   : https://anaconda.org/channels/YangmingSi/packages/riborf/overview
#   容器    : quay.io/bioinfortools/riborf:2.1（社区；无官方 biocontainer）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 conda，否则 git 部署
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: riborf）
#   bash install.sh --method source                   # 强制 git 部署 perl 脚本（无需 conda）
#   bash install.sh --conda-env riborf2 --force       # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/riborf             # source 模式自定义前缀
# =============================================================================
set -euo pipefail

DEFAULT_VERSION="2.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/riborf-$DEFAULT_VERSION}"
CONDA_ENV="riborf"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

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

OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（RibORF 无 --version；以脚本可编译 + README 版本行为准） ----------------
assert_source() {
    local dir="$1" pl="$dir/ribORF.pl"
    [[ -f "$pl" ]] || die "未找到 ribORF.pl（${dir}），安装不完整"
    command -v perl >/dev/null 2>&1 || die "需要 perl（apt-get install perl 或 conda 路线）"
    perl -c "$pl" >/dev/null 2>&1 || die "perl -c 编译失败: $pl"
    grep -qi 'version 2.0' "$dir/README.txt" 2>/dev/null || warn "README.txt 未含版本号（请人工核对）"
    log "版本断言通过：RibORF ${VERSION}（perl 脚本可编译）"
}

# ---------------- 路线 A：conda（YangmingSi 频道） ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 riborf=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda -c YangmingSi "riborf=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda -c YangmingSi "riborf=${VERSION}"
    fi
    log "验证：环境内 perl 脚本可解析（removeAdapter.pl / ribORF.pl）"
    "$CONDA_BIN" run -n "$CONDA_ENV" sh -c 'command -v ribORF.pl && perl -c "$(command -v ribORF.pl)" >/dev/null' \
        || die "conda 环境内 RibORF 脚本校验失败"
    log "完成：conda activate $CONDA_ENV 后即可运行 python native/main.py <subcommand>"
}

# ---------------- 路线 B：git 部署 perl 脚本（无 conda 兜底） ----------------
install_source() {
    command -v git >/dev/null 2>&1 || die "source 路线需要 git"
    log "git 部署 RibORF ${VERSION} 到前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    git clone --depth 1 https://github.com/zhejilab/RibORF.git "$tmp/RibORF" >/dev/null 2>&1
    local src="$tmp/RibORF/RibORF.2.0"
    [[ -d "$src" ]] || die "RibORF.2.0 目录缺失（上游结构变化？）"
    # 复制全部子脚本 + 说明 + 许可证到 bin（保留目录组织便于追溯）
    mkdir -p "$PREFIX/bin/RibORF.2.0"
    cp "$src"/*.pl "$PREFIX/bin/RibORF.2.0/"
    cp "$src"/README.txt "$src"/LICENSE "$PREFIX/bin/RibORF.2.0/" 2>/dev/null || true
    # 为无 shebang 的脚本补 #!/usr/bin/env perl 并赋执行权限（等价 bioinfortools:2.1 打包修复）
    for pl_file in "$PREFIX/bin/RibORF.2.0"/*.pl; do
        if ! head -1 "$pl_file" | grep -q "^#!/usr/bin/env perl"; then
            sed -i '1i#!/usr/bin/env perl' "$pl_file"
        fi
        chmod +x "$pl_file"
    done
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_source "$PREFIX/bin/RibORF.2.0"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin/RibORF.2.0:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin/RibORF.2.0" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin/RibORF.2.0，跳过写入 $PROFILE"
        else
            { echo ""; echo "# riborf (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后即可用；完整流程工具（bowtie2/tophat/R）请另配 conda 环境"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin/RibORF.2.0:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "riborf $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
            warn "未检测到 mamba/conda，改走 git 部署路线（仅 perl 脚本本体）"
            install_source
        fi ;;
esac
log "安装成功"
