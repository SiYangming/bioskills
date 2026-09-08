#!/usr/bin/env bash
# =============================================================================
# install.sh — GeneTribe 宿主机本地安装脚本
#
# 归属    ：bioskills modules/genetribe/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 / README「环境安装」）
#   - conda 路线（auto 在检测到 mamba/conda 时优先）：建独立环境，装 YangmingSi 个人频道
#     genetribe=1.2.1 + bioconda blast/bedtools/jcvi（GeneTribe 不在 bioconda，404 核实；
#     jcvi 在 bioconda，当前 1.6.7）
#   - source 路线（无 conda 兜底 / --method source）：官方源码安装法（官方文档
#     https://chenym1.github.io/genetribe/tutorial/installation.html：git clone + ./install.sh
#     + PATH），部署到用户前缀 --prefix（默认 ~/software/genetribe-<ver>），无需 root、
#     不写 /opt/biosoft、不写 /home/train；需 blastp/makeblastdb、bedtools、jcvi 已在 PATH
#     （上游 install.sh 自带依赖自检）
#   - 版本默认 1.2.1，与 modules/genetribe/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/chenym1/genetribe
#   文档     : https://chenym1.github.io/genetribe/（Installation / Quick Start / File Formats）
#   git      : https://github.com/chenym1/genetribe.git（tag v1.2.1；release 2022-08-15）
#   conda    : https://anaconda.org/channels/YangmingSi/packages/genetribe/overview（1.2.1 noarch）
#   依赖     : BLAST / BEDTools / jcvi（MCscan；pip install jcvi 或 bioconda jcvi）
#   (容器自建：native/Dockerfile + Apptainer.def —— 官方 bioconda/quay/depot 全无，见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 conda，否则源码
#   bash install.sh --method conda                    # 强制 conda（YangmingSi 频道）
#   bash install.sh --method source                   # 强制官方 tag v<ver> 源码 + 上游 ./install.sh
#   bash install.sh --conda-env gt --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/opt/genetribe          # source 模式自定义前缀
#   bash install.sh --version 1.2.0                   # 覆盖版本（source 模式 clone 对应 tag）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.2.1"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/genetribe-$DEFAULT_VERSION}"
CONDA_ENV="genetribe"
METHOD="auto"          # auto | conda | source
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# tag v1.2.1 锚点 commit（GitHub API 核实：chenym1/genetribe refs/tags/v1.2.1 → 5aa4fc5d...）。
# 上游不发布源码包 sha256 摘要（无官方 digest，无法核实 → 不内嵌 sha256），改用 commit 锚点核对。
COMMIT_ANCHOR="5aa4fc5d7a2e00129000bd282efc1161b57d023c"

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
        --method)      METHOD="${2:?--method 需要 auto|conda|source}"; shift 2 ;;
        --conda-env)   CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: ${1}（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|source) ;; *) die "--method 仅支持 auto|conda|source（收到: ${METHOD}）" ;; esac

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# source 路线依赖自检（对应上游 install.sh 检查项：blastp / bedtools / python3 -m jcvi.compara）
deps_ok_source() {
    local ok=1
    command -v blastp >/dev/null 2>&1 || { warn "未找到 blastp（BLAST；apt 装 ncbi-blast+ 或 conda 装 blast）"; ok=0; }
    command -v makeblastdb >/dev/null 2>&1 || { warn "未找到 makeblastdb（随 BLAST 提供）"; ok=0; }
    command -v bedtools >/dev/null 2>&1 || { warn "未找到 bedtools（apt 或 conda 安装）"; ok=0; }
    command -v python3 >/dev/null 2>&1 || { warn "未找到 python3"; ok=0; }
    if [[ "$ok" == 1 ]] && ! python3 -c "import jcvi" >/dev/null 2>&1; then
        warn "未找到 jcvi/MCscan（python3 -c 'import jcvi' 失败；pip install jcvi 或 conda 装 bioconda jcvi）"
        ok=0
    fi
    [[ "$ok" == 1 ]]
}

# ---------------- 版本断言（genetribe -h 打印 "Program: GeneTribe ... Version: 1.2.1"） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -h 2>&1 || true)"
    printf '  %s\n' "$(printf '%s\n' "$out" | grep -E 'Version|Program' | head -n 2 || true)"
    grep -q "GeneTribe" <<<"$out" || die "版本校验失败：输出未见 GeneTribe banner（实际输出见上）"
    grep -qE "${VERSION//./\.}" <<<"$out" || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：GeneTribe ${VERSION}"
}

