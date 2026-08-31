# 生信技能库（Skill Library）架构与构建方案

（截至 2026 年 8 月 · 最终全景融合版）

## 一、 定位与目标

构建一个以软件/工具为中心、高度自包含（Self-contained）、标准化解耦，且同时原生支持“人类工程师手动调用”与“大模型/AI Agent 自动编排”的自动化生信技能库（Bioinformatics Skill Infrastructure）。

### 核心指标

- **双源并存架构（Official-Annotated + Custom-Native）**：官方已有模块以“说明+配置规范”形式映射接入；缺失/自定义模块以“本地自包含”形式完整构建。
- **软件与流程双层归档**：原子技能以具体软件为单位归档，复合流程以常用组合为单位归档，彻底解决代码碎片化与长链条编排易错问题。
- **零外部网络依赖**：自定义模块的代码、**镜像构建配方 (Dockerfile/Apptainer)**、**环境依赖 (Conda/Mamba)**、测试数据与标准 Schema 全量本地化（Offline-first）。
- **内置运行性能优化**：针对 CPU 线程、内存限制、I/O 缓冲区及临时文件清理进行标准化配置与自动传参。
- **双模调用兼容**：既能作为独立的 CLI 工具运行，也能作为 JSON-Schema 驱动的 Function Calling / Tool Definition 供 AI Agent 解析。

## 二、 核心设计原则

1. **软件与复合流程分层归档**：
   - **原子技能（Atomic Skill）**：顶级目录按照软件 Canonical Name 命名，规范统一小写（如 `samtools`, `bwa-mem2`）。
   - **复合技能（Composite Skill）**：涉及多软件串联的常用小流程统一归档在 `custom/` 下。
2. **官方现有模块与自定义构建双轨制（Hybrid Sourcing Strategy）**：
   - **官方现有（Official-Annotated）**：对于 `nf-core/modules` 或 `Snakemake-wrappers` 中已有的成熟模块，在本地**只保留说明文档、校验 Schema 及标准接口描述 (`meta.yaml` + `WRAPPER.md`)**，内部注明引用来源与推荐配置参数，不强行重写源码。
   - **本地自定义（Custom-Native）**：官方缺少、或有特殊优化需求的模块，在 `native/` 目录下提供自包含构建（`main.py` + `Dockerfile`/`environment.yml` + `test/`）。
3. **环境配方与性能优化内嵌**：
   - 自定义 Native 模块必须提供本地镜像与 Conda 描述文件。
   - 驱动层（`main.py`）必须处理线程调度（CPU Threads）、内存上限控制（Memory Caps）、流管道化（I/O Streaming）与临时目录挂载（`TMPDIR` 优化）。
4. **统一元数据抽象（Unified Metadata Layer）**：无论是官方包装模块还是本地自定义模块，对外（给 Agent / 上层流程）暴露完全一致的 `meta.yaml` JSON-Schema 接口，保证调用逻辑无缝切换。

## 三、 完整目录结构规范

Bash

