#!/usr/bin/env bash
# =============================================================================
# install.sh — OmiGA 宿主机本地安装脚本
#
# 归属    ：bioskills modules/omiga/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」）
#   - binary 路线（默认）：官方预编译 Linux x86_64 tar.xz（仅 amd64；自带运行时，无需 Julia）。
#     官方单源 https://omiga.bio/releases/latest.json（发版更新该文件；2026-09-07 抓取
#     release=1.8.17 → filename=OmiGA-build-v1.8.17-x86_64.tar.xz）。部署到用户前缀 --prefix
#     （默认 ~/software/omiga-<ver>），无需 root、不写 /opt/biosoft、不写 /home/train；
#     安装后写 OMIGA_PATH/PATH 到 --profile 并断言 omiga --version 含目标版本。
#   - conda 路线（--method conda）：omiga 不在 bioconda（anaconda 页面 + API 404 核实）→ 仅建
#     python 驱动 env（python=3.11 + pyyaml，供 native/main.py 的 Schema/自省使用）；omiga 本体
#     仍需按 binary 路线 / 容器镜像另行部署（conda 分支末尾提示）。
#   - 版本默认 1.8.17，与 modules/omiga/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://omiga.bio/（docsify；Installation.md 安装手册）
#   仓库     : https://github.com/SCAU-AnimalGenetics/OmiGA（仅源码 + src zip，无二进制 release）
#   二进制   : https://omiga.bio/releases/latest.json（单一数据源；url 为 efile111.hpccube.com
#              一次性 token 直链，会随发版失效/更换 → 重建时重新抓 latest.json 取最新
#              filename/sha256/url，勿沿用本脚本内嵌值）
#   论文     : Nature Communications 2026（10.1038/s41467-026-68978-0）
#   (容器自建：native/Dockerfile + Apptainer.def —— 官方 bioconda/quay/depot 全无，见模块 README)
#
# 用法示例：
#   bash install.sh                                   # 默认 binary：linux-x64 直装 1.8.17
#   bash install.sh --method binary                   # 强制官方二进制路线
#   bash install.sh --method conda                    # 仅建 python 驱动 env（本体另行部署）
#   bash install.sh --conda-env omiga-driver --force  # 指定驱动 env 名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/omiga              # binary 模式自定义前缀
#   bash install.sh --version 1.8.16                  # 覆盖版本（跳过内嵌 sha，提示抓 latest.json）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.8.17"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/omiga-$DEFAULT_VERSION}"
CONDA_ENV="omiga-native"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方发布单源：https://omiga.bio/releases/latest.json
# 2026-09-07 抓取 release=1.8.17 的记录（efile token 一次性、随发版失效 —— 失效请重抓 latest.json）：
OMIGA_URL="https://efile111.hpccube.com:65014/efile/s/d/YWNyZHBkcXZieQ==/08410635d771c08d"
# 官方 sha256（latest.json 官方字段；仅 stable 版本提供，如 1.8.16 sha=3df80e…）：
SHA256_LINUX_X86_64="6cfbed0b52085489d5a4b4b549c2343e6ae53921474087cdf28876c2c214ea23"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    awk 'NR>1 && /^#/{ sub(/^# ?/,""); print; next } /^#/{ next } { exit }' "$0"
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
        *) die "未知参数: ${1}（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# 官方预编译二进制仅覆盖 Linux x86_64（仅 amd64；无 macos/arm 资产）
