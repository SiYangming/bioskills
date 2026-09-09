#!/usr/bin/env bash
# =============================================================================
# install.sh — Trimmomatic 宿主机本地安装脚本
#
# 归属    ：bioskills modules/trimmomatic/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5 / §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::trimmomatic
#     （bioconda trimmomatic 为 noarch Java 包，自带 openjdk 依赖；0.39 仍在频道内）
#   - binary 路线（无 conda 兜底）：官方 usadellab 二进制 zip（Trimmomatic-0.39.zip，
#     内含 jar + adapters/），部署到用户前缀 --prefix（默认 ~/software/trimmomatic-0.39）
#     并生成 bin/trimmomatic launcher（内部 java -jar），无需 root、不写 /opt/biosoft
#   - 版本默认 0.39，与 modules/trimmomatic/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : http://www.usadellab.org/cms/?page=trimmomatic
#   bioconda : https://anaconda.org/bioconda/trimmomatic
#   release  : http://www.usadellab.org/cms/uploads/supplementary/Trimmomatic/Trimmomatic-0.39.zip
#              （官网页面确认 0.39 仍提供直链；≥0.40 官方下载已迁移至 GitHub releases）
#   (容器：quay.io/biocontainers/trimmomatic —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 与编译型工具不同，Trimmomatic 是 Java 程序：官方 zip 跨平台（linux/macos/arm64 均可），
# 因此 binary 路线不按 uname 架构守卫，只要求宿主已装 java（>=8）；conda 路线则自带 openjdk。
# 官方 zip 的 sha256 未核实（本模块为纯录入、禁止编造校验和）→ 默认版本也跳过 sha256 校验并提示。
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则官方 zip
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: trimmomatic）
#   bash install.sh --method binary                   # 强制官方 zip（无需 conda，需宿主 java）
#   bash install.sh --conda-env trim --force          # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/trimmomatic        # binary 模式自定义前缀
#   bash install.sh --version 0.41                    # 覆盖版本（conda 直装；binary 需 TRIMMOMATIC_ZIP_URL）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="0.39"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/trimmomatic-$DEFAULT_VERSION}"
CONDA_ENV="trimmomatic"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方二进制 zip 下载（0.39 官网直链，2026-09-08 核实在线）
ZIP_URL="http://www.usadellab.org/cms/uploads/supplementary/Trimmomatic/Trimmomatic-0.39.zip"
# ≥0.40 官方下载迁移至 GitHub releases：https://github.com/usadellab/Trimmomatic/releases
# （URL 模板/资产名未核实，需用户自行指定：TRIMMOMATIC_ZIP_URL=... bash install.sh --version X.Y）
# 旧 0.33 版本（文档历史）：同上官网路径 Trimmomatic-0.33.zip（CentOS 6 方案，参数用 -phred33）

# 官方 zip sha256 —— 未核实（不编造），留空即跳过校验
SHA256_ZIP=""

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
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
OS="$(uname -s)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

java_major() {
    local v
    v="$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9._]+)".*/\1/')"
    case "$v" in
        1.*) echo "${v#1.}" | cut -d. -f1 ;;
        *)   echo "$v" | cut -d. -f1 ;;
    esac
}

require_java() {
    command -v java >/dev/null 2>&1 || die "binary/zip 路线需要宿主已装 Java 8+（conda: mamba install -n <env> -c conda-forge openjdk；官方 zip 不自带 java）"
    local major
    major="$(java_major)"
    [[ -n "$major" && "$major" -ge 8 ]] || die "Java 版本过低（$(java -version 2>&1 | head -1)），需 8+"
    log "检测到 Java $(java -version 2>&1 | head -1)"
}

# ---------------- 运行断言：以最小 SE 修剪冒烟（Trimmomatic 无 -version 输出，用真实跑通校验） ----------------
assert_jar() {
    local jar="$1" smoke out
    smoke="$(mktemp /tmp/trimmomatic_smoke_XXXXXX.fq)"
    out="${smoke%.fq}.out.fq"
    printf '@smoke_read\nACGTACGTACGTACGTACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n' > "$smoke"
    log "冒烟测试：java -jar $(basename "$jar") SE（LEADING:3 TRAILING:3 MINLEN:10）"
    out_txt="$(java -jar "$jar" SE -phred33 "$smoke" "$out" LEADING:3 TRAILING:3 MINLEN:10 2>&1 || true)"
    printf '  %s\n' "$out_txt" | sed 's/^/  /'
    grep -q "Completed successfully" <<<"$out_txt" || die "冒烟测试未通过（期望输出含 Completed successfully）"
    log "版本/功能校验通过（trimmomatic ${VERSION} jar 可运行）"
    rm -f "$smoke" "$out"
}

