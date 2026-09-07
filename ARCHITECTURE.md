# 生信技能库（Skill Library）架构与构建方案

（截至 2026 年 8 月 · 最终全景融合版）

## 一、 定位与目标

构建一个以软件/工具为中心、高度自包含（Self-contained）、标准化解耦，且同时原生支持“人类工程师手动调用”与“大模型/AI Agent 自动编排”的自动化生信技能库（Bioinformatics Skill Infrastructure）。

### 核心指标

* **双源并存架构（Official-Annotated + Custom-Native）**：官方已有模块以“说明+配置规范”形式映射接入；缺失/自定义模块以“本地自包含”形式完整构建。

* **软件与流程双层归档**：原子技能以具体软件为单位归档，复合流程以常用组合为单位归档，彻底解决代码碎片化与长链条编排易错问题。

* **官方镜像优先（代码/测试/Schema 本地化）**：自定义模块的代码、测试数据与标准 Schema 全量本地化（Offline-first）；工具环境默认登记**官方维护镜像**（bioconda → quay.io/biocontainers → depot.galaxyproject.org），**查无官方才内嵌自建镜像配方**（apt 最小化兜底）。

* **内置运行性能优化**：针对 CPU 线程、内存限制、I/O 缓冲区及临时文件清理进行标准化配置与自动传参。

* **双模调用兼容**：既能作为独立的 CLI 工具运行，也能作为 JSON-Schema 驱动的 Function Calling / Tool Definition 供 AI Agent 解析。

## 二、 核心设计原则

1. **软件与复合流程分层归档**：

   * **原子技能（Atomic Skill）**：顶级目录按照软件 Canonical Name 命名，规范统一小写（如 `samtools`, `bwa-mem2`, `fastqc`）。命名优先级：Debian 仓库名 > nf-core/modules 目录名 > Bioconda 名；冲突时在 meta.yaml 写清别名。

   * **复合流程（Composite Workflow）**：涉及多软件串联的流程统一归档在 `workflow/`（完整流程）与 `subworkflow/`（常用组合）下，与 `modules/` 平级。
2. **官方现有模块与自定义构建双轨制（Hybrid Sourcing Strategy）**：

   * **官方已有 → 不单独建目录**：对 `nf-core/modules`、`snakemake-wrappers` 或 nf-core 官方完整流程中**已经存在**的成熟实现，本地**不建立单独目录**，只把说明、校验 Schema、接口描述与引用（meta.yaml 的 `implementations[source_type: official]` 条目 + `software_versions` + `source_reference.submodules[]` + README 强提示）登记到软件级 meta/README，**不重写源码**（workflow 层同理：官方已有完整流程如 nf-core/riboseq 不建 nextflow/ 目录）。

   * **本地自定义（Custom-Native）**：仅当官方缺失、或有特殊优化需求时，才在 `native/`（总是）/ `nextflow/` / `snakemake/` 下提供自包含构建（`main.py` + `test/`，容器配方 `Dockerfile`/`Apptainer.def`/`environment.yml` **仅查无官方镜像时提供**，或 `.nf`/`.smk`）。