platform_ok_binary() {
    { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 版本断言（安装后运行 omiga --version 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" --version 2>&1 || true)"
    printf '  %s\n' "$(printf '%s\n' "$out" | head -n 2)"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：omiga --version 输出未包含 ${VERSION}（实际输出见上）"
    log "版本校验通过：OmiGA ${VERSION}"
}

# ---------------- 路线 A：官方预编译二进制（默认；仅 Linux x86_64） ----------------
install_binary() {
    log "使用官方预编译二进制安装 omiga=${VERSION}（Linux x86_64）"
    log "下载: ${OMIGA_URL}"
    log "安装前缀: ${PREFIX}"
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀 ${PREFIX} 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 重建，或改用 --prefix 指定其它前缀"
        fi
    fi
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/omiga.tar.xz" "$OMIGA_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/omiga.tar.xz" "$OMIGA_URL"
    else
        die "需要 curl 或 wget 下载官方二进制"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "${SHA256_LINUX_X86_64}  $tmp/omiga.tar.xz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "${SHA256_LINUX_X86_64}  $tmp/omiga.tar.xz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过（官方 latest.json 摘要）"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验 —— 请从 https://omiga.bio/releases/latest.json 抓取该版本的官方 filename/sha256/url 自行核对（efile token 直链随发版变化）"
    fi

    tar -Jxf "$tmp/omiga.tar.xz" -C "$tmp"
    # 定位解压出的顶层目录（内含 bin/omiga；顶层名随版本变化，如 OmiGA-build-v1.8.17-x86_64）
    local srcdir=""
    srcdir="$(dirname "$(dirname "$(find "$tmp" -maxdepth 3 -type f -path '*/bin/omiga' | head -n 1)")")"
    test -x "$srcdir/bin/omiga" || die "release 包内未找到 bin/omiga（URL 或版本号有误？）"
    cp -R "$srcdir/." "$PREFIX/"
    chmod -R u+rwX,go+rX "$PREFIX"
    chmod +x "$PREFIX/bin/"* 2>/dev/null || true
    test -x "$PREFIX/bin/omiga" || die "未找到可执行文件 ${PREFIX}/bin/omiga"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/omiga"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local oline pline
        oline="export OMIGA_PATH=\"${PREFIX}/bin\""
        pline="export PATH=\"\${OMIGA_PATH}:\${PATH}\""
        if [[ -f "$PROFILE" ]] && grep -qF "OMIGA_PATH=" "$PROFILE"; then
            log "OMIGA_PATH 已写入 ${PROFILE}，跳过（如指向旧版本请手动更新）"
        else
            { echo ""; echo "# omiga (bioskills install.sh)"; echo "$oline"; echo "$pline"; } >> "$PROFILE"
            log "已追加 OMIGA_PATH/PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 omiga 即可"
    else
        log "完成（未改 PATH）：使用时请执行"
        log "  export OMIGA_PATH=\"${PREFIX}/bin\""
        log "  export PATH=\"\${OMIGA_PATH}:\${PATH}\""
    fi
    log "首次运行前请初始化：omiga --init（官方 Installation 手册；产出 OK 自检文件）"
}

# ---------------- 路线 B：conda（仅 python 驱动 env；omiga 本体不在 bioconda） ----------------
install_conda() {
    log "使用 conda 建 python 驱动 env=${CONDA_ENV}（python=3.11 + pyyaml）"
    log "注意：OmiGA 不在 bioconda（anaconda 页面 + api.anaconda.org HTTP 404 核实），conda 分支只提供"
    log "      native/main.py 驱动环境（--schema/--list-commands 自省用）；omiga 本体请另行："
    log "      1) bash install.sh --method binary（Linux x86_64 官方二进制）；或"
    log "      2) 容器镜像（见模块 README「Docker / Apptainer」自建配方）"
    local env_exists=""
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge python=3.11 pyyaml
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge python=3.11 pyyaml
    fi
    # 断言驱动 env 可用（pyyaml 供 base.py / main.py 自省）
    "$CONDA_BIN" run -n "$CONDA_ENV" python -c "import yaml; print('pyyaml OK', yaml.__version__)" \
        || die "conda 驱动 env 校验失败"
    log "完成：conda activate ${CONDA_ENV} 后可用 python main.py --schema 自省；omiga 本体按上方提示部署"
}

# ---------------- 主流程 ----------------
log "OmiGA ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方二进制（官方仅分发 Linux x86_64）；无 conda 包可装，无法继续"
        install_binary ;;
    auto)
        # omiga 无 conda 包 → auto 默认即官方二进制路线（linux-x64）；其余平台无包可装 → 报错
        platform_ok_binary || die "官方二进制仅覆盖 Linux x86_64（本机 ${OS}/${ARCH}），且 omiga 无 conda 包；请在 Linux x86_64 上执行或使用容器镜像（见模块 README）"
        install_binary ;;
esac
log "安装成功"
