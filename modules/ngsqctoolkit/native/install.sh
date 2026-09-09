#!/usr/bin/env bash
# =============================================================================
# install.sh — NGSQCToolkit 宿主机本地安装脚本（⚠️ deprecated，仅历史复现）
#
# 归属    ：bioskills modules/ngsqctoolkit/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5/§7）最小化实现
#
# ⚠️ 软件已淘汰（2026-09 登记）：官方主页 https://www.nipgr.ac.in/NGSQCToolkit.php
#    与 v2.3.3 zip（https://www.nipgr.ac.in/ngsqctoolkit/NGSQCToolkit_v2.3.3.zip）
#    均已核实 HTTP 404，旧域名 nipgr.res.in 无法解析；请改用 Trimmomatic / fastp /
#    cutadapt（本仓库 modules/trimmomatic、fastp、cutadapt）。本脚本只为历史复现
#    旧流程服务，不建议新项目使用。
#
# 官方来源：
#   homepage : https://www.nipgr.ac.in/NGSQCToolkit.php（2026-09-08 核实 404）
#   官网 zip : https://www.nipgr.ac.in/ngsqctoolkit/NGSQCToolkit_v2.3.3.zip
#              （2026-09-08 核实 404；脚本仍会先尝试，失败自动回退镜像）
#   镜像主源 : https://github.com/SiYangming/NGSQCToolkit（用户 fork 修复版，
#              tag/release v2.3.3，2026-09-08；对应官方最终 2.3.3，sha256 未核实）
#   镜像备选 : https://github.com/mjain-lab/NGSQCToolkit（作者 lab 源码留存，
#              仅 v2.3 / main 分支，无 2.3.3 后续）
#   Perl 依赖: String::Approx / YAML / GD / GD::Text / GD::Graph（CPAN 在线，
#              2026-09 核实）；conda 兜底包见下
#
# 双路线（最小化）：
#   - conda 路线（默认 auto 优先）：mamba/conda 建独立环境 ngsqctoolkit
#     （conda-forge perl + perl-app-cpanminus；bioconda perl-string-approx /
#     perl-yaml / perl-gd / perl-gdgraph / perl-gdtextutil，2026-09 在线核实存在）
#   - cpan 路线（无 conda 兜底）：宿主 perl + cpanm 安装 CPAN 依赖
#     （GD 需系统 libgd 头文件：macOS `brew install gd` / Debian `apt install libgd-dev`，
#     本脚本不代装系统包）
#   两条路线随后都下载 NGSQCToolkit 脚本包（官网 zip 优先，404 回退 GitHub 镜像）
#   部署到 --prefix（默认 ~/software/ngsqctoolkit-<ver>），并写 NGSQCTOOLKIT_ROOT。
#
# 用法示例：
#   bash install.sh                                   # auto：有 mamba/conda 走 conda，否则 cpan
#   bash install.sh --method conda                    # 强制 conda 路线
#   bash install.sh --method cpan                     # 强制 cpan 路线（需宿主 perl + cpanm）
#   bash install.sh --prefix ~/opt/ngsqctoolkit        # 自定义部署前缀
#   bash install.sh --conda-env ngsqc --force          # 指定环境名 / 强制重建
#   bash install.sh --version 2.3                      # 走旧镜像（mjain-lab，v2.3）；默认 2.3.3 走修复镜像 v2.3.3
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.3.3"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/ngsqctoolkit-$VERSION}"
CONDA_ENV="ngsqctoolkit"
METHOD="auto"          # auto | cpan | conda
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

OFFICIAL_ZIP_URL="https://www.nipgr.ac.in/ngsqctoolkit/NGSQCToolkit_v2.3.3.zip"
MIRROR_ZIP_URL="https://codeload.github.com/SiYangming/NGSQCToolkit/zip/refs/tags/v2.3.3"
MIRROR_LEGACY_ZIP_URL="https://codeload.github.com/mjain-lab/NGSQCToolkit/zip/refs/heads/main"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|cpan|conda}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|cpan|conda) ;; *) die "--method 仅支持 auto|cpan|conda（收到: ${METHOD}）" ;; esac

