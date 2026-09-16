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

***

## 七、 skills/ 指令层（索引常驻与按需拉取）

### 7.1 定位：与 modules/ 并列的第二层

本库由**两层**组成，二者互补、互不重复：

| 层 | 目录 | 内容 | 面向对象 | 是否可执行 |
|---|---|---|---|---|
| **实现层** | `modules/` `workflow/` `subworkflow/` | `meta.yaml` + `native/main.py` + `.smk`/`.nf` | 流程引擎、CLI | 是（本仓自建） |
| **指令层** | `skills/` | `SKILL.md`（YAML frontmatter + Markdown）+ 索引层 | Claude 系 Agent 框架（OpenClaw / NanoClaw / Biomni 等） | 否（纯指令文档） |

**边界约定**：`skills/` 只做**上游内容的索引与按需拉取**，不在其中写本仓自有实现；`modules/` 不嵌入 `SKILL.md`，保持实现层格式纯净。跨层检索走 §7.7。

### 7.2 索引常驻 + 内容按需（三层模型）

上游 `skills/` 全量 **76 MB / 7,227 文件**。本仓**不整体归档**，改为三层分离——**发现能力留在仓库里，正文按需拉取**：

| 层 | 路径 | 入库 | 体积 | 作用 |
|---|---|---|---|---|
| **索引层** | `skills/index/` | 是 | ~0.80 MB | 全量 1,705 个技能的索引，**完全离线**可检索、可发现 |
| **登记层** | `skills/lock.yaml` | 是 | <1 KB | 已拉取技能的 `tree-hash` + 上游 commit，供 `verify` 审计 |
| **内容层** | `skills/<source>/<skill>/` | 否（gitignored） | 按需 | 技能正文，由 `skill-cli add` 从 mirror 拉取，可随时重建 |

入库合计 **约 0.81 MB**，较全量归档（76 MB）减少 **99%**。

索引层构成：

* `index/bioskill_index_v3.csv`（673 KB）— 上游原样索引，1,676 行，含 `skill_name` / `description` / `category` / `archive_path` / `file_count`。
* `index/skill_meta.csv`（144 KB）— 本仓派生，从全部 `SKILL.md` frontmatter 抽取 `name` / `primary_tool`（577 个）/ `tool_type` / `category`。

> **为什么必须派生 `skill_meta.csv`**：上游索引不含 `primary_tool` 字段，若只依赖它，`link` 的高置信命中会从 43 个降到接近 0。该文件是跨层索引高置信匹配的**唯一依据**，内容层虽按需拉取，匹配能力不打折。上游同步时需一并重建（§7.6）。

### 7.3 上游来源与基线

