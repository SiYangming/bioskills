#!/usr/bin/env bash
# =============================================================================
# install.sh — PacBioToCA / PBcR（wgs-assembler 8.3rc2）宿主机安装脚本（登记型）
#
# 归属    ：bioskills modules/pacbiotoca/native/install.sh（native 实现安装方式）
# 性质    ：⚠️ deprecated 软件（上游 2015-05 停更、官方 wiki 建议改用 Canu）。
#           本脚本只做「安装方法登记」：命令与官方 README/wiki 一致即可，仅为
#           历史复现服务；新项目请用 Canu / Flye / hifiasm。
# 形态    ：现代规范（AGENT.md §4.5 参数契约 / §7 官方镜像优先）下的最小化实现
#   - source 路线（默认 auto 优先）：官方源码包 wgs-8.3rc2.tar.bz2（sourceforge）
#     → 官方编译步骤（README 原文）：
#         bzip2 -dc wgs-8.3rc2.tar.bz2 | tar -xf -
#         cd wgs-8.3rc2 && cd kmer && make install && cd .. && cd src && make
#     → 整个 wgs-8.3rc2/ 部署到用户前缀 --prefix（默认 ~/software/wgs-8.3rc2），
#     免 root、不写 /opt/biosoft、/home/train
#   - conda 路线（--method conda 显式）：bioconda 历史包 wgs-assembler=8.3
#     （2017-02-22 后未维护；linux-64；依赖 2017 时代 blasr/falcon/pbdagcon 等，
#     仅历史复现，不建议新项目）→ 建独立 env
#   - 版本断言：fastqToCA/PBcR/runCA 均无 --version 旗标（未核实存在任何版本
#     输出开关）→ 退化为判二进制存在且可执行
#   - Perl 依赖：PBcR 等驱动脚本需 Statistics::Descriptive（cpanm 安装；apt 包名
#     libstatistics-descriptive-perl；conda 渠道无该模块包，2026-09 核实）
#
# 官方来源（2026-09-08 逐渠道核实）：
#   homepage : http://wgs-assembler.sourceforge.net/（wiki：PBcR 页顶部即 deprecated 声明）
#   files    : https://sourceforge.net/projects/wgs-assembler/files/wgs-assembler/wgs-8.3/
#   source   : https://downloads.sourceforge.net/project/wgs-assembler/wgs-assembler/wgs-8.3/wgs-8.3rc2.tar.bz2
#   （同目录另有 2015-05-24 Linux_amd64 / 2015-12-22 Darwin_amd64 预编译包可免编译解压即用；
#     官方未提供 sha256 摘要页 → 本脚本不内嵌校验值（未核实），下载后请自行核对文件区）
#   bioconda : https://anaconda.org/bioconda/wgs-assembler（wgs-assembler=8.3，
#              最后更新 2017-02-22，pl5.22.0_0，仅 linux-64）
#   quay/depot : biocontainers/wgs-assembler:8.3--pl5.22.0_0（历史镜像，见模块 README）
#   brew     : homebrew-core 与 brewsci/bio 均无公式（404 核实）→ 无 brew 路线
#
# 用法示例：
#   bash install.sh                                   # auto：默认官方源码编译路线
#   bash install.sh --method source                   # 强制官方源码编译（推荐）
#   bash install.sh --method conda                    # 强制 bioconda 历史包（仅 linux-64）
#   bash install.sh --prefix ~/opt/wgs-8.3rc2         # source 模式自定义前缀
#   bash install.sh --conda-env wgs83 --force         # conda 环境名 / 已存在时强制重建
#   bash install.sh --version 8.3rc1                  # 覆盖为旧 rc（非默认版本提示自查）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="8.3rc2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/wgs-$DEFAULT_VERSION}"
CONDA_ENV="pacbiotoca-native"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方源码包直链（sourceforge downloads 镜像；同文件区另有 *-Linux_amd64 /
# Darwin_amd64 预编译包，见 README「环境安装」§4）
SOURCE_URL_BASE="https://downloads.sourceforge.net/project/wgs-assembler/wgs-assembler/wgs-8.3"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    # 打印文件头注释（两个 ==== 装饰行之间），自动截断，不粘连脚本正文
    awk 'NR==1 {next} /^# ===/{n++; if(n==2) exit} {sub(/^# ?/,""); print}' "$0"
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

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（二进制无 --version → 判二进制存在） ----------------
# wgs 8.3 二进制未核实存在版本输出开关 → 以 <arch>/bin 下核心二进制存在且可执行为准
BIN_NAMES=(runCA fastqToCA PBcR)
assert_ready() {
    local bindir="$1" b missing=0
    for b in "${BIN_NAMES[@]}"; do
        if [[ ! -x "$bindir/$b" ]]; then
            warn "缺少可执行文件: ${bindir}/${b}"
            missing=1
        fi
    done
    if [[ "$missing" == 1 ]]; then
        die "wgs-${VERSION} 未就绪：${bindir} 下缺少核心二进制（runCA/fastqToCA/PBcR）"
    fi
    log "wgs-${VERSION} 可用（${bindir}：runCA / fastqToCA / PBcR 均在）"
}

