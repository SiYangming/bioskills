# samtools / official_snakemake

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 `bio/samtools/*` 的引用说明与桥接脚本。

## 设计原则

本目录不重写 wrapper 源码，仅保留：
- `meta.yaml` —— 统一抽象接口 Schema 与 Agent 引导
- `wrapper.py` —— 本地桥接脚本（生成 rule 模板、封装 wrapper 路径与默认资源）
- `README.md` —— 本说明

## 子模块清单

`bio/samtools/` 下的 wrapper：`view` `sort` `index` `flagstat` `idxstats` `stats` `mpileup` `merge` `faidx` `quickcheck` `depth` `dict`

## 在 Snakemake 中使用

```python
# 方式一：直接引用（master / 指定 tag）
rule samtools_sort:
    input: "{sample}.bam"
    output: "{sample}.sorted.bam"
    threads: 8
    wrapper: "v3.13.0/bio/samtools/sort"

# 方式二：用桥接脚本生成模板
python wrapper.py sort
```

## 桥接脚本能力

```bash
python wrapper.py sort --tag v3.13.0
# 输出可直接粘贴到 Snakefile 的 rule 模板，含默认 threads/mem_mb
```

作为模块导入：

```python
from wrapper import SamtoolsWrapperBridge
bridge = SamtoolsWrapperBridge()
bridge.wrapper_path("sort")   # -> "v3.13.0/bio/samtools/sort"
bridge.defaults("sort")       # -> {"threads": 8, "mem_mb": 8192}
```

## 何时选择本实现

- 目标流程语言为 **Snakemake**
- 希望复用 Snakemake 中央 wrapper 缓存，降低本地维护成本

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../native/`。
