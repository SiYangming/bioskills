#!/usr/bin/env bash
# =============================================================================
# install.sh — Musket 宿主机本地安装脚本
#
# 归属    ：bioskills modules/musket/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」）
#   - source 路线（默认）：官方 SourceForge 源码包 musket-<ver>.tar.gz（官方仅发布
#     C++ 源码、无预编译二进制 release；最新 1.1，2013-10-09）→ make（官方 README：
#     Type "make" in the root directory）→ musket 部署到用户前缀 --prefix
#     （默认 ~/software/musket-<ver>），免 root、不写 /opt/biosoft、不写 /home/train；
#     安装后写 PATH 到 --profile 并做「迷你修正冒烟」断言。
#   - conda 路线（--method conda）：musket 不在 bioconda、也不在 conda-forge
#     （2026-09-08 API 核实均 {"error":"musket" could not be found"}）→ 仅建
#     python 驱动 env（python=3.11 + pyyaml，供 native/main.py 的 Schema/自省使用）；
#     musket 本体仍需按 source 路线 / 容器镜像另行部署（conda 分支末尾提示）。
#   - 版本默认 1.1，与 modules/musket/meta.yaml software_versions.native 对齐
#
# 官方来源（2026-09-08 逐渠道核实）：
#   homepage : https://musket.sourceforge.net/（参数文档 = homepage.htm：官方 README）
#   project  : https://sourceforge.net/projects/musket/（License: Apache-2.0 + GPL-2.0）
#   source   : https://downloads.sourceforge.net/project/musket/musket-1.1.tar.gz
#              112.1 kB；2026-09-08 HEAD 302 → master.dl.sourceforge.net（真实存在）。
#              注意官方文件名为 .tar.gz —— 部分教学文档所记 .tar.bz2 直链 404 不存在。
#   sha256   ：SourceForge 不提供文件摘要、无 bioconda/brew recipe 可参照 → 官方未公布
#              （本脚本不内嵌、不编造 sha；有校验需求请自行对下载文件计算）。
#   (容器自建：native/Dockerfile + Apptainer.def —— 官方 bioconda/quay/depot 全无，见模块 README)
#
# 用法示例：
#   bash install.sh                                   # 默认 source：下载官方源码 → make → ~/software/musket-1.1
#   bash install.sh --method source                   # 强制官方源码编译路线
#   bash install.sh --method conda                    # 仅建 python 驱动 env（本体另行部署）
#   bash install.sh --conda-env musket-driver --force # 指定驱动 env 名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/musket             # source 模式自定义前缀
#   bash install.sh --version 1.0.8                   # 覆盖版本（URL 模板 musket-<ver>.tar.gz）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/musket-$DEFAULT_VERSION}"
CONDA_ENV="musket-native"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

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
        *) die "未知参数: ${1}（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 可用性断言：musket 无 --version/--help（官方 README 参数表核实） ----------------
# 官方参数表（musket.sourceforge.net/homepage.htm）无 version/help 选项 → 无法用 <bin> --version
# 断言；采用「真实迷你修正冒烟」：1 条小 FASTQ → musket 修正 → 输出文件非空即判定可用。
# （2026-09 录入：无参运行输出形态未核实，故不用 grep 用法文本作判据。）
assert_smoke() {
    local bin="$1" work out
    work="$(mktemp -d)"
    # 4 条 60 bp reads（末条在第 31 位放 1 个替换错误，模拟低覆盖替换错误；质量行统一 'I'）
    printf '@r1\n%s\n+\n%s\n' \
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT" \
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" > "$work/smoke_in.fastq"
    printf '@r2\n%s\n+\n%s\n' \
        "TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCA" \
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" >> "$work/smoke_in.fastq"
    printf '@r3\n%s\n+\n%s\n' \
        "GGGGAAAACCCCAAAAGGGGAAAACCCCAAAAGGGGAAAACCCCAAAAGGGGAAAACCCCAAAA" \
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" >> "$work/smoke_in.fastq"
    printf '@r4\n%s\n+\n%s\n' \
        "TTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGG" \
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" >> "$work/smoke_in.fastq"
    out="$work/smoke_out.fastq"
    if ! "$bin" -k 21 100000 -o "$out" "$work/smoke_in.fastq" >"$work/smoke.log" 2>&1; then
        sed 's/^/    /' "$work/smoke.log" >&2 || true
        rm -rf "$work"
        die "musket 冒烟运行失败（退出非 0）：${bin} -k 21 100000 -o ...（完整输出见上）"
    fi
    if [[ ! -s "$out" ]]; then
        sed 's/^/    /' "$work/smoke.log" >&2 || true
        rm -rf "$work"
        die "musket 冒烟输出为空（修正未产出任何 reads？）"
    fi
    rm -rf "$work"
    log "冒烟通过：musket ${VERSION} 可运行并正常产出修正输出（无官方 --version，此即可用性判据）"
}