# ---------------- 路线 source：官方源码包编译（默认/推荐；录入官方 README 步骤） ----------------
source_platform_deps_ok() {
    command -v bzip2 >/dev/null 2>&1 || return 1
    command -v tar   >/dev/null 2>&1 || return 1
    command -v make  >/dev/null 2>&1 || return 1
    command -v g++   >/dev/null 2>&1 || command -v c++ >/dev/null 2>&1 || return 1
    return 0
}

install_source() {
    local tmp="" url src_dir arch_dir
    warn "⚠️ Celera Assembler（wgs-assembler）已淘汰（官方建议 Canu 替代）：以下仅为历史复现安装。"
    if [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "--version ${VERSION} ≠ 默认 ${DEFAULT_VERSION}：sourceforge 最新发布即 8.3rc2"
        warn "（2015-05-24；上游无正式 8.3）。将尝试下载 wgs-${VERSION}，请自行核对文件区可用性。"
    fi
    if ! source_platform_deps_ok; then
        die "源码编译缺少依赖：需要 bzip2 / tar / make / C++ 编译器（g++ 或 c++）。
  Debian/Ubuntu: sudo apt-get install -y --no-install-recommends bzip2 make g++ perl
  macOS: xcode-select --install（自带 clang++）；再重跑本脚本。"
    fi
    # 平台守卫：8.3rc2 官方编译面向 2015 时代的 Linux/macOS x86_64
    case "${OS}/${ARCH}" in
        Linux/x86_64)   arch_dir="Linux-amd64" ;;
        Darwin/x86_64)  arch_dir="Darwin-amd64" ;;
        *)
            die "平台 ${OS}/${ARCH} 非官方支持（2015 时代仅 x86_64）；可试用官方
  Linux_amd64 预编译包于容器/虚拟机，或改用 Canu/Flye/hifiasm。"
            ;;
    esac

    log "官方源码包编译 wgs-${VERSION}（${OS}/${ARCH}）→ 前缀: ${PREFIX}"
    mkdir -p "$(dirname "$PREFIX")"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    # 1) 下载官方源码包（sourceforge 直链；官方无 sha256 摘要页 → 不内嵌校验，未核实）
    url="${SOURCE_URL_BASE}/wgs-${VERSION}.tar.bz2"
    log "下载源码包: ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$tmp/wgs.tar.bz2" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/wgs.tar.bz2" "$url"
    else
        die "需要 curl 或 wget 下载源码包"
    fi
    warn "官方未提供 sha256 摘要页：脚本不内嵌校验值（未核实），下载后请自行对照"
    warn "sourceforge 文件区（wgs-${VERSION}.tar.bz2，8.3rc2 为 24.6 MB）。"

    # 2) 解压（官方 README 原步骤）
    bzip2 -dc "$tmp/wgs.tar.bz2" | tar -xf - -C "$tmp"
    src_dir="$tmp/wgs-${VERSION}"
    [[ -d "$src_dir/kmer" && -d "$src_dir/src" ]] \
        || die "源码包结构异常：未在 wgs-${VERSION}/ 下找到 kmer/ 与 src/（解压目录: ${src_dir}）"

    # 3) 编译（官方 README 原步骤：kmer 先 install，src 再 make）
    log "编译 kmer 子包（官方：cd kmer && make install）："
    ( cd "$src_dir/kmer" && make install )
    log "编译 src（官方：cd src && make）："
    ( cd "$src_dir/src" && make )

    # 4) 部署整个 wgs-${VERSION}/ 到用户前缀（编译产物在 <arch>/bin，如 Linux-amd64/bin）
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀 ${PREFIX} 已存在（--force），先删除"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 覆盖，或 --prefix 指定其它路径"
        fi
    fi
    mv "$src_dir" "$PREFIX"
    log "已部署到 ${PREFIX}"

    # 5) 版本断言（无 --version → 判 <arch>/bin 核心二进制存在）
    assert_ready "$PREFIX/$arch_dir/bin"

    # 6) Perl 依赖登记：PBcR 等驱动脚本需 Statistics::Descriptive（cpanm）
    if command -v perl >/dev/null 2>&1 \
       && perl -MStatistics::Descriptive -e 1 >/dev/null 2>&1; then
        log "Perl Statistics::Descriptive 已可用"
    else
        warn "Perl 模块 Statistics::Descriptive 未安装（PBcR 驱动脚本依赖）——"
        warn "安装方式：cpanm Statistics::Descriptive   （推荐，需先装 cpanminus）"
        warn "        或 apt-get install libstatistics-descriptive-perl（Debian/Ubuntu）"
        warn "conda 渠道无该模块包（2026-09 核实）；缺失时 PBcR 会报错，runCA 主流程不受影响。"
    fi

    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 7) PATH 写入
    local bindir="$PREFIX/$arch_dir/bin"
    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$bindir:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$bindir" "$PROFILE"; then
            log "PATH 已包含 ${bindir}，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# wgs-assembler ${VERSION} (bioskills install.sh, deprecated)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 fastqToCA / PBcR 即可（仅供历史复现）"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"${bindir}:\$PATH\""
    fi
}