```
skills/
├── registry.yaml                # 动态生成的注册表索引缓存（整合 Native 与 官方 Wrapper）
├── base.py                      # Python Skill Runner 基类与 JSON Schema 导出工具
├── bin/                         # 技能库 CLI 管理工具（如 `skill-cli validate`, `skill-cli run`）
│
├── fastqc/                      # 【原子技能】软件归档主目录
│   ├── meta.yaml                # 软件级总览元数据（标注可用实现类型与推荐优先级）
│   │
│   ├── native/                  # [自定义/优先] 本地自包含 Native 实现（官方缺少或有自定义需求时）
│   │   ├── meta.yaml            # 技能实现级元数据（含 Schema 与性能优化）
│   │   ├── main.py              # 标准入口驱动（参数校验、内存/线程/IO 优化）
│   │   ├── environment.yml      # Conda/Mamba 依赖环境配方
│   │   ├── Dockerfile           # Docker 容器镜像构建配方
│   │   ├── Apptainer.def        # Apptainer / Singularity 构建配方
│   │   ├── test/                # 最小自动化测试集
│   │   └── README.md
│   │
│   ├── official_nfcore/         # [官方现有说明] 指向 nf-core/modules 的包装与规范说明
│   │   ├── meta.yaml            # 统一抽象的接口 Schema 与 Agent 引导说明
│   │   ├── module.json          # 官方模块元信息映射（版本、 upstream commit sha）
│   │   └── README.md            # 说明文档（包含如何在 Nextflow 中直接 include 官方模块）
│   │
│   └── official_snakemake/      # [官方现有说明] 指向 Snakemake-wrappers 的包装与规范说明
│       ├── meta.yaml            # 统一抽象的接口 Schema
│       ├── wrapper.py           # 本地桥接脚本（配置官方 wrapper 路径与默认参数）
│       └── README.md            # 说明文档（包含 master/vX.X.X 官方库引用示例）
│
├── bwa/
├── samtools/
├── custom_tool_x/               # 官方不存在的全新自定义软件（仅包含 native/）
│   └── native/
│
└── custom/                      # 【复合技能】多软件组合的常用小流程（Composite Skills）
    ├── dna_seq_align_qc/        # 示例：Fastp + BWA + Samtools 基因组比对与质控链
    │   ├── meta.yaml
    │   ├── main.py
    │   └── ...
    └── rna_seq_quant/
```

## 四、 官方模块与自定义模块的元数据表达

为实现对外接口的完全统一，区分官方模块与自定义模块的关键在于 `meta.yaml` 中的 `source_type` 和 `execution` 声明：

### 1. 官方现有模块说明示例 (`fastqc/official_snakemake/meta.yaml`)

> **核心点**：不重复写逻辑，通过 `source_type: official` 说明其来源，在 `execution` 中提供框架调用句柄。

YAML

```
id: fastqc_official_snakemake
version: "v3.13.0"               # 对应 Snakemake Wrappers 的发布版本
software: fastqc
type: snakemake_wrapper
source_type: official            # 标识为官方现有模块

source_reference:
  repository: "https://github.com/snakemake/snakemake-wrappers"
  wrapper_path: "bio/fastqc"
  tag: "v3.13.0"

summary: "Official Snakemake Wrapper for FastQC quality control."
agent_guidance:
  when_to_use: "Use when orchestrating pure Snakemake pipelines that leverage central tool caching."
  recommendation_priority: "Medium (Use native implementation for CLI/Agent direct tool calls)."

inputs:
  input:
    type: file
    format: [fastq, fastq.gz]
    required: true
    description: "Input FASTQ file"

outputs:
  html:
    type: file
    format: html
    description: "FastQC HTML report"
  zip:
    type: file
    format: zip
    description: "FastQC zip output"

# 官方模块的执行说明/规则模板
execution:
  mode: snakemake_rule
  rule_template: |
    rule fastqc:
        input:
            "{sample}.fastq.gz"
        output:
            html="qc/{sample}_fastqc.html",
            zip="qc/{sample}_fastqc.zip"
        threads: 4
        resources:
            mem_mb=8192
        wrapper:
            "v3.13.0/bio/fastqc"
```

### 2. 官方现有模块说明示例 (`fastqc/official_nfcore/meta.yaml`)

YAML

```
id: fastqc_official_nfcore
version: "2.1.0"
software: fastqc
type: nfcore_module
source_type: official            # 标识为官方现有模块

source_reference:
  repository: "https://github.com/nf-core/modules"
  module_name: "modules/nf-core/fastqc"

summary: "Official nf-core Process for FastQC."
agent_guidance:
  when_to_use: "Use when assembling modern Nextflow DSL2 pipelines targeting HPC or Cloud."

inputs:
  meta:
    type: map
    description: "Groovy map containing sample info, e.g., [ id:'sample1', single_end:false ]"
  reads:
    type: file
    format: [fastq.gz]
    description: "List of FASTQ files"

outputs:
  html:
    type: file
    format: html
  zip:
    type: file
    format: zip

execution:
  mode: nextflow_include
  include_statement: "include { FASTQC } from './modules/nf-core/fastqc/main'"
  container: "community.wave.seqera.io/library/fastqc:0.12.1--a5a415a7822c60e3"
```

