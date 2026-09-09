#!/usr/bin/env bash
# =============================================================================
# install.sh — LoRDEC 宿主机本地安装脚本
#
# 归属    ：bioskills modules/lordec/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / 安装方式登记对齐）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，bioconda 频道 lordec
#     （-c conda-forge -c bioconda lordec=0.9；2026-09 核实 bioconda 有 0.9，
#     linux-64 lordec-0.9-h77376b9_3 / osx-64 lordec-0.9-h892528c_3，2022-02-24 上传）
#   - source 路线（无 conda 兜底）：官方源码包 lordec-src_<ver>.tar.bz2（gite.lirmm.fr
#     uploads 稳定直链，官方仅发布 md5、无 sha256）→ 按官方 conda build.sh 同款命令
#     `make CXX=... all` + `PREFIX=<prefix>/bin make install` 编译安装到用户前缀
#     --prefix（默认 ~/software/lordec-<ver>），免 root、不写 /opt/biosoft、/home/train
#   - 版本默认 0.9，与 modules/lordec/meta.yaml software_versions.native 对齐
#
# 官方来源（2026-09-08 逐渠道核实）：
#   homepage : http://www.atgc-montpellier.fr/lordec/
#   releases : https://gite.lirmm.fr/lordec/lordec-releases（public 项目；releases/tags API 为空，
#              源码以 uploads 附件形式发布：lordec-src_0.9.tar.bz2）
#   src 直链 : https://gite.lirmm.fr/lordec/lordec-releases/uploads/800a96d81b3348e368a0ff3a260a88e1/lordec-src_0.9.tar.bz2
#              （curl HEAD 200 稳定直链、非一次性 token；md5 dc57581bf2d265bd245f824a1e74209b，
#              来自 bioconda recipe 官方值 —— 官方渠道只发布 md5，无 sha256）
#   bioconda : https://anaconda.org/bioconda/lordec（lordec=0.9；官方 recipe 测试判据：
#              lordec-trim -h 2>&1 | grep Usage）
#   brew     : homebrew-core 与 brewsci/bio 两源均无 lordec 公式（404）→ 不提供 brew 路线
#   (容器：官方镜像 quay.io/biocontainers/lordec:0.9--h77376b9_3 /
#    depot.galaxyproject.org sif 直拉，见模块 README「环境安装」；本地不再自建配方)
#
# 源码编译说明（历史路径，见 README「历史留存/源码编译」）：
#   lordec-src_0.9 为 C++ 工程（依赖 GATB core 1.4.1 + Boost + HDF5 + zlib；官方 conda recipe
#   host/run 均 pin gatb=1.4.1 + boost + hdf5 + zlib）。源码 Makefile 默认
#   AUTOMATIC_LIBBOOST_LOCAL_INSTALL=yes，make 时会尝试自动下载并编译 GATB core
#   （github.com/GATB/gatb-core/archive/v1.4.1.tar.gz，2026-09-08 探测 200）与 Boost 1.64 头
#   （sourceforge kent.dl 镜像，2026-09-08 探测超时 000 → 自动 Boost 下载可能失败；失败时请装
#   系统 Boost 头（Debian/Ubuntu: libboost-dev；macOS: brew install boost）或改走 conda 路线）。
#   因此 source 路线需要：make + C++ 编译器 + cmake + wget + hdf5/zlib 开发库（且需联网）。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 conda（bioconda），否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: lordec）
#   bash install.sh --method source                   # 强制源码编译（无需 conda）
#   bash install.sh --conda-env lordec09 --force      # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/lordec             # source 模式自定义前缀
#   bash install.sh --version 0.6                     # 覆盖版本（gite 直链不可用时提示走 conda）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="0.9"
EXPECTED_MD5="dc57581bf2d265bd245f824a1e74209b"   # 官方 bioconda recipe 值（md5，非 sha256）
GITE_UPLOAD_ID="800a96d81b3348e368a0ff3a260a88e1"  # lordec-src_0.9.tar.bz2 的 gite uploads id
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/lordec-$DEFAULT_VERSION}"
CONDA_ENV="lordec"
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
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（lordec 无统一 --version；官方/bioconda 判据为 -h 输出含 Usage） ----------------
assert_ready() {
    local bindir="$1" out
    for prog in lordec-correct lordec-trim lordec-trim-split; do
        [[ -x "$bindir/$prog" ]] || die "版本校验失败：$bindir/${prog} 不存在"
    done
    # bioconda recipe 测试同款判据：lordec-trim -h 2>&1 | grep Usage（lordec -h 帮助走 stderr 且可能返回非 0，故加 || true）
    out="$("$bindir/lordec-trim" -h 2>&1 || true)"
    grep -qi "Usage" <<<"$out" \
        || die "lordec 未就绪：lordec-trim -h 输出未命中 Usage 文本"
    log "lordec ${VERSION} 可用（lordec-correct / lordec-trim / lordec-trim-split 就绪）"
}

