# AGENT.md — bioskills 技能库构建规范

> 本文档是「每次新增/维护一个软件技能时必须遵守的标准」。
> 按本规范构建可保证：目录一致、接口统一、Agent 可路由、可自动校验。
> 参考实现：`modules/samtools/`（黄金样例：5 条实现路径全覆盖）。

***

## 0. 一句话总览

```
modules/<software>/
├── meta.yaml                              # 【唯一 meta】软件级 + 实现级合并：implementations / software_versions
│                                          #   / inputs / outputs / environment / optimization / execution
├── README.md                              # 合并各实现用法（native/snakemake/nextflow 章节）+ 容器/conda 链接 + 安装方式
├── native/                                # [本地实现] source_type: custom, type: native
│   ├── install.sh                         #   native 本地安装脚本（现代规范：conda/官方 release 双路线；README「安装方式」见下）
│   ├── main.py                            #   继承 base.SkillBase 的标准入口驱动
│   ├── *.py / *.sh                        #   本地运行脚本（与流程无关的经典脚本直接放 native/ 根）
│   ├── Dockerfile / Apptainer.def         #   容器构建 recipe（可选：仅查无官方镜像时提供）
│   ├── test/{generate_data.py,run_test.sh}
│   └── （不再有 meta.yaml / README.md / environment.yml —— 已并入软件级）
├── snakemake/                             # [Snakemake 实现] source_type: custom, type: snakemake_local
│   ├── *.smk                              #   本地规则
│   ├── scripts/                           #   规则配套 wrapper 脚本（如 td2_longorfs.py）
│   ├── *.yaml                             #   snakemake conda env（如有）
│   └── （官方 snakemake-wrappers 信息记录在软件级 README/software_versions）
└── nextflow/                              # [Nextflow 实现] 有实际实现才建（fastqc 有 main.nf.template）
    ├── 实现文件（main.nf.template 等）
    └── （官方 nf-core 信息记录在软件级 README/software_versions）
```

> **要点**：
>
> * 每个软件**只有一个 meta.yaml**（modules/<sw>/meta.yaml）与**一个 README.md**，不再按实现拆分；
>
> * 官方实现（nf-core / snakemake-wrappers）不建目录，其链接、submodules、版本差异记录在软件级 README 与 `software_versions`；
>
> * `native/` = main.py + 本地脚本 + test（**官方镜像优先**：bioconda → quay.io/biocontainers → depot.galaxyproject.org 有官方维护 → 不维护 Dockerfile/Apptainer.def，meta.yaml 登记 `container_official`；查无官方才保留自建配方）；conda 环境与容器信息记录到软件级 README（安装方式记本地安装：conda/brew/官方二进制 + 引用 native/install.sh；anaconda/官方镜像已有环境仅记录链接）；
>
> * 环境文件（conda env yaml）按引擎放置：snakemake/ 下的 `*.yaml`、nextflow 用 container（`environment.yaml` 与 snakemake 可共享）。
>
> * **snakemake/ 集成层（td2 式规范，新增模块/存量模块对齐均适用）**：
>
>   * 布局：wrapper（`*.py`）与 conda 环境（`*.yaml`）**平铺**在 `snakemake/` 根；`.smk` 内 `conda:` / `script:` 一律用**同目录相对名**（如 `"td2.yaml"` / `"td2_longorfs.py"`），**禁止** `envs/…`、`scripts/`、`../envs`、`../scripts` 等幽灵引用（除非对应子目录真实存在，如 fastqc）；
>
>   * 多子命令软件**每个 rule 一个** **`.smk`**（如 `td2_longorfs.smk` + `td2_predict.smk` 共用 `td2.yaml`）；规则 **config 驱动**：顶部 `config.setdefault(...)` 给默认、`td2_input_fasta`/`td2_outdir` 类键由 `--config` 提供、头注写独立运行示例，摆脱对 workflow 的 `SAMPLES` / `{sample}` 层级的依赖；
>
>   * wrapper 统一：在 `import docker_wrapper` 前 `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))`（注入到 `modules/`，两级）；用 `docker_wrapper.docker_wrapper_binary(config, <sw>, <bin_key>, <默认二进制>)` 解析 docker/native/conda 三种模式；
>
>   * **执行指令选择（按调用软件步骤数）**：单条命令、无额外逻辑 → 优先官方 `wrapper:` 句柄（如 `"0.0.8/bio/samtools/index"`）或 `shell:` 直写；需要多步/条件分支/产物搬运等逻辑（如 td2/transdecoder 的 longorfs→predict、predict 产物收集）→ 用 `script:` + 同目录 wrapper。`shell:` / `script:` / `run:` / `wrapper:` 在同一 rule 内互斥，只能选一种执行指令；不同 rule 可在同一 `.smk`/流程内混用；`script:` 内部仍可再调 `shell()` 执行子命令；
>
>   * `meta.yaml` 的 `execution.snakemake_include_hint` 逐个列出 include 的 `.smk` 并给出 config 契约；建议配 `snakemake/test/`（模仿 native/test：generate\_data.py + run\_test.sh 静态自检，见 td2）；
>
> * **snakemake/ 提交前自查**：`grep -nE '\.\./(envs|scripts)|(^|["'\''])(envs|scripts)/' modules/*/snakemake/*.smk` 应为空；wrapper 注入深度为两级（指向 `modules/`）；目录内无 `.DS_Store` / `*副本` / `__pycache__`。

