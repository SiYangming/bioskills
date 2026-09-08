#!/usr/bin/env bash
# =============================================================================
# install.sh — DIA-NN 宿主机本地安装脚本
#
# 归属    ：bioskills modules/dia-nn/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」）
#   - binary 路线（默认，auto 在 linux-x64 优先）：官方 GitHub release Academia
#     Linux zip（含 diann-linux + 模型 + dll），解压部署到用户前缀
#     --prefix（默认 ~/software/diann-2.6.1），写 diann wrapper（LD_LIBRARY_PATH
#     指向安装目录）到 --prefix/bin；无需 root、不写 /opt/biosoft
#   - conda 路线（兜底）：DIA-NN 不在 bioconda（404）；仅 YangmingSi 个人频道有
#     dia-nn=2.3.2（linux-64），故 conda 路线版本仅支持 2.3.2
#   - 版本默认 2.6.1，与 modules/dia-nn/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/vdemichev/DiaNN
#   release  : https://github.com/vdemichev/DiaNN/releases（tag=2.0 下追加 2.0~2.6.1 资产）
#   zip      : https://github.com/vdemichev/DiaNN/releases/download/2.0/DIA-NN-<ver>-Academia-Linux.zip
#   运行依赖 : .NET 8 Runtime（Linux 经 packages.microsoft.com 装 dotnet-runtime-8.0，勿装 SDK）
#   conda    : https://anaconda.org/channels/YangmingSi/packages/dia-nn/overview（仅 2.3.2）
#   (容器自建：native/Dockerfile + Apptainer.def —— 官方 bioconda/quay/depot 全无，见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：linux-x64 走官方 zip 2.6.1
#   bash install.sh --method binary                   # 强制官方 release zip（linux-x64）
#   bash install.sh --method conda --version 2.3.2    # 强制 conda（YangmingSi 频道）
#   bash install.sh --prefix ~/opt/diann              # binary 模式自定义前缀
#   bash install.sh --version 2.5.1                   # 覆盖版本（binary URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.6.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/diann-$DEFAULT_VERSION}"
CONDA_ENV="dia-nn"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 Academia Linux zip（仅 linux-x64）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
# 来源：GitHub release tag=2.0 资产 digest（2026-09-07 抓取 API 核实）
SHA256_LINUX_X86_64="f98e396af791f1903168b365a83fc2cc72208cc133281b9ce6ebe3a794b999ba"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'
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