if [[ "$VERSION" != "2.3.3" && "$VERSION" != "2.3" ]]; then
    warn "--version ${VERSION} 不在已知发布内（2.3.3 官网版 / 2.3 GitHub 镜像版），继续尝试（可能失败）"
fi

# ---------------- 探测 ----------------
OS="$(uname -s)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi
PERL_BIN=""
if command -v perl >/dev/null 2>&1; then PERL_BIN="$(command -v perl)"; fi
CPANM_BIN=""
if command -v cpanm >/dev/null 2>&1; then CPANM_BIN="$(command -v cpanm)"; fi

# ---------------- 下载脚本包（官网 zip 404 已知 → 自动回退 GitHub 镜像） ----------------
# 官网 zip 已于 2026-09-08 核实 404，此处仍先尝试以保留「官网仍在时」的路径；
# 两处 URL 均无官方 sha256 发布 → 不内嵌校验和，下载后仅做 zip 完整性自检（unzip -t）。
fetch_url() { # url outfile：curl 优先，wget 兜底
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$out" "$url"
    else
        die "需要 curl 或 wget 下载 toolkit 包"
    fi
}

fetch_toolkit() {
    local tmp="$1" zip_file ok=0
    zip_file="$tmp/toolkit.zip"

    if [[ "$VERSION" == "2.3.3" ]]; then
        log "尝试官网 zip: ${OFFICIAL_ZIP_URL}"
        if fetch_url "$OFFICIAL_ZIP_URL" "$zip_file" 2>/dev/null; then ok=1; fi
    fi
    if [[ "$ok" == 0 ]]; then
        local murl="$MIRROR_ZIP_URL"
        if [[ "$VERSION" == "2.3.3" ]]; then
            warn "官网 zip 404（2026-09 核实），回退用户修复镜像 tag v2.3.3: ${murl}"
        else
            murl="$MIRROR_LEGACY_ZIP_URL"
            warn "--version=${VERSION} ≠ 2.3.3：回退作者 lab 镜像 main 分支（仅 v2.3）: ${murl}"
        fi
        warn "镜像 sha256 无法核实（无官方摘要发布），仅做 zip 完整性自检"
        fetch_url "$murl" "$zip_file" || die "镜像下载失败（网络受限？可浏览器下载后手动解压到 PREFIX）"
    fi
    (cd "$tmp" && unzip -q -t "$zip_file" >/dev/null) || die "zip 完整性自检失败：${zip_file}"
    (cd "$tmp" && unzip -q "$zip_file") || die "解压失败: ${zip_file}"
    # 顶层目录名不确定（官网 zip / 修复镜像 v2.3.3 为 NGSQCToolkit-2.3.3/，作者镜像为 NGSQCToolkit-main/），统一找含 QC/ 的目录
    local srcdir
    srcdir="$(find "$tmp" -type d -name QC | head -1 | xargs -I{} dirname {})"
    [[ -n "$srcdir" && -d "$srcdir/QC" && -d "$srcdir/Trimming" ]] \
        || die "下载包内未找到 QC/ 与 Trimming/ 目录（URL 或版本有误？）"
    echo "$srcdir"
}

# ---------------- 版本断言（无独立二进制；断言脚本文件 + perl 可用） ----------------
assert_install() {
    local prefix="$1"
    [[ -f "$prefix/QC/IlluQC_PRLL.pl" && -f "$prefix/Trimming/TrimmingReads.pl" \
       && -f "$prefix/Trimming/AmbiguityFiltering.pl" ]] \
        || die "安装断言失败：$prefix 下缺少官方脚本（QC/IlluQC_PRLL.pl 等）"
    local perl_out
    perl_out="$("${PERL_BIN:-perl}" -e 'print $^V' 2>/dev/null)" \
        || die "安装断言失败：perl 不可用"
    printf '  perl %s\n' "$perl_out"
    warn "工具包内部版本号无法独立断言：官网 v2.3.3 zip 已 404（sha256 未核实）；主源镜像 SiYangming tag v2.3.3 对应官方最终版，作者镜像 mjain-lab 仅 v2.3"
    log "脚本文件断言通过：QC/IlluQC_PRLL.pl、Trimming/TrimmingReads.pl、Trimming/AmbiguityFiltering.pl 就位"
}

