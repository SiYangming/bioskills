#!/usr/bin/env bash
# =============================================================================
# install.sh — LongReadSum 宿主机本地安装脚本
#
# 归属    ：bioskills modules/longreadsum/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / 自建兜底对齐）
#   - conda 路线（默认优先）：mamba/conda 创建独立环境，pin wglab 频道 longreadsum
#     （-c wglab -c conda-forge -c jannessp -c bioconda；wglab 频道 2026-09 核实含 1.6.0）
#   - source 路线（无 conda 兜底）：git clone v1.6.0 tag → make swig_build +
#     setup.py build_ext（SWIG C++ 编译；需要 g++/swig/htslib/HDF5 开发库），
#     venv + pip 装 Python 运行依赖（numpy/plotly/pyarrow/pod5），用户级前缀安装到
#     --prefix（默认 ~/software/longreadsum-<ver>），无需 root、不写 /opt/biosoft
#   - 版本默认 1.6.0，与 modules/longreadsum/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/WGLab/LongReadSum
#   bioconda : https://anaconda.org/bioconda/longreadsum（官方仅到 1.3.1，非本脚本默认源）
#   wglab    : https://anaconda.org/wglab/longreadsum（1.6.0）
#   release  : https://github.com/WGLab/LongReadSum/releases/tag/v1.6.0（无二进制资产，源码 tag）
#   (容器：官方仅 1.3.1；1.6.0 走 native/Dockerfile 自建或 quay.io/bioinfortools/longreadsum:1.6.0 社区镜像，见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 conda（wglab），否则源码编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: longreadsum）
#   bash install.sh --method source                   # 强制源码编译（无需 conda）
#   bash install.sh --conda-env lrs --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/longreadsum        # source 模式自定义前缀
#   bash install.sh --version 1.5.0                   # 覆盖版本（tag URL 模板 + wglab conda pin）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.6.0"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/longreadsum-$DEFAULT_VERSION}"
CONDA_ENV="longreadsum"
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

# ---------------- 版本断言（longreadsum 无 --version 子命令：以 --help 主帮助可用为准） ----------------
assert_ready() {
    local bin="$1" out
    out="$("$bin" --help 2>&1)" || die "longreadsum 未就绪：--help 执行失败"
    grep -qiE "File types|outputfolder" <<<"$out" \
        || die "版本校验失败：--help 输出不符合 longreadsum（期望含 File types）"
    log "longreadsum 可用（版本目标 ${VERSION}）"
}

# ---------------- 路线 A：conda（wglab 频道含 1.6.0） ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 longreadsum=${VERSION}（-c wglab 频道）到环境: ${CONDA_ENV}"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 官方 README 推荐顺序：wglab 在前（作者频道，含 1.6.0；bioconda 仅 1.3.1）
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c wglab -c conda-forge -c jannessp -c bioconda "longreadsum=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c wglab -c conda-forge -c jannessp -c bioconda "longreadsum=${VERSION}"
    fi
    log "验证：conda run -n ${CONDA_ENV} longreadsum --help"
    "$CONDA_BIN" run -n "$CONDA_ENV" longreadsum --help >/dev/null 2>&1 \
        || die "conda 安装后 longreadsum --help 执行失败"
    "$CONDA_BIN" list -n "$CONDA_ENV" longreadsum | sed 's/^/  /'
    log "完成：conda activate ${CONDA_ENV} 后即可使用 longreadsum"
}

# ---------------- 路线 B：源码编译（SWIG C++，用户级前缀 + venv，免 conda） ----------------
source_platform_deps_ok() {
    # 检查编译工具链与 htslib/HDF5 开发库（Debian 系包名；macOS 走 Homebrew htslib/hdf5）
    for t in g++ make swig python3 git; do
        command -v "$t" >/dev/null 2>&1 || return 1
    done
    if [[ "$OS" == "Linux" ]]; then
        for f in /usr/include/htslib/sam.h /usr/include/hdf5/serial/H5Cpp.h; do
            [[ -f "$f" ]] || return 1
        done
    elif [[ "$OS" == "Darwin" ]]; then
        # Homebrew htslib/hdf5（含 HDF5 C++ 头）
        local hb
        hb="$(brew --prefix htslib 2>/dev/null || true)"
        [[ -n "$hb" && -f "$hb/include/htslib/sam.h" ]] || return 1
        if ! ls "$(brew --prefix hdf5 2>/dev/null)/include/hdf5/serial/H5Cpp.h" >/dev/null 2>&1 \
           && ! ls "$(brew --prefix hdf5 2>/dev/null)/include/H5Cpp.h" >/dev/null 2>&1; then
            return 1
        fi
    else
        return 1
    fi
    return 0
}

