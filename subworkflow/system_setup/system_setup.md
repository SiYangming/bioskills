# subworkflow/system_setup — 宿主机系统引导（01.CentOS_System_Configuration）

**命名**：选用 **`system_setup`**（非 `system_configuration`）。

| 候选 | 结论 |
|---|---|
| `system_configuration` | 偏「改配置文件」，覆盖不全（源章还有软件安装 / 运行时解压） |
| **`system_setup`** | **采用**：覆盖配置 + 基线包 + 中间件 + 目录准备；与仓库全小写下划线命名一致 |

来源：`chenlianfu_training_pipelines_v8.0/01.CentOS_System_Configuration/` 的两份脚本（`modify_system_config_files.sh`、`system_software_installation.sh`），按 bioskills 分层规范迁入 **native 目录形态**。

> 本组合是 **环境前置**，不是生信分析流程。生信工具本体仍走 `modules/<sw>/`（官方镜像优先，见 AGENT.md §7）。各 workflow 文档「前置环境」可交叉引用本组合。

## Stage 图

```
configure_repos
      │
      ▼
install_base_packages
      │
      ├─► harden_ssh
      ├─► configure_firewall
      └─► configure_selinux_limits
      │
      ▼
configure_user_env
      │
      ├─► setup_httpd          （结果网页浏览）
      └─► setup_mariadb        （PASA / MAKER / OrthoMCL 等外部依赖）
      │
      ▼
prepare_soft_dirs              （bio_soft_root / sys_soft_root）
      │
      └─► install_sysoft_runtimes  （可选；默认跳过；现代路线用 conda）
```

stages 声明见 [meta.yaml](meta.yaml)。

## 编排入口（native/main.py）

仓库根执行：

```bash
# 自省
python3 subworkflow/system_setup/native/main.py --list-stages

# 默认 dry-run（打印将执行的命令；参数化用户与路径）
python3 subworkflow/system_setup/native/main.py \
  --train-user analysis --train-home /home/analysis \
  --bio-soft-root /data/biosoft --sys-soft-root /data/sysoft

# 只跑部分 stage
python3 subworkflow/system_setup/native/main.py \
  --stages prepare_soft_dirs,configure_user_env

# 真实执行（需 root + 显式确认）
sudo python3 subworkflow/system_setup/native/main.py --real --confirm-root
```

实现：

- [native/main.py](native/main.py)：`--list-stages` / `--dry-run` / `--real`
- [native/system_setup_stages.sh](native/system_setup_stages.sh)：单 stage 执行器（参数化路径）

## 相对源脚本的刻意差异

| 源行为 | 本仓处理 |
|---|---|
| 写死 `/home/train`、`/opt/biosoft` | `--train-user` / `--train-home` / `--bio-soft-root` / `--sys-soft-root` |
| MariaDB 默认口令 `123456` 写入脚本 | **不入库弱口令**；文档说明手工建账号 |
| 源码编译 GCC / 全量 yum 装生信依赖 | 基线包可配；运行时解压默认 **关闭**（`--enable-sysoft-runtimes` 才开） |
| CentOS 8 专用 `dnflocal` / ISO | `configure_repos` 有则用、无则跳过提示 |

## 与其它流程的关系

- **W2 / W4**：PASA、MAKER、OrthoMCL 需要 MariaDB → 引用本组合 `setup_mariadb`（服务在宿主机 / compose，镜像只装客户端，见 U5 口径）。
- **W7**：httpd 结果目录浏览 → `setup_httpd`。
- **不替代** `modules/*/native/install.sh` 与官方 biocontainer。

## 安全警告

- `--real` 会改 `/etc/ssh/sshd_config`、SELinux、firewall、sudoers，**仅用于隔离教学机**。
- 开放 `3306`、禁用 SELinux 会扩大攻击面。
- 勿把含明文口令的历史脚本再提交进仓库。

## 测试

```bash
bash subworkflow/system_setup/native/test/run_test.sh
```

仅覆盖 `--list-stages` 与 dry-run 命令拼装（不改系统）。