write_profile() {
    [[ "$UPDATE_PATH" == 1 ]] || return 0
    local line="export NGSQCTOOLKIT_ROOT=\"$PREFIX\""
    if [[ -f "$PROFILE" ]] && grep -qF "NGSQCTOOLKIT_ROOT=\"$PREFIX\"" "$PROFILE"; then
        log "NGSQCTOOLKIT_ROOT 已写入 $PROFILE，跳过"
    else
        { echo ""; echo "# ngsqctoolkit (bioskills install.sh, deprecated 历史复现)"; echo "$line"; } >> "$PROFILE"
        log "已追加 NGSQCTOOLKIT_ROOT 到 ${PROFILE}（main.py 缺省从此读取）"
    fi
}

# ---------------- 路线 A：conda（conda-forge perl + bioconda perl 模块） ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    local env_exists
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    log "conda 创建环境 ${CONDA_ENV}（perl + CPAN 依赖的 bioconda 兜底包）"
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda \
        perl perl-app-cpanminus \
        perl-string-approx perl-yaml perl-gd perl-gdgraph perl-gdtextutil
    log "验证：conda run -n $CONDA_ENV perl -e 'require String::Approx; require YAML; require GD; print qq(perl deps OK\\n)'"
    "$CONDA_BIN" run -n "$CONDA_ENV" perl -e \
        'require String::Approx; require YAML; require GD; print "perl deps OK\n"' \
        || die "conda 环境 perl 依赖加载失败（GD::Text/GD::Graph 若缺失可 conda run -n '"$CONDA_ENV"' cpanm -n GDTextUtil GDGraph）"
    log "完成：conda activate $CONDA_ENV 后运行本模块 main.py"
}

# ---------------- 路线 B：cpan（宿主 perl + cpanm 装依赖） ----------------
install_cpan() {
    [[ -n "$PERL_BIN" ]] || die "--method cpan 但 PATH 中无 perl（先装 perl，或改用 conda 路线）"
    if [[ -z "$CPANM_BIN" ]]; then
        die "PATH 中无 cpanm；请先安装 App::cpanminus（如：cpan App::cpanminus 或 brew install cpanminus），或改用 conda 路线"
    fi
    warn "cpan 路线将在宿主 perl 环境安装模块（GD 编译需要系统 libgd 头文件：macOS 'brew install gd' / Debian 'apt install libgd-dev'；失败时建议改用 conda 路线）"
    cpanm -n String::Approx YAML GD GDTextUtil GDGraph \
        || die "cpanm 安装 Perl 依赖失败（缺少系统库？见上方提示，或改用 conda 路线）"
    log "Perl 依赖安装完成"
}

# ---------------- 主流程 ----------------
log "NGSQCToolkit ${VERSION} 安装开始（⚠️ deprecated，历史复现用；本机 ${OS}）"
mkdir -p "$PREFIX"
tmp="$(mktemp -d)"
cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
trap cleanup_tmp EXIT

case "$METHOD" in
    conda)
        install_conda ;;
    cpan)
        install_cpan ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif [[ -n "$PERL_BIN" ]]; then
            warn "未检测到 mamba/conda，改走 cpan 路线（需 cpanm + 系统 libgd 头文件）"
            install_cpan
        else
            die "未检测到 mamba/conda 且无 perl；请先安装 perl 或 mamba，再运行本脚本"
        fi ;;
esac

srcdir="$(fetch_toolkit "$tmp")"
# 部署脚本包到用户前缀（免 root；禁 /opt/biosoft、/home/train）
log "部署脚本包: ${srcdir} -> ${PREFIX}"
cp -R "$srcdir"/. "$PREFIX"/
# 官方 zip 解压内容在子目录 NGSQCToolkit_v2.3.3/ 时将其内容上提到 PREFIX（已处理：srcdir 即顶层内容所在）
assert_install "$PREFIX"
rm -rf "$tmp"; tmp=""; trap - EXIT

write_profile
log "完成：export NGSQCTOOLKIT_ROOT=\"$PREFIX\" 后即可用 native/main.py 作历史 argv 参考；"
log "新项目请改用 trimmomatic / fastp / cutadapt（本仓库对应模块）"
log "安装成功"
