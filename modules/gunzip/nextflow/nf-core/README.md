# gunzip / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 gunzip 模块的引用说明。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。真正执行时需使用 `nf-core` CLI 将模块
> 安装到**项目自身**的 `modules/nf-core/` 目录下；本目录本身不可被 Nextflow 直接 `include`。
> 若官方模块缺失（例如需要自定义参数），请使用 `../local/` 编写自定义 process。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方引用信息 |
| `module.json` | 上游仓库、版本、pinned commit 占位、安装命令 |
| `README.md` | 本说明 |

## 模块说明

`gunzip` 是 **单模块**（`modules/nf-core/gunzip/` 下无子模块拆分，只有
`main.nf` / `environment.yml` / `meta.yml` / `tests/`），负责 `.gz` → 原始文件解压
（`gzip -cd`），并输出标准 `versions.yml`。

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装模块到 modules/nf-core/
//   nf-core modules install gunzip

// 2. include 使用
include { GUNZIP } from './modules/nf-core/gunzip'

workflow {
    GUNZIP([id: 'sample1'], Channel.fromPath('reads.fa.gz'))
}
```

## 安装到项目

```bash
nf-core modules install gunzip
```

## 刷新子模块清单的 curl 命令

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/gunzip | grep '"name"'
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `gunzip_nextflow_local`。

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