复合流程与 `modules/` 平级，分**两种形态**：

* **根级文档形态**（默认）：流程文档命名 `<flow_name>.md`、元数据命名 `<flow_name>.yaml`，直接放 `workflow/` 根（无 native 代码资产的轻量流程；本仓库现有 `nanoseq/isoseq/riboseq` 因含 `native/` 代码均取目录形态）；

* **目录形态**：当流程含 **native 代码资产**（经典完整实现脚本与/或流程编排入口 `native/main.py`，如 `workflow/nanoseq/`、`workflow/isoseq/`、`workflow/riboseq/`、`subworkflow/fastp_bwa_samtools/`）或需要多个子资产时保留目录 `workflow/<flow_name>/`（内部文档亦命名 `<flow_name>.md`，元数据 `meta.yaml`）；

* `subworkflow/<组合名>/` —— **常用软件组合**：可复用的多软件串联小流程（如 `subworkflow/fastp_bwa_samtools/`：fastp -> bwa-mem2 -> samtools sort/index -> QC），供 workflow 引用或独立调用；含 native 代码时取目录形态（`<组合名>.md` + `meta.yaml` + `native/`），仅剩文档时折叠到 subworkflow/ 根（`<组合名>.md` + `<组合名>.yaml`）。

> **workflow 命名与折叠规则**：
>
> * 流程文档统一命名 `<flow_name>.md`（目录内不再用通用 README.md 名）；根级文档形态的元数据命名 `<flow_name>.yaml`；
>
> * 若某流程目录内只剩文档（无 native 经典实现、无其他代码资产）→ **整体折叠到 workflow/ 根**（`<flow_name>.md` + `<flow_name>.yaml`），不保留目录；
>
> * 流程级 `native/` 保留**经典完整实现脚本**（多步组合 `run_*.sh` / 历史脚本库，如 `riboseq/native`）与**流程编排入口** **`native/main.py`**（逐 stage 委托 `modules/<sw>/native/main.py`、提供 `--list-stages` / `--dry-run` / `--real` 的可执行入口，如 `nanoseq` / `isoseq` 的 `native/main.py`）；仅当无上述代码资产时，纯编排逻辑不入库、记录于流程文档「执行方式 A」；
>
> * `nextflow/`：官方已有完整流程（nf-core）→ **不建目录**，只在文档登记引用与差异；确需本地自建时才建；
>
> * `snakemake/`：流程集成层内容并入流程文档「执行方式 B」后移除目录；需要 Snakemake 执行时在项目内按文档重建（工具规则仍存于 `modules/<sw>/snakemake/`）。

> **通用规则（workflow / subworkflow / modules 全适用）**：官方已经有的流程或软件实现 → **不单独构建目录**，信息并入对应 README / meta.yaml 登记（source\_type: official + 官方仓库/子模块/版本差异 + 强提示）；**只有官方不存在的自定义实现才建目录**（source\_type: custom）。

**脚本归位**：专属于某软件（如 samtools flagstat 汇总）的辅助脚本 → 归位到该软件 `snakemake/`（wrapper/helper 平铺同目录，见「snakemake 集成层规范」）或 `native/`；流程级通用脚本 → 仓库根 `scripts/`（run\_smk.sh / run\_bg.sh 等）或共享 `modules/docker_wrapper.py`；流程专属 snakemake 脚本（如分组汇总）逻辑记录于流程文档。

***

## 容器与 Conda 包查找规则（必须遵守，按顺序查找）

为软件登记容器与 conda 包时，按以下顺序查找**官方维护镜像**，**官方渠道（1–3）全无 → 才允许自建配方**：

1. **bioconda 频道 conda 包**：<https://anaconda.org/bioconda/packages/><sw>（判定「官方维护」的第一来源；native 宿主机 conda/mamba 装工具亦由此来）
2. **quay.io / biocontainers 频道**：`quay.io/biocontainers/<sw>:<ver>--<build>`（bioconda 自动构建官方镜像，tag 含版本+build）
3. **depot.galaxyproject.org**（Galaxy 官方镜像仓库，tag 与 quay.io/biocontainers 互通）
4. 补充渠道（仅登记备用，不作「官方维护」判定）：Docker Hub、docker.1ms.run（国内加速）、quay.io/bioinfortools、YangmingSi 频道（如 gs-tama=1.0.4）

官方渠道（1–3）均无 → 判为「无官方维护」→ 走**自建兜底路线**（Dockerfile/Apptainer.def，apt 最小化）；并在 README「容器与 Conda 链接」记录替代方案（社区镜像 / 源码构建 / 上游 github 链接）。

## 1. 命名约定（必须遵守）

