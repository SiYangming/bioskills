#!/usr/bin/env bash
# =============================================================================
# install.sh — HMMER（3.x 现行版 / 2.x 遗留版）宿主机本地安装脚本
#
# 归属    ：bioskills modules/hmmer/native/install.sh（native 实现安装方式；单一实现覆盖两条版本线）
# 迁移形态：现代规范（AGENT.md §7 官方镜像优先 / README「环境安装」对齐）
#   - conda  路线（默认优先）：mamba/conda 创建独立环境
#       3.x → bioconda::hmmer=3.4
#       2.x → bioconda::hmmer2=2.3.2（包内二进制带 2 后缀：hmmsearch2 / hmmbuild2 / …）
#   - binary 路线（无 conda 兜底）：官方 eddylab 源码归档自编译，用户级前缀
#     安装到 --prefix（默认 3.x ~/software/hmmer-<ver>；2.x ~/software/hmmer2-<ver>），
#     无需 root、不写 /opt/biosoft
#     （2.x 自编译产出无后缀二进制 hmmsearch/hmmbuild，与 HMMER3 同名，注意 PATH 顺序）
#   - 版本默认：3.x = 3.4；2.x = 2.3.2，与 modules/hmmer/meta.yaml software_versions 对齐
#
# 官方来源：
#   homepage : http://hmmer.org/
#   bioconda : 3.x https://anaconda.org/bioconda/hmmer · 2.x https://anaconda.org/bioconda/hmmer2
#   source   : 3.x http://eddylab.org/software/hmmer/hmmer-3.4.tar.gz
#              2.x http://eddylab.org/software/hmmer/2.3.2/hmmer-2.3.2.tar.gz
#   （容器：quay.io/biocontainers/hmmer 与 quay.io/biocontainers/hmmer2——本脚本为宿主机安装，
#     容器用法见模块 README）
#
# 用法示例：
#   bash install.sh                                   # 3.x：auto（有 conda/mamba 走 bioconda，否则源码自编译）
#   bash install.sh --line 2                          # 2.x 遗留版：auto
#   bash install.sh --line both                       # 两条版本线都装
#   bash install.sh --line 2 --method binary          # 强制 2.x 官方源码自编译（无需 conda）
#   bash install.sh --conda-env h3 --force            # 指定环境名 / 已存在时强制重建
#   bash install.sh --line 2 --prefix ~/software/hmmer2-2.3.2
#   bash install.sh --version 2.3.2                   # 覆盖版本（非默认版本跳过内嵌 sha256 校验）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions 对齐） ----------------
DEFAULT_VERSION_3="3.4"
DEFAULT_VERSION_2="2.3.2"
LINE="3"                 # 3 | 2 | both
METHOD="auto"            # auto | conda | binary
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0
VERSION=""               # 未显式指定时，按版本线取 DEFAULT_VERSION_*
PREFIX=""                # 未显式指定时，按版本线取默认前缀
CONDA_ENV=""             # 未显式指定时，按版本线取默认环境名

# 官方 eddylab 源码归档内嵌 sha256（平台无关）；非默认版本或未内嵌时自动跳过校验。
# HMMER 3.4：实测下载核对（19,669,667 bytes，http://eddylab.org/software/hmmer/hmmer-3.4.tar.gz）。
SHA256_SOURCE_3="ca70d94fd0cf271bd7063423aabb116d42de533117343a9b27a65c17ff06fbf3"
# HMMER 2.3.2：实测下载核对（1,024,933 bytes，http://eddylab.org/software/hmmer/2.3.2/hmmer-2.3.2.tar.gz）。
SHA256_SOURCE_2="d20e1779fcdff34ab4e986ea74a6c4ac5c5f01da2993b14e92c94d2f076828b4"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --line)        LINE="${2:?--line 需要 3|2|both}"; shift 2 ;;
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

case "$LINE" in 3|2|both) ;; *) die "--line 仅支持 3|2|both（收到: ${LINE}）" ;; esac
case "$METHOD" in auto|conda|binary) ;; *) die "--method 仅支持 auto|conda|binary（收到: ${METHOD}）" ;; esac
[[ "$LINE" == "both" ]] && { [[ -z "$VERSION" ]] || die "--line both 与 --version 不能同时指定"; }

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)";   ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

# 源码自编译模式覆盖 Linux / macOS（源码平台无关；其他平台请走 conda）
platform_ok_binary() {
    [[ "$OS" == "Linux" || "$OS" == "Darwin" ]]
}

sha256_check() {
    local file="$1" expected="$2"
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$expected  $file" | sha256sum -c - >/dev/null 2>&1
    else
        echo "$expected  $file" | shasum -a 256 -c - >/dev/null 2>&1
    fi
}

download() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$out" "$url"
    else
        die "需要 curl 或 wget 下载源码归档"
    fi
}

append_path() {
    local prefix="$1"
    if [[ "$UPDATE_PATH" != 1 ]]; then
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$prefix/bin:\$PATH\""
        return
    fi
    local line="export PATH=\"$prefix/bin:\$PATH\""
    if [[ -f "$PROFILE" ]] && grep -qF "$prefix/bin" "$PROFILE"; then
        log "PATH 已包含 $prefix/bin，跳过写入 $PROFILE"
    else
        { echo ""; echo "# hmmer (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
        log "已追加 PATH 到 $PROFILE"
    fi
    log "完成：重新登录或 source $PROFILE 后即可使用（3.x 用 hmmsearch；2.x 用 hmmsearch2 / 源码自编译的 hmmsearch）"
}

# =========================================================================== #
# HMMER 3.x（默认版本线）
# =========================================================================== #
install_conda_3() {
    local ver="$1" env="$2" env_exists
    log "使用 conda 安装 hmmer=$ver 到环境: $env（HMMER 3.x 现行版）"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$env" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $env 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$env"
        else
            die "conda 环境 $env 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    # 顺序固定 conda-forge 在前，避免依赖冲突
    "$CONDA_BIN" create -y -n "$env" -c conda-forge -c bioconda "hmmer=$ver"
    log "验证：$CONDA_BIN run -n $env hmmsearch -h"
    "$CONDA_BIN" run -n "$env" hmmsearch -h 2>&1 | grep -qi "HMMER 3\." \
        || die "conda 环境 $env 中未找到可用的 HMMER3 hmmsearch"
    log "完成：conda activate $env 后即可使用 hmmbuild / hmmpress / hmmsearch"
}

install_binary_3() {
    local ver="$1" prefix="$2" url srcdir make_jobs tmp
    url="http://eddylab.org/software/hmmer/hmmer-${ver}.tar.gz"

    log "下载官方 HMMER ${ver} 源码: $url"
    log "安装前缀: $prefix"
    mkdir -p "$prefix"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    download "$url" "$tmp/hmmer3.tar.gz"

    if [[ "$ver" == "$DEFAULT_VERSION_3" && -n "$SHA256_SOURCE_3" ]]; then
        sha256_check "$tmp/hmmer3.tar.gz" "$SHA256_SOURCE_3" || die "sha256 校验失败：下载文件不完整或被篡改"
        log "sha256 校验通过"
    else
        log "跳过内嵌 sha256 校验（${ver} 未内嵌摘要；官方源码页可自行核对，见 http://hmmer.org/download.html）"
    fi

    tar -xzf "$tmp/hmmer3.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "hmmer-*" | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档解压失败（URL 或版本号有误？）"

    make_jobs="$( { command -v nproc >/dev/null 2>&1 && nproc; } || sysctl -n hw.ncpu 2>/dev/null || echo 2 )"
    log "configure --prefix=$prefix && make -j${make_jobs} && make install"
    (
        cd "$srcdir"
        ./configure --prefix="$prefix"
        make -j"${make_jobs}"
        make install
    )
    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -x "$prefix/bin/hmmsearch" ]] || die "未在 $prefix/bin 找到 hmmsearch（编译失败？）"
    local out
    out="$("$prefix/bin/hmmsearch" -h 2>&1 || true)"
    grep -qE "HMMER 3\..*${ver//./\.}" <<<"$out" || grep -qE "HMMER 3\." <<<"$out" \
        || die "版本校验失败：期望 HMMER 3.x（${ver}），实际输出见上"
    log "版本校验通过：${ver}"

    append_path "$prefix"
}

# =========================================================================== #
# HMMER 2.x（遗留版）
# =========================================================================== #
install_conda_2() {
    local ver="$1" env="$2" env_exists
    log "使用 conda 安装 hmmer2=$ver 到环境: $env（HMMER 2.x 遗留版）"
    env_exists="$("$CONDA_BIN" env list | awk -v e="$env" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 $env 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$env"
        else
            die "conda 环境 $env 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi
    "$CONDA_BIN" create -y -n "$env" -c conda-forge -c bioconda "hmmer2=$ver"
    # bioconda 包内二进制带 2 后缀（hmmsearch2/hmmbuild2）：优先断言 hmmsearch2，回退 hmmsearch
    log "验证：$CONDA_BIN run -n $env hmmsearch2 -h"
    if ! "$CONDA_BIN" run -n "$env" hmmsearch2 -h 2>&1 | grep -qi "HMMER 2\."; then
        "$CONDA_BIN" run -n "$env" hmmsearch -h 2>&1 | grep -qi "HMMER 2\." \
            || die "conda 环境 $env 中未找到可用的 HMMER2 hmmsearch2/hmmsearch"
    fi
    log "完成：conda activate $env 后即可使用 hmmsearch2 / hmmbuild2（2 后缀）"
}