# ---------------- 路线 A：conda（bioconda 官方频道，含 0.9） ----------------
install_conda() {
    local env_exists out
    log "使用 conda 安装 lordec=${VERSION}（-c conda-forge -c bioconda）到环境: ${CONDA_ENV}"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "lordec=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "lordec=${VERSION}"
    fi
    log "验证：conda run -n ${CONDA_ENV} lordec-trim -h（grep Usage）"
    out="$("$CONDA_BIN" run -n "$CONDA_ENV" lordec-trim -h 2>&1 || true)"
    grep -qi "Usage" <<<"$out" \
        || die "conda 安装后 lordec-trim -h 未命中 Usage 文本"
    "$CONDA_BIN" list -n "$CONDA_ENV" lordec | sed 's/^/  /'
    log "完成：conda activate ${CONDA_ENV} 后即可使用 lordec-correct / lordec-trim / lordec-trim-split"
}

# ---------------- 路线 B：官方源码包编译（C++：GATB core + Boost + HDF5，用户级前缀，免 conda） ----------------
source_platform_deps_ok() {
    # 工具链：make + C++ 编译器 + cmake（Makefile 自动编译 GATB core 需要）+ wget（Makefile 自动下载用）
    command -v make >/dev/null 2>&1 || return 1
    command -v cmake >/dev/null 2>&1 || return 1
    command -v wget >/dev/null 2>&1 || return 1
    if [[ "$OS" == "Linux" ]]; then
        command -v g++ >/dev/null 2>&1 || return 1
        # HDF5 头/库（Debian: libhdf5-dev libhdf5-cpp-dev? lordec 只需 C 版 hdf5；zlib1g-dev）
        [[ -f /usr/include/hdf5/serial/hdf5.h || -f /usr/include/hdf5.h ]] || return 1
    elif [[ "$OS" == "Darwin" ]]; then
        (command -v clang++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1) || return 1
        [[ -n "$(brew --prefix hdf5 2>/dev/null || true)" ]] || return 1
    else
        return 1
    fi
    return 0
}

