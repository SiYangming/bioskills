# orffinder / snakemake / snakemake-wrappers

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 `bio/orffinder/*` 的引用说明与桥接脚本。

> ⚠️ **本目录仅为说明 + Schema 挂载层 + 本地桥接脚本**。真正的 wrapper 由
> Snakemake 运行时根据 `wrapper: "vX.Y.Z/bio/orffinder/<subcommand>"` 句柄从中央仓库或
> 本地缓存解析执行；wrapper.py 脚本本身不运行 ORFfinder，只生成 rule 模板。
>
> **重要：截至 2026-09-01，官方 snakemake-wrappers 仓库中 `bio/orffinder` 目录不存在（API 返回 404），**
> **因此本目录无可用 wrapper 清单；Snakemake 场景请直接使用 `../local/orffinder.smk`（orffinder_snakemake_local）。**

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、wrapper 模板（submodules 为空） |
| `wrapper.py` | 桥接脚本：封装 `wrapper_path()` / `defaults()` / `rule()`（占位） |
| `README.md` | 本说明 |

## 子模块清单

`bio/orffinder/`：**官方不存在**（抓取 404）。

## 在 Snakemake 中使用（推荐走 local）

```python
# 官方 wrapper 缺失，使用本仓库自维护 rule：
include: "modules/orffinder/snakemake/local/orffinder.smk"

rule orffinder:
    input: "long_read/{sample}.fasta"
    output: "orffinder/{sample}.asn1"    # outfmt=2 默认后缀
    params: outfmt=2, extra="-s 2 -ml 30"
    conda: "envs/orffinder.yaml"         # orffinder=0.4.3
```

桥接脚本（占位登记用）：

```bash
python wrapper.py run --tag v3.13.0
# 输出占位 rule 模板（含「官方缺失」提示）
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录的自维护 rule（`source_type: custom`、`type: snakemake_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `orffinder_snakemake_local`。

## 何时选择本实现

- 官方 wrapper 出现后（重新抓取 bio/orffinder 有目录时）可恢复使用
- 当前 Snakemake 场景一律走 `../local/orffinder.smk`

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
