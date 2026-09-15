#!/usr/bin/env bash
# =============================================================================
# install.sh — Tracer v1.7.1 宿主机本地安装脚本
#
# 归属    ：bioskills modules/tracer/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::tracer
#   - binary 路线（无 conda 兜底）：官方 GitHub release 预编译包（Java，平台无关），
#     解压到 --prefix（默认 ~/software/Tracer-<ver>），无需 root、不写 /opt
#   - 版本默认 1.7.1，与 modules/tracer/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://tree.bio.ed.ac.uk/software/tracer/
#   bioconda : https://anaconda.org/bioconda/tracer
#   release  : https://github.com/beast-dev/tracer/releases
#   (容器：quay.io/biocontainers/tracer —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方预编译包
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: tracer）
#   bash install.sh --method binary                   # 强制官方预编译包（需 java）
#   bash install.sh --conda-env tracer --force        # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/Tracer             # binary 模式自定义前缀
#   bash install.sh --version 1.7.2                   # 覆盖版本（URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
#
# 注：Tracer 为交互式 Java GUI，无 `--version` 子命令；安装校验改为断言 bin/tracer 与
#     lib/tracer.jar 存在 + README.txt 版本行（见 assert_tracer）。
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.7.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/Tracer-$DEFAULT_VERSION}"
CONDA_ENV="tracer"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release 预编译包（Java，平台无关）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_TGZ="200d7ffa1e48994b71245994e299847ac2be72d3d5c37d9048418557e1d8c12e"

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

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# binary 模式仅覆盖 Linux / macOS（官方预编译包为 Java 跨平台，但仍限定主流桌面/服务器平台）
platform_ok_binary() {
    { [[ "$OS" == "Linux" && ( "$ARCH" == "x86_64" || "$ARCH" == "aarch64" ) ]] ||
      [[ "$OS" == "Darwin" ]]; }
}

# ---------------- 安装后校验（Tracer 无 --version：断言启动器/jar 与 README 版本行） ----------------
assert_tracer() {
    local dir="$1"
    [[ -x "$dir/bin/tracer" ]] || die "缺少可执行启动器: $dir/bin/tracer"
    [[ -f "$dir/lib/tracer.jar" ]] || die "缺少 lib/tracer.jar"
    if [[ -f "$dir/README.txt" ]]; then
        grep -qE "Version ${VERSION//./\\.}" "$dir/README.txt" \
            || warn "README.txt 未命中 'Version ${VERSION}'（仅提示，文件结构校验已通过）"
    fi
    log "结构校验通过：$dir/bin/tracer + $dir/lib/tracer.jar"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 tracer=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "tracer=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "tracer=$VERSION"
    fi
    log "校验：conda list -n $CONDA_ENV tracer"
    "$CONDA_BIN" list -n "$CONDA_ENV" tracer | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 tracer（JVM 调优走 JAVA_OPTS）"
}

# ---------------- 路线 B：官方 GitHub release 预编译包 ----------------
install_binary() {
    local url sha tmp srcdir
    url="https://github.com/beast-dev/tracer/releases/download/v${VERSION}/Tracer_v${VERSION}.tgz"
    sha="$SHA256_TGZ"

    log "下载官方预编译包: $url"
    log "安装前缀: $PREFIX"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/Tracer.tgz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/Tracer.tgz" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/Tracer.tgz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/Tracer.tgz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    mkdir -p "$PREFIX"
    tar -xzf "$tmp/Tracer.tgz" -C "$PREFIX" --strip-components=1
    srcdir="$PREFIX"
    chmod 755 "$srcdir/bin/tracer"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_tracer "$srcdir"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# tracer (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 tracer 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "tracer $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方预编译包；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）无官方预编译包，无法自动安装"
        fi ;;
esac
log "安装成功"