install_source() {
    local tmp="" url src_dir cxx nproc
    if ! source_platform_deps_ok; then
        die "源码编译缺少依赖：需要 make + C++ 编译器 + cmake + wget + HDF5/zlib 开发库（且需联网让
  Makefile 自动下载编译 GATB core）。Debian/Ubuntu 请装：
  sudo apt-get install -y --no-install-recommends build-essential g++ make cmake wget \
      libhdf5-dev zlib1g-dev libboost-dev
macOS（Homebrew）：xcode-select --install && brew install cmake wget hdf5 boost
若不便安装上述依赖，推荐改用 conda 路线（--method conda）。"
    fi
    log "使用官方源码包编译 lordec=${VERSION} 到前缀: ${PREFIX}"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    # 1) 下载官方源码包（gite.lirmm.fr uploads 稳定直链；官方仅发布 md5）
    url="https://gite.lirmm.fr/lordec/lordec-releases/uploads/${GITE_UPLOAD_ID}/lordec-src_${VERSION}.tar.bz2"
    log "下载源码包: ${url}"
    curl -fsSL -o "$tmp/lordec-src.tar.bz2" "$url" 2>/dev/null \
        || wget -qO "$tmp/lordec-src.tar.bz2" "$url" \
        || die "下载官方源码包失败（需要 curl 或 wget）"

    # 2) md5 校验（官方仅发布 md5、无 sha256；非默认版本时提示自行核对）
    if command -v md5 >/dev/null 2>&1; then
        actual_md5="$(md5 -q "$tmp/lordec-src.tar.bz2" 2>/dev/null || true)"
    elif command -v md5sum >/dev/null 2>&1; then
        actual_md5="$(md5sum "$tmp/lordec-src.tar.bz2" | awk '{print $1}')"
    else
        actual_md5=""
    fi
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if [[ -n "$actual_md5" ]]; then
            [[ "$actual_md5" == "$EXPECTED_MD5" ]] \
                || die "md5 校验失败：期望 ${EXPECTED_MD5}，实际 ${actual_md5}（下载可能不完整或被篡改）"
            log "md5 校验通过（${EXPECTED_MD5}；官方 recipe 值）"
        else
            warn "未找到 md5/md5sum，跳过内嵌 md5 校验（官方仅发布 md5，建议手工核对）"
        fi
    else
        warn "--version ${VERSION} 为非默认版本（默认 ${DEFAULT_VERSION}），跳过内嵌 md5 校验；"
             "且 gite uploads 附件 id 仅对应 0.9，请自行核对官方 releases 页是否有 ${VERSION} 源码包"
    fi

    # 3) 解压并定位源码根（内含 Makefile；目录名形如 lordec-src_0.9/）
    tar -xjf "$tmp/lordec-src.tar.bz2" -C "$tmp"
    src_dir="$(find "$tmp" -maxdepth 2 -mindepth 1 -type d -name 'lordec-src*' | head -n 1 || true)"
    if [[ -z "$src_dir" || ! -f "$src_dir/Makefile" ]]; then
        # 兜底：直接找 Makefile 所在目录
        src_dir="$(dirname "$(find "$tmp" -maxdepth 3 -type f -name Makefile | head -n 1 || true)")"
    fi
    [[ -n "$src_dir" && -f "$src_dir/Makefile" ]] || die "源码包内未找到 Makefile（lordec-src_${VERSION}.tar.bz2 结构异常）"
    log "源码目录: ${src_dir}"

    # 4) 编译 + 安装（与官方 conda build.sh 同款：make CXX=... all + PREFIX=<bin> make install）
    #    Makefile 默认 AUTOMATIC_LIBBOOST_LOCAL_INSTALL=yes 且会自动下载编译 GATB core；
    #    boost sourceforge 镜像 2026-09 探测超时 → 若失败请装系统 boost 头（libboost-dev/brew boost）
    #    并把 CXX 指向可用编译器后重跑。
    if [[ "$OS" == "Darwin" ]]; then
        cxx="${CXX:-clang++}"
    else
        cxx="${CXX:-g++}"
    fi
    nproc="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
    log "执行: make -j${nproc} CXX=${cxx} all（官方 build.sh 同款；自动拉取编译 GATB core，耗时较长）"
    ( cd "$src_dir" && make -j"$nproc" CXX="$cxx" all )
    log "执行: PREFIX=${PREFIX}/bin make install（官方 build.sh 同款）"
    ( cd "$src_dir" && PREFIX="$PREFIX/bin" make install )
    # 兜底：若 install target 未安装（个别环境），直接复制编译产物
    if [[ ! -x "$PREFIX/bin/lordec-correct" ]]; then
        warn "make install 未生成 lordec-correct，尝试从源码目录复制编译产物"
        ( cd "$src_dir" && find . -maxdepth 2 -type f \( -name 'lordec-correct' -o -name 'lordec-trim' \
            -o -name 'lordec-trim-split' -o -name 'lordec-stats' -o -name 'lordec-build-SR-graph' \) \
            -exec install -m 0755 {} "$PREFIX/bin/" \; )
    fi

    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_ready "$PREFIX/bin"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# lordec (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 lordec-correct 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "lordec ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
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
            log "未检测到 mamba/conda，转官方源码编译路线（需 make/g++/cmake/wget + hdf5 开发库；见 --help）"
            install_source
        fi ;;
esac
log "安装成功"