3. **环境路线官方镜像优先，自建 apt 配方仅兜底（性能优化内嵌）**：

   * **官方镜像优先（默认）**：凡软件在 **bioconda → quay.io/biocontainers → depot.galaxyproject.org** 有官方维护镜像 → `native/` **不维护 Dockerfile/Apptainer.def**；meta.yaml（`environment.container_official` + `software_versions.native.build_route=official biocontainer`）与 README 登记官方镜像及 tag；native `main.py` 驱动在宿主机运行（conda/mamba 装工具），或 docker run 官方镜像直跑工具。

   * **宿主安装方式（README 记录）与容器路线并行**：conda/mamba、Homebrew（homebrew-core / brewsci/bio tap）、官方 release 二进制/源码，一键脚本为 `native/install.sh`。

   * **官方 release 二进制为兜底分发**：GitHub release 无预编译资产（如 TransDecoder 纯 Perl、STAR 源码）时，二进制小节写 tag 源码归档或官网下载（如 NCBI sdk 版本化目录），并注明平台限制（如 CentOS 官方包仅到某版本）。

   * **自建兜底（仅查无官方维护）**：目前如 gstama / orfanage / dorado / gnu_sort / gunzip（dorado 官方仅 GitHub 二进制）才保留自建配方：**`debian:bookworm-slim + apt --no-install-recommends`** + 清理四连 + `%test` 版本断言；自建兜底**禁止默认引入 miniconda/micromamba**。Docker 运行一律带 `-u $(id -u):$(id -g)`。

   * **自建 conda 频道包（native/conda-recipe/）**：官方 1–3 渠道无 conda 包且需发布自建频道（如 YangmingSi）时，配方按平台分目录归档（`native/conda-recipe/<platform>/meta.yaml`，每平台独立 meta、仅受支持平台建目录；重建 `conda build` + `anaconda upload` 发布）。实例：orffinder（linux-64）、riborf（linux-64+osx-arm64）、riboss（linux-64），细则见 AGENT.md §7。

   * **snakemake/ 集成层（td2 式）**：wrapper 与 env yaml 平铺 `snakemake/` 根，`.smk` 同目录相对引用（禁 `../envs|scripts`、`envs/`、`scripts/` 幽灵引用）；多子命令软件每 rule 一 `.smk`、config 驱动可独立运行；wrapper 统一注入两级到 `modules/` 共享 `docker_wrapper.py`；建议配 `snakemake/test/` 静态自检。**执行指令选择**：单条命令用官方 `wrapper:` 句柄（如 `"0.0.8/bio/samtools/index"`）或 `shell:`，需逻辑（多步/条件/产物搬运）用 `script:`，同一 rule 内互斥。细则与自查见 AGENT.md「snakemake 集成层规范」。

   * 驱动层（`main.py`）必须处理线程调度、内存上限、流管道化、临时目录挂载与清理。
4. **统一元数据抽象（Unified Metadata Layer）**：无论是官方包装模块还是本地自定义模块，对外都暴露一致的 `meta.yaml` Schema + `software_versions{}` 差异声明，保证 Agent 路由与版本核对零歧义。
5. **官方子模块「目录严格对齐」原则**：

   * `nextflow/nf-core/meta.yaml` 的 `source_reference.submodules[]` 必须与官方 `modules/nf-core/<tool>/` 在线目录严格一致。

   * `snakemake/snakemake-wrappers/meta.yaml` 的 `submodules[]` 必须与官方 `bio/<tool>/` 在线目录严格一致。

***

## 三、 完整目录结构规范

> **已重构目录名**：本节目录已对齐 AGENT.md §1 的 5 类 type 枚举。
> `official_nfcore/` / `official_snakemake/` 旧目录名废弃。**官方实现不建目录**（nf-core / snakemake-wrappers 只登记到软件级 meta/README，见 §二/§五 规则）；
> `nextflow/nf-core` / `nextflow/local` / `snakemake/snakemake-wrappers` / `snakemake/local` 中的 nf-core / snakemake-wrappers 仅作为**登记枚举（type）**，不做目录。

