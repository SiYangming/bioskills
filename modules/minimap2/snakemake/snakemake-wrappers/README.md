# minimap2 / snakemake / snakemake-wrappers

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 `bio/minimap2/*` 的引用说明与桥接脚本。

> ⚠️ **本目录仅为说明 + Schema 挂载层 + 本地桥接脚本**。真正的 wrapper 由
> Snakemake 运行时根据 `wrapper: "vX.Y.Z/bio/minimap2/<subcommand>"` 句柄从中央仓库或
> 本地缓存解析执行；wrapper.py 脚本本身不运行 minimap2，只生成 rule 模板。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、wrapper 模板 |
| `wrapper.py` | 桥接脚本：封装 `wrapper_path()` / `defaults()` / `rule()` |
| `README.md` | 本说明 |

## 子模块清单

`bio/minimap2/` 下的 wrapper（2026-08 抓取）：`aligner` `index`

## 在 Snakemake 中使用

```python
# 方式一：直接引用 tag
rule minimap2_aligner:
    input:
        reads="reads/{sample}.fa",
        reference="ref/ref.fa"
    output:
        bam="aln/{sample}.bam"
    threads: 8
    wrapper: "v3.13.0/bio/minimap2/aligner"

# 方式二：用桥接脚本生成 rule 模板
python wrapper.py aligner --tag v3.13.0
```

## 桥接脚本能力

```bash
python wrapper.py aligner --tag v3.13.0
# 输出可直接粘贴到 Snakefile 的 rule 模板，含默认 threads/mem_mb
```

作为模块导入：

```python
from wrapper import Minimap2WrapperBridge
bridge = Minimap2WrapperBridge()
bridge.wrapper_path("aligner")   # -> "v3.13.0/bio/minimap2/aligner"
bridge.defaults("aligner")       # -> {"threads": 8, "mem_mb": 16384}
```

## 子模块清单刷新（curl 样例）

```bash
curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/minimap2 \
  | python3 -c "import sys,json; print('\n'.join(sorted(x['name'] for x in json.load(sys.stdin))))"
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录编写自维护 Snakemake rule（`source_type: custom`、`type: snakemake_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `minimap2_snakemake_local`。

## 何时选择本实现

- 目标流程语言为 **Snakemake**
- 希望复用 Snakemake 中央 wrapper 缓存，降低本地维护成本

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