| 项                | 规则                                                                                                                                                                     | 示例                                                                                           |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| 软件目录             | Canonical Name，全小写，`-` 分词                                                                                                                                              | `samtools`、`bwa-mem2`、`fastqc`                                                               |
| 引擎目录名            | `nextflow/` / `snakemake/`                                                                                                                                             | —                                                                                            |
| 引擎内来源名           | 官方：`nf-core` / `snakemake-wrappers`；自定义：`local`                                                                                                                        | —                                                                                            |
| 实现 ID            | `<software>_<impl>`，全小写下划线                                                                                                                                             | `samtools_native`、`samtools_nextflow_nfcore`、`samtools_snakemake_local`                      |
| `type` 枚举（5 个）   | `native` · `nextflow_nfcore` · `nextflow_local` · `snakemake_wrappers` · `snakemake_local`                                                                             | —                                                                                            |
| `source_type` 枚举 | `official`（说明层）· `custom`（自实现）                                                                                                                                         | —                                                                                            |
| 复合流程             | 根级文档 `workflow/<flow_name>.md`（+ `.yaml`，无 native 代码时），或目录 `workflow/<flow_name>/`（含 native 代码时，内部 `<flow_name>.md` + `meta.yaml` + `native/`）；`subworkflow/<组合名>/` 同理 | `workflow/nanoseq/`、`workflow/isoseq/`、`workflow/riboseq/`、`subworkflow/fastp_bwa_samtools/` |

**实现 ID ↔ type ↔ 路径 对照（必须一一对应）：**

| 实现 ID                  | type              | 相对路径         | source\_type      |
| ---------------------- | ----------------- | ------------ | ----------------- |
| `<sw>_native`          | `native`          | `native/`    | `custom`          |
| `<sw>_nextflow_local`  | `nextflow_local`  | `nextflow/`  | `custom`（有实际实现才建） |
| `<sw>_snakemake_local` | `snakemake_local` | `snakemake/` | `custom`（有实际规则才建） |

> 官方实现（nf-core / snakemake-wrappers）不再建目录，其链接与版本差异记录在对应实现 `README.md` / `software_versions`。

***

## 2. source\_type 判据（每次先问自己：官方有没有？）

> **统一规则（workflow / subworkflow / modules 全适用）**：官方已有（nf-core 完整流程、nf-core modules、snakemake-wrappers）→ **不单独建目录**，只在对应 README + meta.yaml 登记（`source_type: official`、官方仓库/submodules/版本差异、include/wrapper 句柄与强提示）；**官方没有、需本地自定义的实现才建目录**（`source_type: custom`）。

| 场景                                                            | 处理                                                                                                                       |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| 官方已存在稳定实现（nf-core 流程 / nf-core modules / snakemake-wrappers）→ | **不建目录**；官方信息登记到流程/软件 README + meta.yaml（`software_versions`、`source_reference.submodules[]`、`execution` 句柄与 README 强提示） |
| 官方缺失 / 需本地定制 →                                                | **才建本地目录**（写真正的 `.nf` / `.smk`）；modules 侧 `nextflow/`、`snakemake/` 同理                                                    |
| 非流程引擎场景（CLI/Agent 直调）**总是需要** →                               | `native/`（source\_type: custom，自包含）                                                                                      |

> 核心原则：**官方有就不重复造目录，只做说明 + Schema + 引用；官方没有的自定义实现才完整构建。**

***

## 3. meta.yaml 字段规范

### 3.1 软件级 `modules/<software>/meta.yaml`

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
    version: "<软件版本>"          # 纯软件版本（不带 -v 技能后缀）
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
    build_route: "official biocontainer（默认；查无官方才 apt 自建）"
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

````yaml
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
  source: "<official biocontainer / apt / bioconda / babraham-zip / samtools-src ... 的具体说明>"
  note: "<若与其它实现不同，此处补充说明>"
### 3.3 `native` 实现额外必填