```
modules/
├── registry.yaml                # 动态生成的注册表索引缓存（整合 Native 与 官方 Wrapper）
├── base.py                      # Python Skill Runner 基类与 JSON Schema 导出工具
├── bin/                         # 技能库 CLI 管理工具（skill-cli validate / scan / schema / run）
│
├── fastqc/                      # 【原子技能】软件归档主目录（单 meta.yaml + 单 README 模式）
│   ├── meta.yaml                # 【唯一 meta】implementations + software_versions + inputs/outputs/environment/optimization/execution
│   ├── README.md                # 合并各实现用法 + 容器/conda/brew 链接 + 安装方式（conda/brew/官方二进制 + native/install.sh）
│   │
│   ├── native/                  # [本地实现] type=native
│   │   ├── main.py              # 标准入口驱动
│   │   ├── install.sh           # native 本地安装脚本（宿主一键安装：conda 优先 / 官方 release 二进制兜底）
│   │   ├── *.py / *.sh          # 本地运行脚本（经典脚本直接放 native/ 根）
│   │   ├── Dockerfile / Apptainer.def   # 容器构建 recipe（可选：仅查无官方镜像时提供）
│   │   └── test/                # 最小自动化回归（generate_data.py + run_test.sh）
│   │
│   ├── snakemake/               # [Snakemake 实现] type=snakemake_local
│   │   ├── *.smk                # 本地规则
│   │   ├── scripts/             # 规则配套 wrapper 脚本（可选）
│   │   └── *.yaml               # snakemake conda env（可选）
│   │
│   └── nextflow/                # [Nextflow 实现] 有实际实现才建（如 fastqc 的 main.nf.template）
│       └── 实现文件
│
├── samtools/                    # 【黄金样例】software_versions 差异声明 + 官方镜像优先登记
│   └── ...
├── bwa-mem2/                    # canonical 示例：Debian/Bioconda 统一 "bwa-mem2"，避免 bwa_mem2/bwa2 别名
│   └── ...
├── custom_tool_x/               # 官方不存在的全新自定义软件；仍保留 5 路目录（local/可占位）
│   └── ...
```

> **modules 目录构建规则**：官方已有（nf-core modules / snakemake-wrappers）→ **不单独建目录**，官方信息登记到软件级 `meta.yaml`（`source_type: official` 条目 + `software_versions` + `source_reference.submodules[]`）与 README（强提示）；只有官方没有的**自定义**实现才建 `native/`（总是）/ `nextflow/` / `snakemake/` 目录（`source_type: custom`）。

```
workflow/                         # 【复合流程层】完整流程；与 modules/ 平级，可引用 subworkflow 与原子模块
├── nanoseq/                      # 例：Nanopore RNA-seq（目录形态：编排入口 + 经典多步脚本）
├── isoseq/                       # 例：PacBio Iso-Seq（目录形态：编排入口 + 文档）
└── riboseq/                      # 例：Ribo-seq / RPF + Total RNA-seq（目录形态：native/ 经典脚本库）
    （目录内：<flow_name>.md + meta.yaml + native/〔main.py 编排入口 / run_*.sh 经典脚本〕）
    （轻量/纯文档流程才取根级 <flow_name>.md + <flow_name>.yaml）

subworkflow/                      # 【复合流程层】常用软件组合：可复用小流程，供 workflow 引用或独立调用
└── fastp_bwa_samtools/           # 例：Fastp + BWA-MEM2 + Samtools 比对与质控链（目录形态：md + meta.yaml + native/main.py）
```

> workflow/ 与 subworkflow/ 为复合流程层，与 modules/（原子技能）平级，不参与 skill-cli scan/validate。
>
> **workflow 命名与折叠规则**：
> - 流程文档统一命名 `<flow_name>.md`（根级文档形态的元数据为 `<flow_name>.yaml`；目录形态为 `meta.yaml`）；
> - 流程目录内**只剩文档**（无 native 代码资产）→ 整体折叠到 `workflow/` 根，不保留目录；
> - 流程级 `native/` 保留**经典完整实现脚本**（如 `riboseq/native` 历史脚本库、nanoseq 的 `run_*.sh`）与**编排入口 `main.py`**（逐 stage 委托 `modules/<sw>/native/main.py`，提供 `--list-stages` / `--dry-run` / `--real`）；无代码时编排逻辑记录于流程文档「执行方式 A」；
> - `nextflow/`：官方已有完整流程（nf-core）→ **不建目录**，只在流程文档登记引用与差异；
> - `snakemake/`：流程集成层内容并入流程文档「执行方式 B」后移除目录（工具规则仍存于 `modules/<sw>/snakemake/`，按需在项目内重建）。

### 容器与 Conda 包查找规则（简要）

