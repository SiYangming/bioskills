#!/usr/bin/env bash
# =============================================================================
# install.sh — RNAmmer 1.2 宿主机本地安装脚本
#
# 归属    ：bioskills modules/rnammer/native/install.sh（native 实现安装方式）
# 迁移形态：宿主机安装（官方渠道无镜像：bioconda / quay.io/biocontainers /
#   depot.galaxyproject.org 均无 rnammer，2026-09 核实；RNAmmer 1.2 源码为
#   CBS DTU 官网注册制下载，无法在容器内公开拉取），双路线：
#     - conda  路线（默认优先）：mamba/conda 创建独立环境，装 HMMER2 + perl +
#       XML::Simple 等运行依赖（hmmer2 为 2.3.2，RNAmmer 对 HMMER 版本敏感，
#       教学如需 2.2g 请用 --method manual）
#     - manual 路线：官方 hmmer-2.2g 源码编译到用户前缀 + 解压并就地配置用户
#       已注册下载的 rnammer-1.2 源码包（--rnammer-tarball 必需）
#   - 要点：RNAmmer 本体源码为注册制下载，本脚本无法自动获取，必须由用户从
#     CBS DTU 官网注册下载后经 --rnammer-tarball 传入（manual 路线必需）。
#   - 版本默认 1.2，与 modules/rnammer/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   RNAmmer 1.2 源码（注册制）：https://services.healthtech.dtu.dk/services/RNAmmer-1.2/
#   RNAmmer 1.2 源码替代来源（自建归档镜像，已归档/只读、私有需授权）：
#                               https://github.com/SiYangming/rnammer-1.2
#   HMMER 2.2g 源码：           http://eddylab.org/software/hmmer/hmmer-2.2g.tar.gz
#   HMMER2 conda 包：           https://anaconda.org/bioconda/hmmer2
#   （bioconda / quay.io/biocontainers / depot.galaxyproject.org 均无 rnammer，2026-09 核实）
#
# 用法示例：
#   bash install.sh                                                        # auto：有 conda 走 conda，否则 manual
#   bash install.sh --method conda                                         # 强制 conda 路线（装 HMMER2/perl 依赖）
#   bash install.sh --method manual --rnammer-tarball ~/Downloads/rnammer-1.2.tar.gz
#   bash install.sh --method manual --hmmer-version 2.2g --hmmer-prefix ~/software/hmmer-2.2g
#   bash install.sh --prefix ~/software/rnammer-1.2 --conda-env rnammer --force
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="1.2"
VERSION="$DEFAULT_VERSION"
DEFAULT_HMMER_VERSION="2.2g"
HMMER_VERSION="$DEFAULT_HMMER_VERSION"
PREFIX=""
HMMER_PREFIX=""
CONDA_ENV="rnammer"
METHOD="auto"          # auto | conda | manual
RNAMMER_TARBALL=""
PYTHON=""
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
install.sh — RNAmmer 1.2 宿主机本地安装脚本（官方渠道无镜像：conda / manual 双路线）

用法：
  bash install.sh [选项]

选项：
  --method auto|conda|manual  安装路线（默认 auto：有 mamba/conda 走 conda，否则 manual）
  --python <路径>             安装后自省冒烟用的 python3 解释器（默认自动探测 python3）
  --conda-env <名>            conda 路线环境名（默认 rnammer）
  --hmmer-version <版本>      manual 路线编译的 HMMER 版本（默认 2.2g）
  --hmmer-prefix <路径>       HMMER 安装前缀（默认 ~/software/hmmer-<版本>）
  --rnammer-tarball <路径>    用户已注册下载的 rnammer-1.2 源码 tarball（manual 路线必需）
  --prefix <路径>             RNAmmer 安装前缀（默认 ~/software/rnammer-1.2）
  --profile <路径>            PATH 写入目标（默认 ~/.bashrc）
  --no-path-update            不写 shell profile
  --force                     环境/前缀已存在时强制重建
  --version <版本>            软件版本（默认 1.2；仅 1.2 受支持）
  --help, -h                  显示本帮助并退出

官方来源：
  RNAmmer 1.2 源码（注册制下载）: https://services.healthtech.dtu.dk/services/RNAmmer-1.2/
  源码替代来源（自建归档镜像，已归档/只读、私有需授权）:
                                  https://github.com/SiYangming/rnammer-1.2
  HMMER 2.2g 源码:                http://eddylab.org/software/hmmer/hmmer-2.2g.tar.gz
  HMMER2 conda 包:                https://anaconda.org/bioconda/hmmer2
  （bioconda / quay.io/biocontainers / depot.galaxyproject.org 均无 rnammer，2026-09 核实）
