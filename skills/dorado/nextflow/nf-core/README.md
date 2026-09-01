# dorado / nextflow / nf-core

官方 [nf-core/modules](https://github.com/nf-core/modules) 中 dorado 模块的引用说明。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。真正执行时需使用 `nf-core` CLI 将模块
> 安装到**项目自身**的 `modules/nf-core/` 目录下；本目录本身不可被 Nextflow 直接 `include`。
> 若 nf-core 官方缺失或需要定制，请使用 `../local/`。
>
> **重要：截至 2026-09，nf-core 官方仓库中 `modules/nf-core/dorado` 目录不存在（API 返回 404），**
> **因此本目录无可用子模块清单；Nextflow 场景请直接使用 `../local/`（dorado_nextflow_local）。**

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方引用信息（submodules 为空） |
| `module.json` | 上游仓库、版本、安装命令（占位登记） |
| `README.md` | 本说明 |

## 子模块清单

`modules/nf-core/dorado/`：**官方不存在**（抓取 404）。

## 在 Nextflow DSL2 中使用（推荐走 local）

```groovy
// 官方模块缺失 —— 使用本地 process：
// 在 modules/local/dorado.nf 中定义：

process DORADO_BASECALL {
    container 'docker.1ms.run/nanoporetech/dorado:latest'   // nanoseq config 默认镜像

    input:
    tuple val(meta), path(pod5_dir)
    val(model)

    output:
    path "*.fastq", emit: fastq

    script:
    """
    mkdir -p out
    dorado basecaller ${model} ${pod5_dir} --emit-fastq --output-dir out
    """
}
```

## 抓取子模块清单（更新时执行）

```bash
curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/dorado \
  | python3 -c "import sys,json; print([e['name'] for e in json.load(sys.stdin) if e['type']=='dir'])"
# 预期输出：{"message": "Not Found", ...} —— 官方无此目录
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自定义 Nextflow process（`source_type: custom`、`type: nextflow_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `dorado_nextflow_local`。

## 何时选择本实现

- 官方模块出现后（重新抓取 modules/nf-core/dorado 有目录时）可恢复使用
- 当前 Nextflow 场景一律走 `../local/`

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
