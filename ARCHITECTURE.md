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
   - **原子技能（Atomic Skill）**：顶级目录按照软件 Canonical Name 命名，规范统一小写（如 `samtools`, `bwa-mem2`, `fastqc`）。命名优先级：Debian 仓库名 > nf-core/modules 目录名 > Bioconda 名；冲突时在 meta.yaml 写清别名。
   - **复合流程（Composite Workflow）**：涉及多软件串联的流程统一归档在 `workflow/`（完整流程）与 `subworkflow/`（常用组合）下，与 `modules/` 平级。
2. **官方现有模块与自定义构建双轨制（Hybrid Sourcing Strategy）**：
   - **官方现有（Official-Annotated）**：对 `nf-core/modules` 或 `snakemake-wrappers` 中已有的成熟模块，在本地**只保留说明文档、校验 Schema、标准接口描述 (meta.yaml + 三件套)**，注明引用仓库与官方子模块清单，**不重写源码**。
   - **本地自定义（Custom-Native）**：官方缺少、或有特殊优化需求的模块，在 `native/` 目录下提供自包含构建（`main.py` + `Dockerfile`/`Apptainer.def`/`environment.yml` + `test/`）。
3. **环境配方与性能优化内嵌（apt 默认路线）**：
   - Native 容器**默认使用 `debian:bookworm-slim + apt --no-install-recommends`**；软件本体不在 apt/backports 时才退化到「apt 装运行时依赖 + 官方二进制/官方源码」，**禁止默认引入 miniconda**。
   - 驱动层（`main.py`）必须处理线程调度、内存上限、流管道化、临时目录挂载与清理。
4. **统一元数据抽象（Unified Metadata Layer）**：无论是官方包装模块还是本地自定义模块，对外都暴露一致的 `meta.yaml` Schema + `software_versions{}` 差异声明，保证 Agent 路由与版本核对零歧义。
5. **官方子模块「目录严格对齐」原则**：
   - `nextflow/nf-core/meta.yaml` 的 `source_reference.submodules[]` 必须与官方 `modules/nf-core/<tool>/` 在线目录严格一致。
   - `snakemake/snakemake-wrappers/meta.yaml` 的 `submodules[]` 必须与官方 `bio/<tool>/` 在线目录严格一致。

---

## 三、 完整目录结构规范

> **已重构目录名**：本节目录已对齐 AGENT.md §1 的 5 类 type 枚举。
> `official_nfcore/` / `official_snakemake/` 旧目录名废弃，统一改为 `nextflow/nf-core` / `nextflow/local` / `snakemake/snakemake-wrappers` / `snakemake/local`。

```
modules/
├── registry.yaml                # 动态生成的注册表索引缓存（整合 Native 与 官方 Wrapper）
├── base.py                      # Python Skill Runner 基类与 JSON Schema 导出工具
├── bin/                         # 技能库 CLI 管理工具（skill-cli validate / scan / schema / run）
│
├── fastqc/                      # 【原子技能】软件归档主目录（canonical = bioconda/nf-core/Debian 统一名）
│   ├── meta.yaml                # 软件级总览：implementations[5] 按优先级 + default_implementation + software_versions
│   │
│   ├── native/                  # [自定义/最高优先级] Native 自包含（source_type=custom, type=native）
│   │   ├── meta.yaml            # Schema + software_versions + environment + optimization + execution
│   │   ├── main.py              # 标准入口驱动（参数校验 + 线程/内存/临时目录自动传参）
│   │   ├── environment.yml      # Conda 环境（保留，离线 / 非容器场景备选）
│   │   ├── Dockerfile           # Docker：debian:bookworm-slim + apt 默认路线 + 清理四连
│   │   ├── Apptainer.def        # Apptainer：同一 apt 默认路线 + %test 版本号断言
│   │   ├── test/                # 最小自动化回归（generate_data.py + run_test.sh）
│   │   └── README.md
│   │
│   ├── nextflow/
│   │   ├── nf-core/             # [官方说明] nextflow_nfcore（source_type=official）
│   │   │   ├── meta.yaml        #   submodules[] 与 modules/nf-core/<tool>/ 目录严格对齐 + software_versions
│   │   │   ├── module.json      #   上游仓库映射 + pinned commit + install_command
│   │   │   └── README.md        #   顶部强提示：仅说明层 / 真正执行需 nf modules install
│   │   └── local/               # [自定义] nextflow_local（source_type=custom）
│   │       ├── meta.yaml        #   未启用时 version="" 占位
│   │       └── README.md
│   │
│   └── snakemake/
│       ├── snakemake-wrappers/  # [官方说明] snakemake_wrappers（source_type=official）
│       │   ├── meta.yaml        #   submodules[] 与 bio/<tool>/ 目录严格对齐 + software_versions
│       │   ├── wrapper.py       #   本地桥接（不做官方源码重分发）
│       │   └── README.md        #   顶部强提示：仅说明层 / 真正执行靠 Snakemake 运行时 wrapper: 句柄
│       └── local/               # [自定义] snakemake_local（source_type=custom）
│           ├── meta.yaml
│           └── README.md
│
├── samtools/                    # 【黄金样例】submodules 抓官方目录 + software_versions 三方差异声明 + apt 最小化
│   └── ...
├── bwa-mem2/                    # canonical 示例：Debian/Bioconda 统一 "bwa-mem2"，避免 bwa_mem2/bwa2 别名
│   └── ...
├── custom_tool_x/               # 官方不存在的全新自定义软件；仍保留 5 路目录（local/可占位）
│   └── ...
```

