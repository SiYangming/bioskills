# AGENT.md — bioskills 技能库构建规范

> 本文档是「每次新增/维护一个软件技能时必须遵守的标准」。
> 按本规范构建可保证：目录一致、接口统一、Agent 可路由、可自动校验。
> 参考实现：`skills/samtools/`（黄金样例：5 条实现路径全覆盖）。

---

## 0. 一句话总览

```
skills/<software>/
├── meta.yaml                              # 软件级总览（列出所有实现 + 推荐优先级）
├── native/                                # [最高优先级] 本地自包含实现（source_type: custom, type: native）
│   ├── meta.yaml                          #   含 inputs/outputs/environment/optimization/execution
│   ├── main.py                            #   继承 base.SkillBase 的标准入口驱动
│   ├── environment.yml                    #   Conda/Mamba 配方
│   ├── Dockerfile                         #   Docker 镜像配方
│   ├── Apptainer.def                      #   Apptainer/Singularity 配方
│   ├── test/{generate_data.py,run_test.sh}
│   └── README.md
│
├── nextflow/
│   ├── nf-core/                           # 官方 nf-core/modules（source_type: official, type: nextflow_nfcore）
│   │   ├── meta.yaml                      #   统一 Schema + source_reference + execution
│   │   ├── module.json                    #   上游映射 / 安装命令
│   │   └── README.md                      #   必须明确：本目录仅说明，不可直接 include
│   └── local/                             # 自定义 Nextflow 模块（source_type: custom, type: nextflow_local）
│       ├── meta.yaml
│       └── README.md
│
└── snakemake/
    ├── snakemake-wrappers/                # 官方 snakemake-wrappers（source_type: official, type: snakemake_wrappers）
    │   ├── meta.yaml
    │   ├── wrapper.py                     #   rule 模板生成脚本
    │   └── README.md
    └── local/                             # 自定义 Snakemake rule（source_type: custom, type: snakemake_local）
        ├── meta.yaml
        └── README.md
```

复合流程与 `skills/` 平级，分**两层**：

- `workflow/<flow_name>/` —— **专门设计流程**：面向特定领域的完整流程（如 `nanoseq`、`isoseq`、`flrnaseq`），可引用 subworkflow 与各原子模块；
- `subworkflow/<组合名>/` —— **常用软件组合**：可复用的多软件串联小流程（如 `fastp_bwa_samtools`：fastp -> bwa-mem2 -> samtools sort/index -> QC），供 workflow 引用或独立调用。

每个流程目录含 `meta.yaml`（stages/inputs/outputs）、入口编排脚本、`workflow_skeleton/`（模板）与 `README.md`。

**目录扁平化**：`workflow_skeleton/` 下的辅助文件尽量放根级（`config.yaml`、`common.smk`、脚本等），避免 `config/`/`rules/` 等多级子目录；仅当同层文件确实过多时才建子目录。

**脚本归位**：流程中出现的辅助脚本先判断归属——专属于某软件（如 samtools flagstat 汇总脚本）→ 归位到该软件 `native/legacy/` 或 `snakemake/local/`；流程级通用脚本（docker_wrapper、samplesheet 处理）→ 保留在流程 `workflow_skeleton/` 下。

---

## 1. 命名约定（必须遵守）

| 项 | 规则 | 示例 |
|----|------|------|
| 软件目录 | Canonical Name，全小写，`-` 分词 | `samtools`、`bwa-mem2`、`fastqc` |
| 引擎目录名 | `nextflow/` / `snakemake/` | — |
| 引擎内来源名 | 官方：`nf-core` / `snakemake-wrappers`；自定义：`local` | — |
| 实现 ID | `<software>_<impl>`，全小写下划线 | `samtools_native`、`samtools_nextflow_nfcore`、`samtools_snakemake_local` |
| `type` 枚举（5 个） | `native` · `nextflow_nfcore` · `nextflow_local` · `snakemake_wrappers` · `snakemake_local` | — |
| `source_type` 枚举 | `official`（说明层）· `custom`（自实现） | — |
| 复合流程 | `workflow/<flow_name>/` 或 `subworkflow/<组合名>/`，全小写下划线 | `workflow/nanoseq`、`subworkflow/fastp_bwa_samtools` |

