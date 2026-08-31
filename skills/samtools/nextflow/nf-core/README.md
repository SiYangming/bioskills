# samtools / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 samtools 子模块的引用说明。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。真正执行时需使用 `nf-core` CLI 将所需子模块
> 安装到**项目自身**的 `modules/nf-core/` 目录下；本目录本身不可被 Nextflow 直接 `include`。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方引用信息 |
| `module.json` | 上游仓库、版本、pinned commit 占位、安装命令 |
| `README.md` | 本说明 |

## 子模块清单

nf-core 将 samtools 拆为独立 process：

| 子模块 | 作用 |
|--------|------|
| `view` | SAM/BAM/CRAM 互转与过滤 |
| `sort` | 排序 |
| `index` | 建立索引 |
| `flagstat` / `idxstats` / `stats` | 统计 |
| `mpileup` | pileup |
| `merge` | 合并 BAM |
| `faidx` / `dict` | FASTA 索引 / 序列字典 |
| `quickcheck` | 完整性校验 |
| `convert` | 格式转换 |

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装子模块到 modules/nf-core/
//   nf-core modules install samtools/view
//   nf-core modules install samtools/sort

// 2. include 使用
include { SAMTOOLS_VIEW } from './modules/nf-core/samtools/view'
include { SAMTOOLS_SORT } from './modules/nf-core/samtools/sort'

workflow {
    SAMTOOLS_VIEW(params.reads)
    SAMTOOLS_SORT(SAMTOOLS_VIEW.out.bam)
}
```

## 安装到项目

按用户偏好：优先使用 nf-core 标准模块，安装时复制到项目 `modules/nf-core/` 目录。

```bash
nf-core modules install samtools/view
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `samtools_nextflow_local`。

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
