# sra-tools / snakemake / snakemake-wrappers

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 `bio/sra-tools/*` 的引用说明与桥接脚本。

> ⚠️ **本目录仅为说明 + Schema 挂载层 + 本地桥接脚本**。真正的 wrapper 由
> Snakemake 运行时根据 `wrapper: "vX.Y.Z/bio/sra-tools/<subcommand>"` 句柄从中央仓库或
> 本地缓存解析执行；wrapper.py 脚本本身不运行 sra-tools，只生成 rule 模板。
>
> **注意：截至 2026-09，官方 `bio/sra-tools` 只有 `fasterq-dump` 一个 wrapper；**
> **prefetch / fastq-dump 缺失，请使用 `../local/`（sra-tools_snakemake_local，sra_tools.smk）。**

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、wrapper 模板 |
| `wrapper.py` | 桥接脚本：封装 `wrapper_path()` / `defaults()` / `rule()` |
| `README.md` | 本说明 |

## 子模块清单

`bio/sra-tools/` 下的 wrapper：`fasterq-dump`（SRA → FASTQ 快速转换；sra-tools=3.4.1）。

## 在 Snakemake 中使用

```python
# 方式一：直接引用 tag
rule sra_fasterq_dump:
    input: "sra/{sample}.sra"
    output: "fastq/{sample}.fastq"
    threads: 8
    wrapper: "v3.13.0/bio/sra-tools/fasterq-dump"

# 方式二：用桥接脚本生成 rule 模板
python wrapper.py fasterq-dump --tag v3.13.0
```

## 桥接脚本能力

```bash
python wrapper.py fasterq-dump --tag v3.13.0
# 输出可直接粘贴到 Snakefile 的 rule 模板，含默认 threads/mem_mb
```

作为模块导入：

```python
from wrapper import SraToolsWrapperBridge
bridge = SraToolsWrapperBridge()
bridge.wrapper_path("fasterq-dump")   # -> "v3.13.0/bio/sra-tools/fasterq-dump"
bridge.defaults("fasterq-dump")       # -> {"threads": 8, "mem_mb": 8192}
```

## 若官方缺失 / 需定制

prefetch（SRA 下载）与 fastq-dump（兼容旧版转换）官方无 wrapper，请使用 `../local/` 目录
编写自维护 Snakemake rule（`source_type: custom`、`type: snakemake_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `sra-tools_snakemake_local`。

## 何时选择本实现

- 目标流程语言为 **Snakemake**
- 复用 Snakemake 中央 wrapper 缓存，降低本地维护成本

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