**实现 ID ↔ type ↔ 路径 对照（必须一一对应）：**

| 实现 ID | type | 相对路径 | source_type |
|---------|------|----------|-------------|
| `<sw>_native` | `native` | `native/` | `custom` |
| `<sw>_nextflow_nfcore` | `nextflow_nfcore` | `nextflow/nf-core/` | `official` |
| `<sw>_nextflow_local` | `nextflow_local` | `nextflow/local/` | `custom` |
| `<sw>_snakemake_wrappers` | `snakemake_wrappers` | `snakemake/snakemake-wrappers/` | `official` |
| `<sw>_snakemake_local` | `snakemake_local` | `snakemake/local/` | `custom` |

---

## 2. source_type 判据（每次先问自己）

| 场景 | 选择 |
|------|------|
| nf-core/modules **已存在** 稳定子模块 → | `nextflow/nf-core/`（**只写说明**，不重写源码） |
| nf-core 缺失 / 需本地定制 Nextflow process → | `nextflow/local/`（写真正的 `.nf` 文件） |
| snakemake-wrappers **已存在** 稳定 wrapper → | `snakemake/snakemake-wrappers/`（**只写说明**） |
| snakemake-wrappers 缺失 / 需本地定制 rule → | `snakemake/local/`（写自维护 rule） |
| 非流程引擎场景（CLI/Agent 直调）**总是需要** → | `native/`（source_type: custom，自包含） |

> 核心原则：**官方模块只做说明 + Schema + 引用，不重写源码。**

---

## 3. meta.yaml 字段规范

### 3.1 软件级 `skills/<software>/meta.yaml`

```yaml
software: <canonical>          # 必填
canonical: <canonical>
category: <分类>               # alignment_utils / qc / variant_calling / ...
description: <一句话>
homepage: <URL>
license: <SPDX>

implementations:               # 必填；按优先级降序（native 永远最高）
  - id: <software>_native
    path: native
    source_type: custom
    type: native
    version: "<软件版本>-v<技能版本>"
    priority: high
    when_to_use: 非流程引擎场景（AI Agent Function Calling / 独立 CLI）首选
  - id: <software>_nextflow_nfcore
    path: nextflow/nf-core
    source_type: official
    type: nextflow_nfcore
    version: "<nf-core 子模块版本>"
    priority: medium
    when_to_use: Nextflow DSL2 流程、HPC/Cloud 目标时使用
  - id: <software>_nextflow_local
    path: nextflow/local
    source_type: custom
    type: nextflow_local
    version: ""                 # 未启用时可留空
    priority: low
    when_to_use: nf-core 缺失 / 本地定制
  - id: <software>_snakemake_wrappers
    path: snakemake/snakemake-wrappers
    source_type: official
    type: snakemake_wrappers
    version: "v<tag>"
    priority: medium
    when_to_use: Snakemake 流程、复用中央 wrapper 缓存
  - id: <software>_snakemake_local
    path: snakemake/local
    source_type: custom
    type: snakemake_local
    version: ""
    priority: low
    when_to_use: snakemake-wrappers 缺失 / 本地定制

default_implementation: <software>_native   # Agent 默认路由目标

# ---------------------------------------------------------------------------
# 【必填】版本差异声明：native / nf-core / snakemake-wrappers 的上游二进制版本可能不同
# （尤其 Debian apt ≠ bioconda 时）。此字段让 Agent 跨引擎迁移时一眼看到风险。
# 参考字段见下；实际 key 按该软件的 implementations 子集调整。
# ---------------------------------------------------------------------------
software_versions:
  native:
    <software>: "<版本>"
    build_route: "apt + 官方二进制 / 官方源码编译 / bioconda（尽量 apt）"
    source: "<URL / package spec>"
    note: "<差异说明 / 升级注意事项>"
  nextflow_nfcore:
    <software>:        "<版本>"
    module_version:    "<nf-core 子模块版本号>"
    source:            "bioconda::<software>=<ver>（environment.yml / Wave container）"
    note:              "nf-core 升级后请同步刷新"
  nextflow_local:
    <software>: "（继承 native 容器或显式 pin；未启用则写占位）"
  snakemake_wrappers:
    <software>:        "<版本>"
    wrapper_tag:       "v<tag>"
    wrapper_utils:     "<ver>"
    source:            "bioconda <software>=<ver> + snakemake-wrapper-utils=<ver>（bio/<software>/environment.yaml）"
    note:              "切 wrapper tag 后务必核对"
  snakemake_local:
    <software>: "（继承 native 容器或显式 pin；未启用则写占位）"
```

