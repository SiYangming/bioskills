# workflow/ — 复合流程层索引与新建模板指南

本目录存放**复合流程（完整流程）**：面向特定领域的多软件串联流程，与 `modules/`（原子技能）、`scripts/`（通用工具）、`subworkflow/`（常用组合）平级。

workflow/ 层**不参与** `skill-cli scan/validate`。组织规则（详见 [AGENT.md §0](../AGENT.md)）：

- **官方已有流程不建目录**：nf-core 官方已有完整流程 → 不建 `nextflow/` 等目录，只在流程文档登记引用与差异；
- **流程文档命名 `<flow_name>.md`**（根级文档形态的元数据为 `<flow_name>.yaml`）；
- **目录内只剩文档 → 折叠到 workflow/ 根**：无代码资产的流程以 `workflow/<flow_name>.md` + `.yaml` 形式存放，不保留目录；
- **流程级 `native/`**：有上游大树时用 **git submodule**（如 `riboseq/native`、`snakemake-template/native`）；无大树时**可不建 native/**，只在流程 md 登记如何串联 `modules/<sw>/native/main.py`（如 `isoseq/`、`nanoseq/`）。批处理薄封装放在对应 **模块** `batch_*.sh`，不要流程级第二套 `run.sh`/`main.py`；
- **`snakemake/` 集成内容并入流程文档后移除**（工具规则仍存于 `modules/<sw>/snakemake/`，按需在项目内重建）。

## 现有流程

| 流程 | 形态 | 定位 |
|---|---|---|
| `nanoseq` | 根级 `nanoseq.md` + `nanoseq.yaml` | Nanopore RNA-seq：文档串联 modules（FLAIR/StringTie/TD2） |
| `isoseq` | 根级 `isoseq.md` + `isoseq.yaml` | PacBio Iso-Seq：文档串联 modules；批处理在各模块 `batch_*.sh` |
| `riboseq` | `riboseq/`（`riboseq.md` + `riboseq.yaml` + `native/` **git submodule** → [SiYangming/Ribo-seq](https://github.com/SiYangming/Ribo-seq)） | Ribo-seq / RPF + Total RNA-seq |
| `snakemake-template` | `snakemake-template/`（md + `meta.yaml` + `native/` **git submodule** → [snakemake-workflow-template](https://github.com/snakemake-workflows/snakemake-workflow-template)） | Snakemake 官方流程脚手架 |

## 新建流程模板的来源与方法

新建「官方不存在、需要自定义」的流程时，**先用官方模板生成骨架再改造**，不要从零手写。

### Nextflow：nf-core 官方工具生成（最推荐）

- 来源：nf-core 官方工具链 [nf-core/tools](https://github.com/nf-core/tools)（文档见 [nf-co.re](https://nf-co.re/tools/create)）
- 方法：

```bash
# 安装 nf-core 工具（Python）
pip install nf-core          # 或 conda install -c bioconda nf-core

# 生成新流程模板：交互式输入 Pipeline 名称与描述（v4 用法；旧版为 `nf-core create`）
nf-core pipelines create -n <name> -d "<description>" -a "<author>" -o <output_dir>
```

- 名称规范：纯小写、无连字符/下划线等标点（nf-core 规范，如 `example`、`sarek`）
- 产物：符合 nf-core 最佳实践的完整 Nextflow pipeline 骨架（main.nf / nextflow.config / modules / workflows / assets / tests / docs 等）
- 需要参考实例时按上述命令**临时生成即可**（生成后核对结构，无需入库；曾用 `nf-core pipelines create -n example` 生成的骨架已按此规则清理，仅保留本方法）
- 之后按需裁剪并接入本仓库规范（先登记原子模块，缺失的自建，见 [AGENT.md](../AGENT.md)）

### Snakemake：snakemake-workflow-template

- 来源：[snakemake-workflows/snakemake-workflow-template](https://github.com/snakemake-workflows/snakemake-workflow-template)
- 本仓挂法：与 riboseq 相同——[snakemake-template/](snakemake-template/) 只留登记文档，`native/` 为官方模板 **git submodule**（`git submodule update --init workflow/snakemake-template/native`）
- 方法：GitHub 「Use this template」/ clone 上游到项目目录再改造；或对照 submodule 内结构复制，**不要改 submodule 工作树当业务仓**
- 需符合 Snakemake 最佳实践：rule 命名、conda/envs、wrapper 引用、schema 校验、profile 部署等（官方文档 [snakemake.readthedocs.io](https://snakemake.readthedocs.io)）

## 使用注意（请谨慎使用此类代码）

- **模板仅是脚手架**：`nf-core pipelines create` / snakemake-workflow-template 生成的是「行业最佳实践起点」，包含大量脚手架（CI、许可证、文档、示例配置等），**不可原样照搬**，需按本仓库 [AGENT.md §10 Checklist](../AGENT.md#10-新增软件检查清单checklist) 与 [ARCHITECTURE.md](../ARCHITECTURE.md) 审查、裁剪、对齐版本与目录规范后再入库；
- **先查官方、再决定建不建**：动手前先确认 nf-core（[nf-core pipelines](https://nf-co.re/pipelines)）/ snakemake-wrappers 是否已有同类完整流程——官方已有 → **不建本地目录，只在文档/meta 登记引用**；确需本地自定义才用上述模板新建；
- **生成时注意**：`nf-core pipelines create -o <现有 git 仓库目录>` 会直接在目标目录铺开骨架并 `git init`/运行 pre-commit，可能污染仓库——建议在临时空目录生成后再移动到目标位置，并移除生成的嵌套 `.git`；
- 模板骨架中的工具版本/容器/conda 版本以各 `modules/<sw>/meta.yaml` 的 `software_versions` 为准做差异核对。

## 相关规范与文档

- 本仓库流程构建规范：[AGENT.md](../AGENT.md)（§0 流程结构 / §2 source_type 判据 / §10 Checklist）
- 架构总览：[ARCHITECTURE.md](../ARCHITECTURE.md)（§三 workflow 目录构建规则 / §六 实施步骤）
- nf-core 官方：文档 https://nf-co.re/docs ；`create` 用法 https://nf-co.re/tools/create
- Snakemake 官方：https://snakemake.readthedocs.io ；流程模板 https://github.com/snakemake-workflows/snakemake-workflow-template
