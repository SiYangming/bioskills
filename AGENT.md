# AGENT.md — bioskills 技能库构建规范

> 本文档是「每次新增/维护一个软件技能时必须遵守的标准」。
> 按本规范构建可保证：目录一致、接口统一、Agent 可路由、可自动校验。
> 参考实现：`skills/samtools/`（作为黄金样例）。

---

## 0. 一句话总览

```
skills/<software>/
├── meta.yaml              # 软件级总览（列出所有实现 + 推荐优先级）
├── native/                # [自定义/优先] 本地自包含实现（source_type: custom）
│   ├── meta.yaml          # 实现级 Schema + optimization
│   ├── main.py            # 标准入口驱动（继承 base.SkillBase）
│   ├── environment.yml    # Conda/Mamba 配方
│   ├── Dockerfile         # Docker 镜像配方
│   ├── Apptainer.def      # Apptainer/Singularity 配方
│   ├── test/             # 最小测试集
│   └── README.md
├── official_nfcore/       # [官方说明] 指向 nf-core/modules（source_type: official）
│   ├── meta.yaml
│   ├── module.json
│   └── README.md
└── official_snakemake/    # [官方说明] 指向 snakemake-wrappers（source_type: official）
    ├── meta.yaml
    ├── wrapper.py
    └── README.md
```

复合流程（多软件串联）放 `skills/custom/<flow_name>/`。

---

## 1. 命名约定（必须遵守）

| 项 | 规则 | 示例 |
|----|------|------|
| 软件目录 | Canonical Name，全小写，`-` 分词 | `samtools`、`bwa-mem2` |
| 实现目录 | 固定名：`native` / `official_nfcore` / `official_snakemake` | — |
| meta 文件 | 固定 `meta.yaml`（每个实现目录一份 + 软件级一份） | — |
| 技能 ID | `<software>_<impl>`，全小写下划线 | `samtools_native` |
| 复合流程 | `custom/<flow_name>/`，flow_name 全小写下划线 | `custom/dna_seq_align_qc` |

---

## 2. 三种 source_type 与实现路径

| source_type | type | 含义 | 本地内容 |
|-------------|------|------|----------|
| `custom` | `native` | 本地自维护，全量代码 | `main.py` + 配方 + test |
| `official` | `nfcore_module` | 引用 nf-core/modules | 仅说明 + Schema + 映射 |
| `official` | `snakemake_wrapper` | 引用 snakemake-wrappers | 仅说明 + 桥接脚本 |

**核心判据**：官方已有成熟模块 → 仅保留 `meta.yaml` 说明，**不重写源码**；
官方缺失或有定制需求 → 在 `native/` 全量自包含构建。

---

## 3. meta.yaml 字段规范

### 3.1 软件级 `skills/<software>/meta.yaml`

```yaml
software: <canonical>          # 必填
canonical: <canonical>
category: <分类>               # 如 alignment_utils / qc / variant_calling
description: <一句话>
homepage: <URL>
license: <SPDX>

implementations:               # 必填，列出所有实现与优先级
  - id: <software>_native
    path: native
    source_type: custom
    type: native
    version: "<软件版本>-v<技能版本>"
    priority: high
    when_to_use: <场景>
  - id: <software>_official_nfcore
    ...
  - id: <software>_official_snakemake
    ...

default_implementation: <software>_native   # Agent 默认路由目标
```

### 3.2 实现级 `meta.yaml` 必填字段

```yaml
id: <software>_<impl>          # 必填，全局唯一
version: "<x>"                 # 必填
software: <canonical>          # 必填
type: native|nfcore_module|snakemake_wrapper   # 必填
source_type: official|custom    # 必填
summary: <描述>
agent_guidance:
  when_to_use: <场景>
  recommendation_priority: High|Medium|Low
inputs: { ... }               # 统一输入 Schema（JSON Schema 导出依据）
outputs: { ... }
```

