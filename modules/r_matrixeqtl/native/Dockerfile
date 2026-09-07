# r_matrixeqtl 自建容器（native/Dockerfile）
#
# 路线：官方 quay.io/biocontainers/r-matrixeqtl 仅 2.1.1/R3.3（版本过旧），
#       本配方以 rocker/r-ver:4.5.2 + CRAN MatrixEQTL 作为「新版替代」（自建兜底）。
#       R 包不在 Debian apt 源，故采用 rocker 官方 R 底座 + CRAN 直装；MatrixEQTL
#       NeedsCompilation: no（纯 R），无需编译链。容器运行务必加 -u $(id -u):$(id -g)。
#
# 构建：
#   docker build -t r-matrixeqtl:2.3 .
# 运行（等价能力由 native/main.py analyze 子命令提供，见 README「实战示例」）：
#   docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#       r-matrixeqtl:2.3 Rscript run_matrixeqtl.R <params.tsv>

FROM rocker/r-ver:4.5.2

ENV TMPDIR=/tmp

# 内置 eQTL 分析驱动（供 docker run 直接以 Rscript /opt/skill/run_matrixeqtl.R 使用）
COPY run_matrixeqtl.R /opt/skill/run_matrixeqtl.R
RUN chmod +x /opt/skill/run_matrixeqtl.R

# MatrixEQTL 纯 R 源码安装（NeedsCompilation: no，无需编译链）；RhpcBLASctl 线程控制
# 需要编译工具链且仅影响 OpenBLAS 线程，可选 —— 需要时在宿主机单独 install.packages
RUN R -e "install.packages('MatrixEQTL', repos='https://cloud.r-project.org', quiet=TRUE)" \
 && Rscript -e 'stopifnot(requireNamespace("MatrixEQTL", quietly=TRUE))' \
 && rm -rf /usr/local/lib/R/doc/html /tmp/* /var/tmp/*

# 工作目录（产物归属由 -u $(id -u):$(id -g) 决定）
WORKDIR /data

CMD ["R"]
