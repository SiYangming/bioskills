# bioskills — Bioinformatics Skill Library

以**软件/工具为中心**的自动化生信技能库。高度自包含、标准化解耦，**同时原生支持人类工程师手动调用与大模型 / AI Agent 自动编排**。

## 核心特性

| 特性 | 说明 |
|------|------|
| **双源并存架构** | 官方成熟模块（nf-core/modules、snakemake-wrappers）以「说明 + Schema + 引用」挂载；缺失/自定义模块在 `native/` 下自包含构建 |
| **双层归档** | 原子技能按软件归档（`modules/<software>/`）；复合流程归档于 `workflow/` 根级文档（`<flow>.md`/`.yaml`）或目录（含经典 native 时），常用组合放 `subworkflow/<组合名>.md`/`.yaml` |
| **指令层按需拉取（skills/）** | 与 `modules/` 并列的第二层：上游 [awesome-bio-agent-skills](https://github.com/BioTender-max/awesome-bio-agent-skills) 的 1,705 个技能（16 分类 / 21 来源目录）。**索引常驻入库（0.81 MB）、正文按需拉取**——全量技能离线可检索，`skill-cli add` 才把正文落盘。**实现层管「怎么跑」，指令层管「怎么用」**；三层模型与同步流程见 [ARCHITECTURE.md §七](ARCHITECTURE.md#七-skills-指令层索引常驻与按需拉取) |
| **零外部网络依赖** | 自定义模块的代码 / 测试 / Schema 仍**全部本地化**；工具环境改走**官方镜像优先**（bioconda → quay.io/biocontainers → depot.galaxyproject.org，官方已有即登记、不本地内置容器配方），查无官方才自建 apt 最小化镜像 |
| **软件版本差异透明** | 每个软件的 `meta.yaml.software_versions` 字段**显式声明** native / nf-core / snakemake-wrappers 三路之间的版本差与构建路线 |
| **官方镜像优先 & 自建兜底** | 官方已有（bioconda → quay.io/biocontainers → depot.galaxyproject.org 任一）→ 不维护 Dockerfile/Apptainer.def，meta.yaml 登记 `container_official` + `build_route=official biocontainer`，README 登记官方镜像/tag；查无官方（如 gstama / orfanage / dorado / gnu_sort / gunzip）→ 才自建 `debian:bookworm-slim + apt --no-install-recommends + 清理四连` 最小化镜像；docker run 必须带 `-u $(id -u):$(id -g)`（见「环境路线」小节） |
| **官方 submodules 目录严格对齐** | nf-core / snakemake-wrappers 的 `submodules[]` 必须抓在线目录更新，避免本地漏子模块导致 Agent 路由失效 |
| **内置性能优化** | 线程调度、内存上限、I/O 管道化、临时目录清理统一配置并自动传参 |
| **双模调用兼容** | 既可作为独立 CLI 运行，也可作为 JSON-Schema 驱动的 Function Calling / Tool Definition 供 Agent 解析 |

## 快速开始

```bash
# 0. 环境：建议 Python 3.11+。原生运行 native main.py 需先在宿主机/conda（mamba）装好对应工具，
#    或直接 docker run 官方镜像跑工具本体（quay.io/biocontainers/<tool>，tag 见 modules/<tool>/README.md）。
#    Docker 示例命令必须带 -u $(id -u):$(id -g)，避免输出文件属主污染。

# 1. 查看已登记的技能与实现（registry.yaml）
cat modules/registry.yaml

# 2. 校验软件（单合并 meta：modules/<sw>/meta.yaml；validate 自动检查各实现目录）
python modules/bin/skill-cli validate modules/fastqc
python modules/bin/skill-cli validate modules/samtools

# 3. 为软件导出 JSON Schema（供 Agent 挂载 Function Calling / Tool Definition）
python modules/bin/skill-cli schema modules/fastqc/meta.yaml

# 4. 直接调用 native 技能（要求宿主机已装 samtools；缺工具可改用官方镜像直跑，例：）
python modules/bin/skill-cli run samtools -- flagstat /path/to/sorted.bam
# docker run --rm -u $(id -u):$(id -g) -v "$PWD":/work -w /work \
#   quay.io/biocontainers/samtools:<tag>  flagstat sorted.bam   # <tag> 见 modules/samtools/README.md

# 5. 重新扫描整个 modules/ 目录，重建全局 registry.yaml（新增/改动软件后必做）
python modules/bin/skill-cli scan
```

> 对应规范链接：
> - `skill-cli validate` 硬性检查 → [AGENT.md §8](AGENT.md#8-校验与注册流程每次新增改动后必做)
> - `skill-cli scan` 注册表扫描 → [ARCHITECTURE.md §六.3](ARCHITECTURE.md#六-规范化实施步骤与里程碑)
> - 新增软件 Checklist → [AGENT.md §10](AGENT.md#10-新增软件检查清单checklist)

## 目录结构

```
bioskills/
├── AGENT.md                     # 技能构建规范 / 新增软件 Checklist
├── ARCHITECTURE.md              # 架构总览（原 blue_plan.md）
├── LICENSE                      # MIT
├── README.md                    # 本文件
├── .gitignore
├── modules/
    ├── base.py                  # Skill Runner 基类 + Schema 导出 + 资源探测
    ├── registry.yaml            # 技能注册表（skill-cli scan 自动生成）
    ├── bin/skill-cli            # 管理 CLI：validate / scan / schema / run
    ├── samtools/                # 【原子技能】samtools
    │   ├── meta.yaml            # 软件级总览（实现 + 容器/conda/github 链接）
    │   ├── native/              # 自包含实现（最高优先级，经典脚本直接放 native/）
    │   ├── nextflow/            # 有实际 Nextflow 实现才建（单层，官方信息记录 README）
    │   └── snakemake/           # 有实际 Snakemake 规则才建（单层，官方信息记录 README）
    └── fastqc/                  # 更多原子技能…
├── workflow/                    # 【复合流程】完整流程（workflow/ 下 nanoseq/、isoseq/、riboseq/ 目录形态；轻量流程才根级 md+yaml）
├── scripts/                     # 通用 shell 工具（run_smk.sh 流程执行入口、run_bg.sh daemon 管理等共享脚本）
├── subworkflow/                 # 【复合流程】常用软件组合（fastp_bwa_samtools/ 目录形态等）
└── skills/                      # 【指令层】索引常驻 + 内容按需（入库 0.81 MB / 1,705 个技能）
    ├── index/                   #   [索引层·入库] 全量技能索引，离线可检索
    │   ├── bioskill_index_v3.csv  #     上游原样索引（1,676 行，含 description / category）
    │   └── skill_meta.csv         #     本仓派生（primary_tool / tool_type，跨层匹配依据）
    ├── lock.yaml                #   [登记层·入库] 已拉取技能的 tree-hash + 上游 commit
    ├── ROADMAP.md               #   7 条分析场景路线图
    ├── LICENSE                  #   上游汇编层 CC0
    ├── assets/banner.svg
    └── <source>/<skill>/        #   [内容层·不入库] 由 skill-cli add 按需拉取
```

> **目录构建规则（workflow / subworkflow / modules 通用）**：官方已有的流程/软件实现（nf-core 流程、nf-core modules、snakemake-wrappers）**不单独建目录**，信息并入对应 README / meta.yaml 登记（`source_type: official` + 官方仓库/submodules/版本差异 + 强提示）；**只有官方没有的自定义实现才建目录**（`source_type: custom`）。例：nf-core/riboseq 官方已有 → `workflow/riboseq` 不再建 `nextflow/` 目录只登记引用；本地自定义 Snakemake 重构保留 `snakemake/`。

## 实现优先级与路由

上层 Agent / 流程引擎按以下规则决策（按实现优先级降序）：

```
是否属于流程引擎上下文？
├─ 是 → 目标语言？
│       ├─ Nextflow  → nextflow/nf-core（官方）→ nextflow/local（自定义）→ native
│       └─ Snakemake → snakemake/snakemake-wrappers → snakemake/local → native
└─ 否（Agent / 独立 CLI）→ native（最高优先级）
```

> **官方已有实现一律不建目录**：只把说明 + Schema + 引用登记到流程/软件 README 与 meta.yaml（`source_type: official`）；本地自定义实现（`source_type: custom`）才建目录并写源码。

## skills/ 指令层（怎么用）

`skills/` 是与 `modules/` **并列的第二层**，面向 Claude 系 Agent 框架（OpenClaw / NanoClaw / Biomni 等）。采用**索引常驻 + 内容按需**：仓库里常驻全量索引（0.81 MB），技能正文按需拉取、不入库。

```bash
# 1. 离线检索（读 skills/index/，不需要技能正文，也不需要网络）
python modules/bin/skill-cli search "variant calling"

# 2. 按需拉取正文到本地（从 .cache/ 上游 mirror 抽取，并登记 skills/lock.yaml）
python modules/bin/skill-cli add bioskills/gatk-variant-calling

# 3. 校验已拉取内容（正文缺失 / 本地改动 / 上游更新）
python modules/bin/skill-cli verify

# 4. 跨层索引：同一软件的「怎么跑」(modules/) 与「怎么用」(skills/) 关联
python modules/bin/skill-cli link    # 产出 modules/link_map.yaml
```

首次运行 `add` 会自动建上游 mirror（`.cache/`，不入库）；拉取过的技能之后可离线复用。

| 关注点 | 去哪里看 |
|---|---|
| 上游来源、基线 commit、三层模型、裁剪规则 | [ARCHITECTURE.md §七](ARCHITECTURE.md#七-skills-指令层索引常驻与按需拉取) |
| 22 个来源仓库明细与各自技能数 | ARCHITECTURE.md §7.3（该表已内联） |
| 上游更新后如何同步（含可执行命令） | ARCHITECTURE.md §7.6 |
| 跨层索引的匹配规则与置信度分档 | ARCHITECTURE.md §7.7（产出：`modules/link_map.yaml`） |
| 后续扩展方向（场景对接、README 回填、反向补全） | ARCHITECTURE.md §7.8 |

> ⚠️ **许可证提示**：上游汇编层为 CC0，但各技能自带许可证（19 个目录有独立 `LICENSE`）；`openclaw` 来源下 148 个 `SKILL.md` 带「proprietary and confidential」声明且与 frontmatter 的 MIT 矛盾，**再分发或商用前须逐一核实**。详见 ARCHITECTURE.md §7.5。

## 新增一个软件？

请阅读 [AGENT.md](AGENT.md) 与 [ARCHITECTURE.md](ARCHITECTURE.md)。它们包含：
- 完整命名约定与字段规范
- `native/main.py` 构建契约
- 官方模块三件套契约（submodules 抓官方目录、README 强提示、software_versions 对齐 conda pin）
- 测试与**环境路线（官方镜像优先；查无官方才自建 apt 最小化：bookworm-slim + 清理四连）**
- 校验流程 + **新增软件 Checklist**（含 software_versions / container_official 登记（查无官方时改自建配方）/ submodules 三条硬性检查）

> ⚙️ **新增软件自动化 Skill（推荐）**：本仓库在 TRAE 会话中打开时会自动挂载「bioskills-package-standardizer」Skill（本地路径 `.trae/modules/bioskills-package-standardizer/SKILL.md`，**不入库**），
> 等价的标准清单见 [AGENT.md §10 新增软件 Checklist](AGENT.md#10-新增软件检查清单checklist) 与 [ARCHITECTURE.md §六.3 验收工具链](ARCHITECTURE.md#六-规范化实施步骤与里程碑)。

参考黄金样例 `modules/samtools/`（三引擎五实现完整对照 + 官方镜像优先登记 + software_versions 差异声明）。
参考第二个完整样例 `modules/fastqc/`（官方镜像路线登记示范：environment.container_official + build_route=official biocontainer；单 process / 单 wrapper 的 submodules 占位写法）。
参考复合流程骨架 [subworkflow/fastp_bwa_samtools/](subworkflow/fastp_bwa_samtools/fastp_bwa_samtools.md)（多软件 stages 声明、native/main.py 编排入口；Snakemake / Nextflow 骨架要点见其文档）及目录说明 [AGENT.md](AGENT.md)。

## 构建规范

| 层 | 规范 |
|----|------|
| 软件目录名（canonical） | Debian 仓库名优先；全小写，`-` 分词。例：`samtools` / `fastqc` / `bwa-mem2`（不要 `bwa_mem2` / `bwa2`）。 |
| 实现 ID 命名 | `<software>_<impl>` 严格 5 类：`fastqc_native` / `fastqc_nextflow_nfcore` / `fastqc_nextflow_local` / `fastqc_snakemake_wrappers` / `fastqc_snakemake_local` |
| `source_type` | `official`（说明层，不重写源码）或 `custom`（自实现） |
| `type` | 5 枚举之一：`native` / `nextflow_nfcore` / `nextflow_local` / `snakemake_wrappers` / `snakemake_local` |
| **软件级 software_versions（必填）** | 在 `modules/<tool>/meta.yaml` 声明 native / nf-core / snakemake-wrappers / local 四路的版本差异与构建路线；用于跨引擎路由冲突检测。 |
| **实现级 software_versions（必填）** | 在每个 `<impl>/meta.yaml` 写清「该实现真正会跑的二进制版本 + 来源」，不要与软件级总览重复。 |
| **官方 submodules 对齐** | `nextflow/nf-core` → 与 `modules/nf-core/<tool>/` 目录 1:1；`snakemake/snakemake-wrappers` → 与 `bio/<tool>/` 目录 1:1。抓目录命令见 ARCHITECTURE.md §3.2。单 process/wrapper 也保留 1 条占位。 |
| **Dockerfile 路线（可选）** | **仅查无官方镜像时提供**（自建兜底，如 gstama/orfanage/dorado/gnu_sort/gunzip）：`FROM debian:bookworm-slim` + `apt-get install -y --no-install-recommends <pkgs>` + `autoremove/clean/rm apt lists tmp` + 构建期工具 purge；Docker 示例写 `-u $(id -u):$(id -g)`。禁止默认 miniconda。官方已有镜像 → 不写 Dockerfile，登记 container_official。 |
| **Apptainer.def 路线（可选）** | **仅查无官方镜像时提供**（自建兜底）：`Bootstrap: docker; From: debian:bookworm-slim`；`%post` 同 apt 四连；`%test` 至少断言 `<binary> --version` 的目标版本号。 |

### 环境路线（官方镜像优先速查）

```
官方镜像优先（default）：凡软件在 bioconda → quay.io/biocontainers → depot.galaxyproject.org
任一有官方维护 → native/ 不维护 Dockerfile/Apptainer.def；meta.yaml 登记
environment.container_official + software_versions.native.build_route=official biocontainer，
README 登记官方镜像及 tag；native main.py 在宿主机运行（conda/mamba 装工具）或 docker run 官方镜像直跑工具。

仅当查无官方维护（目前如 gstama / orfanage / dorado / gnu_sort / gunzip；dorado 官方仅 GitHub 二进制）
才自建：debian:bookworm-slim + apt-get install -y --no-install-recommends + 清理四连
（apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*）+ 构建末尾
purge 仅用于下载/构建的 curl/wget/dpkg-dev。

版本断言：仅自建路线必填（版本号与 software_versions 对齐）；官方路线以登记的官方镜像 tag 为准。
docker run 一律带 -u $(id -u):$(id -g)。
```

### 版本差异写法示例

```yaml
# modules/fastqc/meta.yaml ← 软件级（官方镜像优先路线示例；同文件 environment.container_official 登记 quay.io/biocontainers/fastqc）
software_versions:
  native:
    fastqc: "0.12.1"
    build_route: "official biocontainer（quay.io/biocontainers/fastqc / depot.galaxyproject.org）"
    source: "https://anaconda.org/bioconda/fastqc"
    note: "官方镜像优先：bioconda → quay.io/biocontainers → depot.galaxyproject.org 有官方维护，native/ 不维护容器配方；镜像/tag 以 environment.container_official 与 README 登记为准。"
  nextflow_nfcore:
    fastqc: "0.12.1"
    module_version: "2.1.0"
    source: "bioconda::fastqc=0.12.1"
  snakemake_wrappers:
    fastqc: "0.12.1"
    wrapper_tag: "v3.13.0"
    source: "bio/fastqc/environment.yaml"
```

## GitHub 仓库 Description / Topics 建议（精简核心组）

> 建议（Description）：
> `Software-centric bioinformatics skill library — 标准化生信技能库。双引擎（Nextflow + Snakemake）× 三路线（nf-core / snakemake-wrappers / 自包含 Native），官方镜像优先 + apt 自建兜底，JSON-Schema 原生支持 AI Agent 编排。`

> 建议（Topics，约 12 个核心词；避免 nextflow-pipeline vs nextflow-pipelines 重复）：
```
bioinformatics
nextflow
snakemake
nf-core
pipeline
workflow
workflow-automation
ai-agent
tool-calling
docker
apptainer
samtools
fastqc
```

## License

本仓自建部分（`modules/` / `workflow/` / `subworkflow/` / `scripts/`）为 MIT — 详见 [LICENSE](LICENSE)。

`skills/` 为**上游第三方内容**，遵循其各自许可证，不适用本仓 MIT：上游汇编层为 CC0 1.0，各技能自带许可证（19 个目录含独立 `LICENSE`，随 `skill-cli add` 一并落盘），且 `openclaw` 来源下 148 个 `SKILL.md` 存在「proprietary and confidential」声明与 MIT frontmatter 冲突的遗留问题。**再分发或商用前须逐一核实**，详见 [ARCHITECTURE.md §7.5](ARCHITECTURE.md#75-许可证与合规提示)。