# ---------------- 路线 A：conda（YangmingSi 频道 genetribe + bioconda 依赖） ----------------
install_conda() {
    log "使用 conda 安装 genetribe=${VERSION}（频道 yangmingsi + bioconda 依赖）到环境: ${CONDA_ENV}"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 频道顺序 conda-forge → bioconda → yangmingsi；jcvi 走 bioconda（当前 1.6.7）；pyyaml 供 main.py 驱动
    if [[ "$(basename "$CONDA_BIN")" == "mamba" ]]; then
        mamba create -y -n "$CONDA_ENV" -c conda-forge -c bioconda -c yangmingsi \
            "genetribe=${VERSION}" blast bedtools jcvi pyyaml
    else
        conda create -y -n "$CONDA_ENV" -c conda-forge -c bioconda -c yangmingsi \
            "genetribe=${VERSION}" blast bedtools jcvi pyyaml
    fi
    log "验证：conda run -n ${CONDA_ENV} genetribe -h"
    "$CONDA_BIN" run -n "$CONDA_ENV" genetribe -h >/dev/null 2>&1 || die "conda 环境内 genetribe 运行失败"
    # 断言版本（conda run 捕获输出较繁琐，直接在临时目录取版本）
    local vout
    vout="$("$CONDA_BIN" run -n "$CONDA_ENV" python -c 'import subprocess;print(subprocess.run(["genetribe","-h"],capture_output=True,text=True).stdout)' 2>/dev/null || true)"
    grep -qE "${VERSION//./\.}" <<<"$vout" || warn "未能在 conda run 输出中确认版本号（安装本身成功；请 conda activate ${CONDA_ENV} 后运行 genetribe -h 自查）"
    log "完成：conda activate ${CONDA_ENV} 后即可使用 genetribe"
}

# ---------------- 路线 B：官方源码（git clone tag + 上游 ./install.sh） ----------------
install_source() {
    local repo_dir tmp
    log "使用官方源码安装 genetribe=${VERSION}（git clone tag v${VERSION} + 上游 ./install.sh）"
    log "安装前缀: ${PREFIX}"
    deps_ok_source || die "source 路线依赖缺失（见上方警告）：需 blastp/makeblastdb、bedtools、jcvi(M Cscan) 已在 PATH；conda 用户可改用 --method conda"
    # 上游官方声称仅提供 Linux 64-bit；其它平台给提示但放行（python3+bash 实现，尽力而为）
    if [[ "$OS" == "Darwin" ]]; then
        warn "上游官方仅声明支持 Linux 64-bit（本机 ${OS}/${ARCH}）——后续运行如有问题请改用 conda 路线或容器镜像"
    fi
    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "前缀 ${PREFIX} 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 重建，或改用 --prefix 指定其它前缀"
        fi
    fi
    mkdir -p "$(dirname "$PREFIX")"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://api.github.com/repos/chenym1/genetribe/zipball/refs/tags/v${VERSION}" -o "$tmp/genetribe.zip"
    else
        die "需要 curl（或改用 git clone 手动安装）"
    fi
    # 上游不发布官方 sha256 → 不校验文件摘要（未核实）；以 tag 的 commit 锚点核对解压内容
    python3 - "$tmp/genetribe.zip" "$tmp/src" <<'PY'
import sys, zipfile
zf = zipfile.ZipFile(sys.argv[1])
# zipball 顶层目录名由 GitHub 生成（chenym1-genetribe-<sha>），整体解压到 src/
zf.extractall(sys.argv[2])
print("[install] zipball entries:", len(zf.namelist()))
PY
    repo_dir="$(find "$tmp/src" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [[ -n "$repo_dir" ]] || die "解压失败：未找到仓库目录（URL 或版本号有误？）"

    # zipball 顶层名含 commit sha（chenym1-genetribe-5aa4fc5...），据此核对锚点（= v1.2.1 tag commit）
    topdir="$(basename "$repo_dir")"
    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if [[ "$topdir" != *"${COMMIT_ANCHOR:0:7}"* ]]; then
            warn "zipball 顶层目录 $(basename "$repo_dir") 的 commit 前缀与 v1.2.1 锚点 ${COMMIT_ANCHOR:0:7} 不一致——请核对下载源（仍继续安装）"
        else
            log "commit 锚点核对通过：${topdir}"
        fi
    else
        warn "非默认版本（${VERSION}），跳过 commit 锚点核对（该版本 tag commit 见 GitHub refs/tags/v${VERSION}）"
    fi

    install -d "$PREFIX"
    cp -R "$repo_dir/." "$PREFIX/"
    chmod -R u+rwX,go+rX "$PREFIX"

    # 上游 ./install.sh：依赖自检 + 生成 bin/ 符号链接（blastp/bedtools/jcvi 已确认在 PATH）
    (cd "$PREFIX" && ./install.sh)
    test -x "$PREFIX/genetribe" || die "上游 ./install.sh 未生成入口 genetribe"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    assert_version "$PREFIX/genetribe"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
            log "PATH 已包含 ${PREFIX}，跳过写入 ${PROFILE}"
        else
            { echo ""; echo "# genetribe (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 ${PROFILE}"
        fi
        log "完成：重新登录或 source ${PROFILE} 后执行 genetribe 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "GeneTribe ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    source)
        install_source ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif deps_ok_source; then
            install_source
        else
            die "未检测到 mamba/conda 且本机缺 source 路线依赖（blastp/bedtools/jcvi）；请先装 conda 或补齐依赖后重试"
        fi ;;
esac
log "安装成功"