| 项 | 值 |
|---|---|
| 上游仓库 | [BioTender-max/awesome-bio-agent-skills](https://github.com/BioTender-max/awesome-bio-agent-skills) |
| 归档基线 commit | `8cbdd18837aa6296c4e77616a03b323bd69b57b1`（2026-07-02） |
| 基线内容 | 1,705 个 `SKILL.md` / 21 个来源目录 / 16 个分类 |
| 本仓镜像 | `.cache/upstream-awesome-skills.git`（裸库，已 gitignore，可再生） |
| 上游 LICENSE | CC0 1.0（仅覆盖汇编层，各技能自带许可证见 §7.5） |

上游声明的 22 个来源仓库（技能数为上游 README 标注值；本仓实际落盘 21 个来源目录，上游自身计数与实测有出入）：

| 来源仓库 | 技能数 | 定位 |
|---|---:|---|
| [GPTomics/bioSkills](https://github.com/GPTomics/bioSkills) | 536 | 系统化生信套件，覆盖 QC 到多组学 |
| [FreedomIntelligence/OpenClaw-Medical-Skills](https://github.com/FreedomIntelligence/OpenClaw-Medical-Skills) | 359 | 医学 AI 库，聚合 12 个专项子仓库 |
| [jaechang-hits/SciAgent-Skills](https://github.com/jaechang-hits/SciAgent-Skills) | 154 | 统计、数据库与临床决策 |
| [K-Dense-AI/scientific-agent-skills](https://github.com/K-Dense-AI/scientific-agent-skills) | 102 | 通用科学计算与 HPC 工作流 |
| [CUHK-AIM-Group/NeuroClaw](https://github.com/CUHK-AIM-Group/NeuroClaw) | 86 | 神经影像：sMRI / fMRI / dMRI / EEG，BIDS、FreeSurfer、FSL |
| [ClawBio/ClawBio](https://github.com/ClawBio/ClawBio) | 63 | GWAS 与单细胞流程编排 |
| [wu-yc/LabClaw](https://github.com/wu-yc/LabClaw) | 59 | 实验室自动化与生物医学研究 |
| [QSong-github/DrugClaw](https://github.com/QSong-github/DrugClaw) | 57 | 药物智能：DTI / ADR / DDI / 药物基因组学 |
| [ChrisLou-bioinfo/nobel-medicine-minds](https://github.com/ChrisLou-bioinfo/nobel-medicine-minds) | 55 | 52 位诺奖得主（2004–2025）认知框架 |
| [zongtingwei/Bioclaw_Skills_Hub](https://github.com/zongtingwei/Bioclaw_Skills_Hub) | 46 | 十大类生物技能中枢 |
| [Runchuan-BU/BioClaw](https://github.com/Runchuan-BU/BioClaw) | 37 | 核心生信工具与数据库查询 |
| [fmschulz/omics-skills](https://github.com/fmschulz/omics-skills) | 29 | 单细胞与空间组学 |
| [JimLiu/science-skills](https://github.com/JimLiu/science-skills) | 29 | Claude Science 内置技能逆向整理 |
| [TianGzlab/OmicsClaw](https://github.com/TianGzlab/OmicsClaw) | 28 | 六类组学：空间 / scRNA / bulk RNA / 基因组 / 蛋白 / 代谢 |
| [adaptyvbio/protein-design-skills](https://github.com/adaptyvbio/protein-design-skills) | 21 | 蛋白设计全链：RFDiffusion / ProteinMPNN / Boltz / Chai |
| [aristoteleo/PantheonOS](https://github.com/aristoteleo/PantheonOS) | 18 | 单细胞与空间转录组（Dynamo / Spateo 团队） |
| [NVIDIA-BioNeMo/bionemo-agent-toolkit](https://github.com/NVIDIA-BioNeMo/bionemo-agent-toolkit) | 17 | NVIDIA BioNeMo NIM 官方技能 |
| [EvoScientist/EvoSkills](https://github.com/EvoScientist/EvoSkills) | 13 | 研究全周期：选题、计划、执行、写作、评审 |
| [xjtulyc/MedgeClaw](https://github.com/xjtulyc/MedgeClaw) | 7 | 生物医学研究，含仪表盘 / RStudio / JupyterLab |
| [zamushwani2/biomedical-ai-skills](https://github.com/zamushwani2/biomedical-ai-skills) | 4 | R 语言肿瘤多组学分析 |
| [ArcInstitute/SRAgent](https://github.com/ArcInstitute/SRAgent) | 1 | SRA / GEO 数据集智能检索 |
| [BioTender-max/awesome-bio-agent-skills](https://github.com/BioTender-max/awesome-bio-agent-skills) | 1 | 自指中枢技能，索引整个集合 |

### 7.4 上游内容裁剪规则（拉取时生效）

内容层按需拉取时，以下排除规则仍然适用（`.gitignore` + `skill-cli add` 双重保证）：

**规则 1：不拉取内嵌上游源码目录 `*/repo/`**

上游 8 个技能把整仓第三方项目 vendored 进 `repo/`（STAgent、TrialGPT、MAGE、Biomni、BioMCP、BioMaster、CellAgent 等）。这些是第三方源码副本，非技能指令，且含 `chroma_squidpy_db/` 向量库（2 份重复，142 MB）、TREC 评测语料（102 MB）等派生物，均可从原始地址重建。`skill-cli add` 只按技能目录粒度拉取，内容层中不会出现 `repo/`。

**规则 2：不归档集合级打包产物 `bioskill_collection_v3.zip`**

104 MB 的整包 zip，与本仓索引层内容重复。

**规则 3：clawbio 等技能的运行时数据随技能一并拉取，不得裁剪**

`clawbio/**/data/`（15.2 MB）是**运行时依赖**而非可选样例：

* `genome-compare/data/george_church_23andme.txt.gz` — IBS 比对基准基因组（CC0），被 `genome_compare.py` 硬编码引用；
* `galaxy-bridge/galaxy_catalog.json` — 离线工具发现索引，缺失即退化为必须联网；
* `methylation-clock/data/GSE139307_small.csv.gz` — 测试夹具，附 `PROVENANCE.md`（含 SHA-256）。

**规则 4：排除 `.DS_Store`**

### 7.5 许可证与合规提示

* 上游部分技能目录自带独立 `LICENSE` / `LICENSE.txt`（19 个）。`skill-cli add` 按技能目录粒度拉取，许可证随技能一并落盘，**不得删除**。
* `openclaw` 来源下有 148 个 `SKILL.md` 带 HTML 注释形式的「proprietary and confidential」声明，与其 frontmatter 中的 `license: MIT` 相互矛盾。索引层保留原文以维持溯源一致性；**再分发或商用前需逐一核实**，本条为已知遗留风险。
* 内容层为**只读快照**：本仓不对拉取下来的技能做本地修改（`skill-cli verify` 会检出改动），以便上游更新时用 `add --force` 直接覆盖。

### 7.6 上游更新后的同步流程

同步分「索引层重建」与「内容层刷新」两条独立路径，互不阻塞。

**索引层重建（上游 commit 前进后必做）**

```bash
# 1) 拉取上游更新（mirror 在 .cache/，已 gitignore）
git --git-dir=.cache/upstream-awesome-skills.git \
    fetch origin '+refs/heads/*:refs/remotes/origin/*' --tags

# 2) 查看基线之后的新提交，评估是否值得跟进
git --git-dir=.cache/upstream-awesome-skills.git \
    log --oneline 8cbdd18..refs/remotes/origin/main

# 3) 重建索引层（v3 原样索引 + ROADMAP + 派生 skill_meta.csv）
python modules/bin/skill-cli index-build

# 4) 把 lock.yaml 的 upstream.commit 更新为新 commit（内容层仍指向旧 commit，verify 会提示差异）
# 5) 重建跨层索引并抽查
python modules/bin/skill-cli link
python modules/bin/skill-cli search samtools --limit 5
```

`index-build` 做了三件事：拉取上游 `bioskill_index_v3.csv` 与 `docs/ROADMAP.md`（后者重写 `../skills/` 链接前缀以适配新位置），以及**遍历上游全部 `SKILL.md` 的 frontmatter 重建 `skill_meta.csv`**。第三步是关键——它承载 `primary_tool`，是 §7.7 高置信匹配的唯一依据，因此上游更新后**必须**重跑，只刷新内容层是不够的。

效率设计：`index-build` 先用 `git ls-tree` 拿到全部 `SKILL.md` 的 blob 哈希，再用单次 `git cat-file --batch` 批量取回，**不需要下载 `skills/` 全量正文**（76 MB），partial clone 下只拉取 SKILL.md 本身。

**内容层刷新（按需，不阻塞索引层）**

```bash
python modules/bin/skill-cli verify                   # 检出：正文缺失 / 本地改动 / 上游已更新
python modules/bin/skill-cli add <技能名> --force      # 只重拉受影响的技能
```

> 与全量归档相比，同步成本从「与上游总量成正比」变为「**与已登记量成正比**」——上游涨到 3,000 个技能时，内容层同步成本不变。

**同步后必做**：更新 §7.3 的归档基线 commit 与统计数字，并在提交信息中写明上游 commit。

### 7.7 跨层索引（`modules/link_map.yaml`）

实现层与指令层通过 `modules/link_map.yaml` 关联：**同一软件，既能拿到「怎么跑」（本仓 `meta.yaml`/`native`），也能拿到「怎么用」（上游 `SKILL.md`）**。

生成方式（与 `registry.yaml` 同属生成物，入库但由 CLI 重建）。注意 `link` **读索引层而非技能正文**，因此内容层为空时依然完整可用：

```bash
python modules/bin/skill-cli link
# 已重建 link_map.yaml：206 个软件，high=43，仅 medium=34，未命中=129；已拉取正文 0/1705
```

匹配分三档，**宁可漏报不误报**：

| 置信度 | 依据 | 说明 |
|---|---|---|
| `high` | `primary_tool` / 技能名 / 目录名 与模块名精确一致（含 `LINK_ALIASES` 已知异写，如 `rna-star`↔`star`） | 可直接用于路由与 README 交叉引用登记 |
| `medium` | 模块名出现在技能 `description` 中 | **仅供人工复核**，不得作为唯一依据 |
| 未命中（`skills: []`） | 上游集合未覆盖该软件 | 见 §7.8 扩展方向 3（反向补全）的候选清单 |

产出结构（`vendored` 表示该技能正文是否已按需拉到本地）：

```yaml
summary: { skills_total: 1705, skills_vendored: 0, modules_total: 206, with_high_confidence: 43, with_only_medium: 34, unmatched: 129 }
links:
- software: samtools
  module_dir: modules/samtools
  skills:
  - { path: skills/bioskills/alignment-indexing, confidence: high, matched_by: primary_tool, vendored: false }
  - { path: skills/bioskills/alignment-sorting,  confidence: high, matched_by: primary_tool, vendored: false }
```

**覆盖度说明**：上游 1,705 个技能中仅 577 个带 `primary_tool` 字段，且 129 个模块对应的是上游未收录的工具，因此高置信命中率约 21%（43/206）属正常水平，不代表索引失效。新增软件后需重跑 `skill-cli link`。

### 7.8 合并计划与后续扩展方向

**已完成**

1. 归档基线锁定为上游 `8cbdd18`；索引层落盘 1,705 行技能索引（v3 原样 + 派生 `skill_meta.csv`）；
2. 采用**索引常驻 + 内容按需**三层模型，入库体积从 76 MB 降至 **0.81 MB**（减 99%）；内容层默认零预置；
3. `.gitignore` 实现内容层 `<source>/<skill>/` 忽略、索引层与 `lock.yaml` 保留；
4. `skill-cli` 新增 `search` / `add` / `remove` / `verify` / `index-build`，`link` 改为读索引并输出 `vendored` 标记；
5. `verify` 支持三类漂移检出（正文缺失 / 本地改动 / 上游更新），修复路径为 `add --force`；
6. `.cache/` 上游镜像重指规范地址并纳入 `.gitignore`；本文档记录来源、基线、裁剪规则、同步流程与合规提示。

**后续扩展方向**

1. **场景路线图与 workflow/ 对接**：`skills/ROADMAP.md` 已给出 7 条分析场景（RNA-seq 差异表达、单细胞、WGS 变异、蛋白设计、宏基因组、药物发现、临床 EHR）。逐条比对 `workflow/` 与 `subworkflow/` 现有流程，缺口即新增 workflow 的候选清单。
2. **回填各模块 README 的交叉引用**：按 `link_map.yaml` 中 `confidence: high` 的条目，在 `modules/<tool>/README.md` 写入「指令层：`skills/<source>/<skill>/`」行（AGENT.md §10 已列为必检项）。建议从 `registry.yaml` 中 `priority: High` 的软件开始。
3. **指令层补实现层（反向补全）**：以 `link_map.yaml` 中 `skills: []` 的 129 个模块为反向清单，另从 1,705 个技能中筛选高频被引用、而 `modules/` 尚未覆盖的工具，按 AGENT.md §10 Checklist 逐个补 `native/` 实现。
4. **批量预拉工具**：为 `add` 增加 `--from-links [--confidence high]`，按 `link_map` 一次性预置某个软件或某个优先级档位的技能正文，便于离线场景。
5. **人工复核 `medium` 条目**：34 个仅 `medium` 命中的模块（依据为 `description` 词面匹配）需人工判断，确认后固化为 `LINK_ALIASES` 或剔除。
6. **同步自动化**：将 §7.6 步骤固化为一条命令（`index-build` + `link` 已可脚本化），并在 CI 中定期比对上游 commit 以提示更新。

