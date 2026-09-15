#!/usr/bin/env bash
# =============================================================================
# install.sh — VarScan 宿主机本地安装脚本
#
# 归属    ：bioskills modules/varscan/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::varscan
#   - binary 路线（无 conda 兜底）：官方 GitHub jar（VarScan.v2.4.6.jar）部署到
#     用户级前缀 --prefix（默认 ~/software/varscan-<ver>），生成 varscan wrapper
#     无需 root、不写 /opt；需宿主已装 JRE（java）
#   - 版本默认 2.4.6，与 modules/varscan/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://dkoboldt.github.io/varscan/
#   jar      : https://github.com/dkoboldt/varscan/raw/master/VarScan.v2.4.6.jar
#   bioconda : https://anaconda.org/bioconda/varscan
#   (容器：quay.io/biocontainers/varscan —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 jar
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: varscan）
#   bash install.sh --method binary                   # 强制官方 jar（需 java）
#   bash install.sh --conda-env vs --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/varscan            # binary 模式自定义前缀
#   bash install.sh --version 2.3.9                   # 覆盖版本（跳过内嵌 sha256 校验）
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.4.6"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/varscan-$DEFAULT_VERSION}"
CONDA_ENV="varscan"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 jar（VarScan.v<ver>.jar）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_JAR="e827230b47a96cab035c5c7178e5089921a1e1c8d1e4836a6b02ff88e3a4c2ab"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
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
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# jar 为平台无关（Java），只需 java
platform_ok_binary() { command -v java >/dev/null 2>&1; }

# ---------------- 版本断言 ----------------
assert_version_jar() {
    local jar="$1" out
    out="$(java -jar "$jar" --version 2>&1 || true)"
    if ! grep -qF "$VERSION" <<<"$out"; then
        out="$(java -jar "$jar" 2>&1 || true)"   # 无参 banner 含版本号，作兜底
    fi
    printf '%s\n' "$out" | head -n 3 | sed 's/^/  /'
    grep -qF "$VERSION" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 varscan=$VERSION 到环境: $CONDA_ENV"
    if "$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {found=1} END {exit found?0:1}'; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "varscan=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "varscan=$VERSION"
    fi
    log "验证：$CONDA_BIN run -n $CONDA_ENV varscan --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" varscan --version 2>&1 | head -n 2 | sed 's/^/  /' || true
    log "完成：conda activate $CONDA_ENV 后即可使用 varscan"
}

# ---------------- 路线 B：官方 jar ----------------
install_binary() {
    command -v java >/dev/null 2>&1 || die "--method binary 需宿主 JRE（java）；请先安装 openjdk 或改用 conda 路线"
    local url="https://github.com/dkoboldt/varscan/raw/master/VarScan.v${VERSION}.jar"
    log "下载官方 jar: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/VarScan.jar" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/VarScan.jar" "$url"
    else
        die "需要 curl 或 wget 下载 jar"
    fi
    # jar 直链（raw）偶发返回 HTML 错误页，做基本大小校验
    [[ -s "$tmp/VarScan.jar" ]] || die "下载的 jar 为空（URL 或版本号有误？）"

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_JAR  $tmp/VarScan.jar" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_JAR  $tmp/VarScan.jar" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 jar 摘要）"
    fi

    install -m 0644 "$tmp/VarScan.jar" "$PREFIX/bin/VarScan.jar"
    # 生成 varscan wrapper（读 JAVA_OPTS，便于容器/宿主统一注入堆内存）
    cat > "$PREFIX/bin/varscan" <<EOF
#!/usr/bin/env bash
exec java \${JAVA_OPTS:-} -jar "$PREFIX/bin/VarScan.jar" "\$@"
EOF
    chmod 0755 "$PREFIX/bin/varscan"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version_jar "$PREFIX/bin/VarScan.jar"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# varscan (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 varscan 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "varscan $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 需宿主 JRE（java）；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且无 java，无法自动安装"
        fi ;;
esac
log "安装成功"
