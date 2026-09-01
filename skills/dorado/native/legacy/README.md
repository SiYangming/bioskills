# dorado native 说明文件
# ---------------------------------------------------------------------------
# nanoseq 流程中 dorado 无 shell 脚本（nanoseq.sh/ 下没有 dorado 脚本），
# 只有 config/config.yaml 的 dorado 配置段：
#
#   enable_dorado: false
#   dorado:
#     docker_image: "docker.1ms.run/nanoporetech/dorado:latest"
#     model: "rna004_130bps_sup@v5.1.0"
#     dorado_bin: "dorado"
#     exec_mode: "docker"
#
# 因此本 legacy/ 目录不保留原始脚本；dorado 的 native 命令逻辑
# （basecall / demux）按 config.yaml 的 model 默认值与 dorado 官方 CLI 用法
# 在 ../main.py 中实现。正式入口为 ../main.py。
# ---------------------------------------------------------------------------
