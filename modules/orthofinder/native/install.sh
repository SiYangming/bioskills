#!/usr/bin/env bash
# =============================================================================
# install.sh — OrthoFinder 宿主机本地安装脚本
#
# 归属    ：bioskills modules/orthofinder/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda 路线（默认优先，跨平台）：mamba/conda 创建独立环境，pin bioconda::orthofinder=2.5.5
#   - binary 路线（官方预编译 standalone 包，仅 linux-x64）：OrthoFinder.tar.gz
#     （内含 frozen orthofinder 可执行 + 捆绑 diamond/mcl/fastme），解压到用户级 --prefix
#   - source 路线（官方源码，需自备依赖）：OrthoFinder_source.tar.gz → 建 orthofinder 包装脚本
#   - 版本默认 2.5.5，与 modules/orthofinder/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/davidemms/OrthoFinder
#   release  : https://github.com/davidemms/OrthoFinder/releases/tag/2.5.5
#   bioconda : https://anaconda.org/bioconda/orthofinder
#   (容器：quay.io/biocontainers/orthofinder —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 说明：orthofinder 2.5.5 无专用 --version；版本号在每次运行启动横幅打印
#      （"OrthoFinder version 2.5.5 ..."），故断言用 `orthofinder -h` 抓版本串。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda；否则 linux-x64 用官方 standalone，其余源码
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: orthofinder）
#   bash install.sh --method binary                   # 强制官方 standalone 预编译包（仅 linux-x64）
#   bash install.sh --method source                   # 强制官方源码（需自备 Python/DIAMOND/MCL/MAFFT/FastTree）
#   bash install.sh --conda-env orthofinder --force
#   bash install.sh --prefix ~/software/orthofinder-2.5.5 --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.5.5"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/orthofinder-$DEFAULT_VERSION}"
CONDA_ENV="orthofinder"
METHOD="auto"          # auto | conda | binary | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release 资产内嵌 sha256（Linux 用 standalone；source 平台无关）
SHA256_BINARY="81dc09a9cfe0cab811359bce0bd3d8d44ff57f9771943ea4b427dc47df576a2d"   # OrthoFinder.tar.gz（linux-x86_64 standalone，含捆绑依赖）
SHA256_SOURCE="43d034a66a13adba8872a0d4a76e32c25305a7fae638754adb61c37a3f957bd9"   # OrthoFinder_source.tar.gz

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|binary|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done
case "$METHOD" in auto|conda|binary|source) ;; *) die "--method 仅支持 auto|conda|binary|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# 官方 standalone 预编译包仅 linux-x86_64（内含 Linux ELF 捆绑依赖）
platform_ok_binary() { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }

# ---------------- 版本断言（orthofinder -h 启动横幅含版本串） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -h 2>&1 || true)"
    printf '  %s\n' "$(head -n 2 <<<"$out" | tr '\n' ' ')"
    grep -qE "${VERSION}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

download() {  # download <url> <outfile>
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$out" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi
}

check_sha256() {  # check_sha256 <file> <sha>
    local file="$1" sha="$2"
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$sha  $file" | sha256sum -c - >/dev/null 2>&1 || die "sha256 校验失败：下载文件不完整或被篡改"
    else
        echo "$sha  $file" | shasum -a 256 -c - >/dev/null 2>&1 || die "sha256 校验失败：下载文件不完整或被篡改"
    fi
    log "sha256 校验通过"
}

write_path() {  # write_path <bindir>
    local bindir="$1" line="export PATH=\"$1:\$PATH\""
    if [[ "$UPDATE_PATH" == 1 ]]; then
        if [[ -f "$PROFILE" ]] && grep -qF "$bindir" "$PROFILE"; then
            log "PATH 已包含 $bindir，跳过写入 $PROFILE"
        else
            { echo ""; echo "# orthofinder (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 orthofinder 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$bindir:\$PATH\""
    fi
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 orthofinder=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "orthofinder=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "orthofinder=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV orthofinder -h"
    "$CONDA_BIN" run -n "$CONDA_ENV" orthofinder -h 2>&1 | grep -m1 -i "OrthoFinder version" | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 orthofinder"
}

# ---------------- 路线 B：官方 standalone 预编译包（仅 linux-x64） ----------------
install_binary() {
    local url tmp="" findir bin_src
    url="https://github.com/davidemms/OrthoFinder/releases/download/${VERSION}/OrthoFinder.tar.gz"

    log "下载官方 standalone 预编译包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    download "$url" "$tmp/OrthoFinder.tar.gz"
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        check_sha256 "$tmp/OrthoFinder.tar.gz" "$SHA256_BINARY"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi
    tar xzf "$tmp/OrthoFinder.tar.gz" -C "$PREFIX"
    findir="$(find "$PREFIX" -maxdepth 1 -mindepth 1 -type d -name 'OrthoFinder*' | head -1)"
    [[ -n "$findir" ]] || die "解压后未找到 OrthoFinder* 目录"
    bin_src="$findir/orthofinder"
    [[ -x "$bin_src" ]] || die "standalone 包内未找到可执行文件 orthofinder"
    ln -sf "$bin_src" "$PREFIX/bin/orthofinder"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/orthofinder"
    write_path "$PREFIX/bin"
}

# ---------------- 路线 C：官方源码（需自备依赖） ----------------
install_source() {
    local url tmp="" findir bin_src
    url="https://github.com/davidemms/OrthoFinder/releases/download/${VERSION}/OrthoFinder_source.tar.gz"

    log "下载官方源码包: $url"
    log "安装前缀: $PREFIX"
    command -v python3 >/dev/null 2>&1 || die "源码路线需 python3（PATH 中未找到）；建议改用 conda 路线"
    warn "源码路线需自备运行依赖：DIAMOND、MCL、MAFFT、FastTree（推荐 conda 路线一并安装）"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    download "$url" "$tmp/OrthoFinder_source.tar.gz"
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        check_sha256 "$tmp/OrthoFinder_source.tar.gz" "$SHA256_SOURCE"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验"
    fi
    tar xzf "$tmp/OrthoFinder_source.tar.gz" -C "$PREFIX"
    findir="$(find "$PREFIX" -maxdepth 1 -mindepth 1 -type d -name 'OrthoFinder*' | head -1)"
    [[ -n "$findir" ]] || die "解压后未找到 OrthoFinder* 目录"
    bin_src="$findir/orthofinder.py"
    [[ -f "$bin_src" ]] || die "源码包内未找到 orthofinder.py"
    # 建 orthofinder 包装脚本（源码入口为 orthofinder.py）
    cat > "$PREFIX/bin/orthofinder" <<EOF
#!/usr/bin/env bash
exec python3 "$bin_src" "\$@"
EOF
    chmod +x "$PREFIX/bin/orthofinder"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/orthofinder"
    write_path "$PREFIX/bin"
}

# ---------------- 主流程 ----------------
log "orthofinder $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译包（standalone 仅 linux-x86_64）；请改用 conda 或 --method source"
        install_binary ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            install_source
        fi ;;
esac
log "安装成功"
