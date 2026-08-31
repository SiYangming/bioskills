# bioskills — Bioinformatics Skill Library

以**软件/工具为中心**的自动化生信技能库。高度自包含、标准化解耦，**同时原生支持人类工程师手动调用与大模型 / AI Agent 自动编排**。

## 核心特性

| 特性 | 说明 |
|------|------|
| **双源并存架构** | 官方成熟模块（nf-core/modules、snakemake-wrappers）以「说明 + Schema + 引用」挂载；缺失/自定义模块在 `native/` 下自包含构建 |
| **双层归档** | 原子技能按软件归档（`skills/<software>/`）；复合流程归档于 `skills/custom/<flow>/` |
| **零外部网络依赖** | 自定义模块的代码、容器配方（Dockerfile/Apptainer.def）、Conda 环境、测试数据、Schema **全部本地化** |
| **软件版本差异透明** | 每个软件的 `meta.yaml.software_versions` 字段**显式声明** native / nf-core / snakemake-wrappers 三路之间的版本差与构建路线 |
| **apt 默认路线 & 容器最小化** | 容器统一使用 `debian:bookworm-slim + apt --no-install-recommends + 清理四连`（见「环境配方」小节），禁止默认引入 miniconda |
| **官方 submodules 目录严格对齐** | nf-core / snakemake-wrappers 的 `submodules[]` 必须抓在线目录更新，避免本地漏子模块导致 Agent 路由失效 |
| **内置性能优化** | 线程调度、内存上限、I/O 管道化、临时目录清理统一配置并自动传参 |
| **双模调用兼容** | 既可作为独立 CLI 运行，也可作为 JSON-Schema 驱动的 Function Calling / Tool Definition 供 Agent 解析 |

## 快速开始

```bash
# 0. 环境：建议 Python 3.11+；原生非容器运行请自行 apt/Conda 装软件，或使用 skills/<tool>/native/ 下的 Docker/Apptainer。
#    Docker 示例命令默认带 -u $(id -u):$(id -g)，避免输出文件属主污染。

# 1. 查看已登记的技能与实现（registry.yaml）
cat skills/registry.yaml

# 2. 校验 5 个实现目录（validate 详情 & 错误项 → AGENT.md §8 → ARCHITECTURE.md 第四节）
python skills/bin/skill-cli validate skills/fastqc/native
python skills/bin/skill-cli validate skills/fastqc/nextflow/nf-core
python skills/bin/skill-cli validate skills/fastqc/nextflow/local
python skills/bin/skill-cli validate skills/fastqc/snakemake/snakemake-wrappers
python skills/bin/skill-cli validate skills/fastqc/snakemake/local

# 3. 为 native 实现导出 JSON Schema（供 Agent 挂载 Function Calling / Tool Definition）
python skills/bin/skill-cli schema skills/fastqc/native/meta.yaml
# 官方说明层同样可导出（nf-core / snakemake-wrappers 的 meta.yaml）
python skills/bin/skill-cli schema skills/fastqc/nextflow/nf-core/meta.yaml

# 4. 直接调用 native 技能（要求宿主机具备 fastqc；若缺则用 docker run，例：）
python skills/bin/skill-cli run samtools -- flagstat /path/to/sorted.bam
# docker run --rm -u $(id -u):$(id -g) -v "$PWD":/work -w /work bioskills/samtools:1.21  flagstat sorted.bam

# 5. 重新扫描整个 skills/ 目录，重建全局 registry.yaml（新增/改动软件后必做）
python skills/bin/skill-cli scan
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
└── skills/
    ├── base.py                  # Skill Runner 基类 + Schema 导出 + 资源探测
    ├── registry.yaml            # 技能注册表（skill-cli scan 自动生成）
    ├── bin/skill-cli            # 管理 CLI：validate / scan / schema / run
    ├── custom/                  # 【复合流程】多软件小流程（Composite Skills）
    │   └── dna_seq_align_qc/    # 示例：fastp + bwa + samtools
    ├── samtools/                # 【原子技能】samtools
    │   ├── meta.yaml            # 软件级总览
    │   ├── native/              # 自包含实现（最高优先级）
    │   ├── nextflow/
    │   │   ├── nf-core/         # 官方 nf-core/modules 说明（不重写源码）
    │   │   └── local/           # 自定义 Nextflow 模块占位
    │   └── snakemake/
    │       ├── snakemake-wrappers/  # 官方 snakemake-wrappers 说明
    │       └── local/               # 自定义 Snakemake rule 占位
    └── fastqc/                  # 更多原子技能…
```

## 实现优先级与路由

上层 Agent / 流程引擎按以下规则决策（按实现优先级降序）：

```
是否属于流程引擎上下文？
├─ 是 → 目标语言？
│       ├─ Nextflow  → nextflow/nf-core（官方）→ nextflow/local（自定义）→ native
│       └─ Snakemake → snakemake/snakemake-wrappers → snakemake/local → native
└─ 否（Agent / 独立 CLI）→ native（最高优先级）
```

> 所有官方实现目录只包含**说明 + Schema + 引用信息**，不重写 nf-core / snakemake-wrappers 的实际源码。