EOF
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)         VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --method)          METHOD="${2:?--method 需要 auto|conda|manual}"; shift 2 ;;
        --python)          PYTHON="${2:?--python 需要解释器路径}"; shift 2 ;;
        --conda-env)       CONDA_ENV="${2:?--conda-env 需要环境名}"; shift 2 ;;
        --hmmer-version)   HMMER_VERSION="${2:?--hmmer-version 需要版本号}"; shift 2 ;;
        --hmmer-prefix)    HMMER_PREFIX="${2:?--hmmer-prefix 需要路径}"; shift 2 ;;
        --rnammer-tarball) RNAMMER_TARBALL="${2:?--rnammer-tarball 需要 tarball 路径}"; shift 2 ;;
        --prefix)          PREFIX="${2:?--prefix 需要路径}"; shift 2 ;;
        --profile)         PROFILE="${2:?--profile 需要路径}"; shift 2 ;;
        --force)           FORCE=1; shift ;;
        --no-path-update)  UPDATE_PATH=0; shift ;;
        --help|-h)         usage; exit 0 ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in auto|conda|manual) ;; *) die "--method 仅支持 auto|conda|manual（收到: ${METHOD}）" ;; esac

if [[ -n "$VERSION" && "$VERSION" != "$DEFAULT_VERSION" ]]; then
    warn "--version ${VERSION} ≠ 默认 ${DEFAULT_VERSION}：RNAmmer 官网现行版为 1.2，按 1.2 继续"
    VERSION="$DEFAULT_VERSION"
fi
PREFIX="${PREFIX:-${HOME}/software/rnammer-${VERSION}}"
HMMER_PREFIX="${HMMER_PREFIX:-${HOME}/software/hmmer-${HMMER_VERSION}}"

# ---------------- 平台 / 工具探测 ----------------
OS="$(uname -s)"; ARCH="$(uname -m)"
CONDA_BIN=""
if command -v mamba >/dev/null 2>&1; then CONDA_BIN="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then CONDA_BIN="$(command -v conda)"; fi

if [[ -z "$PYTHON" ]]; then
    PYTHON="$(command -v python3 || command -v python || true)"
fi

REG_HINT="RNAmmer 1.2 源码为注册制下载，请到 https://services.healthtech.dtu.dk/services/RNAmmer-1.2/ 注册申请后下载；替代来源（自建归档镜像，已归档/只读、私有需授权）：https://github.com/SiYangming/rnammer-1.2"

# ---------------- 断言：hmmsearch 可用 ----------------
# bioconda hmmer2 包内二进制带 2 后缀（hmmsearch2）；HMMER3 的 hmmsearch 不带后缀，故优先探测 hmmsearch2
resolve_hmmsearch() {
    local dir="$1"
    if [[ -x "${dir}/hmmsearch2" ]]; then
        echo "${dir}/hmmsearch2"
    else
        echo "${dir}/hmmsearch"
    fi
}

assert_hmmsearch() {
    local hs="$1"
    [[ -x "$hs" ]] || die "hmmsearch 不可执行: ${hs}（HMMER2 未正确安装？bioconda hmmer2 的二进制名为 hmmsearch2）"
    log "hmmsearch 可用: ${hs}"
}

# ---------------- 断言：perl XML::Simple / XML::Parser 可加载 ----------------
assert_perl_xml() {
    local perl_bin="$1"
    [[ -x "$perl_bin" ]] || die "perl 不可执行: ${perl_bin}"
    "$perl_bin" -MXML::Parser -e1 2>/dev/null \
        || die "perl 缺少 XML::Parser（${perl_bin}）：conda 路线请装 perl-xml-simple，或 cpanm XML::Parser"
    "$perl_bin" -MXML::Simple -e1 2>/dev/null \
        || die "perl 缺少 XML::Simple（${perl_bin}）：conda 路线请装 perl-xml-simple，或 cpanm XML::Simple"
    log "perl 模块 XML::Simple / XML::Parser 可加载（${perl_bin}）"
}

# ---------------- PATH 写入 ----------------
add_path() {
    local dirs="$1"
    if [[ "$UPDATE_PATH" != 1 ]]; then
        warn "未改 PATH；使用时请执行 export PATH=\"${dirs}:\$PATH\""
        return 0
    fi
    if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX" "$PROFILE"; then
        log "PATH 已包含 ${PREFIX}，跳过写入 ${PROFILE}"
        return 0
    fi
    { echo ""; echo "# rnammer (bioskills install.sh)"; echo "export PATH=\"${dirs}:\$PATH\""; } >> "$PROFILE"
    log "已追加 PATH 到 ${PROFILE}"
}