**官方镜像优先**：按序判定官方维护：bioconda → quay.io/biocontainers → depot.galaxyproject.org；官方渠道全无 → 判为「无官方维护」→ 自建配方（apt 最小化兜底）。补充渠道（Docker Hub / docker.1ms.run 国内加速 / quay.io/bioinfortools / YangmingSi 频道）仅登记备用，不作「官方维护」判定。

**宿主安装方式登记（README 记录，与容器判定并行但互不参与）**：容器/镜像判定顺序不变；宿主安装方式登记含 Homebrew——判定 homebrew-core（formulae.brew.sh/api/formula/<sw>.json，免 tap）与 brewsci/bio（GitHub brewsci/homebrew-bio Formula 目录，需 `brew tap brewsci/bio`）；⚠️ 同名异义必须核对 desc（core lima = Linux 虚拟机、core star = Standard tap archiver 此类），确认确为该生物软件后再登记；版本与 meta `software_versions` 不一致时注释标注；brew 只用于 README 宿主安装登记，不参与容器镜像判定。

### 3.1 canonical 目录名（示例）

| 软件（俗称）       | canonical（`modules/<canonical>/`） | 说明                                                               |
| ------------ | --------------------------------- | ---------------------------------------------------------------- |
| Samtools     | `samtools`                        | Debian / Bioconda / nf-core / snakemake-wrappers 完全一致            |
| FastQC       | `fastqc`                          | Bioconda `fastqc` / Babraham zip 小写统一                            |
| BWA-MEM2     | `bwa-mem2`                        | Debian tracker / Bioconda 均写 hyphen；避免 `bwa_mem2`                |
| Trim Galore! | `trim-galore`                     | Debian 仓库优先；Bioconda 是 `trim-galore` 还是 `trim_galore` 以官方 apt 为准 |
| BCFtools     | `bcftools`                        | 官方无 hyphen                                                       |
| Picard       | `picard`                          | nf-core `modules/nf-core/picard` 一致                              |

### 3.2 官方 submodules 必须对齐在线目录（抓官方目录命令样例）

```bash
# nf-core/modules：列出 modules/nf-core/<tool>/ 除 tests/.conda-lock/单文件外的直接子目录
curl -sL "https://github.com/nf-core/modules/tree/master/modules/nf-core/samtools" \
  | grep -oE 'href="/nf-core/modules/tree/master/modules/nf-core/samtools/[^"]+"' \
  | sed 's|.*/samtools/||; s|"$||' \
  | grep -vE '^(tests|\.conda-lock|meta\.yml|environment\.yml|main\.nf|nextflow\.config)$' | sort -u

# snakemake-wrappers：列出 bio/<tool>/ 的直接子目录（即 samtools/bam_index samtools/calmd 等）
curl -sL "https://github.com/snakemake/snakemake-wrappers/tree/master/bio/samtools" \
  | grep -oE 'href="/snakemake/snakemake-wrappers/tree/master/bio/samtools/[^"]+"' \
  | sed 's|.*/samtools/||; s|"$||' | sort -u
```

> 对于 FastQC / Fastp 这类单 process / 单 wrapper 的软件：submodules 保留 1 条 `[ "<tool>" ]`（如 `[ "fastqc" ]`），保证统一字段不为空。

***

## 四、 官方模块与自定义模块的元数据表达

区分官方模块 vs 自定义模块的关键在于：`source_type`（official / custom）、`type`（5 枚举）、`software_versions{}`（版本差异声明）以及 `execution` 段的执行模式。

> **本节 type 枚举已统一**：新版使用 `nextflow_nfcore` / `nextflow_local` / `snakemake_wrappers` / `snakemake_local` / `native`。
> 旧示例中出现的 `nfcore_module` / `snakemake_wrapper`（单数）/ `official_nfcore` / `official_snakemake` 目录与 id 名**已废弃**。
> **官方不建目录**：§4.1 / §4.2 中 `fastqc/nextflow/nf-core/meta.yaml`、`fastqc/snakemake/snakemake-wrappers/meta.yaml` 仅为「官方登记字段」示意——这些字段最终落在软件级 `modules/<sw>/meta.yaml` 与 `README.md`（`source_type: official` 条目 + `source_reference.submodules[]` + `software_versions` + 强提示），**不建立上述目录**（见 §二/§五 规则）。