### 3.3 `native` 实现额外必填

```yaml
environment:
  conda: "environment.yml"
  dockerfile: "Dockerfile"
  apptainer_def: "Apptainer.def"

optimization:
  default_cpus: 4
  default_mem_mb: 8192
  env_vars: { ... }           # 支持 {tmpdir}/{cpus}/{mem_mb} 占位符
  per_subcommand_threads:     # 子命令级线程建议（可选）
    sort: 8
    default: 4

execution:
  entrypoint: "python main.py"
  test_command: "bash test/run_test.sh"
  binary: <可执行文件名>
```

---

## 4. native / main.py 构建契约

继承 `base.SkillBase`，必须实现：

```python
class <Tool>Skill(base.SkillBase):
    software = "<canonical>"
    binary = "<可执行文件名>"

    def build_command(self, subcommand, **kw) -> list[str]:
        # 1. self._resolve_binary() 解析二进制路径
        # 2. 按子命令拼装参数
        # 3. 线程优先级：用户显式 --threads > per_subcommand_threads > default_cpus
        #    用 self._effective_threads(subcommand, kw.get("threads"))
        # 4. 临时文件统一走 self.tmpdir / self.make_tmpdir()
        ...
```

### CLI 入口必须支持

| 调用 | 作用 |
|------|------|
| `python main.py <subcommand> ...` | 人类 / Shell 直跑 |
| `python main.py --schema` | 输出 JSON Schema（Agent 挂载用） |
| `python main.py --list-commands` | 列出子命令清单 |
| 每个子命令接受 `--threads` / `--tmpdir` | 运行期覆盖（放在子命令后） |

> 注意：argparse 的全局选项必须在子命令**之前**；若希望 `--threads` 在子命令**之后**使用，
> 必须把它加到每个 subparser（参考 samtools 的 `_add_runtime_opts`），不要只加到顶层 parser。

### 性能优化必须处理

- **CPU 线程**：`default_cpus` 默认值 + 用户 `--threads` 覆盖；CPU 密集子命令（sort 等）建议默认 8。
- **内存**：`default_mem_mb` 声明供上层调度读取；JVM 类工具需透传 `-Xmx`。
- **临时目录**：sort/merge 等中间文件用 `self.tmpdir` 下临时前缀，`TMPDIR` 环境变量已自动注入。
- **I/O**：大文件优先流管道，避免中间落盘。

---

## 5. 官方说明模块契约（official_nfcore / official_snakemake）

**绝不重写源码**。只产出三件套：

### official_nfcore/
- `meta.yaml`：`source_type: official`、`type: nfcore_module`，含 `source_reference` + `execution.include_statement` + `container`
- `module.json`：上游仓库、版本 tag、pinned commit（占位亦可）、子模块列表、`nf-core modules install` 命令
- `README.md`：子模块清单 + Nextflow DSL2 include 示例

### official_snakemake/
- `meta.yaml`：`type: snakemake_wrapper`，含 `wrapper_template`
- `wrapper.py`：桥接脚本，封装 `wrapper_path()` / `defaults()` / `rule()`，生成 rule 模板
- `README.md`：wrapper 清单 + Snakemake 引用示例

---

## 6. 测试要求

`native/test/` 至少包含：

- `generate_data.py`：**动态生成**合成测试数据（保持仓库轻量，不要提交大文件）
- `run_test.sh`：端到端最小回归，覆盖核心子命令链路

测试脚本约定：

```bash
# 1. mktemp -d 临时工作区，trap 清理
# 2. python generate_data.py $WORK
# 3. 串行调用 main.py 各子命令
# 4. test -f / grep 关键产物做断言
# 5. echo "ALL TESTS PASSED"
```

---

## 7. 环境配方要求

### environment.yml（Conda）
```yaml
name: <software>-native
channels: [conda-forge, bioconda]
dependencies:
  - python=3.11
  - <软件>=<版本>      # 与 meta.version 的软件版本对齐
  - htslib=<版本>      # 如适用
  - pyyaml>=6.0
```