assert_env_trimmomatic() {
    local env_tool="$1" smoke out out_txt
    smoke="$(mktemp /tmp/trimmomatic_smoke_XXXXXX.fq)"
    out="${smoke%.fq}.out.fq"
    printf '@smoke_read\nACGTACGTACGTACGTACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n' > "$smoke"
    log "冒烟测试：conda run -n ${CONDA_ENV} trimmomatic SE（LEADING:3 TRAILING:3 MINLEN:10）"
    out_txt="$("$env_tool" SE -phred33 "$smoke" "$out" LEADING:3 TRAILING:3 MINLEN:10 2>&1 || true)"
    printf '  %s\n' "$out_txt" | sed 's/^/  /'
    grep -q "Completed successfully" <<<"$out_txt" || die "冒烟测试未通过（期望输出含 Completed successfully）"
    log "功能校验通过（conda env ${CONDA_ENV} 内 trimmomatic ${VERSION} 可运行）"
    rm -f "$smoke" "$out"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    local env_exists
    log "使用 conda 安装 trimmomatic=$VERSION 到环境: $CONDA_ENV"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 用 mamba 时回退 conda；顺序固定 conda-forge 在前；bioconda trimmomatic 为 noarch Java 包（自带 openjdk 依赖）
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "trimmomatic=$VERSION"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "trimmomatic=$VERSION"
    fi
    # 校验：环境内应有 trimmomatic launcher（bioconda 包自带 bin/trimmomatic）
    local tool
    tool="$("$CONDA_BIN" run -n "$CONDA_ENV" sh -lc 'command -v trimmomatic' 2>/dev/null | tr -d '\r' || true)"
    if [[ -n "$tool" ]]; then
        assert_env_trimmomatic "$tool"
    else
        # launcher 缺失的兜底：仍可用 java -jar <env>/share/trimmomatic-*/trimmomatic-*.jar
        local jar
        jar="$("$CONDA_BIN" run -n "$CONDA_ENV" sh -lc 'ls "$CONDA_PREFIX"/share/trimmomatic-*/trimmomatic-*.jar 2>/dev/null | head -1' 2>/dev/null | tr -d '\r' || true)"
        [[ -n "$jar" ]] || die "conda env 内既无 trimmomatic launcher 也未找到 jar（包结构有变？）"
        "$CONDA_BIN" run -n "$CONDA_ENV" sh -lc 'command -v java >/dev/null || exit 1' || die "conda env 内无 java（trimmomatic 依赖未装全？）"
        assert_jar "$jar"
    fi
    log "完成：conda activate ${CONDA_ENV} 后即可使用 trimmomatic（adapters 位于 env 内 share/trimmomatic-*/adapters）"
}

# ---------------- 路线 B：官方二进制 zip（Java，跨平台） ----------------
install_binary() {
    local url jar
    [[ "$VERSION" == "$DEFAULT_VERSION" ]] || {
        if [[ -n "${TRIMMOMATIC_ZIP_URL:-}" ]]; then
            url="$TRIMMOMATIC_ZIP_URL"
            warn "使用 TRIMMOMATIC_ZIP_URL 自定义下载: ${url}"
        else
            die "--version ${VERSION} 非默认 ${DEFAULT_VERSION}：官方 ≥0.40 二进制已迁移至 GitHub releases（URL 未核实），"
                "请手动下载后设置 TRIMMOMATIC_ZIP_URL=... 再运行本脚本，或用 --method conda"
        fi
    }
    url="${url:-$ZIP_URL}"
    require_java
    log "下载官方二进制 zip: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/Trimmomatic-${VERSION}.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/Trimmomatic-${VERSION}.zip" "$url"
    else
        die "需要 curl 或 wget 下载官方 zip"
    fi

    if [[ -n "$SHA256_ZIP" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_ZIP  $tmp/Trimmomatic-${VERSION}.zip" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_ZIP  $tmp/Trimmomatic-${VERSION}.zip" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "官方 zip sha256 未核实（纯录入模块不编造校验和），已跳过完整性校验；请自行核对官网/下载摘要"
    fi

    unzip -q "$tmp/Trimmomatic-${VERSION}.zip" -d "$tmp/unz" 2>/dev/null \
        || die "unzip 解压失败（zip 损坏或未装 unzip？）"
    local inner="$tmp/unz/Trimmomatic-${VERSION}"
    [[ -d "$inner" ]] || die "zip 内未找到 Trimmomatic-${VERSION}/ 目录（URL 或版本有误？）"
    cp -R "$inner/." "$PREFIX/"
    jar="$PREFIX/trimmomatic-${VERSION}.jar"
    [[ -f "$jar" ]] || die "未找到 $jar（zip 结构异常）"

    # 生成 launcher：trimmomatic → java -jar（后续 --force 重装会覆盖）
    cat > "$PREFIX/bin/trimmomatic" <<EOF
#!/usr/bin/env bash
# trimmomatic launcher（bioskills install.sh 生成，版本 ${VERSION}）
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
exec java -jar "\$DIR/trimmomatic-${VERSION}.jar" "\$@"
EOF
    chmod +x "$PREFIX/bin/trimmomatic"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_jar "$jar"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# trimmomatic (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 trimmomatic 即可（adapters 位于 ${PREFIX}/adapters）"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"${PREFIX}/bin:\$PATH\"（adapters 位于 ${PREFIX}/adapters）"
    fi
}

# ---------------- 主流程 ----------------
log "trimmomatic $VERSION 安装开始（本机 ${OS}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif command -v java >/dev/null 2>&1; then
            install_binary
        else
            die "未检测到 mamba/conda 且宿主无 java，无法自动安装；请先装 conda 或 Java 8+"
        fi ;;
esac
log "安装成功"
