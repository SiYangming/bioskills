# samtools / official_nfcore

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 samtools 子模块的引用说明。

## 设计原则

本目录**不重写任何源码**，仅保留：
- `meta.yaml` —— 统一抽象接口 Schema 与 Agent 引导
- `module.json` —— 官方模块元信息映射（版本、上游 commit、安装命令）
- `README.md` —— 本说明

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
// 1. 安装子模块到本地
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

## 安装到本项目

按用户偏好：优先使用 nf-core 标准模块，安装时复制到项目 `modules/nf-core/` 目录。

```bash
nf-core modules install samtools/view
# 变更记录在 CHANGES&FIX 目录，版本写入 CHANGELOG.md
```

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../native/`。
