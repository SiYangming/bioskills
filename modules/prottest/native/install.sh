#!/usr/bin/env bash
# =============================================================================
# install.sh — ProtTest3（prottest）宿主机本地安装脚本
#
# 归属    ：bioskills modules/prottest/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §4.5；官方镜像优先语境）
#   - binary 路线（唯一，默认）：官方 GitHub release 预编译 Java 包，解压到用户级
#     前缀 --prefix（默认 ~/software/prottest-3.4.2），无需 root、不写 /opt
#   - 无 conda 路线：bioconda 无 prottest 包（2026-09 核实 404），故 --method conda 直接报错
#   - 版本默认 3.4.2，与 modules/prottest/meta.yaml software_versions.native 对齐
#
# 官方来源：
#   homepage : https://github.com/ddarriba/prottest3
#   release  : https://github.com/ddarriba/prottest3/releases/tag/3.4.2-release
#   source   : https://github.com/ddarriba/prottest3/archive/refs/tags/3.4.2-release.tar.gz（ant jar）
#   (容器：无官方镜像 —— bioconda/quay/depot 全无，本模块自建 native/Dockerfile、Apptainer.def)
#
# 用法示例：
#   bash install.sh                              # 下载官方预编译包到 ~/software/prottest-3.4.2
#   bash install.sh --prefix ~/opt/prottest      # 自定义安装前缀（即 PROTTEST_HOME）
#   bash install.sh --version 3.4.2 --force      # 覆盖版本（跳过内嵌 sha256 校验并提示）
#   bash install.sh --profile ~/.zshrc --no-path-update
# =============================================================================
set -euo pipefail

# ---------------- 默认值（与 meta.yaml software_versions.native 对齐） ----------------
DEFAULT_VERSION="3.4.2"
VERSION="$DEFAULT_VERSION"
PREFIX="${PREFIX:-$HOME/software/prottest-$DEFAULT_VERSION}"
METHOD="binary"        # binary | conda（conda 不可用，仅保留参数面一致性）
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
FORCE=0

# 官方预编译 tarball（release 3.4.2-release/prottest-3.4.2-20160508.tar.gz）内嵌 sha256
SHA256_TARBALL="d5afd55972e5b9903942eab4f0273f9614848bf4b6747a7839d3c675dc9067e6"

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="${2:?--version 需要版本号}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";      shift 2 ;;
        --method)      METHOD="${2:?--method 需要 binary|conda}"; shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}";     shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

case "$METHOD" in
    binary) ;;
    conda)  die "bioconda 无 prottest 包（api.anaconda.org/package/bioconda/prottest 404，2026-09 核实），无 conda 路线；请用默认 --method binary（官方预编译包）" ;;
    *)      die "--method 仅支持 binary|conda（收到: ${METHOD}）" ;;
esac

command -v java >/dev/null 2>&1 || die "未检测到 java（ProtTest3 需 JRE/JDK 运行；请先安装 Java）"

# ---------------- 官方预编译包下载 + 解压 + 校验 ----------------
install_binary() {
    local url tar name srcdir
    name="prottest-3.4.2-20160508.tar.gz"
    url="https://github.com/ddarriba/prottest3/releases/download/${VERSION}-release/${name}"

    log "下载官方预编译包: $url"
    log "安装前缀（PROTTEST_HOME）: $PREFIX"
    [[ "$FORCE" == 1 || ! -e "$PREFIX" ]] || die "前缀已存在：${PREFIX}（加 --force 覆盖，或 --prefix 指定其它目录）"
    mkdir -p "$PREFIX"

    local tmp=""
    tmp="$(mktemp -d)"
    cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp/$name" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/$name" "$url"
    else
        die "需要 curl 或 wget 下载 release"
    fi

    if [[ "$VERSION" == "$DEFAULT_VERSION" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$SHA256_TARBALL  $tmp/$name" | sha256sum -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        else
            echo "$SHA256_TARBALL  $tmp/$name" | shasum -a 256 -c - >/dev/null 2>&1 \
                || die "sha256 校验失败：下载文件不完整或被篡改"
        fi
        log "sha256 校验通过"
    else
        warn "非默认版本（${VERSION}），跳过内嵌 sha256 校验（可自行核对 GitHub release 摘要）"
    fi

    tar -xzf "$tmp/$name" -C "$tmp"
    srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d -name 'prottest-*' | head -1)"
    [[ -n "$srcdir" ]] || die "release 包结构异常（未找到 prottest-* 目录）"
    # 解压内容整体落到 $PREFIX（jar / lib / bin / runProtTestHPC.sh 等）
    cp -R "$srcdir"/. "$PREFIX"/

    local jar
    jar="$(find "$PREFIX" -maxdepth 1 -name 'prottest-3.*.jar' | sort | tail -n 1)"
    [[ -n "$jar" ]] || die "未在 $PREFIX 找到 prottest-3.*.jar（URL 或版本号有误？）"

    # 生成 $PREFIX/bin/prottest 包装脚本（java -jar + JVM 内存）
    mkdir -p "$PREFIX/bin"
    cat > "$PREFIX/bin/prottest" <<EOF
#!/usr/bin/env bash
# ProtTest3 包装脚本（bioskills install.sh 生成）：export PROTTEST_HOME=${PREFIX}
export PROTTEST_HOME="${PREFIX}"
exec java \${JAVA_OPTS:-} -jar "${jar}" "\$@"
EOF
    chmod 0755 "$PREFIX/bin/prottest"
    rm -rf "$tmp"; tmp=""; trap - EXIT

    # 版本断言：prottest -h 输出含 3.4.2（用法行含 prottest-3.4.2.jar）
    local out
    out="$("$PREFIX/bin/prottest" -h 2>&1)"
    printf '%s\n' "$out" | grep -q "${VERSION//./\.}" \
        || die "版本校验失败：期望输出含 ${VERSION}，实际见上"

    log "已安装（ProTest ${VERSION}）；PROTTEST_HOME=$PREFIX"

    if [[ "$UPDATE_PATH" == 1 ]]; then
        local line="export PATH=\"$PREFIX/bin:\$PATH\""
        if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
            log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
        else
            { echo ""; echo "# prottest (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
            log "已追加 PATH 到 $PROFILE"
        fi
        log "完成：重新登录或 source $PROFILE 后执行 prottest 即可"
    else
        log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

# ---------------- 主流程 ----------------
log "prottest $VERSION 安装开始（本机 $(uname -s)/$(uname -m)）"
install_binary
log "安装成功（PROTTEST_HOME=${PREFIX}）"
