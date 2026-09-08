# syntax=docker/dockerfile:1
# =============================================================================
# dia-nn native 自建容器配方（无官方镜像，apt 最小化兜底；Conda 不做默认引入）
#
# 路线判定（2026-09-07 核实）：DIA-NN 官方渠道全无 ——
#   bioconda dia-nn 404 / quay.io/biocontainers/dia-nn 无 / depot.galaxyproject.org 无
#   （仅有社区镜像 quay.io/bioinfortools/diann:2.3.2 与第三方 conda 频道 YangmingSi dia-nn=2.3.2）
#   → 自建兜底：debian:bookworm-slim + apt --no-install-recommends +
#     .NET 8 Runtime（packages.microsoft.com 的 dotnet-runtime-8.0，非 SDK）+ 官方 Academia zip。
#
# DIA-NN 官方仅分发 Windows .msi 与 Linux zip；diann-linux 是 .NET 8 框架依赖程序
# （zip 内带 libtorch/libgomp 等），需 LD_LIBRARY_PATH 指向程序目录。
# 许可证：Academia 版学术/非营利免费；商用需官方许可（使用者自行负责合规）。
#
# 构建：docker build -t dia-nn:2.6.1 native/
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data dia-nn:2.6.1 \
#         diann --fasta ... --dir ... --out ... --threads N
# =============================================================================
FROM debian:bookworm-slim

LABEL org.bioskills.software="dia-nn" \
      org.bioskills.impl="native" \
      org.bioskills.base_image="debian:bookworm-slim" \
      org.bioskills.diann_version="2.6.1" \
      org.bioskills.pkg_route="apt + dotnet-runtime-8.0(packages.microsoft.com) + 官方 zip(DIA-NN-2.6.1-Academia-Linux)"

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    TMPDIR=/tmp

ARG DIANN_VERSION=2.6.1
# zip 解压内层：DIA-NN-<ver>-Academia-Linux/diann-<ver>/
ENV DIANN_HOME=/opt/DIA-NN-${DIANN_VERSION}-Academia-Linux/diann-${DIANN_VERSION}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget unzip libgomp1; \
    wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb; \
    dpkg -i /tmp/packages-microsoft-prod.deb; \
    rm -f /tmp/packages-microsoft-prod.deb; \
    apt-get update; \
    apt-get install -y --no-install-recommends dotnet-runtime-8.0; \
    wget -q "https://github.com/vdemichev/DiaNN/releases/download/2.0/DIA-NN-${DIANN_VERSION}-Academia-Linux.zip" -O /tmp/diann.zip; \
    echo "f98e396af791f1903168b365a83fc2cc72208cc133281b9ce6ebe3a794b999ba  /tmp/diann.zip" | sha256sum -c -; \
    unzip -q /tmp/diann.zip -d /opt; \
    rm -f /tmp/diann.zip; \
    test -x "$DIANN_HOME/diann-linux"; \
    chmod -R a+rX "$DIANN_HOME"; \
    printf '#!/bin/sh\nLD_LIBRARY_PATH=%s${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\nexport LD_LIBRARY_PATH\nexec "%s/diann-linux" "$@"\n' \
        "$DIANN_HOME" "$DIANN_HOME" > /usr/local/bin/diann; \
    chmod 0755 /usr/local/bin/diann; \
    apt-get purge -y wget unzip; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/info /tmp/* /var/tmp/*

# 构建期版本断言：banner 含 DIA-NN 与版本号（diann 无参/未知参数打印 usage 后非零退出，吞码取输出）
RUN set -eux; \
    out="$(diann --help 2>&1 || true)"; \
    printf '%s\n' "$out" | grep -q "DIA-NN"; \
    printf '%s\n' "$out" | grep -q "2.6.1"; \
    printf '%s\n' "$out" | head -n 3

# 不创建固定账号：运行时用 -u $(id -u):$(id -g) 接管（避免 HPC UID 冲突 / 产物归 root）
ENTRYPOINT ["/usr/local/bin/diann"]
CMD ["--help"]