```yaml
environment:
  conda: "environment.yml"                 # 保留（离线/非容器备选）
  # 官方镜像优先：官方已有（bioconda → quay.io/biocontainers → depot.galaxyproject.org）
  # 时必须登记 container_official，且不维护 Dockerfile/Apptainer.def：
  container_official: "quay.io/biocontainers/<software>（tag 以 quay / depot.galaxyproject.org 为准，见 README）"
  # 仅查无官方维护时才提供配方文件（自建兜底），如：
  # dockerfile: "Dockerfile"
  # apptainer_def: "Apptainer.def"
````

optimization:
default\_cpus: 4
default\_mem\_mb: 8192
env\_vars:                   # 支持 {tmpdir}/{cpus}/{mem\_mb} 占位符
TMPDIR: "{tmpdir}"
JAVA\_OPTS: "-Xmx6g"       # 如适用
per\_subcommand\_threads:     # 可选，CPU 密集子命令单独调高
sort: 8
default: 4

execution:
entrypoint: "python main.py"
test\_command: "bash test/run\_test.sh"
binary: <可执行文件名>

````

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
````

### CLI 入口必须支持

| 调用                                | 作用                       |
| --------------------------------- | ------------------------ |
| `python main.py <subcommand> ...` | 人类 / Shell 直跑            |
| `python main.py --schema`         | 打印 JSON Schema（Agent 挂载） |
| `python main.py --list-commands`  | 列出子命令清单                  |
| 每个子命令接受 `--threads` / `--tmpdir`  | 运行期覆盖（放在子命令后）            |

> ⚠️ **argparse 坑**：`--threads` 希望放在子命令**之后**使用时，必须用辅助函数把它加到每个 subparser（参考 samtools 的 `_add_runtime_opts`），不要只加到顶层 parser。

### 性能优化必须处理

* **线程优先级**：用户显式 `--threads` > `per_subcommand_threads` > `default_cpus`。CPU 密集子命令（sort、merge、mpileup）建议默认 8 线程。

* **内存声明**：`default_mem_mb` 字段供上层调度器读取；JVM 类工具（Java/Scala）务必透传 `JAVA_OPTS -Xmx`。

* **临时目录**：中间文件统一使用 `self.tmpdir`，并在 `optimization.env_vars` 中声明 `TMPDIR: "{tmpdir}"`；sort 等子命令使用 `-T` 前缀参数显式指定。

* **I/O**：大文件转换优先管道化，避免多余中间落盘。

***

## 4.5 native/install.sh 本地安装脚本契约（现代规范）

> `modules/<sw>/native/install.sh` 为宿主机本地一键安装脚本（§1 目录树 `native/` 下的现代规范组件；官方镜像优先语境下，宿主机装工具仍可走脚本自动化）。参考实现：`modules/stringtie/native/install.sh`。现代规范三要素：

* **a) 默认 `--method auto` 双路线**：检测到 mamba/conda → 创建 bioconda 独立环境（`mamba/conda create -y -n <env> -c conda-forge -c bioconda <sw>=<版本>`，版本取 meta.yaml `software_versions.native` 所记值）；无 conda 且本平台有官方二进制 → 官方 GitHub release / 官网二进制解压部署到**用户前缀**（默认 `~/software/<sw>-<ver>`，无需 root、不写 `/opt/biosoft`）。

* **b) 参数契约**：至少支持 `--version` / `--prefix` / `--method auto|conda|binary` / `--conda-env` / `--profile` / `--force` / `--no-path-update` / `--help`（`--force`：conda 环境已存在时删除重建；`--no-path-update`：不写 shell profile）。

* **c) 默认版本与版本断言**：默认版本与 meta.yaml `software_versions.native` 对齐；内嵌该默认版本的官方 sha256（Linux / OSX 各一份）；`--version` 覆盖为非默认版本时**跳过内嵌校验并打印提示**；安装完成后必须断言 `<binary> --version`，输出 grep 命中版本号方为成功。

* **d) bash 坑**：`$VAR` 后紧跟全角字符（如 `）`）会被 bash 误并入变量名导致 unbound variable，一律写 `${VAR}`。

* **e) 清理**：失败/中断用 `trap cleanup EXIT` 兜底；成功路径末尾**显式清理并置空**（EXIT 钩子判空跳过），避免双重清理误删正在使用的文件。

* **f) 平台守卫**：官方二进制仅覆盖 linux-x64 / macos-x64（`uname -s`/`uname -m` 判定）；其余平台打印提示改走 conda 路线（`--method auto` 无 conda 时直接报错退出）。

* **g) 测试**：conda 模式实装断言（`conda run -n <env> <binary> --version`）；binary 模式可本机 Rosetta（`arch -x86_64 bash install.sh`）或 Linux 容器验证。

***

## 5. 官方实现登记契约（并入软件级 meta.yaml / README，不建目录）

**官方已有实现一律不单独建目录**（见 §2 统一规则）。登记信息统一落在：

* 软件级 `modules/<sw>/meta.yaml`：`implementations[]` 中登记 `source_type: official` 条目（type 记 `nextflow_local` / `snakemake_local`，path 指向实际存在的本地实现目录或官方占位说明），并承载 `software_versions{}`（对齐官方 conda pin）与 `source_reference`（官方仓库 / submodules\[] / wrapper/include 句柄）；

* `modules/<sw>/README.md`：官方 wrapper / nf-core 子模块清单 + 引用示例 + **强提示**。

* **Snakemake wrapper 调用规则（2026-09 起全库适用）**：凡官方 `bio/<sw>` wrapper 存在（`software_versions.snakemake_wrappers` 非 404 / 非「官方无」占位）且模块**无本地 snakemake 修订**（`snakemake/` 下无自维护 `.smk` / `script` wrapper）→ README 官方登记节必须提供**可直接粘贴的 `rule ... wrapper:` 调用示例**（`wrapper: "v<tag>/bio/<sw>[/<sub>]"`，tag 取 `software_versions.snakemake_wrappers.wrapper_tag` 登记值；扁平 wrapper 按官方 `wrapper.py` 的 params 契约书写，如 `params.command` + `params.extra`）。**本地已有修订 / 自维护规则**的模块**不重复**提供官方 wrapper 调用示例（本地 `.smk` include 即执行路径），仅在 `software_versions` 与官方登记中记录 wrapper 存在性与句柄；wrapper 强提示（运行时解析、勿当 wrapper_path）保持。官方 wrapper 缺失时，才走本地 `snakemake/` 自定义。

> 承载字段要求（语义沿用，不因合并而省略）：

| 登记内容                            | 官方 nf-core                                                                          | 官方 snakemake-wrappers                                               |
| ------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `software_versions`             | 对齐 `modules/nf-core/<sw>/*/environment.yml` / Wave container pin；记 `module_version` | 对齐 `bio/<sw>/*/environment.yaml`；记 `wrapper_tag` + `wrapper_utils`  |
| `source_reference.submodules[]` | **与官方目录** **`modules/nf-core/<sw>/`** **子目录严格一致**（curl 抓目录，见 ARCHITECTURE §3.2）     | **与官方目录** **`bio/<sw>/`** **子目录严格一致**                               |
| 引用句柄                            | `nf modules install nf-core <sw>/<sub>`；include 语句示例                                | `wrapper: "vX.Y.Z/bio/<sw>/{subcommand}"` 运行时解析示例                   |
| README 强提示                      | 「执行请用 `nf-core modules install` 安装到项目自身目录，不要直接引用本仓库示例 main.nf」                      | 「运行靠 Snakemake 解析 `wrapper:` 句柄，不要把本地示例 wrapper.py 当 wrapper\_path」 |
| 缺失兜底                            | 提示用本地 `nextflow/` 自定义（官方缺失才建目录）                                                     | 提示用本地 `snakemake/` 自定义（官方缺失才建目录）                                    |

> 本地自定义实现目录（`nextflow/` / `snakemake/`）仅在官方缺失或需定制时建立，未启用可不建（不保留空占位目录）。

***

## 6. 测试要求

`native/test/` 至少包含：

* `generate_data.py`：**动态生成**合成数据（保持仓库轻量；不要提交 BAM/FASTQ 大文件）

* `run_test.sh`：端到端最小回归

  * `mktemp -d` + `trap` 清理

  * 串行调用 main.py 核心子命令链路（至少 4–5 条）

  * `test -f` / `grep` 对关键产物断言

  * 最终 `echo "ALL TESTS PASSED"`

***

## 7. 环境路线要求（**官方镜像优先；查无官方才自建 apt 最小化**）

> ⚠️ **默认路线（官方镜像优先）**：凡软件在 **bioconda → quay.io/biocontainers → depot.galaxyproject.org** 有官方维护镜像 →
> `native/` **不维护 Dockerfile/Apptainer.def**；在 meta.yaml（`environment.container_official` +
> `software_versions.native.build_route=official biocontainer`）与 README 登记官方镜像及 tag；
> native `main.py` 驱动在宿主机运行（conda/mamba 装工具），或 docker run 官方镜像直跑工具本体。
>
> ⚠️ **自建兜底（仅查无官方维护时）**：目前如 **gstama / orfanage / dorado / gnu\_sort / gunzip**（dorado 官方仅 GitHub 二进制）
> 才保留自建配方：**Debian** **`bookworm-slim`** **+ apt** **`--no-install-recommends`** + **清理四连** + **%test 版本断言**；
> 自建路线**禁止默认引入 miniconda/micromamba**。
> 理由：官方镜像（biocontainer）由 bioconda 自动构建、tag 含版本+build 可追溯，省去本地配方维护；
> 自建兜底沿用 apt 最小化（镜像更小、启动更快、CVE 补丁随 Debian 安全源推送）。
>
> 运行 Docker 时必须加 `-u $(id -u):$(id -g)`，避免输出文件被 root 持有。

### 官方镜像登记（默认路线，native/ 不写配方文件）

* 查找顺序：**bioconda（<https://anaconda.org/bioconda/><sw>）→ quay.io/biocontainers → depot.galaxyproject.org**，任一有官方维护即判为「有官方镜像」；

* meta.yaml 登记：`environment.container_official: "quay.io/biocontainers/<software>（tag 以 quay / depot.galaxyproject.org 为准，见 README「容器与 Conda 链接」）"` + `software_versions.native.build_route: "official biocontainer（quay.io/biocontainers/<sw> / depot.galaxyproject.org）"`，source 写 anaconda.org/bioconda/<sw>；

* README「容器与 Conda 链接」登记官方镜像及 tag；`native/` 不维护 Dockerfile/Apptainer.def；

* Apptainer 官方镜像路线：galaxyproject 已预构建 sif，**直接拉取**（`apptainer pull <sw>.sif docker://depot.galaxyproject.org/singularity/<sw>:<tag>`；等价直链 <https://depot.galaxyproject.org/singularity/<sw>%3A<tag>>），**无需**本地从 quay docker 镜像转换；README「环境安装」的「Apptainer / Singularity」小节登记此直拉命令及 tag（tag 与 quay.io/biocontainers 互通；小节编号随主安装路线顺延）；