install_binary_2() {
    local ver="$1" prefix="$2" url srcdir make_jobs tmp
    url="http://eddylab.org/software/hmmer/${ver}/hmmer-${ver}.tar.gz"

    log "下载官方 HMMER ${ver} 源码: $url"
    log "安装前缀: $prefix"
    mkdir -p "$prefix"

    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    download "$url" "$tmp/hmmer2.tar.gz"

    if [[ "$ver" == "$DEFAULT_VERSION_2" && -n "$SHA256_SOURCE_2" ]]; then
        sha256_check "$tmp/hmmer2.tar.gz" "$SHA256_SOURCE_2" || die "sha256 校验失败：下载文件不完整或被篡改"
        log "sha256 校验通过"
    else
        warn "非默认版本（${ver}），跳过内嵌 sha256 校验（可自行核对 eddylab 源码摘要）"
    fi

    tar -xzf "$tmp/hmmer2.tar.gz" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name "hmmer-*" | head -1)"
    [[ -n "$srcdir" ]] || die "源码归档解压失败（URL 或版本号有误？）"

    make_jobs="$( { command -v nproc >/dev/null 2>&1 && nproc; } || sysctl -n hw.ncpu 2>/dev/null || echo 2 )"
    log "configure --enable-threads --prefix=$prefix && make -j${make_jobs} && make install"
    (
        cd "$srcdir"
        ./configure --enable-threads --prefix="$prefix"
        make -j"${make_jobs}"
        make install
    )
    rm -rf "$tmp"; tmp=""; trap - EXIT

    [[ -x "$prefix/bin/hmmsearch" ]] || die "未在 $prefix/bin 找到 hmmsearch（编译失败？）"
    local out
    out="$("$prefix/bin/hmmsearch" -h 2>&1 || true)"
    grep -qE "HMMER 2\..*${ver//./\.}" <<<"$out" || grep -qE "${ver//./\.}" <<<"$out" \
        || die "版本校验失败：期望包含 ${ver}，实际输出见上"
    log "版本校验通过：${ver}"

    append_path "$prefix"
    warn "注意：源码自编译产出无后缀二进制（hmmsearch/hmmbuild），与 HMMER3 同名；请确保本前缀在 PATH 中优先于 HMMER3。"
}

# ---------------- 单条版本线安装（auto 分派） ----------------
install_line() {
    local line="$1" ver env prefix
    if [[ "$line" == "3" ]]; then
        ver="${VERSION:-$DEFAULT_VERSION_3}"
        env="${CONDA_ENV:-hmmer-native}"
        prefix="${PREFIX:-$HOME/software/hmmer-$ver}"
    else
        ver="${VERSION:-$DEFAULT_VERSION_2}"
        env="${CONDA_ENV:-hmmer2}"
        prefix="${PREFIX:-$HOME/software/hmmer2-$ver}"
    fi
    log "—— 版本线 HMMER ${line}.x（版本 $ver）——"

    case "$METHOD" in
        conda)
            [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"
            if [[ "$line" == "3" ]]; then install_conda_3 "$ver" "$env"; else install_conda_2 "$ver" "$env"; fi ;;
        binary)
            platform_ok_binary || die "--method binary 在 ${OS}/${ARCH} 不支持；请改用 conda 路线"
            if [[ "$line" == "3" ]]; then install_binary_3 "$ver" "$prefix"; else install_binary_2 "$ver" "$prefix"; fi ;;
        auto)
            if [[ -n "$CONDA_BIN" ]]; then
                if [[ "$line" == "3" ]]; then install_conda_3 "$ver" "$env"; else install_conda_2 "$ver" "$env"; fi
            elif platform_ok_binary; then
                if [[ "$line" == "3" ]]; then install_binary_3 "$ver" "$prefix"; else install_binary_2 "$ver" "$prefix"; fi
            else
                die "未检测到 mamba/conda 且本平台（${OS}/${ARCH}）不支持源码路线，无法自动安装"
            fi ;;
    esac
}

# ---------------- 主流程 ----------------
log "hmmer 安装开始（本机 ${OS}/${ARCH}；--line ${LINE}；--method ${METHOD}）"
case "$LINE" in
    3)    install_line 3 ;;
    2)    install_line 2 ;;
    both)
        [[ "$METHOD" == "conda" || -n "$CONDA_BIN" ]] \
            || warn "--line both 且无 conda：两次源码自编译会先后覆盖同名 hmmsearch/hmmbuild，请注意 PATH 顺序"
        install_line 3
        install_line 2 ;;
esac
log "安装成功"