```
workflow/                         # 【复合流程层】完整流程，与 modules/ 平级；可引用 subworkflow 与原子模块
├── nanoseq/                      # 例：Nanopore RNA-seq（SRA/dorado -> minimap2 -> samtools -> FLAIR -> StringTie -> ORF）
├── isoseq/                       # 例：PacBio Iso-Seq（CCS -> Lima -> Refine -> GSTAMA）
└── flrnaseq/                     # 例：全长 RNA-seq ORF 预测（TransDecoder -> TD2 -> ORFfinder）

subworkflow/                      # 【复合流程层】常用软件组合：可复用小流程，供 workflow 引用或独立调用
└── fastp_bwa_samtools/           # 例：Fastp + BWA + Samtools 基因组比对与质控链
```

> workflow/ 与 subworkflow/ 为复合流程层（编排器 + workflow_skeleton 模板 + legacy/testdata），
> 与 modules/（原子技能）平级，不参与 skill-cli scan/validate。

### 3.1 canonical 目录名（示例）

| 软件（俗称）   | canonical（`modules/<canonical>/`） | 说明 |
|---|---|---|
| Samtools       | `samtools`         | Debian / Bioconda / nf-core / snakemake-wrappers 完全一致 |
| FastQC         | `fastqc`           | Bioconda `fastqc` / Babraham zip 小写统一 |
| BWA-MEM2       | `bwa-mem2`         | Debian tracker / Bioconda 均写 hyphen；避免 `bwa_mem2` |
| Trim Galore!   | `trim-galore`      | Debian 仓库优先；Bioconda 是 `trim-galore` 还是 `trim_galore` 以官方 apt 为准 |
| BCFtools       | `bcftools`         | 官方无 hyphen |
| Picard         | `picard`           | nf-core `modules/nf-core/picard` 一致 |

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

---

## 四、 官方模块与自定义模块的元数据表达

区分官方模块 vs 自定义模块的关键在于：`source_type`（official / custom）、`type`（5 枚举）、`software_versions{}`（版本差异声明）以及 `execution` 段的执行模式。

> **本节 type 枚举已统一**：新版使用 `nextflow_nfcore` / `nextflow_local` / `snakemake_wrappers` / `snakemake_local` / `native`。
> 旧示例中出现的 `nfcore_module` / `snakemake_wrapper`（单数）/ `official_nfcore` / `official_snakemake` 目录与 id 名**已废弃**。

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

### 4.3 Native 自定义示例 (`fastqc/native/meta.yaml`)

> 核心：`source_type: custom`；默认 **apt + bookworm-slim** 路线；`software_versions.native` 写明「哪条安装路线 + 实际版本」。

