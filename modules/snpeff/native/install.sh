#!/usr/bin/env bash
# =============================================================================
# install.sh — SnpEff 宿主机本地安装脚本
#
# 归属    ：bioskills modules/snpeff/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::snpeff
#   - binary 路线（无 conda 兜底）：官方 SourceForge snpEff_latest_core.zip 解压到
#     用户级前缀 --prefix（默认 ~/software/snpeff-<ver>），无需 root、不写 /opt
#     需宿主已装 JRE（java）
#   - 版本默认 5.4.0c，与 modules/snpeff/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://pcingola.github.io/SnpEff/
#   bioconda : https://anaconda.org/bioconda/snpeff
#   release  : https://downloads.sourceforge.net/project/snpeff/snpEff_latest_core.zip
#   (容器：quay.io/biocontainers/snpeff —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 说明：官方预编译 zip 仅以 latest 命名分发给（SourceForge 无版本化资产），
#      故 binary 路线不内嵌 sha256（latest 资产会随发布变化，sha256 不稳定）。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 zip
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: snpeff）
#   bash install.sh --method binary                   # 强制官方 zip（需 java + unzip）
#   bash install.sh --conda-env se --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/snpeff             # binary 模式自定义前缀
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="5.4.0c"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/snpeff-$DEFAULT_VERSION}"
CONDA_ENV="snpeff"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
ZIP_URL="https://downloads.sourceforge.net/project/snpeff/snpEff_latest_core.zip"

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

# 官方 zip 为平台无关（Java），只要有 java 即可
platform_ok_binary() { command -v java >/dev/null 2>&1; }

# ---------------- 版本断言（安装后运行 snpEff / java -jar 校验） ----------------
assert_version() {
    local out
    out="$("$@" -version 2>&1 || true)"
    if ! grep -qF "$VERSION" <<<"$out"; then
        # snpEff 无参数时打印含版本号的 banner，作兜底
        out="$("$@" 2>&1 || true)"
    fi
    printf '%s\n' "$out" | head -n 3 | sed 's/^/  /'
    grep -qF "$VERSION" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 snpeff=$VERSION 到环境: $CONDA_ENV"
    if "$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {found=1} END {exit found?0:1}'; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "snpeff=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "snpeff=$VERSION"
    fi
    log "验证：$CONDA_BIN run -n $CONDA_ENV snpEff -version"
    local out
    out="$("$CONDA_BIN" run -n "$CONDA_ENV" snpEff -version 2>&1 || true)"
    printf '%s\n' "$out" | head -n 3 | sed 's/^/  /'
    grep -qF "$VERSION" <<<"$out" || die "版本校验失败（conda 环境）：期望 ${VERSION}"
    log "完成：conda activate $CONDA_ENV 后即可使用 snpEff"
}

# ---------------- 路线 B：官方 SourceForge 预编译 zip ----------------
install_binary() {
    command -v java >/dev/null 2>&1 || die "--method binary 需宿主 JRE（java）；请先安装 openjdk 或改用 conda 路线"
    log "下载官方预编译包: $ZIP_URL"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/snpeff.zip" "$ZIP_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/snpeff.zip" "$ZIP_URL"
    else
        die "需要 curl 或 wget 下载预编译包"
    fi

    warn "官方预编译包以 latest 分发（无版本化资产），跳过 sha256 校验；如需校验请自行核对 SourceForge 摘要"

    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$tmp/snpeff.zip" -d "$tmp/extract"
    else
        python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
            "$tmp/snpeff.zip" "$tmp/extract" || die "需要 unzip 或 python3(zipfile) 解压"
    fi
    local srcdir
    srcdir="$(find "$tmp/extract" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "${srcdir:-}" && -f "${srcdir}/snpEff.jar" ]] || die "解压包内未找到 snpEff.jar（下载异常？）"

    # 覆盖式部署 jar 与 scripts 到前缀
    rm -rf "$PREFIX/snpEff"
    cp -R "$srcdir" "$PREFIX/snpEff"
    local bin_src="" bin_name="Java"
    for cand in snpEff SnpSift; do
        if [[ -f "$PREFIX/snpEff/$cand" ]]; then
            install -m 0755 "$PREFIX/snpEff/$cand" "$PREFIX/bin/$cand" 2>/dev/null || {
                mkdir -p "$PREFIX/bin"; install -m 0755 "$PREFIX/snpEff/$cand" "$PREFIX/bin/$cand"; }
            bin_src="$PREFIX/bin/$cand"
            bin_name="$cand"
            break
        fi
    done
    rm -rf "$tmp"; tmp=""; trap - EXIT

    local jar="$PREFIX/snpEff/snpEff.jar"
    log "验证：java -jar $jar -version"
    assert_version java -jar "$jar"

    if [[ -n "$bin_src" ]]; then
        log "wrapper 已放置：$bin_src（$bin_name）"
    fi

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export SNPEFF_HOME=\"$PREFIX/snpEff\""
        local line2="export SNPEFF_JAR=\"$PREFIX/snpEff/snpEff.jar\""
        if [[ -f "$PROFILE" ]] && grep -qF "$jar" "$PROFILE"; then
            log "PATH/环境已包含，跳过写入 $PROFILE"
        else
            { echo ""; echo "# snpeff (bioskills install.sh)"; echo "$line"; echo "$line2"; } >> "$PROFILE"
            log "已追加 SNPEFF_HOME / SNPEFF_JAR 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 java -jar \$SNPEFF_JAR 即可"
    else
        log "完成（未改环境）：使用时请 export SNPEFF_JAR=\"$jar\""
    fi
}

# ---------------- 主流程 ----------------
log "snpeff $VERSION 安装开始（本机 ${OS}/${ARCH}）"
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
