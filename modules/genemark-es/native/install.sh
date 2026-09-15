#!/usr/bin/env bash
# =============================================================================
# install.sh — GeneMark-ES/ET（gmes_petap）宿主机本地安装脚本
#
# 归属    ：bioskills modules/genemark-es/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方渠道全无 → 官方包 + 自建容器兜底）
#   - 官方渠道核实：bioconda genemark-es 404、quay.io/biocontainers/genemark-es 未找到、
#     depot.galaxyproject.org 无 genemark*（2026-09-11 核实）→ 无官方镜像/conda 包；
#     官方许可禁止再分发，官方 gmes 包需在官网同意许可后下载。
#   - binary 路线（默认，推荐）：--tarball 指定官方 gmes_linux_64_*.tar.gz（或 gmes_linux_64_4.tar.gz），
#     解压到用户前缀（默认 ~/software/gmes_linux_64_4），无需 root、不写 /opt
#   - conda 路线（备选，非官方）：第三方频道 HCC::genemark-et / thiesgehrmann::genemark_es
#     （bioconda 无 genemark-es；此处仅为便利，非官方维护，版本以频道为准）
#
# 官方来源：
#   homepage : http://topaz.gatech.edu/GeneMark/（现 https://exon.gatech.edu/GeneMark/）
#   download : http://topaz.gatech.edu/GeneMark/license_download.cgi（ver 4.72_lic，LINUX 64；需同意许可）
#   key      : gm_key_64.gz（同页申请），解压后装到 ~/.gm_key
#
# 依赖说明：Perl 及 CPAN 模块 YAML / Hash::Merge / Logger::Simple / Parallel::ForkManager；
#   运行需 ~/.gm_key，并建议设置 GENEMARK_PATH 指向安装目录；容器镜像见 native/Dockerfile 与 Apptainer.def。
#
# 用法示例：
#   bash install.sh --tarball ~/Downloads/gmes_linux_64_4.tar.gz     # 官方包解压部署（推荐）
#   bash install.sh --tarball gmes.tar.gz --prefix ~/opt/gmes --force
#   bash install.sh --method conda --conda-env genemark-es           # 第三方频道（非官方，备选）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="4.72"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/gmes_linux_64_4}"
CONDA_ENV="genemark-es"
METHOD="auto"          # auto | binary | conda
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
TARBALL=""

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
        --tarball)     TARBALL="${2:?--tarball 需要官方 gmes 包路径}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|binary|conda}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|binary|conda) ;; *) die "--method 仅支持 auto|binary|conda（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# 官方渠道核实结论（写入日志，便于追溯）
log "官方渠道核实（2026-09-11）：bioconda genemark-es 404 / quay 未找到 / depot 无 genemark* → 无官方镜像"

# ---------------- 路线 A：官方包解压部署（推荐） ----------------
install_binary() {
    local src tarfile tmp
    src="${TARBALL:-}"
    if [[ -z "$src" ]]; then
        die "未提供官方 gmes 包：请在官网同意许可后下载 gmes_linux_64_*.tar.gz，再用 --tarball <路径> 部署
    下载页：http://topaz.gatech.edu/GeneMark/license_download.cgi（GeneMark-ES/ET/EP ver ${VERSION}_lic, LINUX 64）
    密钥页：同页申请 gm_key_64.gz，解压后装到 ~/.gm_key"
    fi
    [[ -f "$src" ]] || die "找不到 tarball: $src"
    tarfile="$(basename "$src")"

    log "官方 gmes 包: $src"
    log "安装前缀: $PREFIX"
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀已存在（--force），删除重建: $PREFIX"
            rm -rf "$PREFIX"
        else
            die "前缀已存在: $PREFIX（加 --force 覆盖重建，或改用 --prefix）"
        fi
    fi

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    tar -xzf "$src" -C "$tmp"
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'gmes*' | head -1)"
    [[ -n "$srcdir" ]] || die "包内未找到 gmes* 目录（tarball 是否正确？）"
    mkdir -p "$(dirname "$PREFIX")"
    cp -a "$srcdir" "$PREFIX"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 断言主脚本存在（gmes_petap.pl 为 GeneMark-ES/ET 入口）
    [[ -f "$PREFIX/gmes_petap.pl" || -f "$PREFIX/bin/gmes_petap.pl" ]] \
        || die "未在前缀内找到 gmes_petap.pl（包结构异常？）"

    # 许可密钥检查（运行必需，官方许可禁止再分发密钥）
    if [[ -f "$HOME/.gm_key" ]]; then
        log "检测到许可密钥 ~/.gm_key"
    else
        warn "未检测到 ~/.gm_key：请在官网申请 gm_key_64.gz 后：gzip -dc gm_key_64.gz > ~/.gm_key && chmod 600 ~/.gm_key"
    fi
    warn "Perl 依赖（YAML / Hash::Merge / Logger::Simple / Parallel::ForkManager）需另行安装（apt: libyaml-perl libhash-merge-perl liblogger-simple-perl libparallel-forkmanager-perl，或 sudo cpan -i ...）"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        {
            echo ""
            echo "# genemark-es (bioskills install.sh)"
            echo "export GENEMARK_PATH=\"$PREFIX\""
            echo "export PATH=\"$PREFIX:\$PATH\""
        } >> "$PROFILE"
        log "已追加 GENEMARK_PATH / PATH 到 $PROFILE"
        log "完成：重新登录或 source $PROFILE 后执行 gmes_petap.pl 即可"
    else
        log "完成（未改 profile）：使用时请 export GENEMARK_PATH=\"$PREFIX\" 且把 $PREFIX 加入 PATH"
    fi
}

# ---------------- 路线 B：conda（第三方频道，非官方，备选） ----------------
install_conda() {
    local env_exists
    warn "bioconda 无 genemark-es（404）；本路线使用第三方频道 HCC::genemark-et（非官方维护，版本以频道为准）"
    log "使用 conda 安装 Genemark 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda -c HCC genemark-et
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda -c HCC genemark-et
    fi
    log "验证：conda run -n $CONDA_ENV gmes_petap.pl --version（若无 --version 则打印说明）"
    "$CONDA_BIN" run -n "$CONDA_ENV" bash -lc 'command -v gmes_petap.pl || true' | sed 's/^/  /' || true
    warn "运行仍需 ~/.gm_key（官网申请）；GENEMARK_PATH 通常需指向该环境的 share 目录"
}

# ---------------- 主流程 ----------------
log "genemark-es $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    binary)
        install_binary ;;
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    auto)
        if [[ -n "$TARBALL" ]]; then
            install_binary
        elif [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            die "未提供 --tarball 且未检测到 conda/mamba；请在官网同意许可后下载 gmes_linux_64_*.tar.gz 后重试：
    bash install.sh --tarball <gmes_linux_64_4.tar.gz>"
        fi ;;
esac
log "安装成功"
