# bamtools / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 bamtools 子模块的引用说明。

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

nf-core 将 bamtools 拆为独立 process（2026-08 抓取 `modules/nf-core/bamtools/`）：

| 子模块 | 作用 |
|--------|------|
| `convert` | BAM → bed/fasta/fastq/json/pileup/sam/yaml（Iso-Seq 流程常用） |
| `split` | 按属性把 BAM 拆分为多个输出文件 |
| `stats` | 输出 BAM 基本统计 |

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装子模块到 modules/nf-core/
//   nf-core modules install bamtools/convert

// 2. include 使用
include { BAMTOOLS_CONVERT } from './modules/nf-core/bamtools/convert'

workflow {
    BAMTOOLS_CONVERT(meta, reads_bam)
    BAMTOOLS_CONVERT.out.out  // *.fasta 等（format 由 module 参数决定）
}
```

## 安装到项目

```bash
nf-core modules install bamtools/convert
```

## 子模块清单刷新（curl 样例）

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/bamtools \
  | python3 -c "import sys,json; print('\n'.join(sorted(x['name'] for x in json.load(sys.stdin))))"
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `bamtools_nextflow_local`。

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
