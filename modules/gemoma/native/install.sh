#!/usr/bin/env bash
# =============================================================================
# install.sh — GeMoMa 宿主机本地安装脚本
#
# 归属    ：bioskills modules/gemoma/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7；官方镜像优先，宿主机走 conda / 官方 Java 包）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::gemoma=1.9
#     （提供 GeMoMa 包装脚本，内部 java -jar GeMoMa-1.9.jar CLI）
#   - binary 路线（官方 Java 包）：jstacs.de 官方 GeMoMa-1.9.zip（jar + 脚本，纯 Java 无需编译），
#     解压到用户前缀（默认 ~/software/GeMoMa-1.9），无需 root、不写 /opt
#   - 版本默认 1.9，与 modules/gemoma/meta.yaml software_versions.native 对齐
#
# 依赖说明：需 Java 1.8+（binary 路线运行期）；JAVA_OPTS（-Xmx）由 main.py 透传。
#
# 官方来源：
#   homepage : http://www.jstacs.de/index.php/GeMoMa
#   download : http://www.jstacs.de/download.php?which=GeMoMa（302 -> downloads/GeMoMa-1.9.zip）
#   bioconda : https://anaconda.org/bioconda/gemoma
#   （容器：quay.io/biocontainers/gemoma —— 本脚本为宿主机安装，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 Java 包
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: gemoma）
#   bash install.sh --method binary                   # 强制官方 Java 包（需 java）
#   bash install.sh --conda-env gemoma --force        # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/GeMoMa             # binary 模式自定义前缀
#   bash install.sh --version 1.9                     # 覆盖版本（跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.9"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/GeMoMa-$DEFAULT_VERSION}"
CONDA_ENV="gemoma"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 Java 包（jstacs.de）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_ZIP="45765e9eee37c21b4e84f86b15cd83a9e3f44317d78f7b121ee7fcd74ad345d8"

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

# ---------------- 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言 ----------------
assert_version() {
    local jar="$1" out
    ls "$jar" | grep -qE "GeMoMa-${VERSION//./\.}\\." || die "版本校验失败：未找到 GeMoMa-${VERSION}.jar"
    if command -v java >/dev/null 2>&1; then
        out="$(java -jar "$jar" CLI 2>&1 | head -n 3 || true)"
        printf '  %s\n' "$out"
    fi
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 gemoma=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "gemoma=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "gemoma=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV GeMoMa CLI | head -n 3"
    "$CONDA_BIN" run -n "$CONDA_ENV" GeMoMa CLI 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 GeMoMa（= java -jar GeMoMa-$VERSION.jar CLI）"
}

# ---------------- 路线 B：官方 Java 包 ----------------
install_binary() {
    local url zip sha tmp jar
    url="https://www.jstacs.de/downloads/GeMoMa-${VERSION}.zip"
    sha="$SHA256_ZIP"
    command -v java >/dev/null 2>&1 || warn "未检测到 java（GeMoMa 运行需 Java 1.8+）"

    log "下载官方 Java 包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/gemoma.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/gemoma.zip" "$url"
    else
        die "需要 curl 或 wget 下载官方 Java 包"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" && -n "${sha:-}" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/gemoma.zip" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/gemoma.zip" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    elif [[ "$VERSION" != "$DEFAULT_VERSION" ]]; then
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官网摘要）"
    fi

    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$tmp/gemoma.zip" -d "$PREFIX"
    else
        die "需要 unzip 解压官方 Java 包"
    fi
    jar="$(find "$PREFIX" -maxdepth 2 -type f -name "GeMoMa-${VERSION}.jar" | head -1)"
    [[ -n "$jar" ]] || die "Java 包内未找到 GeMoMa-${VERSION}.jar（URL 或版本号有误？）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$jar"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local dir; dir="$(dirname "$jar")"
        local line="export GEMOMA_HOME=\"$dir\""
        if [[ -f "$PROFILE" ]] && grep -qF "GEMOMA_HOME=\"$dir\"" "$PROFILE"; then
            log "$PROFILE 已包含 GEMOMA_HOME，跳过写入"
        else
            { echo ""; echo "# gemoma (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 GEMOMA_HOME 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE；${dir}/ 下含 GeMoMa-${VERSION}.jar 与运行脚本"
    else
        log "完成（未改 profile）：使用时请 export GEMOMA_HOME=\"$(dirname "$jar")\""
    fi
}

# ---------------- 主流程 ----------------
log "gemoma $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
