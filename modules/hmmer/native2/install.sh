#!/usr/bin/env bash
# =============================================================================
# install.sh — HMMER 2.x（hmmer2）宿主机本地安装脚本
#
# 归属    ：bioskills modules/hmmer/native2/install.sh（HMMER 2.x 遗留版 native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境，pin bioconda::hmmer2
#     （bioconda 包内二进制带 2 后缀：hmmsearch2 / hmmbuild2 / …）
#   - binary 路线（无 conda 兜底）：官方 eddylab 2.3.2 源码归档自编译，用户级前缀
#     安装到 --prefix（默认 ~/software/hmmer2-<ver>），无需 root、不写 /opt/biosoft
#     （自编译产出无后缀二进制 hmmsearch/hmmbuild，与 HMMER3 同名，注意 PATH 顺序）
#   - 版本默认 2.3.2，与 modules/hmmer/meta.yaml software_versions 的 hmmer2_native 对齐
#
# 官方来源：
#   homepage : http://hmmer.org/
#   bioconda : https://anaconda.org/bioconda/hmmer2
#   source   : http://eddylab.org/software/hmmer/2.3.2/hmmer-2.3.2.tar.gz
#   (容器：quay.io/biocontainers/hmmer2 —— 本脚本为宿主机安装，容器用法见模块 README)
#
# 用法示例：
#   bash install.sh                                   # auto：有 conda/mamba 走 bioconda，否则源码自编译
#   bash install.sh --method conda                    # 强制 conda（默认建独立 env: hmmer2）
#   bash install.sh --method binary                   # 强制官方源码自编译（无需 conda）
#   bash install.sh --conda-env h2 --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --prefix ~/software/hmmer2-2.3.2  # binary 模式自定义前缀
#   bash install.sh --version 2.3.2                   # 覆盖版本（binary 模式 URL 模板 + 跳过内嵌校验和）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="2.3.2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/hmmer2-$DEFAULT_VERSION}"
CONDA_ENV="hmmer2"
METHOD="auto"          # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方 eddylab 源码归档（平台无关）内嵌 sha256；改 --version 后不匹配 → 自动跳过并提示
SHA256_SOURCE="d20e1779fcdff34ab4e986ea74a6c4ac5c5f01da2993b14e92c94d2f076828b4"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'
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
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# binary（源码自编译）模式覆盖 Linux / macOS（源码平台无关；其他平台请走 conda）
platform_ok_binary() {
    [[ "$OS" == "Linux" || "$OS" == "Darwin" ]]
}

# ---------------- 版本断言（安装后运行 hmmsearch -h 校验） ----------------
assert_version() {
    local bin="$1" out
    out="$("$bin" -h 2>&1 || true)"
    printf '  %s\n' "$(printf '%s\n' "$out" | grep -m1 -i 'HMMER' || echo "$out" | head -n1)"
    grep -qE "HMMER 2\..*${VERSION//./\.}" <<<"$out" \
        || grep -qE "${VERSION//./\.}" <<<"$out" \
        || die "版本校验失败：期望包含 ${VERSION}，实际输出见上"
    log "版本校验通过：$VERSION"
}

# ---------------- 路线 A：conda / bioconda ----------------
install_conda() {
    log "使用 conda 安装 hmmer2=$VERSION 到环境: $CONDA_ENV"
    local env_exists
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $CONDA_ENV 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 $CONDA_ENV 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 顺序固定 conda-forge 在前，避免依赖冲突
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda "hmmer2=$VERSION"
    # bioconda 包内二进制带 2 后缀（hmmsearch2/hmmbuild2）：优先断言 hmmsearch2，回退 hmmsearch
    log "验证：$CONDA_BIN run -n $CONDA_ENV hmmsearch2 -h"
    if ! "$CONDA_BIN" run -n "$CONDA_ENV" hmmsearch2 -h 2>&1 | grep -qi "HMMER 2\."; then
        "$CONDA_BIN" run -n "$CONDA_ENV" hmmsearch -h 2>&1 | grep -qi "HMMER 2\." \
            || die "conda 环境 $CONDA_ENV 中未找到可用的 HMMER2 hmmsearch2/hmmsearch"
    fi
    log "完成：conda activate $CONDA_ENV 后即可使用 hmmsearch2 / hmmbuild2（2 后缀）"
}

# ---------------- 路线 B：官方 eddylab 源码自编译（无预编译二进制） ----------------
install_binary() {
    local url tar srcdir make_jobs
    url="http://eddylab.org/software/hmmer/${VERSION}/hmmer-${VERSION}.tar.gz"

    log "下载官方 HMMER 源码: $url"
    log "安装前缀: $PREFIX"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    # 失败/中断时清理临时目录（成功路径末尾显式清理并置空，EXIT 钩子判空跳过）
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/hmmer2.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/hmmer2.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_SOURCE  $tmp/hmmer2.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_SOURCE  $tmp/hmmer2.tar.gz" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 eddylab 源码摘要）"
    fi

    tar -xzf "$tmp/hmmer2.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档解压失败（URL 或版本号有误？）"

    make_jobs="$( { command -v nproc >/dev/null 2>&1 && nproc; } || sysctl -n hw.ncpu 2>/dev/null || echo 2 )"
    log "configure --enable-threads --prefix=$PREFIX && make -j${make_jobs} && make install"
    (
        cd "$srcdir"
        ./configure --enable-threads --prefix="$PREFIX"
        make -j"${make_jobs}"
        make install
    )
    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -x "$PREFIX/bin/hmmsearch" ]] || die "未在 $PREFIX/bin 找到 hmmsearch（编译失败？）"
    assert_version "$PREFIX/bin/hmmsearch"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# hmmer2 (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 hmmsearch -h 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
    warn "注意：源码自编译产出无后缀二进制（hmmsearch/hmmbuild），与 HMMER3 同名；请确保本前缀在 PATH 中优先于 HMMER3。"
}

# ---------------- 主流程 ----------------
log "hmmer2 $VERSION 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
        install_conda ;;
    binary)
        platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 不支持；请改用 conda 路线"
        install_binary ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        elif platform_ok_binary; then
            install_binary
        else
            die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）不支持源码路线，无法自动安装"
        fi ;;
esac
log "安装成功"