### 3. 本地自定义 Native 模块示例 (`fastqc/native/meta.yaml`)

> **核心点**：`source_type: custom`，包含全量本地代码、构建文件与性能优化配置。

YAML

```
id: fastqc_native
version: "0.12.1-v1.0"
software: fastqc
type: native
source_type: custom              # 标识为自维护/自定义模块

summary: "Self-contained Native FastQC runner with automated memory & thread optimization."
agent_guidance:
  when_to_use: "Always execute directly when triggered by AI Agent Function Calls or Standalone Python/Shell CLI."
  recommendation_priority: "High (Primary execution target for non-pipeline engines)."

inputs:
  reads:
    type: file
    required: true
    cli_arg: "--input"
  threads:
    type: integer
    default: 4
    cli_arg: "--threads"

outputs:
  html_report:
    type: file
    format: html
    path_pattern: "{outdir}/{basename}_fastqc.html"

# 自定义模块独有的本地配方与优化
environment:
  conda: "environment.yml"
  dockerfile: "Dockerfile"
  apptainer_def: "Apptainer.def"

optimization:
  default_cpus: 4
  default_mem_mb: 8192
  env_vars:
    JAVA_OPTS: "-Xmx6g -Djava.io.tmpdir={tmpdir}"

execution:
  entrypoint: "python main.py"
  test_command: "bash test/run_test.sh"
```

## 五、 Agent 路由与工具选择逻辑

当注册表同时包含**官方现有模块说明**和**本地自定义 Native 实现**时，AI Agent 通过以下逻辑完成智能化调用：

```
                              [ 用户/Agent 调起技能请求 ]
                                           │
                                  是否属于流程引擎上下文？
                                ┌──────────┴──────────┐
                             (是)                    (否)
                              │                       │
                 目标流程语言是什么？          优先调用 Native 自定义技能
               ┌──────────────┴──────────────┐ (skills/<tool>/native/main.py)
            (Nextflow)                  (Snakemake)
               │                             │
    检查 official_nfcore           检查 official_snakemake
       是否存在？                     是否存在？
      ┌────┴────┐                    ┌────┴────┐
     (是)      (否)                 (顺)      (否)
      │         │                    │         │
 嵌入官方   降级使用           嵌入官方   降级使用
 nf-core    Native 封装         wrapper    Native 封装
```

## 六、 规范化实施步骤与里程碑

### 实施步骤

1. **阶段 1：基础搭建与 CLI 规范（1-2 周）**
   - 创建目录结构并实现 `skill-cli` 校验脚本，支持识别 `source_type: official` 与 `source_type: custom`。
   - 完成 8-12 个核心原子软件的 `native/` 自定义构建，同时在同级目录建立 `official_nfcore/` 与 `official_snakemake/` 的说明与 Schema 挂载。
2. **阶段 2：复合技能沉淀与 CI/CD 测试（2 周）**
   - 在 `custom/` 下建立复合小流程，演示如何既能串联本地 Native 技能，也能自动生成 Snakemake / Nextflow 语法调用官方模块。
   - 配置自动化回归测试（仅测试 `custom` 类型的 Native 代码）。
3. **阶段 3：动态 Registry 生成与 Agent 接入（长期）**
   - 自动扫描所有目录下的 `meta.yaml` 生成全局 `registry.yaml`。
   - 导出 JSON Schema 挂载至大模型 Agent 框架，实现单步与流程级自动路由。