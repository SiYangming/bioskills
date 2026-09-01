# bamtools / snakemake / local — 自维护 Snakemake rule

从 `snakemake.smk/isoseq.smk/workflow/rules/bamtools.smk` 迁移的实际规则
（去掉对 `workflow/lib/helpers.py` 的全局依赖，`docker_run` 分支删除，路径内联）。

## 文件

| 文件 | 作用 |
|------|------|
| `bamtools_convert.smk` | `bamtools convert -format <fmt> -in <bam> -out <out>` 规则 |
| `meta.yaml` | 实现级 Schema（id: `bamtools_snakemake_local`） |

## 使用

在 Snakefile 中：

```python
include: "modules/bamtools/snakemake/local/bamtools_convert.smk"

rule all:
    input:
        "results/bamtools/sample1/sample1.chunk1.fasta",
```

或直接定义目标：

```python
python3 -m snakemake -s Snakefile results/bamtools/sample1/sample1.chunk1.fasta --cores 1
```

## 与 isoseq.smk 的差异

- 删除 `docker_run` 分支与 `BAMTOOLS_DOCKER_IMAGE` 容器配置（默认直接调用 `bamtools` 二进制）。
- `BAMTOOLS_BIN_PATH` / `BAMTOOLS_FORMAT` 由 `config["bamtools"]` 读取并内联默认值：
  - `bamtools_bin: "bamtools"`
  - `format: "fasta"`
- 仍写 `versions.yml`（与 nf-core 模块风格一致）。
