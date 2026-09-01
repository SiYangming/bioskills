# gstama / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 gstama 子模块的引用说明。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。真正执行时需使用 `nf-core` CLI 将所需子模块
> 安装到**项目自身**的 `modules/nf-core/` 目录下；本目录本身不可被 Nextflow 直接 `include`。
> 若官方缺失某子模块，请降级使用 `../local/`。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方引用信息 |
| `module.json` | 上游仓库、版本、pinned commit 参考、安装命令 |
| `README.md` | 本说明 |

## 子模块清单

nf-core 将 gstama 拆为独立 process（2026-08 抓取 `modules/nf-core/gstama/`）：

| 子模块 | 作用 |
|--------|------|
| `collapse` | 转录本去冗余（tama_collapse.py，输入比对 BAM + 参考 FASTA，输出 bed12） |
| `merge` | 合并多来源转录本（tama_merge.py，输入 collapse bed） |
| `polyacleanup` | FLNC polyA 清理（tama_flnc_polya_cleanup.py，输入 FASTA，输出 gz） |

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装子模块到 modules/nf-core/
//   nf-core modules install gstama/polyacleanup collapse merge

// 2. include 使用
include { GSTAMA_POLYACLEANUP } from './modules/nf-core/gstama/polyacleanup'
include { GSTAMA_COLLAPSE } from './modules/nf-core/gstama/collapse'
include { GSTAMA_MERGE } from './modules/nf-core/gstama/merge'

workflow {
    GSTAMA_POLYACLEANUP(meta, flnc_fasta)
    GSTAMA_COLLAPSE(meta, bam, ref_meta, ref_fasta)
    GSTAMA_MERGE(meta, GSTAMA_COLLAPSE.out.bed)
}
```

## 安装到项目

```bash
nf-core modules install gstama/collapse
nf-core modules install gstama/merge polyacleanup
```

## 子模块清单刷新（curl 样例）

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/gstama \
  | python3 -c "import sys,json; print('\n'.join(sorted(x['name'] for x in json.load(sys.stdin))))"
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `gstama_nextflow_local`。

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
