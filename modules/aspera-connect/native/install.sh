#!/usr/bin/env bash
# =============================================================================
# install.sh — IBM Aspera Connect / ascp 宿主机本地安装脚本
#
# 归属    ：bioskills modules/aspera-connect/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」）
#   - binary 路线（默认）：官方 ibm-aspera-connect Linux x86_64 tar.gz（自解压 .sh 安装器），
#     运行后按用户安装到 ${HOME}/.aspera/connect（ascp 位于 bin/ascp）—— 等价 NCBI/ENA 官方指引；
#     无需 root、不写 /opt/biosoft、不写 /home/train。
#   - conda 路线（--method conda）：aspera-connect/aspera/ascp 在 bioconda 与 conda-forge 均无包
#     （api.anaconda.org 全 404，2026-09-08 核实）→ 仅建 python 驱动 env（python=3.11 + pyyaml，
#     供 native/main.py 的 Schema/自省使用）；ascp 本体仍需按 binary 路线 / 容器镜像另行部署。
#   - 版本默认 4.2.19.956，与 modules/aspera-connect/meta.yaml software_versions.native 对齐。
#
# 官方来源（2026-09-08 核实）：
#   homepage : https://www.ibm.com/products/aspera
#   下载页   : https://www.ibm.com/aspera/connect/（页面所列 Linux x86_64 直链）
#   直链     : https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/
#              ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz
#              （latest 为滚动指针、文件名带 -HEAD；HEAD 实测 HTTP 200，版本号可能继续更新）
#   安装方式 : tar -zxvf <pkg>.tar.gz → sh ibm-aspera-connect_<ver>[-HEAD]_linux_x86_64.sh
#              （IBM 官方手册：按用户安装到 ${HOME}/.aspera/connect，勿以 root 运行安装器）
#   说明     : IBM 官方下载页未公布安装包 sha256（2026-09-08 核实）→ 本脚本不内嵌伪造校验和，
#              HTTPS 直链下载完整性请自行核对。
#   历史参照 : 3.9.6.177839 旧式直链 .../connect/bin/ibm-aspera-connect-3.9.6.177839-linux-g2.12-64.tar.gz
#              2026-09-08 实测已 404（勿再用）；downloads.asperasoft.com/connect2/ 亦不可达。
#   密钥     : NCBI/EBI 公共数据下载密钥 asperaweb_id_dsa.openssh 位于安装目录 etc/；社区报告 4.2+
#              或不再随包提供（未核实）→ 缺失时自行准备并 -i 显式指定。
#   (容器自建：native/Dockerfile + Apptainer.def —— 官方 bioconda/quay/depot 全无，见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：linux-x64 走官方安装包 4.2.19.956
#   bash install.sh --method binary                   # 强制官方安装包路线
#   bash install.sh --method conda                    # 仅建 python 驱动 env（ascp 本体另行部署）
#   bash install.sh --prefix ~/aspera-alt             # 以 HOME=~/aspera-alt 安装（落 ~/aspera-alt/.aspera/connect）
#   bash install.sh --url <新直链>                     # 官方 latest 指针更新后手动给 URL（跳过默认）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="4.2.19.956"
VERSION="$DEFAULT_VERSION"
DEFAULT_URL="https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/ibm-aspera-connect_${DEFAULT_VERSION}-HEAD_linux_x86_64.tar.gz"
URL="$DEFAULT_URL"
PREFIX="${PREFIX:-$HOME}"        # 标准 Connect 安装到 ${PREFIX}/.aspera/connect；默认 $HOME
CONDA_ENV="aspera-connect-native"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --url)         URL="${2:?--url 需要直链}";           shift 2 ;;
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

# 官方 Linux Connect 安装包仅覆盖 x86_64（amd64；无 macos tar.gz 形态）
platform_ok_binary() {
    { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }
}

# ---------------- 版本断言（安装后运行 ascp 校验） ----------------
assert_version() {
    local bin="$1" out
    # ascp 自报版本号与 Connect 包版本（4.2.19.956）的精确对应未核实 → 断言以
    # "ascp version" 或 "Usage: ascp" 字样为准（真实安装后请自行核对输出中的版本号）
    out="$({ "$bin" --version 2>&1 || true; "$bin" --help 2>&1 || true; } | head -n 20)"
    printf '  %s\n' "$(printf '%s\n' "$out" | head -n 4)"
    printf '%s\n' "$out" | grep -qiE 'ascp version|Usage: ascp' \
        || die "版本校验失败：ascp 输出未见 'ascp version'/'Usage: ascp'（实际输出见上）"
    log "版本校验通过（ascp 自报版本号以实际输出为准，与 Connect 包版本 ${VERSION} 的对应关系未核实）"
}

