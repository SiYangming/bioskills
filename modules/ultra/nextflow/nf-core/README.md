# ultra / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 uLTRA 子模块的引用说明。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。真正执行时需使用 `nf-core` CLI 将所需子模块
> 安装到**项目自身**的 `modules/nf-core/` 目录下；本目录本身不可被 Nextflow 直接 `include`。
> 若官方模块缺失（例如需要自定义参数），请使用 `../local/` 编写自定义 process。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方引用信息 |
| `module.json` | 上游仓库、版本、pinned commit 占位、安装命令 |
| `README.md` | 本说明 |

## 子模块清单（2026-08 GitHub API 抓取）

nf-core 将 ultra 拆为独立 process：

| 子模块 | 作用 |
|--------|------|
| `index` | `uLTRA index`：由 FASTA + GTF 生成 `*.pickle` / `*.db` |
| `align` | `uLTRA align` + `samtools sort`：reads → BAM |
| `pipeline` | 端到端演示流程（index + align 串联） |

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装子模块到 modules/nf-core/
//   nf-core modules install ultra/index
//   nf-core modules install ultra/align

// 2. include 使用
include { ULTRA_INDEX } from './modules/nf-core/ultra/index'
include { ULTRA_ALIGN } from './modules/nf-core/ultra/align'

workflow {
    ULTRA_INDEX(params.fasta, params.gtf)
    ULTRA_ALIGN(
        ULTRA_INDEX.out.pickle,
        ULTRA_INDEX.out.db,
        params.genome,
        params.reads
    )
}
```

## 安装到项目

```bash
nf-core modules install ultra/index
nf-core modules install ultra/align
```

## 刷新子模块清单的 curl 命令

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/ultra | grep '"name"'
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `ultra_nextflow_local`。

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