### 3.2 实现级 `meta.yaml` 通用必填字段

```yaml
id: <见 §1 对照表>        # 必填，全局唯一
version: "<x>"            # 必填（空版本仅用于占位的 local 目录）
software: <canonical>     # 必填
type: <见 §1 对照表>      # 必填
source_type: official|custom  # 必填

summary: <一句话描述>
agent_guidance:
  when_to_use: <Agent 使用场景>
  recommendation_priority: High|Medium|Low

inputs:
  <name>:
    type: file|string|integer|float|boolean|map
    required: true|false
    cli_arg: <如 "--input" 或 "positional">
    description: ...
    format: [fastq.gz, bam, ...]    # 如适用

outputs:
  <name>:
    type: file
    format: <format>
    description: ...

# 【每个实现级必填】至少 1 行描述：该实现实际会运行的上游二进制版本 + 来源。
# 推荐写成：<软件名>/<构建来源>/<版本>。不要与软件级 software_versions 重复；
# 软件级写“全库差异对比”，实现级写“我这一路用的是什么”。
software_versions:
  <软件名>: "<版本>"
  source: "<apt / bioconda / babraham-zip / samtools-src ... 的具体说明>"
  note: "<若与其它实现不同，此处补充说明>"
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
  env_vars:                   # 支持 {tmpdir}/{cpus}/{mem_mb} 占位符
    TMPDIR: "{tmpdir}"
    JAVA_OPTS: "-Xmx6g"       # 如适用
  per_subcommand_threads:     # 可选，CPU 密集子命令单独调高
    sort: 8
    default: 4

execution:
  entrypoint: "python main.py"
  test_command: "bash test/run_test.sh"
  binary: <可执行文件名>
```

---

## 4. native / main.py 构建契约

继承 `base.SkillBase`：

```python
class <Tool>Skill(base.SkillBase):
    software = "<canonical>"
    binary = "<可执行文件名>"      # 可省略，默认等于 software

    def build_command(self, subcommand, **kw) -> list[str]:
        bin_path = self._resolve_binary()          # 找不到会抛错
        threads  = self._effective_threads(subcommand, kw.get("threads"))
        tmpdir   = self.tmpdir                     # 可用 self.make_tmpdir(prefix) 新建
        # ...
```

### CLI 入口必须支持

| 调用 | 作用 |
|------|------|
| `python main.py <subcommand> ...` | 人类 / Shell 直跑 |
| `python main.py --schema` | 打印 JSON Schema（Agent 挂载） |
| `python main.py --list-commands` | 列出子命令清单 |
| 每个子命令接受 `--threads` / `--tmpdir` | 运行期覆盖（放在子命令后） |

> ⚠️ **argparse 坑**：`--threads` 希望放在子命令**之后**使用时，必须用辅助函数把它加到每个 subparser（参考 samtools 的 `_add_runtime_opts`），不要只加到顶层 parser。

### 性能优化必须处理

- **线程优先级**：用户显式 `--threads` > `per_subcommand_threads` > `default_cpus`。CPU 密集子命令（sort、merge、mpileup）建议默认 8 线程。
- **内存声明**：`default_mem_mb` 字段供上层调度器读取；JVM 类工具（Java/Scala）务必透传 `JAVA_OPTS -Xmx`。
- **临时目录**：中间文件统一使用 `self.tmpdir`，并在 `optimization.env_vars` 中声明 `TMPDIR: "{tmpdir}"`；sort 等子命令使用 `-T` 前缀参数显式指定。
- **I/O**：大文件转换优先管道化，避免多余中间落盘。

---

## 5. 官方说明模块契约（nextflow/nf-core / snakemake/snakemake-wrappers）

**绝不重写源码**。每个官方实现目录产出三件套：

