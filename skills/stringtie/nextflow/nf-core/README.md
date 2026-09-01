# stringtie / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 stringtie 模块的引用说明。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。真正执行时需使用 `nf-core` CLI 将模块
> 安装到**项目自身**的 `modules/nf-core/` 目录下；本目录本身不可被 Nextflow 直接 `include`。
> 若 nf-core 官方缺失或需要定制，请使用 `../local/`。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方引用信息 |
| `module.json` | 上游仓库、版本、安装命令 |
| `README.md` | 本说明 |

## 子模块清单

2026-09 抓取 `https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/stringtie` 得到 2 个子模块：

| 子模块 | 作用 |
|--------|------|
| `stringtie` | 单样本转录本组装（stringtie <bam>，long-read 模式） |
| `merge` | 多样本 GTF 合并（stringtie --merge） |

## 在 Nextflow DSL2 中使用

```groovy
// 1. 在项目目录安装模块到 modules/nf-core/
//   nf-core modules install nf-core stringtie/stringtie
//   nf-core modules install nf-core stringtie/merge

// 2. include 使用
include { STRINGTIE } from './modules/nf-core/stringtie/stringtie/main'
include { STRINGTIE_MERGE } from './modules/nf-core/stringtie/merge/main'

workflow {
    STRINGTIE ( [ [id:'sample1'], bam, gtf ] )
    STRINGTIE_MERGE ( [ [id:'merge'], gtf_list, gtf ] )
}
```

## 抓取子模块清单（更新时执行）

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/stringtie \
  | python3 -c "import sys,json; print([e['name'] for e in json.load(sys.stdin) if e['type']=='dir'])"
# 预期输出：['stringtie', 'merge']
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `stringtie_nextflow_local`。

## 何时选择本实现

- 目标流程语言为 **Nextflow DSL2**
- 部署目标是 HPC 或 Cloud（需要容器化、Wave 缓存）

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
