# gunzip / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 官方缺失（bio/gunzip 404）时的 **Snakemake 自维护 rule**。
> 规则从 `snakemake.smk/isoseq.smk/workflow/rules/gunzip.smk` 迁移，去掉了对
> `workflow/lib/helpers.py` 的全局依赖（docker_run / GUNZIP_DOCKER_IMAGE）。

## 使用方式

```python
# Snakefile 中引入（可按需 use 重命名避免规则冲突）
include: "skills/gunzip/snakemake/local/rule_gunzip.smk"
# 或
use rule gunzip from rule_gunzip as gunzip
```

## 规则清单

| 规则 | 作用 | 迁移自 |
|------|------|--------|
| `gunzip` | `gzip -cd <in.gz> > <out>`（wildcard_constraints 保证不重复解压 .gz） | `gunzip.smk:gunzip` |

## 示例

```python
# 目标：把 results/xxx.fa.gz 解压为 results/xxx.fa
rule gunzip_demo:
    input:  "results/{sample}.fa.gz"
    output: "results/{sample}.fa"
```

## 与原 isoseq.smk 的差异

- 移除 `docker_run` / `GUNZIP_DOCKER_IMAGE`（容器由调用方在 rule 上声明）。
- 移除 `log` 重定向（需要日志时在调用方 rule 补充 `log:` + `2> {log}`）。
- `gzip_bin` 保留 config 可覆盖（默认 `gzip`）。