find_hdf5_include() {
    # 返回 H5Cpp.h 所在 include 目录（供 CXXFLAGS 注入）
    if [[ "$OS" == "Darwin" ]]; then
        local h5 h5p
        h5p="$(brew --prefix hdf5 2>/dev/null || true)"
        for h5 in "$h5p/include/hdf5/serial" "$h5p/include"; do
            [[ -f "$h5/H5Cpp.h" ]] && { printf '%s' "$h5"; return 0; }
        done
    fi
    [[ -f "/usr/include/hdf5/serial/H5Cpp.h" ]] && { printf '%s' "/usr/include/hdf5/serial"; return 0; }
    return 1
}

install_source() {
    local tmp="" hdf5_inc url src_dir venv_py
    if ! source_platform_deps_ok; then
        die "源码编译缺少依赖：需要 g++/make/swig/git/python3(>=3.9) + htslib 与 HDF5 开发库。Debian/Ubuntu 请装：
  sudo apt-get install -y --no-install-recommends build-essential g++ make swig git python3 python3-venv \
      libhts-dev libhdf5-dev libhdf5-cpp-dev zlib1g-dev libbz2-dev liblzma-dev libcurl4-openssl-dev
macOS（Homebrew）：brew install htslib hdf5 swig；再重跑本脚本。"
    fi
    log "使用源码编译 longreadsum=${VERSION} 到前缀: ${PREFIX}"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    # 1) 下载源码（tag 归档；官方 release 无二进制资产）
    url="https://github.com/WGLab/LongReadSum/archive/refs/tags/v${VERSION}.tar.gz"
    log "下载源码 tag 归档: ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/lrs.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/lrs.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码"
    fi
    tar -xzf "$tmp/lrs.tar.gz" -C "$tmp"
    src_dir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$src_dir" ]] || die "源码解压失败"
    cp -R "$src_dir" "$PREFIX/src"
    src_dir="$PREFIX/src"
    log "源码已放置: ${src_dir}"

    # 2) venv + Python 运行依赖（官方 conda run deps 的 pip 对应物）
    python3 -m venv --help >/dev/null 2>&1 || die "python3 缺少 venv 模块（Debian/Ubuntu: sudo apt-get install python3-venv）"
    python3 -m venv "$PREFIX/venv"
    venv_py="$PREFIX/venv/bin/python"
    "$venv_py" -m pip install --no-cache-dir --upgrade pip
    "$venv_py" -m pip install --no-cache-dir numpy plotly pyarrow pod5
    log "Python 运行依赖（numpy/plotly/pyarrow/pod5）已装入 venv"

    # 3) SWIG + C++ 扩展编译（仿官方 conda/build.sh；HDF5 头路径按平台注入）
    ( cd "$src_dir" && make swig_build )
    hdf5_inc="$(find_hdf5_include)" || die "未找到 H5Cpp.h（HDF5 C++ 开发库缺失）"
    log "使用 HDF5 头目录: ${hdf5_inc}"
    ( cd "$src_dir" && CXXFLAGS="-I${hdf5_inc}" "$venv_py" setup.py build_ext --build-lib lib )
    [[ -f "$src_dir/lib/lrst.py" ]] || die "SWIG 构建失败：未生成 lib/lrst.py"

    # 4) 部署运行目录 + wrapper（注入 lib/src 后调用官方 cli installed 分支）
    mkdir -p "$PREFIX/runtime/lib" "$PREFIX/runtime/src"
    cp "$src_dir"/lib/*.py "$src_dir"/lib/_lrst*.so "$PREFIX/runtime/lib/"
    cp "$src_dir"/src/*.py "$PREFIX/runtime/src/"
    cat > "$PREFIX/bin/longreadsum" <<PYEOF
#!/usr/bin/env bash
exec "$venv_py" -c 'import os,sys; sys.path[:0]=["$PREFIX/runtime/lib","$PREFIX/runtime/src"]; os.environ.setdefault("HDF5_PLUGIN_PATH","/usr/lib/x86_64-linux-gnu/hdf5/plugin"); from cli import main; sys.exit(main())' "\$@"
PYEOF
    chmod 0755 "$PREFIX/bin/longreadsum"

    rm -rf "$tmp"; tmp=""; trap - EXIT
    assert_ready "$PREFIX/bin/longreadsum"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# longreadsum (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 longreadsum 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "longreadsum ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
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
            log "未检测到 mamba/conda，转源码编译路线（需 g++/swig/htslib/HDF5 开发库）"
            install_source
        fi ;;
esac
log "安装成功"