### nextflow/nf-core/
| 文件 | 要求 |
|------|------|
| `meta.yaml` | `type: nextflow_nfcore`、`source_type: official`；含 `source_reference.repository` 与 **`submodules[]` 列表（必须与官方目录 `modules/nf-core/<software>/` 子目录严格一致）**；含 `execution.include_statement` 与 `container`；必加 `software_versions{}` 段（对齐 nf-core 该软件的 `environment.yml` / Wave container pin） |
| `module.json` | 上游仓库、tracked branch、pinned commit（占位亦可）、container registry、`install_command: "nf-core modules install <sw>/<sub>"` |
| `README.md` | **（强提示三件套要求）** 子模块清单 + Nextflow DSL2 include 示例；**顶部必须显式声明**：「本目录仅为说明/Schema 挂载层，真正执行需使用 `nf-core modules install` 安装到项目自身的 `modules/nf-core/` 目录，不要直接 include skills/…/nextflow/nf-core 下的 main.nf」；并提示缺失时用 `../local/`；另附 `submodules[]` 更新时抓官方目录的 1 条 curl 命令样例 |

### snakemake/snakemake-wrappers/
| 文件 | 要求 |
|------|------|
| `meta.yaml` | `type: snakemake_wrappers`；含 `source_reference.tag` 与 **`submodules[]` 列表（必须与官方目录 `bio/<software>/` 子目录严格一致）**；含 `execution.wrapper_template: "vX.Y.Z/bio/<sw>/{subcommand}"`；必加 `software_versions{}` 段（对齐 `bio/<software>/environment.yaml` 的 conda pin） |
| `wrapper.py` | 桥接脚本：封装 `wrapper_path()` / `defaults()` / `rule()` 三个 API，能生成可粘贴到 Snakefile 的 rule 模板 |
| `README.md` | **（强提示三件套要求）** wrapper 清单 + Snakemake 引用示例；**顶部必须显式声明**：「本目录仅为说明层，真正执行靠 Snakemake 运行时解析 `wrapper:` 句柄；不要将本 wrapper.py 作为 Snakemake 的 wrapper_path」；缺失时用 `../local/`；附 `submodules[]` 更新时抓官方目录的 1 条 curl 命令样例 |

### local/ 目录（nextflow/local / snakemake/local）

- 未启用时：至少保留**占位** `meta.yaml`（`id/version=""`） + README，说明用途与启用方式。启用时写真正的 `.nf` / `.smk` 文件，补齐 `inputs/outputs/execution`。

---

## 6. 测试要求

`native/test/` 至少包含：

- `generate_data.py`：**动态生成**合成数据（保持仓库轻量；不要提交 BAM/FASTQ 大文件）
- `run_test.sh`：端到端最小回归
  - `mktemp -d` + `trap` 清理
  - 串行调用 main.py 核心子命令链路（至少 4–5 条）
  - `test -f` / `grep` 对关键产物断言
  - 最终 `echo "ALL TESTS PASSED"`

---

## 7. 环境配方要求（**apt + Debian bookworm-slim 默认路线**）

> ⚠️ **默认路线**：native 容器镜像一律走 **Debian `bookworm-slim` + apt `--no-install-recommends`**。
> 只有在 **apt/Debian backports 无法提供所需版本**（例如 fastqc 本身不在官方 apt）的情况下，
> 才退化为：**apt 装 JVM/运行时依赖 + 官方二进制/官方源码包**，**禁止默认引入 miniconda**。
> 理由：apt 镜像更小、启动更快、HPC 无 Conda 环境解析延迟、CVE 补丁随 Debian 安全源推送。
>
> 运行 Docker 时必须加 `-u $(id -u):$(id -g)`，避免输出文件被 root 持有。

### environment.yml（Conda — 仅 native 保留作离线 / 非容器场景备选）
```yaml
name: <software>-native
channels: [conda-forge, bioconda]
dependencies:
  - python=3.11
  - <软件>=<版本>      # 与 meta.version 的软件版本对齐
  - htslib=<版本>      # 如适用
  - pyyaml>=6.0
```