# binary 模式仅官方覆盖平台（DIA-NN 官方仅分发 Windows .msi + Linux x86_64 zip；无 macOS 二进制）
platform_ok_binary() {
    { [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; }
}

# .NET 8 Runtime 探测（diann-linux 为 .NET 8 框架依赖程序；zip 内不含 runtime）
dotnet8_ok() {
    command -v dotnet >/dev/null 2>&1 || return 1
    dotnet --list-runtimes 2>/dev/null | grep -q 'Microsoft.NETCore.App 8\.'
}

# ---------------- 版本断言（安装后运行 diann 校验 banner 含版本号） ----------------
assert_version() {
    local bin="$1" out
    # diann 无参数/未知参数时打印 usage + "DIA-NN <ver>" banner 后非零退出；统一吞退出码取输出
    out="$("$bin" --help 2>&1 || true)"
    printf '  %s\n' "$(printf '%s\n' "$out" | head -n 3)"
    grep -q "DIA-NN" <<<"$out" || die "版本校验失败：输出未见 DIA-NN banner（实际输出见上）"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：DIA-NN ${VERSION}"
}

# ---------------- 路线 A：conda（YangmingSi 频道，仅 2.3.2） ----------------
install_conda() {
    local create_cmd env_exists
    if [[ "$VERSION" != "2.3.2" ]]; then
        die "conda 路线仅支持 dia-nn=2.3.2（YangmingSi 频道当前唯一版本，2026-09-07 核实）；要装 ${VERSION} 请用 binary 路线（官方 zip）"
    fi
    log "使用 conda 安装 dia-nn=${VERSION}（频道 yangmingsi）到环境: ${CONDA_ENV}"
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
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c yangmingsi "dia-nn=${VERSION}"
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c yangmingsi "dia-nn=${VERSION}"
    fi
    log "验证：conda run -n ${CONDA_ENV} diann --version"
    "$CONDA_BIN" run -n "$CONDA_ENV" diann --help 2>&1 | head -n 3 | sed 's/^/  /' || true
    log "完成：conda activate ${CONDA_ENV} 后即可使用 diann"
}

# ---------------- 路线 B：官方 GitHub release zip（linux-x64） ----------------
install_binary() {
    local url tmp srcdir zipname inner
    [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]] || die "--method binary 在 ${OS}/${ARCH} 无官方二进制（官方仅分发 Linux x86_64 zip）；macOS 请改用 conda 路线或模块 Docker/Apptainer 镜像"
    if ! dotnet8_ok; then
        die "未检测到 .NET 8 Runtime：diann-linux 是 .NET 8 框架依赖程序。请先安装 dotnet-runtime-8.0（Linux：wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb && dpkg -i ... && apt-get install -y dotnet-runtime-8.0，勿装 SDK），或直接用 native/Dockerfile / Apptainer.def 镜像"
    fi
    url="https://github.com/vdemichev/DiaNN/releases/download/2.0/DIA-NN-${VERSION}-Academia-Linux.zip"

    log "下载官方二进制: ${url}"
    log "安装前缀: ${PREFIX}"
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀 ${PREFIX} 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 重建，或改用 --prefix 指定其它前缀"
        fi
    fi
    mkdir -p "$PREFIX/bin"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/diann.zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/diann.zip" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "${SHA256_LINUX_X86_64}  $tmp/diann.zip" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "${SHA256_LINUX_X86_64}  $tmp/diann.zip" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    # zip 内层目录：DIA-NN-<ver>-Academia-Linux/diann-<ver>/（内含 diann-linux 与模型等）
    unzip -q "$tmp/diann.zip" -d "$tmp/x"
    bin_src="$(find "$tmp/x" -maxdepth 3 -type f -name diann-linux -perm -111 | head -1)"
    [[ -n "$bin_src" ]] || die "release 包内未找到可执行文件 diann-linux（URL 或版本号有误？）"
    srcdir="$(dirname "$bin_src")"
    inner="$(basename "$srcdir")"

    # 部署结构：$PREFIX/lib/diann-<ver>/（程序+模型） + $PREFIX/bin/diann wrapper + diann-stats
    install -d "$PREFIX/lib"
    cp -r "$srcdir" "$PREFIX/lib/$inner"
    chmod -R u+rwX,go+rX "$PREFIX/lib/$inner"

    cat > "$PREFIX/bin/diann" <<EOF
#!/usr/bin/env bash
# DIA-NN wrapper（bioskills install.sh 生成）：LD_LIBRARY_PATH 指向程序目录（libtorch 等）
export LD_LIBRARY_PATH="$PREFIX/lib/$inner\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$PREFIX/lib/$inner/diann-linux" "\$@"
EOF
    chmod +x "$PREFIX/bin/diann"
    if [[ -f "$srcdir/diann-stats.py" ]]; then
        # diann-stats.py：官方随包统计脚本（需要 python3 + polars/numpy/matplotlib）
        sed '1s|^#!/.*|#!/usr/bin/env python3|' "$srcdir/diann-stats.py" > "$PREFIX/bin/diann-stats" \
            || cp "$srcdir/diann-stats.py" "$PREFIX/bin/diann-stats"
        chmod +x "$PREFIX/bin/diann-stats"
        log "附赠 diann-stats（python 统计脚本）已放入 ${PREFIX}/bin"
    fi
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/bin/diann"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}/bin，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# dia-nn (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 diann 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "DIA-NN ${VERSION} 安装开始（本机 ${OS}/${ARCH}；Academia 版学术/非营利免费，商用需官方许可）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        install_binary ;;
    auto)
        if platform_ok_binary; then
            # linux-x64 默认走官方 zip（2.6.1）：官方渠道优先；conda 频道仅 2.3.2 且属第三方
            install_binary
        elif [[ -n "$CONDA_BIN" ]]; then
            install_conda   # 内部会校验 VERSION==2.3.2 并给出引导
        else
            die "本平台（${OS}/${ARCH}）无官方二进制且未检测到 mamba/conda，无法自动安装；请改用 linux-x64 主机或模块 Docker/Apptainer 镜像"
        fi ;;
esac
log "安装成功"