* 宿主机运行 main.py：conda/mamba 装工具（`mamba create -n <env> -c conda-forge -c bioconda <software>=<版本>`）或 docker run 官方镜像。

### 自建 conda 包配方（native/conda-recipe/，按平台分目录）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org，见 §0 查找规则 1–3）无该软件
conda 包、需发布自建包到个人频道（如 **YangmingSi**）时，conda-build 配方**按平台分目录归档**：

```
native/conda-recipe/
├── linux-64/meta.yaml       # linux x64 构建配方
└── osx-arm64/meta.yaml      # Apple Silicon 构建配方（仅该平台受支持时建）
```

* 每个**受支持平台**一个独立 `meta.yaml`，平台目录名即 conda-build 目标平台（`linux-64` / `osx-arm64` …）；
  平台差异就地调整（如 `noarch: generic`、`target_platform`、source URL、依赖 pin），**不用单个 meta 硬塞多平台**；
  上游仅分发单平台（如 NCBI ORFfinder 仅 linux-i64、riboss 官方仅 Linux）→ 只建对应平台目录，并在配方头注写明理由；
* 重建发布：`conda build conda-recipe/linux-64`（或 `osx-arm64`）→ `anaconda upload ...`；
* 登记：软件级 `software_versions.native.source` 写 anaconda 页面
  （`https://anaconda.org/channels/YangmingSi/packages/<sw>/overview`），`container_ref.yangmingsi` 与 README
  「容器与 Conda 链接」记录配方路径与版本；`native/environment.yml` / `snakemake/*.yaml` 可引用该频道直装；
