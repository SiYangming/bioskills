# 基础镜像：保持原有版本，如需更轻量化可替换为latest-slim（但需测试兼容性）
FROM continuumio/miniconda3:latest

# 添加Quay.io镜像元数据
LABEL maintainer="Yangming Si <siyangming1991@163.com>"
LABEL description="RibOSS (RNA-binding protein prediction tool) - Quay.io auto-build image"
LABEL org.opencontainers.image.source="https://github.com/lcscs12345/riboss"
LABEL org.opencontainers.image.version="0.46"

# 合并RUN指令，解决目录不存在错误+pip参数错误，保留所有体积优化
RUN apt-get update && \
    # 安装必要工具（移除未使用的wget）
    apt-get install -y --no-install-recommends git && \
    # 配置Conda通道
    conda config --add channels conda-forge && \
    conda config --add channels defaults && \
    conda config --add channels bioconda && \
    conda config --set channel_priority flexible && \
    # 浅克隆仓库
    git clone --depth 1 https://github.com/lcscs12345/riboss.git /opt/riboss && \
    # 删除.git目录，节省空间
    rm -rf /opt/riboss/.git && \
    # 切换到项目目录创建Conda环境
    cd /opt/riboss && \
    conda env create -f environment.yml && \
    # 清理conda缓存
    conda clean --all -y && \
    # 验证riboss环境是否创建成功
    conda info --envs | grep -q "riboss" || (echo "Conda环境创建失败" && exit 1) && \
    # 定义riboss环境路径
    export RIBOSS_ENV_PYTHON="/opt/conda/envs/riboss/bin/python" && \
    export RIBOSS_ENV_BIN="/opt/conda/envs/riboss/bin" && \
    # 验证Python可执行文件存在
    if [ ! -f "$RIBOSS_ENV_PYTHON" ]; then echo "riboss环境Python不存在" && exit 1; fi && \
    # 复制并授权riboprof脚本
    if [ -d "bin" ] && [ -f "bin/riboprof" ]; then \
        cp bin/riboprof "$RIBOSS_ENV_BIN" && \
        chmod +x "$RIBOSS_ENV_BIN/riboprof" && \
        echo "riboprof脚本复制成功"; \
    else \
        echo "riboprof脚本不存在" && exit 1; \
    fi && \
    # 常规安装riboss（仅此处保留--root-user-action，抑制安装时的root警告）
    "$RIBOSS_ENV_PYTHON" -m pip install . --force-reinstall --root-user-action=ignore && \
    # 关键修复1：删除/opt/riboss前，先切换到存在的目录（/ 目录永久存在）
    cd / && \
    # 现在再删除无用的源码目录，避免当前工作目录失效
    rm -rf /opt/riboss && \
    # 关键修复2：移除pip cache purge后的无效参数--root-user-action
    "$RIBOSS_ENV_PYTHON" -m pip cache purge && \
    # 验证riboss模块可用性
    "$RIBOSS_ENV_PYTHON" -c "from riboss.orfs import translate; na='ATGGTCTGA'; translate(na); print('Riboss模块安装验证成功，翻译函数可用')" && \
    # 卸载无用工具git
    apt-get remove -y git && \
    apt-get autoremove -y && \
    # 彻底清理apt缓存和临时文件
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 创建自定义entrypoint脚本，避免conda run的失败消息
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'source /opt/conda/etc/profile.d/conda.sh' >> /entrypoint.sh && \
    echo 'conda activate riboss >/dev/null 2>&1' >> /entrypoint.sh && \
    echo 'exec "$@"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# 强制指定PATH优先级，确保riboss环境命令优先执行
ENV PATH="/opt/conda/envs/riboss/bin:/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 构建阶段最终验证
RUN echo "当前Python路径：$(which python)" && \
    python --version && \
    python -c "from riboss.orfs import translate; na='ATGGTCTGA'; result=translate(na); print('容器构建阶段验证成功！翻译结果：', result)"

# 工作目录设置为数据目录
WORKDIR /data

# 容器启动使用自定义entrypoint激活环境
ENTRYPOINT ["/entrypoint.sh"]

# 默认启动bash终端
CMD ["bash"]