### 4.1 官方 snakemake-wrappers 示例 (`fastqc/snakemake/snakemake-wrappers/meta.yaml`)

> 核心：绝不重写官方 wrapper；`source_reference.submodules[]` 与 `bio/fastqc/` 严格对齐；`software_versions` 对齐 wrapper 内 `environment.yaml`。

```yaml
id: fastqc_snakemake_wrappers
version: "v3.13.0"                # 对应 snakemake-wrappers 仓库 tag
software: fastqc
type: snakemake_wrappers          # 新版枚举（复数）
source_type: official

software_versions:
  fastqc: "0.12.1"
  wrapper_tag: "v3.13.0"
  wrapper_utils: "0.9.0"
  source: "bioconda fastqc=0.12.1 + snakemake-wrapper-utils=0.9.0（bio/fastqc/environment.yaml）"
  note: "wrapper tag 升级后务必重新核对 conda pin。"

source_reference:
  repository:  "https://github.com/snakemake/snakemake-wrappers"
  wrapper_url: "https://snakemake-wrappers.readthedocs.io/en/stable/wrappers/fastqc.html"
  wrapper_path: "bio/fastqc"
  tag: "v3.13.0"
  submodules:           # 严格对齐 bio/fastqc/ 目录；单 wrapper 仍保留 1 条占位
    - "fastqc"
  submodules_note: "参考 https://github.com/snakemake/snakemake-wrappers/tree/master/bio/fastqc"

inputs:
  - name: reads
    type: file/list(file)
    required: true
    format: [fastq, fastq.gz]
outputs:
  - name: html
    type: file
    pattern: "qc/{sample}_fastqc.html"
  - name: zip
    type: file
    pattern: "qc/{sample}_fastqc.zip"

execution:
  mode: snakemake_rule
  wrapper_template: "v3.13.0/bio/fastqc"
  rule_example: |
    rule fastqc:
        input:   "raw/{sample}.fq.gz"
        output:
            html="qc/{sample}_fastqc.html",
            zip= "qc/{sample}_fastqc.zip"
        log:     "logs/fastqc/{sample}.log"
        params:  extra=""
        threads: 4
        wrapper: "v3.13.0/bio/fastqc"
```

### 4.2 官方 nf-core 示例 (`fastqc/nextflow/nf-core/meta.yaml`)

```yaml
id: fastqc_nextflow_nfcore
version: "2.1.0"
software: fastqc
type: nextflow_nfcore             # 新版枚举
source_type: official

software_versions:
  module_version: "2.1.0"
  fastqc: "0.12.1"
  source: "bioconda::fastqc=0.12.1（modules/nf-core/fastqc/environment.yml）"
  note: "Wave container tag 与 conda pin 保持一致，升级 modules 时请同步刷新。"

source_reference:
  repository:   "https://github.com/nf-core/modules"
  modules_base: "modules/nf-core/fastqc"
  submodules:
    - "fastqc"
  submodules_note: "参考 https://github.com/nf-core/modules/tree/master/modules/nf-core/fastqc"

execution:
  mode: nextflow_include
  include_statement: "include { FASTQC } from './modules/nf-core/fastqc/main'"
  container: "community.wave.seqera.io/library/fastqc:0.12.1--e83f43ef67f90b0a"
  setup_hint: |
    项目根执行：nf modules install nf-core fastqc
    本目录仅为说明/Schema 挂载层；缺失参数时切换 nextflow/local 自定义实现。
```

### 4.3 Native 示例 (`fastqc/native/meta.yaml` — 官方镜像优先路线)