# ---------------- manual：编译 HMMER2 源码 ----------------
compile_hmmer2() {
    local hp="$1"
    local url="http://eddylab.org/software/hmmer/hmmer-${HMMER_VERSION}.tar.gz"
    command -v make >/dev/null 2>&1 || die "编译 HMMER 需要 make（未找到）；或改用 --method conda"
    if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
        die "编译 HMMER 需要 C 编译器（cc/gcc/clang）；或改用 --method conda"
    fi

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    log "下载 HMMER 源码: ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/hmmer-${HMMER_VERSION}.tar.gz" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/hmmer-${HMMER_VERSION}.tar.gz" "$url"
    else
        die "需要 curl 或 wget 下载 HMMER 源码"
    fi

    tar -xzf "$tmp/hmmer-${HMMER_VERSION}.tar.gz" -C "$tmp"
    local srcdir="${tmp}/hmmer-${HMMER_VERSION}"
    [[ -d "$srcdir" ]] || srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
    [[ -d "$srcdir" ]] || die "HMMER 源码解压失败（${url}）"

    mkdir -p "$hp"
    log "编译安装 HMMER ${HMMER_VERSION} -> ${hp}"
    ( cd "$srcdir" && ./configure --prefix="$hp" && make && make install )

    rm -rf "$tmp"; tmp=""; trap - EXIT
}