### Dockerfile（强制 apt 默认路线 + 最小化清理四连）
- **基础镜像**：`debian:bookworm-slim`（不要再用 `continuumio/miniconda3:24.7.1-0`）
- **安装顺序**：
  1. `apt-get update -y`
  2. `apt-get install -y --no-install-recommends <最小依赖集：软件包本体 + ca-certificates + procps>`
  3. 若 apt 无该软件（例：fastqc），则 **apt 只装运行时**（openjdk/perl/libz1/…）+ 官方二进制 zip/tar.bz2 直接布署到 `/opt/`，并用 `ln -s` 到 `/usr/local/bin`
  4. **清理四连（缺一不可）**：`apt-get autoremove -y` + `apt-get clean` + `rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*`；**仅用于构建的 curl/wget/dkpg-dev 要在 purge 阶段移除**
- **用户态**：不创建固定账号（避免 HPC UID 冲突）；运行时靠 `-u $(id -u):$(id -g)` 接管
- **ENTRYPOINT / CMD**：
  - 对 CLI 工具（samtools/fastqc/…）：`ENTRYPOINT ["/usr/local/bin/<binary>"]` + `CMD ["--help"]`
  - 对 Python 驱动（自定义 main.py）：`ENTRYPOINT ["python","/opt/skill/main.py"]`
- **必须**：`ENV TMPDIR=/tmp`；Java/Scala 类再补 `JAVA_TOOL_OPTIONS="-Xmx8g -Djava.io.tmpdir=/tmp"`
- **禁止**：默认安装 sudo、vim、bash-completion、manpages 等非运行必需

### Apptainer.def
- `Bootstrap: docker` + 同一基础镜像（`debian:bookworm-slim`）
- `%post` 内：**同样遵守 apt 默认路线 + 清理四连**（不要引入 micromamba）
- 必需段：`%files`（如需要）/ `%environment` / `%runscript` / `%test`
- `%test`：至少执行 `<binary> --version` 并 grep 目标版本号；必要时再跑最小链路测试
- `%labels`：`org.bioskills.software`、`impl`、`base_image`、`<软件>_version`、`pkg_route`（写清楚是 apt 还是 apt+zip/编译）

### 版本差异声明的落地对应
- apt 装什么版本（`apt-cache policy <pkg>` 抓得到）→ 填入软件级 / 实现级 `software_versions.native`
- nf-core / snakemake-wrappers 读官方 `environment.yml` 里的 conda pin → 填入对应 `software_versions.nextflow_nfcore` / `snakemake_wrappers`
- 如果三条路版本号不一致 → **必须在 Checklist 中核对并在 `note:` 写明是否允许共存、如何回滚**

---

## 8. 校验与注册流程（每次新增/改动后必做）

```bash
# 1. 校验 5 个实现目录（含占位 local）
python skills/bin/skill-cli validate skills/<software>/native
python skills/bin/skill-cli validate skills/<software>/nextflow/nf-core
python skills/bin/skill-cli validate skills/<software>/nextflow/local
python skills/bin/skill-cli validate skills/<software>/snakemake/snakemake-wrappers
python skills/bin/skill-cli validate skills/<software>/snakemake/local

# 2. 导出 JSON Schema（Agent 用）
python skills/bin/skill-cli schema skills/<software>/native/meta.yaml

# 3. 重建全局 registry.yaml（自动扫描全库 meta.yaml）
python skills/bin/skill-cli scan

# 4. 跑 native 回归测试（需对应软件已安装）
bash skills/<software>/native/test/run_test.sh
```

`skill-cli validate` 的硬性检查：
- 必填字段：`id` `version` `software` `type` `source_type`（注意 local 占位 `version=""` 被接受）
- `source_type ∈ {official, custom}`
- `type ∈ {native, nextflow_nfcore, nextflow_local, snakemake_wrappers, snakemake_local, nfcore_module, snakemake_wrapper}`（后两项为旧值兼容）
- `source_type=custom type=native` 额外要求 `environment` / `execution` 字段、`main.py` 存在、`test/run_test.sh` 存在
- 其他 `source_type=custom`（nextflow_local / snakemake_local）至少要求 `execution`

---

## 9. Agent 路由逻辑（构建时需保证可被路由）

