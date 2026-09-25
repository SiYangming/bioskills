# subworkflow/system_setup — 宿主机系统引导

无编排 `main.py`。按 OS 直接跑脚本：

```
native/centos6|centos8/
  modify_system_config_files.sh
  system_software_installation.sh
```

- 元数据：[system_setup.yaml](system_setup.yaml)
- 这是**环境前置**，不是生信分析流程。

## 用法

```bash
# 先阅读脚本；--real 会改系统（用户名 train 等硬编码）
bash -n subworkflow/system_setup/native/centos8/modify_system_config_files.sh
sudo bash subworkflow/system_setup/native/centos8/modify_system_config_files.sh
sudo bash subworkflow/system_setup/native/centos8/system_software_installation.sh
```

静态自检：`bash native/test/run_test.sh`（仅 `bash -n`）。

## 安全

仅用于隔离实验机；生产环境勿直接执行。
