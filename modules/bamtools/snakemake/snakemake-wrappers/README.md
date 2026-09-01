# bamtools / snakemake / snakemake-wrappers

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 `bio/bamtools/*` 的引用说明与桥接脚本。

> ⚠️ **本目录仅为说明 + Schema 挂载层 + 本地桥接脚本**。真正的 wrapper 由
> Snakemake 运行时根据 `wrapper: "vX.Y.Z/bio/bamtools/<subcommand>"` 句柄从中央仓库或
> 本地缓存解析执行；wrapper.py 脚本本身不运行 bamtools，只生成 rule 模板。
> **注意：`bio/bamtools` 没有 convert wrapper**，Iso-Seq 的 BAM→FASTA 请走 `../../native/`
> 或 `../local/`。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、wrapper 模板 |
| `wrapper.py` | 桥接脚本：封装 `wrapper_path()` / `defaults()` / `rule()` |
| `README.md` | 本说明 |

## 子模块清单

`bio/bamtools/` 下的 wrapper（2026-08 抓取）：`filter` `filter_json` `split` `stats`

## 在 Snakemake 中使用

```python
# 方式一：直接引用 tag
rule bamtools_stats:
    input: "{sample}.bam"
    output: "{sample}.bam.stats"
    threads: 1
    wrapper: "v3.13.0/bio/bamtools/stats"

# 方式二：用桥接脚本生成 rule 模板
python wrapper.py stats --tag v3.13.0
```

## 桥接脚本能力

```bash
python wrapper.py filter --tag v3.13.0
# 输出可直接粘贴到 Snakefile 的 rule 模板，含默认 threads/mem_mb
```

作为模块导入：

```python
from wrapper import BamToolsWrapperBridge
bridge = BamToolsWrapperBridge()
bridge.wrapper_path("stats")   # -> "v3.13.0/bio/bamtools/stats"
bridge.defaults("stats")       # -> {"threads": 1, "mem_mb": 2048}
```

## 子模块清单刷新（curl 样例）

```bash
curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/bamtools \
  | python3 -c "import sys,json; print('\n'.join(sorted(x['name'] for x in json.load(sys.stdin))))"
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自维护 Snakemake rule（`source_type: custom`、`type: snakemake_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `bamtools_snakemake_local`。

## 何时选择本实现

- 目标流程语言为 **Snakemake**
- 希望复用 Snakemake 中央 wrapper 缓存，降低本地维护成本

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