# ---------------- 路线 A：官方安装包（默认；仅 Linux x86_64） ----------------
install_binary() {
    platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 无官方 tar.gz 安装包（官方仅分发 Linux x86_64 tar.gz + macOS pkg/Windows msi）；请改用 linux-x64 主机、官方 macOS/Windows 图形安装器或容器镜像"
    if [[ "$(id -u)" == "0" ]]; then
        die "检测到 root：IBM 官方手册明确勿以 root 运行 Connect 安装器（按用户安装，排除 root）。请改用普通用户执行本脚本，或使用容器镜像（native/Dockerfile / Apptainer.def）"
    fi
    [[ "$VERSION" == "$DEFAULT_VERSION" ]] || warn "非默认版本（${VERSION}）→ 使用 ${URL}（-HEAD 滚动命名或随发版变化，若 404 请 --url 传官方最新直链）"
    log "使用官方安装包安装 aspera-connect=${VERSION}"
    log "下载: ${URL}"
    log "安装目标: ${PREFIX}/.aspera/connect（安装器以 HOME=${PREFIX} 运行）"

    local dest="${PREFIX}/.aspera/connect"
    if [[ -e "$dest" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "${dest} 已存在（--force），删除重建"
            rm -rf "$dest"
        else
            die "${dest} 已存在；加 --force 重建，或改用 --prefix 指定其它安装前缀"
        fi
    fi
    mkdir -p "$PREFIX"

    local tmp="" installer=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/aspera-connect.tar.gz" "$URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/aspera-connect.tar.gz" "$URL"
    else
        die "需要 curl 或 wget 下载官方安装包"
    fi
    # IBM 官方页面未公布安装包 sha256 → 不做校验和断言（HTTPS 完整性请自行核对，本脚本不内嵌伪造值）
    warn "官方页面未公布安装包 sha256（2026-09-08 核实）→ 跳过校验和断言，请自行核对 HTTPS 下载完整性"

    tar -xzf "$tmp/aspera-connect.tar.gz" -C "$tmp"
    installer="$(find "$tmp" -maxdepth 1 -type f -name 'ibm-aspera-connect*.sh' | head -n 1)"
    [[ -n "$installer" ]] || die "安装包内未找到 ibm-aspera-connect*.sh 自解压安装器（URL 或版本号有误？）"

    (cd "$tmp" && HOME="$PREFIX" sh "$(basename "$installer")")
    test -x "$dest/bin/ascp" || die "安装后未找到 ${dest}/bin/ascp（安装器行为与预期不符？）"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$dest/bin/ascp"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$dest/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$dest/bin" "$PROFILE"; then
            log "PATH 已包含 ${dest}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# aspera-connect (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 ascp 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$dest/bin:\$PATH\""
    fi
    log "密钥提示：公共数据源密钥 asperaweb_id_dsa.openssh 默认在 ${dest}/etc/ 下；实机核查 4.2.x"
    log "  （macOS 4.2.13）随包已无该 DSA 密钥 → 缺失时请自行准备密钥文件并 -i 显式指定（NCBI 下载示例见模块 README「实战示例」）"
}

# ---------------- 路线 B：conda（仅 python 驱动 env；ascp 无 conda 包） ----------------
install_conda() {
    log "使用 conda 建 python 驱动 env=${CONDA_ENV}（python=3.11 + pyyaml）"
    log "注意：aspera-connect/aspera/ascp 在 bioconda 与 conda-forge 均无包（api.anaconda.org 全 404，"
    log "      2026-09-08 核实），conda 分支只提供 native/main.py 驱动环境（--schema/--list-commands"
    log "      自省用）；ascp 本体请另行：1) bash install.sh --method binary（Linux x86_64 官方安装包）；"
    log "      或 2) 容器镜像（见模块 README「Docker / Apptainer」自建配方）"
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
    log "完成：conda activate ${CONDA_ENV} 后可用 python main.py --schema 自省；ascp 本体按上方提示部署"
}

# ---------------- 主流程 ----------------
log "aspera-connect ${VERSION} 安装开始（本机 ${OS}/${ARCH}；IBM 专有软件，EULA 合规自行负责）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if platform_ok_binary && [[ "$(id -u)" != "0" ]]; then
            # linux-x64 非 root 默认走官方安装包（官方渠道优先；ascp 无 conda 包）
            install_binary
        elif [[ -n "$CONDA_BIN" ]]; then
            install_conda   # 非 linux-x64 / root 环境退化为驱动 env，并给出引导
        else
            die "本平台（${OS}/${ARCH}）无官方 tar.gz 且未检测到 mamba/conda，无法自动安装；请改用 linux-x64 普通用户主机或容器镜像（见模块 README）"
        fi ;;
esac
log "安装成功"