> 核心：`source_type: custom`；**官方镜像优先**：官方已有（bioconda → quay.io/biocontainers → depot.galaxyproject.org）→ 不维护容器配方，meta 登记 `container_official` + `build_route=official biocontainer`；查无官方才走自建 apt 配方。

```yaml
id: fastqc_native
version: "0.12.1"
software: fastqc
type: native
source_type: custom

software_versions:
  fastqc: "0.12.1"
  build_route: "official biocontainer"
  source: "https://anaconda.org/bioconda/fastqc"
  note:   "官方镜像优先：bioconda → quay.io/biocontainers → depot.galaxyproject.org 有官方维护，native/ 不维护 Dockerfile/Apptainer.def；镜像与 tag 见 environment.container_official / README。版本与 Bioconda 对齐。"

environment:
  conda: "environment.yml"          # 保留（离线/非容器备选）
  container_official: "quay.io/biocontainers/fastqc（bioconda 官方镜像；tag 以 quay / depot.galaxyproject.org 为准，见 README「容器与 Conda 链接」）"

optimization:
  default_cpus: 4
  default_mem_mb: 8192
  env_vars:
    TMPDIR: "{tmpdir}"
    JAVA_TOOL_OPTIONS: "-Xmx6g -Djava.io.tmpdir={tmpdir}"

execution:
  entrypoint: "python main.py"
  test_command: "bash test/run_test.sh"
  binary: fastqc
```

### 4.4 环境路线默认值（官方镜像优先 · 架构级约束）

本节与 AGENT.md §7 一一对应，在此作架构层面再次约束。

| 要素 | 默认值 / 约束（官方镜像优先） | 例外（自建兜底） |
| --- | --- | --- |
| 环境路线（默认判定） | **官方已有（bioconda → quay.io/biocontainers → depot.galaxyproject.org 任一）→ 登记 container_official，不维护配方**：meta.yaml 记 `environment.container_official` + `software_versions.native.build_route=official biocontainer`，README 记镜像/tag | 查无官方维护（如 gstama / orfanage / dorado / gnu_sort / gunzip）→ 保留自建配方 |
| 基础 OS 镜像 | 官方路线：无自建镜像（docker run 官方镜像） | 自建兜底：`debian:bookworm-slim`；dorado 官方仅 GitHub 二进制 → apt 运行时 + GitHub 二进制布署 |
| 包管理器路线 | 官方路线：宿主机 conda/mamba 或 Homebrew 装工具跑 native main.py | 自建兜底：`apt-get install --no-install-recommends` 优先；软件本体缺再「apt 运行时 + 官方二进制/源码」；**禁止默认引入 miniconda/micromamba** |
| 清理（四连，缺一不可） | 官方路线：无本地构建 | 自建兜底必须：`apt-get autoremove -y` + `apt-get clean` + `rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*` + 构建期工具（curl/wget/dpkg-dev） `purge` |
| Docker 运行示例 | `docker run --rm -u $(id -u):$(id -g) -v "$PWD":/work -w /work <官方或自建镜像> <args>` | CI root 运行亦允许，但 README/AGENT.md 文档示例必须写 `-u` 参数，避免用户输出文件被 root 持有。 |
| Apptainer | 官方路线：不维护本地 Apptainer.def，直接拉取 galaxyproject 预构建 sif：`apptainer pull docker://depot.galaxyproject.org/singularity/<sw>:<tag>`（等价直链 `depot.galaxyproject.org/singularity/<sw>%3A<tag>`） | 自建兜底：`Bootstrap: docker; From: debian:bookworm-slim`；`%post` 同 apt 最小化 + 清理四连；`%test` 必须断言 `<binary> --version` |
| `software_versions.native` 字段 | 必填 `build_route` 与 `source`：默认 `official biocontainer`（source=anaconda.org/bioconda/<sw>） | 自建兜底写 `apt` / `apt + babraham zip` / `apt + github tarball` / `apt + 源码编译`；不要只写 "Conda/bioconda"，除非已显式自建走 bioconda。 |