* 实例：`orffinder`（linux-64）、`riborf`（linux-64 + osx-arm64）、`riboss`（linux-64）三模块已按此归位（2026-09）。

### 宿主安装方式登记（conda + Homebrew + 官方二进制）

> 容器/镜像判定顺序不变（bioconda → quay.io/biocontainers → depot.galaxyproject.org，见上）；本小节只管**宿主机本地安装方式**的登记，对应 README「环境安装」中的「Conda / brew（包管理器安装）」与「官方预编译二进制包 / 官方源码编译」小节（小节编号按主安装路线顺延，见下）。

* **conda（bioconda）**：`mamba create -n <env> -c conda-forge -c bioconda <software>=<版本>`（版本与 meta `software_versions` 对齐，见下「environment.yml」），写 README conda 块；

* **Homebrew（brew）**：brew 仅作宿主安装登记，**不参与容器镜像判定**（brew 不是容器来源）。判定两源：

  * homebrew-core：`https://formulae.brew.sh/api/formula/<sw>.json`（或 `brew search <sw>`），命中即免 tap，`brew install <sw>` 后 `--version` 断言；

  * brewsci/bio tap：`https://github.com/brewsci/homebrew-bio/tree/master/Formula`（或 `brew search brewsci/bio/<sw>`），命中需先 `brew tap brewsci/bio` 再安装；

  * ⚠️ **同名异义核对**：同名公式必须核对 desc 确为生物信息软件（或确为该软件版本）后才登记（如 core `lima`=Linux 虚拟机、core `star`=归档器）；brew 当前版本与 meta `software_versions` 不一致 → 注释标注「brew 当前 <ver>，与 meta 登记 <ver> 略有差异（以 formula 为准）」；两源均无 → README 不写 brew 块（仅 conda / 官方容器 / 官方二进制）。

* **官方安装资产（预编译二进制包 + 源码编译，两条官方路线都保留）**：先核实官方是否提供**预编译二进制包**（GitHub release assets / 官网下载页资产）。**两者都存在时以官方预编译包为首选安装方式，源码编译路线并列保留**——README「环境安装」须两条都写（预编译在前、源码编译紧随），meta 的 `container_ref`（`upstream_prebuilt` / `upstream_source`）、`software_versions.build_route/source/note`、`environment.note` 须同时登记，不得只登记其一，也不得在未核实的情况下声称“无预编译资产”；若官方确无预编译资产，则源码归档/源码+补丁即唯一官方路线，须在 README 写明已核实无预编译资产。部署到用户前缀 `~/software/<sw>-<ver>`（无需 root，禁 `/opt/biosoft`、`/home/train` 教学硬编码），一键路线直接引用 `native/install.sh`（契约见 §4.5）。

### README「环境安装」标准结构（官方安装路线优先，不维护本地配方）

> README 环境安装节标题按该软件**主安装路线**命名：
>
> * 官方有**预编译二进制包** → **「## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）」**（预编译小节前置为 §1，源码编译小节并列保留、编号顺延；conda/brew/容器小节作为备选并列）；
>
> * 仅官方容器/conda 可用（无官方预编译包）→ 沿用 **「## 环境安装（官方镜像优先，不维护本地配方）」**（实例：`modules/stringtie/README.md`）。

* 首行写官方已维护说明（官方渠道 bioconda → quay → depot 已维护 → 直接拉官方镜像运行工具二进制，`main.py` 驱动在宿主机跑）；随后编号小节：

  1. **Conda / brew（包管理器安装）**：conda 块后并列 brew 块（判定/登记规则见上「宿主安装方式登记」）；

  2. **Docker（官方镜像）**：quay.io/biocontainers tag；`docker run` 必须含 `-u $(id -u):$(id -g)`（避免产物归 root）；

  3. **Apptainer**：depot 预构建 sif 直拉（`apptainer pull <sw>.sif docker://depot.galaxyproject.org/singularity/<sw>:<tag>`），无需本地从 quay docker 转换；

  4. **官方预编译二进制包（首选）**：官方当前可用 URL（GitHub release assets / 官网下载页资产），解压到用户目录 `~/software/<sw>-<ver>` 并写 PATH，**禁 `/opt/biosoft`、`/home/train`**；可提示一键走 `native/install.sh`（§4.5）；

  5. **官方源码编译（并列保留）**：官方源码归档 / 源码+补丁 / SDK；**官方同时提供预编译包时，本小节不得省略**（两条官方路线都要保留，见上「宿主安装方式登记」）。

