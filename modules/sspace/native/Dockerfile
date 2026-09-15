# =============================================================================
# Dockerfile — sspace (SSPACE STANDARD v3.0) 自建兜底镜像
#
# 为什么自建：2026-09 核实官方渠道全无 —— bioconda `sspace` 404（仅 sspace_basic，
# 为另一工具）、quay.io/biocontainers/sspace 无、depot.galaxyproject.org 无 →
# 走 debian 最小化兜底（apt --no-install-recommends + 清理四连），不引入 miniconda。
#
# 关键依赖：libperl4-corelibs-perl（SSPACE require "getopts.pl"，现代 Perl 已移除该库）。
# 软件本体：官方发行 tar（BaseClear 原 URL 已 404，取自社区归档
#   github.com/yexianingyue/SSPACE-STANDARD-3.0，内嵌 sha256 校验）。
# 捆绑组件：bowtie 0.12.5 与 bwa（linux-x86_64 ELF，随官方 tar 分发）。
# =============================================================================
FROM debian:bookworm-slim

ENV TMPDIR=/tmp
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
      perl \
      libperl4-corelibs-perl \
      ca-certificates \
      curl \
      procps \
 && curl -fsSL -o /tmp/sspace.tar.gz \
      "https://raw.githubusercontent.com/yexianingyue/SSPACE-STANDARD-3.0/main/SSPACE-STANDARD-v.-3.0-linux-x86_64.tar.gz" \
 && echo "4a5064103921e196ad66f80c7ff4373ddc6be9d830b8f30b8cd5c6785693645a  /tmp/sspace.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/sspace \
 && tar -xzf /tmp/sspace.tar.gz -C /opt/sspace \
 && printf '#!/bin/sh\nexec perl /opt/sspace/SSPACE-STANDARD-3.0_linux-x86_64/SSPACE_Standard_v3.0.pl "$@"\n' > /usr/local/bin/SSPACE_Standard_v3.0.pl \
 && chmod +x /usr/local/bin/SSPACE_Standard_v3.0.pl \
 && printf '#!/bin/sh\nexec perl /opt/sspace/SSPACE-STANDARD-3.0_linux-x86_64/tools/sam_bam2tab.pl "$@"\n' > /usr/local/bin/sam_bam2tab.pl \
 && chmod +x /usr/local/bin/sam_bam2tab.pl \
 && apt-get purge -y curl \
 && apt-get autoremove -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PATH="/opt/sspace/SSPACE-STANDARD-3.0_linux-x86_64:/usr/local/bin:${PATH}"

WORKDIR /data
ENTRYPOINT ["/usr/local/bin/SSPACE_Standard_v3.0.pl"]
CMD ["--help"]