### Dockerfile
- 基础镜像 `continuumio/miniconda3`
- 复制 `environment.yml` 建 env → 复制 `main.py`/`meta.yaml`/`test/` → 设 `ENTRYPOINT ["python","/opt/skill/main.py"]`
- 必须设 `ENV TMPDIR=/tmp`

### Apptainer.def
- `Bootstrap: docker` + 同基础镜像
- `%files` / `%environment` / `%runscript` / `%test` 四段齐全

---

## 8. 校验与注册流程（每次新增/改动后必做）

```bash
# 1. 校验单个实现目录的 meta.yaml 结构
python skills/bin/skill-cli validate skills/<software>/native
python skills/bin/skill-cli validate skills/<software>/official_nfcore
python skills/bin/skill-cli validate skills/<software>/official_snakemake

# 2. 导出 JSON Schema（Agent 用）
python skills/bin/skill-cli schema skills/<software>/native/meta.yaml

# 3. 重建全局 registry.yaml（扫描所有 meta.yaml）
python skills/bin/skill-cli scan

# 4. 跑 native 回归测试（需对应软件已安装）
bash skills/<software>/native/test/run_test.sh
```

`skill-cli validate` 的硬性检查：
- 必填字段：`id` `version` `software` `type` `source_type`
- `source_type ∈ {official, custom}`、`type ∈ {native, nfcore_module, snakemake_wrapper}`
- `custom` 模块额外要求 `environment` / `execution` 字段且 `main.py` 存在

---

## 9. Agent 路由逻辑（构建时需保证可被路由）

新增软件时，软件级 `meta.yaml` 的 `default_implementation` 与各实现的 `agent_guidance.when_to_use` 必须能让 Agent 按下表决策：

```
是否流程引擎上下文？
├─ 是 → 目标语言？
│       ├─ Nextflow  → 查 official_nfcore，有则 include，无则降级 native 封装
│       └─ Snakemake → 查 official_snakemake，有则 wrapper，无则降级 native 封装
└─ 否（CLI/Agent Function Calling）→ 直接调用 native/main.py（高优先级）
```

---

## 10. 新增软件检查清单（Checklist）

构建一个新软件 `<tool>` 时，逐项确认：

- [ ] 目录 `skills/<tool>/`，canonical 名全小写
- [ ] `skills/<tool>/meta.yaml` 软件级总览（implementations + default_implementation）
- [ ] `skills/<tool>/native/meta.yaml`（source_type: custom，含 inputs/outputs/environment/optimization/execution）
- [ ] `skills/<tool>/native/main.py` 继承 `base.SkillBase`，实现 `build_command`，支持 `--schema`/`--list-commands`/`--threads`/`--tmpdir`
- [ ] `environment.yml` / `Dockerfile` / `Apptainer.def` 三配方齐全，软件版本与 meta 对齐
- [ ] `test/generate_data.py` + `test/run_test.sh`，本机跑通
- [ ] `README.md`（native / official_* 各一份）
- [ ] 若官方有模块：`official_nfcore/` 与 `official_snakemake/` 三件套（仅说明，不重写源码）
- [ ] `skill-cli validate` 三目录全 [OK]
- [ ] `skill-cli schema` 成功导出 `.schema.json`
- [ ] `skill-cli scan` 重建 registry.yaml 并包含新软件

---

## 11. 黄金样例

**以 `skills/samtools/` 为参考**，它完整演示了：
- 软件级 + 三类实现级 meta.yaml
- native main.py 的子命令分发、线程优先级、临时目录优化
- 三种环境配方
- 动态生成测试数据的最小回归
- 两个官方说明模块（含 nf-core 子模块清单与 Snakemake 桥接脚本）

新增任何软件时，先对照 samtools 的对应文件结构复制改造。
