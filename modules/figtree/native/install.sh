#!/usr/bin/env bash
# =============================================================================
# install.sh — FigTree 宿主机本地安装脚本
#
# 归属    ：bioskills modules/figtree/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5；官方镜像优先语境）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::figtree=1.4.4
#   - binary 路线（无 conda 兜底）：官方 GitHub release 预编译包，解压到用户级前缀
#     --prefix（默认 ~/software/FigTree_v1.4.4），无需 root、不写 /opt
#   - 版本默认 1.4.4，与 modules/figtree/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://tree.bio.ed.ac.uk/software/figtree/
#   release  : https://github.com/rambaut/figtree/releases/tag/v1.4.4
#   source   : https://github.com/rambaut/figtree/archive/refs/tags/v1.4.4.tar.gz（ant 构建）
#   (容器：quay.io/biocontainers/figtree:1.4.4--hdfd78af_1 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                               # auto：有 conda/mamba 走 bioconda，否则官方预编译包
#   bash install.sh --method conda                # 强制 conda（默认建独立 env: figtree）
#   bash install.sh --method binary               # 强制官方 release 包（无需 conda）
#   bash install.sh --conda-env ft --force        # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/FigTree        # binary 模式自定义前缀（即 FIGTREE_HOME）
#   bash install.sh --version 1.4.4 --force       # 覆盖版本（跳过内嵌 sha256 校验并提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.4.4"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/FigTree_v$DEFAULT_VERSION}"
CONDA_ENV="figtree"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方预编译包（FigTree_v<ver>.tgz）内嵌 sha256（Java 包跨平台）
SHA256_TARBALL="529b867657b29e369cf81cd361e6a76bd713d488a63b91932df2385800423aa8"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|binary}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

command -v java >/dev/null 2>&1 || die "未检测到 java（FigTree 需 JRE 运行；请先安装 Java）"

CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 figtree=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "figtree=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "figtree=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV figtree -help"
    "$CONDA_BIN" run -n "$CONDA_ENV" figtree -help 2>&1 | grep -q "${VERSION//./\.}" \
        || die "版本校验失败：期望输出含 ${VERSION}"
    log "完成：conda activate $CONDA_ENV 后即可使用 figtree"
}

# ---------------- 路线 B：官方 GitHub release 预编译包 ----------------
install_binary() {
    local url tgz srcdir
    tgz="FigTree_v${VERSION}.tgz"
    url="https://github.com/rambaut/figtree/releases/download/v${VERSION}/${tgz}"

    log "下载官方预编译包: $url"
    log "安装前缀（FIGTREE_HOME）: $PREFIX"
    [[ "$FORCE" == 1 || ! -e "$PREFIX" ]] || die "前缀已存在：${PREFIX}（加 --force 覆盖，或 --prefix 指定其它目录）"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/$tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/$tgz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_TARBALL  $tmp/$tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_TARBALL  $tmp/$tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    tar -xzf "$tmp/$tgz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'FigTree_*' | head -1)"
    [[ -n "$srcdir" ]] || die "release 包结构异常（未找到 FigTree_* 目录）"
    [[ -f "$srcdir/lib/figtree.jar" ]] || die "release 包内未找到 lib/figtree.jar"
    cp -R "$srcdir"/. "$PREFIX"/

    # 生成 $PREFIX/bin/figtree 包装脚本（java -jar + JVM 内存）
    mkdir -p "$PREFIX/bin"
    cat > "$PREFIX/bin/figtree" <<EOF
#!/usr/bin/env bash
# FigTree 包装脚本（bioskills install.sh 生成）：export FIGTREE_HOME=${PREFIX}
export FIGTREE_HOME="${PREFIX}"
exec java \${JAVA_OPTS:-} -jar "${PREFIX}/lib/figtree.jar" "\$@"
EOF
    chmod 0755 "$PREFIX/bin/figtree"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 版本断言：figtree -help 输出含 1.4.4
    "$PREFIX/bin/figtree" -help 2>&1 | grep -q "${VERSION//./\.}" \
        || die "版本校验失败：期望输出含 ${VERSION}"
    log "已安装（FigTree v${VERSION}）；FIGTREE_HOME=$PREFIX"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# figtree (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 figtree 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "figtree $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            install_binary
        fi ;;
esac
log "安装成功"
