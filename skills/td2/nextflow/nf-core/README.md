# td2 / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 td2 模块的引用说明。

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

nf-core td2 为**两个子模块**（2026-09-01 抓取官方目录）：

| 子模块 | 作用 |
|--------|------|
| `longorfs` | TD2.LongOrfs：转录本 FASTA → 候选最长 ORF |
| `predict` | TD2.Predict：基于 PSAURON 预测最终 CDS（pep/cds/gff3/bed） |

两个子模块的 `environment.yml` 均 pin `bioconda::td2=1.1.0`（⚠️ 比 native 的 1.0.6 新）。

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装模块到 modules/nf-core/
//   nf-core modules install nf-core td2/longorfs
//   nf-core modules install nf-core td2/predict

// 2. include 使用
include { TD2_LONGORFS } from './modules/nf-core/td2/longorfs/main'
include { TD2_PREDICT } from './modules/nf-core/td2/predict/main'

workflow {
    TD2_LONGORFS ( [ [id: 'sample1'], fasta ] )
    TD2_PREDICT ( [ [id: 'sample1'], fasta ] )
}
```

## 抓取子模块清单（更新时执行）

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/td2 \
  | python3 -c "import sys,json; print([e['name'] for e in json.load(sys.stdin) if e['type']=='dir'])"
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `td2_nextflow_local`。

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