> **README 环境安装标准结构**（README「环境安装」节模板，编号 1-4；对应 stringtie README 1-4 节）：
> `## 环境安装（官方镜像优先，不维护本地配方）`
> 1. **Conda / brew**：conda 配方（environment.yml）或 Homebrew 公式（homebrew-core / brewsci/bio，见上「宿主安装方式登记」）；亦可用 `native/install.sh` 一键安装。
> 2. **Docker**：官方镜像直跑，运行一律带 `-u $(id -u):$(id -g)`（避免产物归 root）。
> 3. **Apptainer**：depot 预构建 sif 直拉（`apptainer pull docker://depot.galaxyproject.org/singularity/<sw>:<tag>`），不本地转换/构建。
> 4. **二进制包安装**：官方 release 二进制，解压到用户目录 `~/software` 并加 PATH（无需 root）。
> README 可另含「实战示例」教程节（典型批量用法 + 参数表 + `main.py` 桥接句）。

***

## 五、 Agent 路由与工具选择逻辑

**注意**：本节图中的 `official_nfcore` / `official_snakemake` 旧文字名已同步更新为 `nextflow_nfcore` / `snakemake_wrappers`。

```
                               [ 用户/Agent 调起技能请求 ]
                                            │
                                   是否属于流程引擎上下文？
                                 ┌──────────┴───────────┐
                              (是)                     (否)
                               │                        │
                  目标流程语言是什么？           直接调用 Native 自定义技能
                ┌──────────────┴───────────────┐ （modules/<tool>/native/main.py）
            (Nextflow)                    (Snakemake)
               │                               │
    检查 nextflow_nfcore               检查 snakemake_wrappers
       是否登记 & 版本可用？                是否登记 & 版本可用？
      ┌────┴────┐                        ┌────┴────┐
     (是)      (否)                     (是)      (否)
      │         │                        │         │
 嵌入官方   检查 nextflow_local      嵌入官方   检查 snakemake_local
 nf-core    是否已实现 → 否则      wrappers   是否已实现 → 否则
           降级 Native                        降级 Native
```

关键决定点：`default_implementation` 永远指向 `_native`；在流程引擎上下文中，若 nextflow\_nfcore / snakemake\_wrappers 的 `software_versions` 与用户需求**不一致**（版本不匹配），亦直接降级 native 避免版本偏差。

***

## 六、 规范化实施步骤与里程碑

### 实施步骤

1. **阶段 1：基础搭建与 CLI 规范（1-2 周）**

   * 创建目录结构并实现 `skill-cli` 校验脚本，支持识别 5 种 `type` 枚举，以及 `source_type: official/custom` 分支校验。

   * 建立 `AGENT.md §10` 作为每次新增软件的 Checklist（含 `software_versions` / 官方镜像登记（container_official）或自建配方 / submodules 抓官方目录 / `-u` 参数等硬性检查项）。

   * 完成 8-12 个核心原子软件的 `native/` 自定义构建；官方已有实现（nf-core modules / snakemake-wrappers）**不建说明层目录**，只登记到软件级 meta/README；本地自定义 `nextflow/` / `snakemake/` 仅在官方缺失或需定制时建立。
2. **阶段 2：复合技能沉淀与 CI/CD 测试（2 周）**

   * 在 `workflow/`（或 `subworkflow/`）下建立复合流程，演示「串联本地 Native 技能 + 为 Nextflow/Snakemake 自动生成调用代码」。

   * 配置自动化回归：覆盖 native `run_test.sh`、`skill-cli validate` 5 目录、`skill-cli scan` 产物完整性。
3. **阶段 3：动态 Registry 生成与 Agent 接入（长期）**

   * 自动扫描所有目录下的 `meta.yaml` 生成全局 `registry.yaml`，并按 `default_implementation` / `priority` 排序。

   * 导出 JSON Schema 挂载至 AI Agent；在路由逻辑中额外使用 `software_versions` 段做版本冲突拦截与提示。