* README 亦可含「实战示例」教程节：典型批量用法（bash 循环等）+ 参数表 + 与 `native/main.py` 子命令的桥接句。

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

### Dockerfile（仅自建兜底路线：查无官方维护时提供）

* **基础镜像**：`debian:bookworm-slim`（自建兜底不要再用 `continuumio/miniconda3:24.7.1-0`）

* **安装顺序**：

  1. `apt-get update -y`
  2. `apt-get install -y --no-install-recommends <最小依赖集：软件包本体 + ca-certificates + procps>`
  3. 若 apt 无该软件（例：dorado / gstama / orfanage），则 **apt 只装运行时**（openjdk/perl/libz1/…）+ 官方二进制 zip/tar.bz2（或 GitHub release）直接布署到 `/opt/`，并用 `ln -s` 到 `/usr/local/bin`
  4. **清理四连（缺一不可）**：`apt-get autoremove -y` + `apt-get clean` + `rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*`；**仅用于构建的 curl/wget/dpkg-dev 要在 purge 阶段移除**

* **用户态**：不创建固定账号（避免 HPC UID 冲突）；运行时靠 `-u $(id -u):$(id -g)` 接管

* **ENTRYPOINT / CMD**：

  * 对 CLI 工具（samtools/fastqc/…）：`ENTRYPOINT ["/usr/local/bin/<binary>"]` + `CMD ["--help"]`

  * 对 Python 驱动（自定义 main.py）：`ENTRYPOINT ["python","/opt/skill/main.py"]`

* **必须**：`ENV TMPDIR=/tmp`；Java/Scala 类再补 `JAVA_TOOL_OPTIONS="-Xmx8g -Djava.io.tmpdir=/tmp"`

* **禁止**：默认安装 sudo、vim、bash-completion、manpages 等非运行必需

### Apptainer.def（仅自建兜底路线）

* `Bootstrap: docker` + 同一基础镜像（`debian:bookworm-slim`）

* `%post` 内：**同样遵守 apt 最小化 + 清理四连**（不要引入 micromamba）

* 必需段：`%files`（如需要）/ `%environment` / `%runscript` / `%test`

* `%test`：至少执行 `<binary> --version` 并 grep 目标版本号；必要时再跑最小链路测试

* `%labels`：`org.bioskills.software`、`impl`、`base_image`、`<软件>_version`、`pkg_route`（写清楚是 apt 还是 apt+zip/编译）

### 版本差异声明的落地对应

* **官方镜像路线**：以登记的官方镜像 tag / bioconda pin 为准（quay.io/biocontainers tag 含版本+build）→ 填入软件级 / 实现级 `software_versions.native`（build\_route=official biocontainer）

* **自建兜底路线**：apt 装什么版本（`apt-cache policy <pkg>` 抓得到）→ 填入 `software_versions.native`

* nf-core / snakemake-wrappers 读官方 `environment.yml` 里的 conda pin → 填入对应 `software_versions.nextflow_nfcore` / `snakemake_wrappers`

* 如果三条路版本号不一致 → **必须在 Checklist 中核对并在** **`note:`** **写明是否允许共存、如何回滚**

***

## 8. 校验与注册流程（每次新增/改动后必做）

```bash
# 1. 校验软件（单合并 meta：modules/<sw>/meta.yaml；validate 自动检查各实现目录存在性）
#    只校验实际存在的实现：native/ 必校验；本地自定义 nextflow/、snakemake/（若建了）逐个校验；
#    官方实现不建目录，无需校验。
python modules/bin/skill-cli validate modules/<software>

# 2. 导出 JSON Schema（Agent 用，源自软件级 meta.yaml）
python modules/bin/skill-cli schema modules/<software>/meta.yaml

# 3. 重建全局 registry.yaml（自动扫描全库 meta.yaml）
python modules/bin/skill-cli scan

# 4. 跑 native 回归测试（需对应软件已安装）
bash modules/<software>/native/test/run_test.sh
```

`skill-cli validate` 的硬性检查：

* 必填字段：`id` `version` `software` `type` `source_type`（注意 local 占位 `version=""` 被接受）

* `source_type ∈ {official, custom}`

* `type ∈ {native, nextflow_nfcore, nextflow_local, snakemake_wrappers, snakemake_local, nfcore_module, snakemake_wrapper}`（后两项为旧值兼容）

* `source_type=custom type=native` 额外要求 `environment` / `execution` 字段、`main.py` 存在、`test/run_test.sh` 存在

* 其他 `source_type=custom`（nextflow\_local / snakemake\_local）至少要求 `execution`

***

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

***

## 10. 新增软件检查清单（Checklist）

构建一个新软件 `<tool>` 时，逐项确认：

* [ ] 目录 `modules/<tool>/`，canonical 名全小写，`-` 分词（必须与 bioconda / nf-core / Debian 统一规范名一致）