```
是否流程引擎上下文？
├─ 是 → 目标语言？
│  ├─ Nextflow
│  │   ├─ nextflow/nf-core 已登记且版本可用 → nextflow_nfcore
│  │   ├─ 若未登记但 nextflow/local 已实现 → nextflow_local
│  │   └─ 否则 → 降级 native
│  └─ Snakemake
│      ├─ snakemake/snakemake-wrappers 已登记且版本可用 → snakemake_wrappers
│      ├─ 若未登记但 snakemake/local 已实现 → snakemake_local
│      └─ 否则 → 降级 native
└─ 否（Agent Function Calling / 独立 CLI / Shell）→ 直接调用 native（最高优先级）
```

软件级 `meta.yaml.default_implementation` **永远指向 native**（除非有强理由例外）。

---

## 10. 新增软件检查清单（Checklist）

构建一个新软件 `<tool>` 时，逐项确认：

- [ ] 目录 `skills/<tool>/`，canonical 名全小写，`-` 分词（必须与 bioconda / nf-core / Debian 统一规范名一致）
- [ ] `skills/<tool>/meta.yaml` 软件级总览：implementations（5 条路径，按优先级）+ default_implementation + **software_versions 差异声明**
- [ ] `skills/<tool>/native/`：
  - [ ] `meta.yaml`（source_type=custom/type=native，inputs/outputs/environment/optimization/execution + **software_versions 段**）
  - [ ] `main.py`：继承 `SkillBase`，实现 `build_command`，支持 `--schema` / `--list-commands` / `--threads` / `--tmpdir`
  - [ ] `environment.yml`（保留，仅离线/非容器备选）、**`Dockerfile`（debian:bookworm-slim + apt 默认路线 + 清理四连）**、**`Apptainer.def`（同样 apt 路线）**，版本均与 software_versions 对齐
  - [ ] `test/generate_data.py` + `test/run_test.sh`，本机跑通
  - [ ] `README.md`
- [ ] `skills/<tool>/nextflow/nf-core/`（三件套，type=nextflow_nfcore，source_type=official）：
  - [ ] `submodules[]` 与 **`https://github.com/nf-core/modules/tree/master/modules/nf-core/<tool>/` 目录子项严格一致**
  - [ ] `software_versions{}` 对齐官方 `environment.yml` / Wave container
  - [ ] `README.md` **顶部写强提示**（说明层、不要直接 include、缺失时走 ../local/、附抓 submodules 的命令）
- [ ] `skills/<tool>/nextflow/local/`（占位 meta.yaml + README，type=nextflow_local）
- [ ] `skills/<tool>/snakemake/snakemake-wrappers/`（三件套，type=snakemake_wrappers）：
  - [ ] `submodules[]` 与 **`https://github.com/snakemake/snakemake-wrappers/tree/master/bio/<tool>/` 目录子项严格一致**
  - [ ] `software_versions{}` 对齐官方 `bio/<tool>/environment.yaml`
  - [ ] `README.md` **顶部写强提示**（说明层、wrapper 句柄解析、缺失时走 ../local/、附抓 submodules 的命令）
- [ ] `skills/<tool>/snakemake/local/`（占位 meta.yaml + README，type=snakemake_local）
- [ ] 实现 ID 严格遵守 §1：`<tool>_native` 等
- [ ] **Dockerfile/Apptainer.def 已避免 miniconda 默认引入；Docker 示例命令写了 `-u $(id -u):$(id -g)`**
- [ ] **native / nf-core / snakemake-wrappers 的 software_versions 三方差异已逐条核对**
- [ ] `skill-cli validate` 五个目录全 [OK]
- [ ] `skill-cli schema` 成功导出 `.schema.json`（已列入 .gitignore）
- [ ] `skill-cli scan` 成功重建 registry.yaml 并包含新软件

---

## 11. 黄金样例

**以 `skills/samtools/` 为参考**，它完整演示了：
- 软件级 meta.yaml 含 5 条实现登记（含 local 占位）
- native main.py 的子命令分发、线程优先级、临时目录优化
- 三种环境配方
- 动态生成测试数据的最小回归
- 两个官方说明层（含 "本目录仅说明不可直接 include / wrapper 靠运行时解析" 的强提示）
- 两个 local 占位 meta.yaml + README
- 与 registry.yaml 条目完全对应

新增任何软件时，先对照 samtools 的对应文件结构复制改造。
