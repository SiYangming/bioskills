#!/usr/bin/env bash
# =============================================================================
# install.sh — FGENESH 宿主机本地安装脚本（许可受限）
#
# 归属    ：bioskills modules/fgenesh/native/install.sh（native 实现安装方式）
# 迁移形态：现代规范（AGENT.md §7；官方渠道全无 + 许可受限 → 自建兜底）
#
# ⚠️ 许可受限：FGENESH 为 Softberry 商业软件。学术用户须向 Softberry 申请免费学术许可、
#    商业用户须购买许可后获得发行包。**禁止未授权获取/使用/再分发**。本脚本不下载任何
#    Softberry 资产，仅编排用户自备的授权发行包（--tarball）。
#
#   - 官方渠道核实（2026-09）：bioconda fgenesh 未找到 / quay.io/biocontainers/fgenesh 401
#     （不存在）/ depot.galaxyproject.org 404 —— 无 conda 包、无官方镜像
#   - 官网 softberry.com 2026-09 探测不可达（curl 000），版本号与校验和均无法在线核实
#   - 故本脚本仅做「授权发行包部署 + PATH + 参数文件就位」，用户级前缀（默认 ~/software/fgenesh）
#
# 用法示例：
#   bash install.sh --tarball ~/downloads/fgenesh.tar.gz          # 部署授权发行包
#   bash install.sh --tarball fgenesh.zip --prefix ~/opt/fgenesh  # 自定义前缀
#   bash install.sh --help
# =============================================================================
set -euo pipefail

PREFIX="${PREFIX:-$HOME/software/fgenesh}"
PROFILE="${HOME}/.bashrc"
UPDATE_PATH=1
TARBALL=""
FORCE=0

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install] 错误：%s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tarball)     TARBALL="${2:?--tarball 需要授权发行包路径}"; shift 2 ;;
        --prefix)      PREFIX="${2:?--prefix 需要路径}";  shift 2 ;;
        --profile)     PROFILE="${2:?--profile 需要路径}"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --no-path-update) UPDATE_PATH=0; shift ;;
        --help|-h)     usage ;;
        *) die "未知参数: $1（--help 查看用法）" ;;
    esac
done

# ---------------- 许可与前置提示 ----------------
cat >&2 <<'EOF'

⚠️  FGENESH 为 Softberry 商业软件，许可受限：
    学术用户须向 Softberry 申请免费学术许可；商业用户须购买许可。
    禁止未授权获取、使用与再分发。本脚本仅部署你已合法取得的发行包。
    申请入口（官网，2026-09 探测不可达，请以搜索引擎获取当前地址）：
      http://www.softberry.com/berry.phtml?topic=fgenesh&group=programs&subgroup=gfind

EOF

[[ -n "$TARBALL" ]] || die "缺少 --tarball（Softberry 授权发行包路径）；本软件官方渠道全无且许可受限，无法自动下载"
[[ -f "$TARBALL" ]] || die "找不到授权发行包: $TARBALL"

if [[ -d "$PREFIX" && "$FORCE" != 1 ]]; then
    die "前缀已存在: $PREFIX（加 --force 覆盖，或 --prefix 指定其它目录）"
fi
[[ "$FORCE" == 1 && -d "$PREFIX" ]] && rm -rf "$PREFIX"
mkdir -p "$PREFIX"

log "解压授权发行包: $TARBALL -> $PREFIX"
tmp="$(mktemp -d)"
cleanup_tmp() { [[ -n "${tmp:-}" ]] && rm -rf "$tmp"; }
trap cleanup_tmp EXIT

case "$TARBALL" in
    *.tar.gz|*.tgz)  tar -xzf "$TARBALL" -C "$PREFIX" ;;
    *.tar.bz2|*.tbz2) tar -xjf "$TARBALL" -C "$PREFIX" ;;
    *.tar)           tar -xf  "$TARBALL" -C "$PREFIX" ;;
    *.zip)           command -v unzip >/dev/null 2>&1 || die "解压 .zip 需要 unzip"; unzip -q "$TARBALL" -d "$PREFIX" ;;
    *) die "不支持的归档格式: $TARBALL（支持 .tar.gz/.tar.bz2/.tar/.zip）" ;;
esac
rm -rf "$tmp"; tmp=""; trap - EXIT

# ---------------- 定位并暴露可执行文件 ----------------
mkdir -p "$PREFIX/bin"
bin_src="$(find "$PREFIX" -maxdepth 4 -type f -name fgenesh -perm -u+x 2>/dev/null | head -1)"
[[ -n "$bin_src" ]] || bin_src="$(find "$PREFIX" -maxdepth 4 -type f -name fgenesh 2>/dev/null | head -1)"
[[ -n "$bin_src" ]] || die "发行包内未找到 fgenesh 可执行文件（归档结构异常/版本不符？）"
chmod 0755 "$bin_src"
ln -sf "$bin_src" "$PREFIX/bin/fgenesh"
log "已就位可执行文件: $PREFIX/bin/fgenesh -> $bin_src"

# ---------------- 参数文件（fungi/arabidopsis/rice/human/mouse/drosophila/worm.par） ----------------
params_dir="$(dirname "$bin_src")/params"
if [[ -d "$params_dir" ]]; then
    log "参数文件目录: $params_dir（如 fungi.par / human.par / ...）"
else
    warn "未在 $params_dir 找到 params 目录；请确认 Softberry 发行包内含 *.par（--params-dir 指向之）"
fi

# ---------------- 版本断言（软校验：FGENESH 无统一 --version，运行时可能需许可） ----------------
out="$("$PREFIX/bin/fgenesh" 2>&1 || true)"
printf '%s\n' "$out" | head -n 3 | sed 's/^/  /'
grep -qiE "fgenesh|usage|parameter" <<<"$out" \
    && log "冒烟通过（fgenesh 可执行）" \
    || warn "fgenesh 未输出预期的 usage（可能需在授权环境运行；文件已就位）"

# ---------------- PATH ----------------
if [[ "$UPDATE_PATH" == 1 ]]; then
    line="export PATH=\"$PREFIX/bin:\$PATH\""
    if [[ -f "$PROFILE" ]] && grep -qF "$PREFIX/bin" "$PROFILE"; then
        log "PATH 已包含 $PREFIX/bin，跳过写入 $PROFILE"
    else
        { echo ""; echo "# fgenesh (bioskills install.sh)"; echo "$line"; } >> "$PROFILE"
        log "已追加 PATH 到 $PROFILE"
    fi
    log "完成：重新登录或 source $PROFILE 后执行 fgenesh 即可"
else
    log "完成（未改 PATH）：使用时请执行 export PATH=\"$PREFIX/bin:\$PATH\""
fi
log "安装成功（请确保使用符合 Softberry 许可条款）"
