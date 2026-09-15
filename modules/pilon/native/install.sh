#!/usr/bin/env bash
# =============================================================================
# install.sh — Pilon 宿主机本地安装脚本
#
# 归属    ：bioskills modules/pilon/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::pilon=1.23（自带 openjdk）
#   - jar 路线（无 conda 兜底）：官方 GitHub release 单 jar，用户级前缀安装
#     到 --prefix（默认 ~/software/pilon-1.23），并生成 `pilon` 封装脚本（内部 java -jar）
#   - 版本默认 1.23，与 modules/pilon/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/broadinstitute/pilon/
#   bioconda : https://anaconda.org/bioconda/pilon
#   release  : https://github.com/broadinstitute/pilon/releases
#   (容器：quay.io/biocontainers/pilon —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 jar
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: pilon）
#   bash install.sh --method jar                      # 强制官方 release jar（需宿主有 java）
#   bash install.sh --conda-env pl --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/pilon              # jar 模式自定义前缀
#   bash install.sh --version 1.24                    # 覆盖版本（jar 模式 URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.23"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/pilon-$DEFAULT_VERSION}"
CONDA_ENV="pilon"
METHOD="auto"          # auto | conda | jar
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 release jar 为平台无关（Java），内嵌默认 1.23 的 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_JAR="bde1d3c8da5537abbc80627f0b2a4165c2b68551690e5733a6adf62413b87185"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 auto|conda|jar}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|jar) ;; *) die "--method 仅支持 auto|conda|jar（收到: ${METHOD}）" ;; esac

# ---------------- 工具探测 ----------------
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# ---------------- 版本断言（安装后运行 pilon --version 校验） ----------------
assert_version() {
    local out
    out="$("$@" --version 2>&1 || true)"
    printf '  %s\n' "$out"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 pilon=$VERSION 到环境: $CONDA_ENV"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "pilon=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "pilon=$VERSION"
    fi
    log "验证：conda run -n $CONDA_ENV pilon --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" pilon --version | sed 's/^/  /'
    log "完成：conda activate $CONDA_ENV 后即可使用 pilon"
}

# ---------------- 路线 B：官方 GitHub release jar ----------------
install_jar() {
    local url sha tmp=""
    command -v java >/dev/null 2>&1 || die "jar 路线需要宿主 java（java -jar 运行）；请先安装 JDK，或改用 --method conda"
    url="https://github.com/broadinstitute/pilon/releases/download/v${VERSION}/pilon-${VERSION}.jar"

    log "下载官方 jar: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/pilon.jar" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/pilon.jar" "$url"
    else
        die "需要 curl 或 wget 下载 release jar"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        sha="$SHA256_JAR"
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$sha  $tmp/pilon.jar" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$sha  $tmp/pilon.jar" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    install -m 0644 "$tmp/pilon.jar" "$PREFIX/pilon-${VERSION}.jar"
    # 生成 pilon 封装（内部 java -jar；堆内存可用 JAVA_OPTS 覆盖）
    cat > "$PREFIX/bin/pilon" <<EOF
#!/usr/bin/env bash
exec java \${JAVA_OPTS:--Xmx8g} -jar "$PREFIX/pilon-${VERSION}.jar" "\$@"
EOF
    chmod 0755 "$PREFIX/bin/pilon"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/pilon"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# pilon (bioskills install.sh)"; echo "export PATH=\"$PREFIX/bin:\$PATH\""; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 pilon 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "pilon $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    jar)
        install_jar ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v java >/dev/null 2>&1; then
            install_jar
        else
            die "未检测到 mamba/conda 且宿主无 java；请先安装 JDK 或 conda"
        fi ;;
esac
log "安装成功"
