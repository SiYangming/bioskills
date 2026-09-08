# syntax=docker/dockerfile:1
# =============================================================================
# genetribe native 自建容器配方（无官方镜像，apt 最小化兜底；Conda 不做默认引入）
#
# 路线判定（2026-09-07 核实）：GeneTribe 官方渠道全无 ——
#   bioconda genetribe 404 / quay.io/biocontainers/genetribe 无 / depot.galaxyproject.org 无
#   （仅有社区镜像 quay.io/bioinfortools/genetribe:1.2.1 与个人 conda 频道 YangmingSi
#   genetribe=1.2.1 noarch）→ 自建兜底：debian:bookworm-slim + apt --no-install-recommends +
#   python3-venv + pip 装 jcvi + git clone 官方 tag v1.2.1 + 上游 ./install.sh。
#
# 依赖与版本（bookworm apt / PyPI，2026-09-07 核实）：
#   - ncbi-blast+ = 2.12.0+ds-3（>= 官方文档推荐 2.9.0，避免旧版强锁 blast=2.9.0 的 C 库
#     冲突/OOM 教训，见 README「历史留存」）
#   - bedtools    = 2.30.0+dfsg-3（>= 官方推荐 2.29.2）
#   - jcvi        = pip 最新 1.6.7（官方文档推荐 v1.0.6；bookworm 无 python-jcvi apt 包）
#   - genetribe   = v1.2.1（git tag；commit 5aa4fc5d7a2e00129000bd282efc1161b57d023c）
# 本配方仅登记（linux/amd64），不参与实际构建。
#
# 构建：docker build -t genetribe:1.2.1 native/
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data genetribe:1.2.1 \
#         core -l aet -f rice --threads 16
#   （pipeline 类子命令在工作目录找 <前缀>.bed/.fa/.chrlist 等，见模块 README「实战示例」）
# 注意：ENTRYPOINT 指向 /opt/genetribe/genetribe（勿符号链接到别处——上游入口脚本按
#   argv[0] 相对路径找 bin/，符号链接会破坏 bin 解析）。
# =============================================================================
FROM debian:bookworm-slim

LABEL org.bioskills.software="genetribe" \
      org.bioskills.impl="native" \
      org.bioskills.base_image="debian:bookworm-slim" \
      org.bioskills.genetribe_version="1.2.1" \
      org.bioskills.pkg_route="apt(ncbi-blast+/bedtools/python3-venv) + pip(jcvi) + git clone v1.2.1 + ./install.sh"

ENV DEBIAN_FRONTEND=noninteractive \
    TMPDIR=/tmp \
    GENETRIBE_VERSION=1.2.1

ARG GENETRIBE_TAG=v1.2.1

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git gawk \
        ncbi-blast+ bedtools \
        python3 python3-venv python3-pip; \
    # jcvi(MCscan)：python3-venv 隔离安装（Debian PEP668 下 /usr/bin pip 不可直接写系统） \
    python3 -m venv /opt/genetribe-venv; \
    /opt/genetribe-venv/bin/pip install --no-cache-dir 'jcvi>=1.0.6'; \
    # 官方源码：clone tag v1.2.1 + 上游 ./install.sh（生成 bin/ 符号链接） \
    git clone --depth 1 --branch "${GENETRIBE_TAG}" \
        https://github.com/chenym1/genetribe.git /opt/genetribe; \
    cd /opt/genetribe; \
    ./install.sh; \
    test -x /opt/genetribe/genetribe; \
    # 清理四连（仅构建期 git/curl/python3-pip 一并移除） \
    apt-get purge -y curl git python3-pip; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/info /tmp/* /var/tmp/*

# PATH：直接加入 /opt/genetribe（上游安装法即把仓库目录加 PATH；不要符号链接入口）
ENV PATH="/opt/genetribe:/opt/genetribe-venv/bin:${PATH}"

# 构建期版本断言：genetribe -h 打印 Program/Version: 1.2.1；blastp/bedtools/jcvi 可导入
RUN set -eux; \
    out="$(genetribe -h)"; \
    printf '%s\n' "$out" | grep -q "GeneTribe"; \
    printf '%s\n' "$out" | grep -q "1.2.1"; \
    blastp -version | head -n 1; \
    bedtools --version; \
    python3 -c "import jcvi; print('jcvi OK', getattr(jcvi, '__version__', '?'))"

# 不创建固定账号：运行时用 -u $(id -u):$(id -g) 接管（避免 HPC UID 冲突 / 产物归 root）
ENTRYPOINT ["/opt/genetribe/genetribe"]
CMD ["-h"]