## 新增一个软件？

请阅读 [AGENT.md](AGENT.md) 与 [ARCHITECTURE.md](ARCHITECTURE.md)。它们包含：
- 完整命名约定与字段规范
- `native/main.py` 构建契约
- 官方模块三件套契约（submodules 抓官方目录、README 强提示、software_versions 对齐 conda pin）
- 测试与**环境配方默认路线（apt + bookworm-slim + 清理四连）**
- 校验流程 + **新增软件 Checklist**（含 software_versions / apt / submodules 三条硬性检查）

> ⚙️ **新增软件自动化 Skill（推荐）**：本仓库在 TRAE 会话中打开时会自动挂载「bioskills-package-standardizer」Skill（本地路径 `.trae/skills/bioskills-package-standardizer/SKILL.md`，**不入库**），
> 等价的标准清单见 [AGENT.md §10 新增软件 Checklist](AGENT.md#10-新增软件检查清单checklist) 与 [ARCHITECTURE.md §六.3 验收工具链](ARCHITECTURE.md#六-规范化实施步骤与里程碑)。

参考黄金样例 `skills/samtools/`（三引擎五实现完整对照 + apt 最小化 + software_versions 差异声明）。
参考第二个完整样例 `skills/fastqc/`（apt JVM + Babraham 官方 zip 路线示范、单 process / 单 wrapper 的 submodules 占位写法）。
参考复合流程骨架 [skills/custom/dna_seq_align_qc/README.md](skills/custom/dna_seq_align_qc/README.md)（多软件 stages 声明、`--dry-run`/`--list-stages` 编排器、Snakefile / Nextflow 模板）及目录说明 [skills/custom/README.md](skills/custom/README.md)。

## 构建规范

| 层 | 规范 |
|----|------|
| 软件目录名（canonical） | Debian 仓库名优先；全小写，`-` 分词。例：`samtools` / `fastqc` / `bwa-mem2`（不要 `bwa_mem2` / `bwa2`）。 |
| 实现 ID 命名 | `<software>_<impl>` 严格 5 类：`fastqc_native` / `fastqc_nextflow_nfcore` / `fastqc_nextflow_local` / `fastqc_snakemake_wrappers` / `fastqc_snakemake_local` |
| `source_type` | `official`（说明层，不重写源码）或 `custom`（自实现） |
| `type` | 5 枚举之一：`native` / `nextflow_nfcore` / `nextflow_local` / `snakemake_wrappers` / `snakemake_local` |
| **软件级 software_versions（必填）** | 在 `skills/<tool>/meta.yaml` 声明 native / nf-core / snakemake-wrappers / local 四路的版本差异与构建路线；用于跨引擎路由冲突检测。 |
| **实现级 software_versions（必填）** | 在每个 `<impl>/meta.yaml` 写清「该实现真正会跑的二进制版本 + 来源」，不要与软件级总览重复。 |
| **官方 submodules 对齐** | `nextflow/nf-core` → 与 `modules/nf-core/<tool>/` 目录 1:1；`snakemake/snakemake-wrappers` → 与 `bio/<tool>/` 目录 1:1。抓目录命令见 ARCHITECTURE.md §3.2。单 process/wrapper 也保留 1 条占位。 |
| **Dockerfile 路线** | 默认 `FROM debian:bookworm-slim` + `apt-get install -y --no-install-recommends <pkgs>` + `autoremove/clean/rm apt lists tmp` + 构建期工具 purge；Docker 示例写 `-u $(id -u):$(id -g)`。禁止默认 miniconda。 |
| **Apptainer.def 路线** | `Bootstrap: docker; From: debian:bookworm-slim`；`%post` 同 apt 四连；`%test` 至少断言 `<binary> --version` 的目标版本号。 |

### 环境配方（apt 默认路线速查）

```
1. 首选 apt：deb.debian.org bookworm 能装 → apt pin 版本号（如 samtools=1.21-1）。
2. bookworm 版不够新 → 启用 bookworm-backports，仍走 apt。
3. apt/backports 都没有 → apt 只装运行时依赖（openjdk/perl/libz1/…）+ 官方二进制 zip/tar.bz2 直接布署到 /opt/（如 fastqc=0.12.1）。
4. 以上都走不通 → 允许 bioconda，但必须在 software_versions.native.note 写明「为什么不满足前三条」。

以上每步均执行：apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*，并在构建末尾 purge 仅用于下载的 curl/wget 等。
```

### 版本差异写法示例

```yaml
# skills/fastqc/meta.yaml ← 软件级
software_versions:
  native:
    fastqc: "0.12.1"
    build_route: "apt (openjdk-17) + babraham zip"
    source: "https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.12.1.zip"
    note: "bookworm apt 无 fastqc，故走官方 zip；JVM 版本与 nf-core 同路线。"
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
> `Software-centric bioinformatics skill library — 标准化生信技能库。双引擎（Nextflow + Snakemake）× 三路线（nf-core / snakemake-wrappers / 自包含 Native），apt 最小化容器，JSON-Schema 原生支持 AI Agent 编排。`

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

MIT — 详见 [LICENSE](LICENSE)。
