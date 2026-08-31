# samtools native Docker 镜像配方
# 构建：docker build -t bioskills/samtools:1.21-v1.0 -f Dockerfile .
# 运行：docker run --rm -u $(id -u):$(id -g) -v $PWD:/data bioskills/samtools:1.21-v1.0 ...

FROM continuumio/miniconda3:24.7.1-0

LABEL maintainer="bioskills"
LABEL software="samtools"
LABEL version="1.21-v1.0"

# 安装 conda 环境
COPY environment.yml /tmp/environment.yml
RUN conda env create -f /tmp/environment.yml -n samtools && \
    conda clean -afy

# 将 native 驱动与 meta 挂入镜像
COPY main.py /opt/skill/main.py
COPY meta.yaml /opt/skill/meta.yaml
COPY test/ /opt/skill/test/

ENV PATH=/opt/conda/envs/samtools/bin:$PATH \
    PYTHONPATH=/opt/skill \
    TMPDIR=/tmp

WORKDIR /data
ENTRYPOINT ["python", "/opt/skill/main.py"]
