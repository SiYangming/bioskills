# =============================================================================
# ANNOVAR 自建镜像（官方渠道无 ANNOVAR 镜像 → 兜底配方）
#
# 路线：apt 最小化优先（debian:bookworm-slim + apt --no-install-recommends + 清理四连）。
#   ANNOVAR 无 conda 包（bioconda 404）/ 无 quay / 无 depot，故不引入 conda 兜底，
#   仅安装运行时 Perl。
#
# ⚠️ 构建前请先在官网注册下载 annovar.latest.tar.gz（许可受限，学术/非营利免费，
#    商用需授权），并将该文件放到本目录（与 Dockerfile 同级）：
#      https://www.openbioinformatics.org/annovar/annovar_download_form.php
#    构建示例：
#      cp ~/Downloads/annovar.latest.tar.gz modules/annovar/native/
#      docker build -t annovar:latest -f modules/annovar/native/Dockerfile modules/annovar/native/
#    运行（必须 -u $(id -u):$(id -g)，否则产物归 root）：
#      docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data annovar:latest \
#          /data/variants.vcf /data/humandb/ -buildver hg38 -out variants.annovar \
#          -remove -protocol refGene -operation g -nastring . -vcfinput
# =============================================================================
FROM debian:bookworm-slim

ARG ANNOVAR_TARBALL=annovar.latest.tar.gz

ENV DEBIAN_FRONTEND=noninteractive \
    TMPDIR=/tmp \
    ANNOVAR_HOME=/opt/annovar \
    PATH=/opt/annovar:/usr/local/bin:/usr/bin:/bin

# apt 最小化：仅装运行时（perl + 网络下载依赖 libwww-perl + ca-certificates + procps）
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
        perl \
        libwww-perl \
        ca-certificates \
        procps \
 && apt-get autoremove -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 部署用户注册获取的 ANNOVAR tarball（含顶层 annovar/ 目录，--strip-components=1 展开）
COPY ${ANNOVAR_TARBALL} /tmp/annovar.tar.gz
RUN mkdir -p /opt/annovar \
 && tar -xzf /tmp/annovar.tar.gz -C /opt/annovar --strip-components=1 \
 && rm -f /tmp/annovar.tar.gz \
 && chmod +x /opt/annovar/*.pl \
 && test -f /opt/annovar/table_annovar.pl \
 && test -f /opt/annovar/annotate_variation.pl

WORKDIR /data
# ANNOVAR 为 Perl 脚本；默认以 table_annovar.pl 作为入口
ENTRYPOINT ["perl", "/opt/annovar/table_annovar.pl"]
CMD ["--help"]