```yaml
id: fastqc_native
version: "0.12.1-v1.0"
software: fastqc
type: native
source_type: custom

software_versions:
  fastqc: "0.12.1"
  java:   "openjdk-17-jre-headless (apt bookworm)"
  source: "https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.12.1.zip"
  note:   "bookworm apt 不提供 fastqc 二进制，故路线为 apt JVM + Babraham 官方 zip。版本与 Bioconda 对齐。"

environment:
  conda: "environment.yml"          # 保留（离线/非容器备选）
  dockerfile: "Dockerfile"          # debian:bookworm-slim + openjdk-17 + fastqc.zip → /opt/FastQC
  apptainer_def: "Apptainer.def"    # 同一 apt 路线 + %test 版本号 grep

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

### 4.4 环境配方默认路线（apt 最小化原则 · 架构级约束）

本节与 AGENT.md §7 一一对应，在此作架构层面再次约束。

| 要素             | 默认值 / 约束 | 例外 |
|---|---|---|
| 基础 OS 镜像      | `debian:bookworm-slim` | 若 bookworm apt 包版本不够新 → 可在 apt 内启用 `bookworm-backports`；仍必须走 apt，不要直接换基础镜像。 |
| 包管理器路线       | `apt-get install --no-install-recommends` 优先；软件本体缺再「apt 运行时 + 官方二进制/源码」 | 只有当 apt + backports + 官方二进制/源码 三条路全走不通时才允许写 bioconda，并在 `software_versions.native.note` 解释原因。 |
| 清理（四连，缺一不可） | `apt-get autoremove -y` + `apt-get clean` + `rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*` + 构建期工具（curl/wget/dpkg-dev） `purge` | — |
| Docker 运行示例   | `docker run --rm -u $(id -u):$(id -g) -v "$PWD":/work -w /work <image> <args>` | CI root 运行亦允许，但 README/AGENT.md 文档示例必须写 `-u` 参数，避免用户输出文件被 root 持有。 |
| Apptainer         | `Bootstrap: docker; From: debian:bookworm-slim`；`%post` 同 apt 路线；`%test` 必须断言 `<binary> --version` | — |
| `software_versions.native` 字段 | 必填 `build_route` 与 `source`（写清 `apt` / `apt + babraham zip` / `apt + github tarball` / `apt + 源码编译`） | 不要只写 "Conda/bioconda"，除非已显式走 bioconda。 |

---

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

关键决定点：`default_implementation` 永远指向 `_native`；在流程引擎上下文中，若 nextflow_nfcore / snakemake_wrappers 的 `software_versions` 与用户需求**不一致**（版本不匹配），亦直接降级 native 避免版本偏差。

---

## 六、 规范化实施步骤与里程碑

### 实施步骤

1. **阶段 1：基础搭建与 CLI 规范（1-2 周）**
   - 创建目录结构并实现 `skill-cli` 校验脚本，支持识别 5 种 `type` 枚举，以及 `source_type: official/custom` 分支校验。
   - 建立 `AGENT.md §10` 作为每次新增软件的 Checklist（含 `software_versions` / apt 最小化 / submodules 抓官方目录 / `-u` 参数等硬性检查项）。
   - 完成 8-12 个核心原子软件的 `native/` 自定义构建，同时在同级目录建立 `nextflow/nf-core/` / `snakemake/snakemake-wrappers/` 的说明层与 Schema 挂载，并补充 `nextflow/local` / `snakemake/local` 占位。
2. **阶段 2：复合技能沉淀与 CI/CD 测试（2 周）**
   - 在 `workflow/`（或 `subworkflow/`）下建立复合流程，演示「串联本地 Native 技能 + 为 Nextflow/Snakemake 自动生成调用代码」。
   - 配置自动化回归：覆盖 native `run_test.sh`、`skill-cli validate` 5 目录、`skill-cli scan` 产物完整性。
3. **阶段 3：动态 Registry 生成与 Agent 接入（长期）**
   - 自动扫描所有目录下的 `meta.yaml` 生成全局 `registry.yaml`，并按 `default_implementation` / `priority` 排序。
   - 导出 JSON Schema 挂载至 AI Agent；在路由逻辑中额外使用 `software_versions` 段做版本冲突拦截与提示。
