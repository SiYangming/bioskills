# longreadsum native Docker 镜像配方（自建兜底：SWIG 源码编译路线，apt 最小化，禁 miniconda）
#
# 背景：LongReadSum 1.6.0（2025-09）无官方镜像 —— bioconda / quay.io/biocontainers / depot.galaxyproject.org
#       官方渠道仅到 1.3.1（2026-09-07 核实）；1.6.0 仅 GitHub tag 源码 / wglab conda 频道 / bioinfortools 社区镜像。
#       因此本配方走「debian:bookworm-slim + apt 构建依赖 + git clone v1.6.0 + make swig_build +
#       python3 setup.py build_ext」源码编译（仿官方 conda/build.sh；python 运行依赖用 venv + pip，
#       不引入 miniconda/micromamba）。
# 底座：Debian 12 bookworm-slim
#
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）：
#   docker build -t bioskills/longreadsum:1.6.0 -f modules/longreadsum/native/Dockerfile modules/
# 运行（ENTRYPOINT 即 longreadsum 本体；须 -u 避免产物归 root）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data bioskills/longreadsum:1.6.0 \
#       fa -i /data/reads.fa -o /data/out
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       --entrypoint /opt/lrs-venv/bin/python bioskills/longreadsum:1.6.0 \
#       /opt/skill/main.py fq -i /data/reads.fastq -o /data/out

ARG LONGREADSUM_VERSION=1.6.0
# 基础镜像可用 --build-arg BASE_IMAGE=<国内加速 registry>/library/debian:bookworm-slim 覆盖（默认官方源）
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

LABEL maintainer="bioskills"
LABEL software="longreadsum"
LABEL version="${LONGREADSUM_VERSION}"
LABEL longreadsum_version="${LONGREADSUM_VERSION}"
LABEL org.bioskills.software="longreadsum"
LABEL impl="native"
LABEL base_image="debian:bookworm-slim"
LABEL pkg_route="apt + git-tag source (SWIG build)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TMPDIR=/tmp

# 1) apt 最小依赖：构建（g++/make/swig/python3-dev/htslib-dev/hdf5-dev）+ 运行（libvbz-hdf-plugin）
#    LongReadSum 源码为 C++/SWIG 工程（setup.py 链接 hts/hdf5_cpp/hdf5/hdf5_hl_cpp/hdf5_hl），
#    需 htslib 与 HDF5 C++ 开发库；python3.11 受 PEP 668 保护，Python 运行依赖走 venv（免 miniconda）。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        g++ \
        make \
        swig \
        git \
        ca-certificates \
        curl \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libcurl4-openssl-dev \
        libhts-dev \
        libhdf5-dev \
        libhdf5-cpp-dev \
        libvbz-hdf-plugin \
        procps \
        tini \
    ; \
    # Python 运行依赖（官方 conda run deps 的 pip 对应物：numpy/plotly/pyarrow/pod5）
    python3 -m venv /opt/lrs-venv; \
    /opt/lrs-venv/bin/pip install --no-cache-dir --upgrade pip; \
    /opt/lrs-venv/bin/pip install --no-cache-dir \
        numpy \
        plotly \
        pyarrow \
        pod5; \
    /opt/lrs-venv/bin/python -c "import numpy, plotly, pod5, pyarrow; print('python deps OK')"

# 2) 源码编译：git clone v${LONGREADSUM_VERSION} tag → make swig_build（生成 lib/lrst.py + src/lrst_wrap.cpp）
#    → setup.py build_ext（编译 _lrst C++ 扩展，CXXFLAGS 补 Debian HDF5 serial 头路径）
RUN set -eux; \
    git clone --depth 1 --branch v${LONGREADSUM_VERSION} \
        https://github.com/WGLab/LongReadSum /tmp/LongReadSum; \
    cd /tmp/LongReadSum; \
    git describe --tags --always; \
    make swig_build; \
    CXXFLAGS="-I/usr/include/hdf5/serial" \
        /opt/lrs-venv/bin/python setup.py build_ext --build-lib lib; \
    ls -la lib/; \
    # 仿官方 conda/build.sh 部署到 /opt/longreadsum（lib=SWIG python 模块+so；src=cli/报告 python 源码）
    mkdir -p /opt/longreadsum/lib /opt/longreadsum/src; \
    cp -r lib/*.py lib/_lrst*.so /opt/longreadsum/lib/; \
    cp -r src/*.py /opt/longreadsum/src/; \
    test -f /opt/longreadsum/lib/lrst.py && test -f /opt/longreadsum/lib/_lrst*.so

# 3) longreadsum 启动 wrapper：注入 lib/src 后调用官方 cli（installed 分支），由 venv python 运行
COPY longreadsum/native/wrapper.py /usr/local/bin/longreadsum
RUN chmod 0755 /usr/local/bin/longreadsum

# 4) 版本断言：longreadsum 主命令可用
RUN /usr/local/bin/longreadsum --help >/tmp/lrs_help.txt && grep -qi "File types" /tmp/lrs_help.txt

# 5) 拷贝驱动层（context=modules/）：main.py + base.py + 软件级 meta.yaml + test/
COPY base.py /opt/skill/base.py
COPY longreadsum/native/main.py /opt/skill/main.py
COPY longreadsum/meta.yaml /opt/skill/longreadsum/meta.yaml
COPY longreadsum/native/test/ /opt/skill/test/
RUN /opt/lrs-venv/bin/python /opt/skill/main.py --list-commands >/dev/null \
    && /opt/lrs-venv/bin/python /opt/skill/main.py --schema >/tmp/lrs_schema.json \
    && test -s /tmp/lrs_schema.json

# 6) 仅构建期工具移除 + 清理四连
RUN set -eux; \
    rm -rf /tmp/LongReadSum /tmp/lrs_help.txt /tmp/lrs_schema.json; \
    apt-get purge -y git curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf \
        /usr/share/doc/* \
        /usr/share/man/* \
        /usr/share/info/* \
        /usr/share/locale/* \
        /var/cache/debconf/* \
        /var/lib/apt/lists/* \
        /root/.cache/pip \
        /tmp/* \
        /var/tmp/*

ENV PYTHONPATH=/opt/skill \
    PATH=/usr/local/bin:$PATH

WORKDIR /data

# ENTRYPOINT tini：负责正确收割子进程 + 转发信号；本体即 longreadsum
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/longreadsum"]
CMD ["--help"]
