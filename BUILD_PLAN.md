# 构建计划：chenlianfu 教学流程 → bioskills 复合流程层

> **v7**（新增 S22 `system_setup`：原 01 章入库为 subworkflow）
> 规范：[AGENT.md](AGENT.md)、[ARCHITECTURE.md](ARCHITECTURE.md)
> 状态：**执行中**（本文件为可执行蓝图；细节随实施迭代）

---

## 修订记录（近期）

### v6 → v7（2026-09-20）

| # | 决定 | 落地 |
|---|---|---|
| 1 | 原「01.CentOS_System_Configuration 不入库」**撤销** | 新增 **S22 `subworkflow/system_setup/`**（native 目录形态） |
| 2 | 命名在 `System_setup` / `System_Configuration` 间择一 | 采用 **`system_setup`**（全小写下划线；覆盖配置+装包+中间件，见下） |

### 命名说明

| 候选 | 结论 |
|---|---|
| `system_configuration` | 仅强调改配置，覆盖不全 |
| **`system_setup`** | **采用**：与 `sratools_pipeline` 等命名风格一致；语义含配置、基线包、httpd/MariaDB、软件根目录 |

---

## S22 `system_setup`（P1，规则 C，来源 01）

| 项 | 内容 |
|---|---|
| **目录** | `subworkflow/system_setup/`（`system_setup.md` + `meta.yaml` + `native/`） |
| **源脚本** | `modify_system_config_files.sh`、`system_software_installation.sh` |
| **形态** | native 编排：`--list-stages` / `--dry-run`（默认）/ `--real --confirm-root` |
| **硬约束** | 路径/用户参数化；不入库弱口令；`--real` 需显式确认；sysoft 预编译解压默认关闭 |
| **与 AGENT.md** | 不替代 modules 官方镜像路线；本组合只做**宿主机前置** |
| **被引用** | W2/W4（MariaDB）、W7（httpd）、各 workflow「前置环境」脚注 |

**Stage 链**：`configure_repos` → `install_base_packages` → `harden_ssh` → `configure_firewall` → `configure_selinux_limits` → `configure_user_env` → `setup_httpd` → `setup_mariadb` → `prepare_soft_dirs` →（可选）`install_sysoft_runtimes`

**明确不做**：把 CentOS ISO / 预编译 tarball 二进制入库；在容器内跑本组合改 `/etc`。

---

## 与旧「明确不做」表的关系

| 原 v5/v6 条目 | v7 |
|---|---|
| `01.CentOS_System_Configuration` → 不入库，仅脚注 | **改为入库** S22；脚注改为「详见 `subworkflow/system_setup`」 |
| 硬编码 `/home/train`、`/opt/biosoft` | **仍禁止写死**；S22 用 CLI 参数提供同名默认值 |
| 各章 `software_installation.sh` 源码编译生信软件 | **仍不入库**（与官方镜像优先冲突）；S22 只保留系统基线包 + 可选 sysoft 解压 |

---

## 实施顺序（节选）

```
阶段 1.5 / 2 并行：S22 system_setup（骨架已落地；可与 S18/S19 并行）
  └─ 验收：bash subworkflow/system_setup/native/test/run_test.sh
```

其余 workflow / subworkflow 优先级仍以历史评审结论为准（W1/W2 P0；S18 MVP 等）。完整 v6 细则若需从会话恢复，可在本文件后续章节回填。
