# gnu_sort / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 官方缺失（bio/gnu 404）时的 **Snakemake 自维护 rule**。
> 规则从 `snakemake.smk/isoseq.smk/workflow/skills/gnu_sort/snakemake/local/gnu_sort.smk` 迁移，去掉了对
> `workflow/lib/helpers.py` 的全局依赖（`get_gnu_sort_args` 的后缀 override 逻辑）。

## 使用方式

```python
# Snakefile 中引入（可按需 use 重命名避免规则冲突）
include: "skills/gnu_sort/snakemake/local/gnu_sort.smk"
# 或
use rule gnu_sort from rule_gnu_sort as gnu_sort
```

## 规则清单

| 规则 | 作用 | 迁移自 |
|------|------|--------|
| `gnu_sort` | `sort <args> <in> > <out>.sorted`（args 由 config 透传） | `gnu_sort.smk:gnu_sort` |

## 示例

```python
# 目标：把 results/xxx.gtf 排序为 results/xxx.gtf.sorted
config["gnu_sort"] = {"args": "-k1,1 -k4,4n"}

rule gnu_sort_demo:
    input:  "results/{filepath}.gtf"
    output: "results/{filepath}.gtf.sorted"
```

## 与原 isoseq.smk 的差异

- 移除 `helpers.get_gnu_sort_args`（按后缀 override）：简化为 `config["gnu_sort"]["args"]`
  单一透传；如需按文件后缀切换参数，在调用方用 `use rule ... from ...` 覆盖 `params.args`。
- 移除 `docker_run` / `GNU_SORT_DOCKER_IMAGE`（容器由调用方在 rule 上声明）。
- `sort_bin` 保留 config 可覆盖（默认 `sort`）。