# ---------------- 路线 conda：bioconda 历史包（--method conda 显式；仅 linux-64） ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
    warn "⚠️ bioconda wgs-assembler=8.3 为 2017-02-22 后未维护的历史包（perl 5.22 老构建，"
    warn "依赖 2017 时代 blasr/falcon/pbdagcon 等），仅历史复现；推荐 --method source。"
    if [[ "${OS}" != "Linux" || "${ARCH}" != "x86_64" ]]; then
        die "bioconda wgs-assembler 仅 linux-64 有包（2026-09 核实）：当前 ${OS}/${ARCH} 无法走 conda 路线，请改用 --method source"
    fi
    local env_exists
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    log "创建环境 ${CONDA_ENV}（-c conda-forge -c bioconda wgs-assembler=8.3）"
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "wgs-assembler=8.3"
    local env_root bin_dir
    env_root="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')"
    bin_dir="${env_root}/bin"
    # 版本断言：判环境内核心二进制存在（无 --version 可判）
    assert_ready "$bin_dir"
    "$CONDA_BIN" list -n "$CONDA_ENV" wgs-assembler | sed 's/^/  /'
    log "完成：conda activate ${CONDA_ENV} 后运行 fastqToCA / PBcR（仅供历史复现）"
}

# ---------------- 主流程 ----------------
log "pacbiotoca（wgs-assembler ${VERSION}）安装开始（本机 ${OS}/${ARCH}；软件 deprecated）"
case "$METHOD" in
    conda)
        install_conda ;;
    source)
        install_source ;;
    auto)
        log "auto：优先官方源码编译路线（默认；conda 历史包质量差，需显式 --method conda）"
        install_source ;;
esac
log "安装成功"
