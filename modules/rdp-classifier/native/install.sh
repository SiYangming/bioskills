#!/usr/bin/env bash
# =============================================================================
# install.sh — RDP Classifier 宿主机本地安装脚本
#
# 归属    ：bioskills modules/rdp-classifier/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::rdp_classifier
#   - binary 路线（无 conda 兜底）：官方 SourceForge 分发包（zip，含 dist/classifier.jar），
#     解压到用户级前缀 --prefix（默认 ~/software/rdp_classifier-<ver>），无需 root、不写 /opt
#   - 版本默认 2.14，与 modules/rdp-classifier/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   project  : https://sourceforge.net/projects/rdp-classifier/
#   code     : https://github.com/rdpstaff/classifier
#   bioconda : https://anaconda.org/bioconda/rdp_classifier
#   容器     : quay.io/biocontainers/rdp_classifier（官方镜像，容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 zip
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: rdp-classifier）
#   bash install.sh --method binary                   # 强制官方 zip（需 java + unzip）
#   bash install.sh --conda-env rdp --force           # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/rdp_classifier     # binary 模式自定义前缀
#   bash install.sh --version 2.13                    # 覆盖版本（binary 模式 URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.14"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/rdp_classifier-$DEFAULT_VERSION}"
CONDA_ENV="rdp-classifier"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 SourceForge 分发包内嵌 sha256（来源：bioconda recipe recipes/rdp_classifier/meta.yaml 的 source.sha256，
# 对应 rdp_classifier_2.14.zip）；改 --version 后自动跳过并提示。
SHA256_DEFAULT_ZIP="2aac7ba2bf602eb025e1791f356c0c437200486ece6905f93219d51395504b2b"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
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
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# RDP Classifier 为 Java 程序：binary 路线要求 java（+unzip）
has_java() { command -v java >/dev/null 2>&1; }

# ---------------- 版本断言（RDP 无 --version：运行无参输出 usage 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" 2>&1 || true)"
    printf '  %s\n' "$(head -n 2 <<<"$out")"
    grep -qi 'classifier' <<<"$out" || die "版本断言失败：期望输出含 'Classifier' 用法信息，实际见上"
    log "rdp_classifier 可用（版本 ${VERSION}）"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 rdp_classifier=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "rdp_classifier=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "rdp_classifier=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV rdp_classifier"
    local out
    out="$("$CONDA_BIN" run -n "$CONDA_ENV" rdp_classifier 2>&1 || true)"
    grep -qi 'classifier' <<<"$out" || die "conda 环境内 rdp_classifier 不可用"
    log "完成：conda activate $CONDA_ENV 后即可使用 rdp_classifier"
}

# ---------------- 路线 B：官方 SourceForge 分发包（zip） ----------------
install_binary() {
    has_java || die "--method binary 需要 java（JRE/JDK >=11）在 PATH 中，请先安装"
    command -v unzip >/dev/null 2>&1 || die "--method binary 需要 unzip 工具"
    local url zip
    url="https://sourceforge.net/projects/rdp-classifier/files/rdp-classifier/rdp_classifier_${VERSION}.zip"
    zip="$PREFIX/rdp_classifier_${VERSION}.zip"

    log "下载官方分发包: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$tmp/rdp.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/rdp.zip" "$url"
    else
        die "需要 curl 或 wget 下载官方分发包"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_DEFAULT_ZIP  $tmp/rdp.zip" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_DEFAULT_ZIP  $tmp/rdp.zip" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过（bioconda recipe 登记的官方分发包摘要）"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对官方下载摘要）"
    fi

    unzip -q "$tmp/rdp.zip" -d "$tmp"
    local srcdir
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'rdp_classifier*' | head -1)"
    [[ -n "$srcdir" && -f "$srcdir/dist/classifier.jar" ]] \
        || die "分发包内未找到 dist/classifier.jar（URL 或版本号有误？）"

    cp -R "$srcdir"/. "$PREFIX/"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    mkdir -p "$PREFIX/bin"
    cat > "$PREFIX/bin/rdp_classifier" <<'WRAP'
#!/usr/bin/env bash
# rdp_classifier 包装脚本（bioskills install.sh 生成）：转发到 dist/classifier.jar
set -eu -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec java -jar "$DIR/dist/classifier.jar" "$@"
WRAP
    chmod +x "$PREFIX/bin/rdp_classifier"

    assert_version "$PREFIX/bin/rdp_classifier"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# rdp_classifier (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 rdp_classifier 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
log "rdp_classifier $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif has_java; then
            install_binary
        else
            die "未检测到 mamba/conda 且无 java；请先安装 mamba（推荐）或 JRE>=11 后重试"
        fi ;;
esac
log "安装成功"