# ---------------- 解压并就地配置 RNAmmer 源码 ----------------
setup_rnammer() {
    local hmmsearch_bin="$1" perl_bin="$2"

    [[ -n "$RNAMMER_TARBALL" ]] \
        || die "配置 RNAmmer 需要 --rnammer-tarball（用户已注册下载的 rnammer-1.2 tarball）；${REG_HINT}"
    [[ -f "$RNAMMER_TARBALL" ]] || die "未找到 rnammer tarball: ${RNAMMER_TARBALL}；${REG_HINT}"

    if [[ -e "$PREFIX" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            case "$PREFIX" in
                ""|"/"|"$HOME") die "拒绝删除危险前缀: ${PREFIX}" ;;
            esac
            log "前缀 ${PREFIX} 已存在（--force），删除重建"
            rm -rf "$PREFIX"
        else
            die "前缀 ${PREFIX} 已存在；加 --force 重建，或改用 --prefix 指定其它目录"
        fi
    fi
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    log "解压 rnammer 源码: ${RNAMMER_TARBALL} -> ${PREFIX}"
    tar -xf "$RNAMMER_TARBALL" -C "$tmp"
    local src="$tmp"
    if [[ ! -f "$tmp/rnammer" ]]; then
        local cand
        cand="$(find "$tmp" -maxdepth 2 -type f -name rnammer | head -n 1)"
        [[ -n "$cand" ]] || die "tarball 内未找到 rnammer 脚本（确认是 rnammer-1.2 源码包？）"
        src="$(dirname "$cand")"
    fi
    cp -R "$src"/. "$PREFIX"/
    rm -rf "$tmp"; tmp=""; trap - EXIT

    local script="${PREFIX}/rnammer"
    [[ -f "$script" ]] || die "未找到 rnammer 脚本: ${script}"
    chmod +x "$script" || true

    # 就地替换两处路径：INSTALL_PATH 指向安装目录、HMMSEARCH_BINARY 指向 HMMER2 hmmsearch
    log "就地配置 INSTALL_PATH=${PREFIX}"
    log "就地配置 HMMSEARCH_BINARY=${hmmsearch_bin}"
    if ! INSTALL_PATH="$PREFIX" HMMSEARCH_BINARY="$hmmsearch_bin" "$perl_bin" -p -i -e '
            s{^(\s*(?:my\s+)?\$INSTALL_PATH\s*=\s*).*$}{$1"$ENV{INSTALL_PATH}";};
            s{^(\s*(?:my\s+)?\$HMMSEARCH_BINARY\s*=\s*).*$}{$1"$ENV{HMMSEARCH_BINARY}";};
        ' "$script"; then
        warn "perl 就地替换返回非零；请手动检查 ${script}"
    fi

    grep -qF "$PREFIX" "$script" \
        && log "INSTALL_PATH 已生效" \
        || warn "未自动匹配到 INSTALL_PATH 赋值行；请手动把 ${script} 内的 INSTALL_PATH 改为 ${PREFIX}"
    grep -qF "$hmmsearch_bin" "$script" \
        && log "HMMSEARCH_BINARY 已生效" \
        || warn "未自动匹配到 HMMSEARCH_BINARY 赋值行；请手动把 ${script} 内的 HMMSEARCH_BINARY 改为 ${hmmsearch_bin}"

    log "冒烟测试：perl -c ${script}"
    if ! "$perl_bin" -c "$script"; then
        warn "perl 语法/依赖检查未通过（请确认 XML::Simple 等依赖已装）"
    fi
}

# ---------------- 路线 conda：建环境 + 提示 RNAmmer 源码 ----------------
install_conda() {
    [[ -n "$CONDA_BIN" ]] || die "--method conda 但未检测到 mamba/conda（PATH 中）"

    local env_exists
    env_exists="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $1}')"
    if [[ -n "$env_exists" ]]; then
        if [[ "$FORCE" == 1 ]]; then
            log "环境 ${CONDA_ENV} 已存在（--force），删除重建"
            "$CONDA_BIN" env remove -y -n "$CONDA_ENV"
        else
            die "conda 环境 ${CONDA_ENV} 已存在；加 --force 重建，或改用 --conda-env 指定其它环境名"
        fi
    fi

    warn "bioconda hmmer2 为 2.3.2（教学用 hmmer-2.2g）；RNAmmer 对 HMMER 版本敏感，如需 2.2g 请用 --method manual"
    log "创建环境 ${CONDA_ENV}（HMMER2 + perl + XML::Simple 等运行依赖）"
    "$CONDA_BIN" create -y -n "$CONDA_ENV" -c conda-forge -c bioconda \
        python=3.11 pyyaml hmmer2 perl perl-xml-simple perl-xml-parser

    local env_prefix
    env_prefix="$("$CONDA_BIN" env list | awk -v e="$CONDA_ENV" '$1==e {print $NF}')"
    [[ -n "$env_prefix" ]] || die "无法解析 conda 环境前缀: ${CONDA_ENV}"
    [[ -d "$env_prefix" ]] || die "conda 环境目录不存在: ${env_prefix}"

    local env_hmmsearch
    env_hmmsearch="$(resolve_hmmsearch "${env_prefix}/bin")"
    local env_perl="${env_prefix}/bin/perl"
    assert_hmmsearch "$env_hmmsearch"
    assert_perl_xml "$env_perl"

    if [[ -n "$RNAMMER_TARBALL" ]]; then
        setup_rnammer "$env_hmmsearch" "$env_perl"
        add_path "${PREFIX}:${env_prefix}/bin"
    else
        warn "conda 路线已装好 HMMER2/perl 运行依赖；${REG_HINT}"
        warn "下载后用 --rnammer-tarball <rnammer-1.2.tar.gz> 重跑本脚本，或按 README ③ 手动解压配置"
        warn "配置时 HMMSEARCH_BINARY 指向: ${env_hmmsearch}"
    fi

    if [[ -n "$PYTHON" ]]; then
        "$PYTHON" "$SELF_DIR/main.py" --list-commands >/dev/null 2>&1 \
            || warn "main.py --list-commands 自省失败（python: ${PYTHON}）"
    fi
    log "完成：conda activate ${CONDA_ENV} 后运行 python native/main.py scan ..."
}

# ---------------- 路线 manual：源码编译 HMMER2 + 配置 rnammer ----------------
install_manual() {
    [[ -n "$RNAMMER_TARBALL" ]] || die "--method manual 需要 --rnammer-tarball；${REG_HINT}"

    local hmmsearch_bin="${HMMER_PREFIX}/bin/hmmsearch"
    if [[ -x "$hmmsearch_bin" ]]; then
        log "复用已编译 HMMER: ${hmmsearch_bin}"
    else
        compile_hmmer2 "$HMMER_PREFIX"
    fi
    assert_hmmsearch "$hmmsearch_bin"

    command -v perl >/dev/null 2>&1 || die "manual 路线需要系统 perl（未找到）；或改用 --method conda"
    local perl_bin
    perl_bin="$(command -v perl)"
    assert_perl_xml "$perl_bin"

    setup_rnammer "$hmmsearch_bin" "$perl_bin"
    add_path "${PREFIX}:${HMMER_PREFIX}/bin"

    if [[ -n "$PYTHON" ]]; then
        "$PYTHON" "$SELF_DIR/main.py" --list-commands >/dev/null 2>&1 \
            || warn "main.py --list-commands 自省失败（python: ${PYTHON}）"
    fi
    log "完成：重新登录或 source ${PROFILE} 后执行 rnammer 即可"
}

# ---------------- 主流程 ----------------
log "RNAmmer ${VERSION} 安装开始（本机 ${OS}/${ARCH}）"
case "$METHOD" in
    conda)
        install_conda ;;
    manual)
        install_manual ;;
    auto)
        if [[ -n "$CONDA_BIN" ]]; then
            install_conda
        else
            warn "未检测到 mamba/conda，改走 manual 路线"
            install_manual
        fi ;;
esac
log "安装成功"
