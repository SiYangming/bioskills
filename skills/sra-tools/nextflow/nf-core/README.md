# sra-tools / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 SRA Toolkit 子模块的引用说明。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。真正执行时需使用 `nf-core` CLI 将模块
> 安装到**项目自身**的 `modules/nf-core/` 目录下；本目录本身不可被 Nextflow 直接 `include`。
> 若 nf-core 官方缺失（如需要 `fastq-dump` 子模块）或需要定制，请使用 `../local/`。
>
> **注意命名差异：nf-core 官方模块目录名为 `sratools`（无连字符），不是 `sra-tools`。**

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方引用信息 |
| `module.json` | 上游仓库、版本、安装命令 |
| `README.md` | 本说明 |

## 子模块清单

nf-core 将 SRA Toolkit 拆为两个独立 process（`modules/nf-core/sratools/`）：

| 子模块 | 作用 |
|--------|------|
| `fasterqdump` | SRA → FASTQ（官方推荐快速转换，`--split-3` 双端拆分） |
| `prefetch` | SRA accession → 本地 .sra（NCBI 下载） |

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装子模块到 modules/nf-core/（注意模块名是 sratools）
//   nf-core modules install sratools/fasterqdump
//   nf-core modules install sratools/prefetch

// 2. include 使用
include { SRATOOLS_FASTERQDUMP } from './modules/nf-core/sratools/fasterqdump/main'
include { SRATOOLS_PREFETCH } from './modules/nf-core/sratools/prefetch/main'

workflow {
    SRATOOLS_PREFETCH(params.accession)
    SRATOOLS_FASTERQDUMP(SRATOOLS_PREFETCH.out.sra)
}
```

## 安装到项目

```bash
nf-core modules install sratools/fasterqdump
nf-core modules install sratools/prefetch
```

## 抓取子模块清单（更新时执行）

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/sratools \
  | python3 -c "import sys,json; print([e['name'] for e in json.load(sys.stdin) if e['type']=='dir'])"
# 预期输出：['fasterqdump', 'prefetch']
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `sra-tools_nextflow_local`。
（例如 nanoseq 脚本使用的 `fastq-dump --split-3 --gzip` 官方无对应子模块，可走 local。）

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
