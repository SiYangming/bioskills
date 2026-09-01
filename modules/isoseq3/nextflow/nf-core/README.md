# isoseq3 / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 isoseq 模块的引用说明。
> 命名提示：nf-core 目录名为 `modules/nf-core/isoseq/{refine,cluster}`（bioconda 包 `isoseq`，
> 二进制 `isoseq3`）。本技能（canonical `isoseq3`）对应其中的 **`refine`** 子模块。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。真正执行时需使用 `nf-core` CLI 将模块
> 安装到**项目自身**的 `modules/nf-core/` 目录下；本目录本身不可被 Nextflow 直接 `include`。
> 若 nf-core 官方缺失或需要定制，请使用 `../local/`。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方引用信息 |
| `module.json` | 上游仓库、版本、pinned commit 占位、安装命令 |
| `README.md` | 本说明 |

## 子模块清单

`modules/nf-core/isoseq/` 下的子目录（2026-08 抓取）：

| 子模块 | 作用 | 本技能对应 |
|--------|------|-----------|
| `refine` | 去除 polyA 尾与人工连接体（isoseq3 refine） | ✅ 是 |
| `cluster` | 转录本聚类去冗余（isoseq cluster） | 否 |

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装模块到 modules/nf-core/
//   nf-core modules install nf-core isoseq/refine

// 2. include 使用
include { ISOSEQ_REFINE } from './modules/nf-core/isoseq/refine/main'

workflow {
    ISOSEQ_REFINE ( [ [id: 'sample1'], cleaned_ccs_bam, primers_fasta ] )
}
```

## 抓取子模块清单（更新时执行）

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/isoseq \
  | python3 -c "import sys,json; print([e['name'] for e in json.load(sys.stdin) if e['type']=='dir'])"
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `isoseq3_nextflow_local`。

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