# ---------------- 路线 A：官方源码包编译（默认；C++ 工程，用户级前缀，免 conda） ----------------
source_platform_deps_ok() {
    command -v make >/dev/null 2>&1 || return 1
    command -v cc >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 || return 1
    return 0
}

install_source() {
    local tmp="" url mkf src_dir bin_src hasher
    if ! source_platform_deps_ok; then
        die "源码编译缺少依赖：需要 make + C++ 编译器（g++/clang）。macOS 请装 Xcode Command Line
  Tools（xcode-select --install）；Debian/Ubuntu: sudo apt-get install -y --no-install-recommends
  build-essential make zlib1g-dev；再重跑本脚本。"
    fi
    # zlib 头检查（Linux 上 -zlib 输出 / gzip 输入需 zlib；macOS 系统自带）
    if [[ "$OS" == "Linux" ]] && ! { [[ -f /usr/include/zlib.h ]] || ls /usr/include/*/zlib.h >/dev/null 2>&1; }; then
        die "缺少 zlib 开发头（zlib.h）：Debian/Ubuntu 请先 sudo apt-get install -y --no-install-recommends zlib1g-dev（musket 读 gzip 输入/写 zlib 输出需要 zlib）"
    fi
    log "使用官方源码包编译 musket=${VERSION} 到前缀: ${PREFIX}"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    # 1) 下载官方源码包（sourceforge 直链；官方无预编译二进制 release；文件名 musket-<ver>.tar.gz）
    url="https://downloads.sourceforge.net/project/musket/musket-${VERSION}.tar.gz"
    log "下载源码包: ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/musket.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/musket.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码包"
    fi
    # sha256 说明：SourceForge 不提供文件摘要、无 bioconda/brew recipe 参照 → 官方未公布即不编造；
    # 非默认版本覆盖时同样提示自行核对（URL 模板 musket-<ver>.tar.gz，旧版如 1.0.8 仍适用）。
    warn "musket-${VERSION}.tar.gz 官方未公布 sha256（SourceForge 不提供摘要）→ 跳过内嵌校验；如需完整性校验请自行计算核对"

    # 2) 解压并定位 Makefile（官方包结构：musket-<ver>/Makefile，make 在源码根目录执行）
    tar -xzf "$tmp/musket.tar.gz" -C "$tmp"
    mkf="$(find "$tmp" -maxdepth 2 -type f -name Makefile | head -n 1 || true)"
    [[ -n "$mkf" ]] || die "源码包内未找到 Makefile（musket-${VERSION}.tar.gz 结构异常）"
    src_dir="$(dirname "$mkf")"
    log "源码目录: ${src_dir}"

    # 3) make 编译（官方 README：Type "make" in the root directory）
    make -C "$src_dir"
    # 定位产物二进制（源码根生成 musket；顶层目录名随版本变化）
    bin_src="$(find "$src_dir" -maxdepth 2 -type f -name musket -perm -u+x | head -n 1 || true)"
    [[ -n "$bin_src" ]] || bin_src="$src_dir/musket"
    [[ -x "$bin_src" ]] || die "make 未生成可执行文件 musket（查看 ${src_dir}/Makefile；可能需要较新 g++/zlib1g-dev）"
    install -m 0755 "$bin_src" "$PREFIX/bin/musket"

    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_smoke "$PREFIX/bin/musket"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# musket (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 musket 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 路线 B：conda（仅 python 驱动 env；musket 本体不在 bioconda/conda-forge） ----------------
install_conda() {
    log "使用 conda 建 python 驱动 env=${CONDA_ENV}（python=3.11 + pyyaml）"
    log "注意：Musket 不在 bioconda、也不在 conda-forge（2026-09-08 核实 API 均返回 "
    log "      {\"error\":\"musket\" could not be found}），conda 分支只提供 native/main.py 驱动环境"
    log "      （--schema/--list-commands 自省用）；musket 本体请另行："
    log "      1) bash install.sh --method source（官方 sourceforge 源码 make）；或"
    log "      2) 容器镜像（见模块 README「Docker / Apptainer」自建配方）"
    local env_exists=""
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge python=3.11 pyyaml
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge python=3.11 pyyaml
    fi
    # 断言驱动 env 可用（pyyaml 供 base.py / main.py 自省）
    "$CONDA_BIN" run -n "$CONDA_ENV" python -c "import yaml; print('pyyaml OK', yaml.__version__)" \
        || die "conda 驱动 env 校验失败"
    log "完成：conda activate ${CONDA_ENV} 后可用 python main.py --schema 自省；musket 本体按上方提示部署"
}

# ---------------- 主流程 ----------------
log "musket ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source|auto)
        # musket 无 conda 包 → auto 默认即官方源码编译路线（需 make + C++ 编译器）
        install_source ;;
esac
log "安装成功"