* [ ] `modules/<tool>/meta.yaml` 软件级总览：implementations（登记 native + 官方 + 本地自定义条目，按优先级）+ default\_implementation + **software\_versions 差异声明**

* [ ] `modules/<tool>/native/`（**总是建**，source\_type=custom/type=native）：
  * [ ] 字段：inputs/outputs/environment/optimization/execution + **software\_versions 段**

  * [ ] `main.py`：继承 `SkillBase`，实现 `build_command`，支持 `--schema` / `--list-commands` / `--threads` / `--tmpdir`

  * [ ] `native/install.sh`：现代规范双路线（conda / 官方二进制，契约见 §4.5）；默认版本对齐 meta `software_versions.native`，安装后 `<binary> --version` 断言

  * [ ] `environment.yml`（保留，仅离线/非容器备选）

  * [ ] **容器路线（官方镜像优先）**：官方已有（bioconda → quay.io/biocontainers → depot.galaxyproject.org）→ meta.yaml 登记 `container_official` + `software_versions.native.build_route=official biocontainer`，README 登记镜像/tag，**native/ 不维护 Dockerfile/Apptainer.def**；查无官方（如 gstama/orfanage/dorado/gnu\_sort/gunzip）→ 才提供 **`Dockerfile`（debian:bookworm-slim + apt --no-install-recommends + 清理四连）** 与 **`Apptainer.def`（同 apt 路线 + %test）**，版本均与 software\_versions 对齐

  * [ ] `test/generate_data.py` + `test/run_test.sh`，本机跑通

  * [ ] `README.md`

* [ ] **官方登记（不建 nf-core / snakemake-wrappers 目录）**：官方已有实现的信息并入软件级 `meta.yaml`（`source_type: official` 条目 + `software_versions`）与 `README.md`：
  * [ ] `submodules[]` 与官方目录（`modules/nf-core/<tool>/` / `bio/<tool>/`）子项严格一致

  * [ ] `software_versions{}` 对齐官方 `environment.yml` / `environment.yaml` / Wave container

  * [ ] README 顶部写强提示（官方已存在 → 不建目录只登记；执行请用 `nf-core modules install` / `wrapper:` 句柄；缺失时走本地自定义目录）

* [ ] **本地自定义目录（仅官方缺失 / 需定制时才建）**：`nextflow/`（写 `.nf`）、`snakemake/`（写 `.smk`）；未建则不登记目录

* [ ] 实现 ID 严格遵守 §1：`<tool>_native` 等

* [ ] **meta 容器登记二选一**：官方已有 → 必填 `container_official` + `build_route=official biocontainer`（无配方文件）；查无官方 → 必含 Dockerfile/Apptainer.def 自建配方；**自建兜底时避免 miniconda/micromamba 默认引入；所有 Docker 示例命令（官方或自建镜像）都写** **`-u $(id -u):$(id -g)`**

* [ ] **brew 公式存在性已查**（homebrew-core `https://formulae.brew.sh/api/formula/<tool>.json` / brewsci/bio `https://github.com/brewsci/homebrew-bio/tree/master/Formula` 两源；⚠️ 同名异义核对 desc，如 core `lima`=虚拟机、core `star`=归档器）；存在 → README「Conda / brew（包管理器安装）」小节 conda 块后登记 brew 块并注释标注与 meta 的版本差异；两源均无 → 不写 brew（brew 仅宿主登记，不参与容器镜像判定）
* [ ] **官方安装资产双路线已核实**：官方同时提供「预编译二进制包」与「源码编译」时，两条都要保留在 README「环境安装」（预编译优先、源码并列），且 meta `container_ref`/`software_versions`/`environment.note` 同步登记；未核实不得断言“无预编译资产”

* [ ] **Apptainer 登记为 depot 预构建 sif 直拉**（有官方 tag 时：README「环境安装」的「Apptainer / Singularity」小节写 `apptainer pull <tool>.sif docker://depot.galaxyproject.org/singularity/<tool>:<tag>`，无需本地从 quay docker 转换）

* [ ] **native / nf-core / snakemake-wrappers 的 software\_versions 三方差异已逐条核对**

* [ ] `skill-cli validate modules/<tool>` 全 \[OK]（实际存在的实现目录均通过）

* [ ] `skill-cli schema` 成功导出 `.schema.json`（已列入 .gitignore）

* [ ] `skill-cli scan` 成功重建 registry.yaml 并包含新软件

***

## 11. 黄金样例

**以** **`modules/samtools/`** **为参考**，它完整演示了：

* 软件级 meta.yaml 合并登记（native 总是 + 官方登记条目 + 本地自定义目录按需建立）

* native main.py 的子命令分发、线程优先级、临时目录优化

* 环境路线示例（官方镜像优先：container\_official + build\_route=official biocontainer 登记；查无官方才自建配方）

* 动态生成测试数据的最小回归

* 两个官方说明层（含 "本目录仅说明不可直接 include / wrapper 靠运行时解析" 的强提示）

* 两个 local 占位 meta.yaml + README

* 与 registry.yaml 条目完全对应

新增任何软件时，先对照 samtools 的对应文件结构复制改造。
