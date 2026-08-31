# fastqc / snakemake / snakemake-wrappers — 官方 wrapper 标注目录

本目录不做官方源码重分发，只提供：

- `meta.yaml`: 官方 wrapper 的字段 Schema + 在 Snakefile 中如何 include 的参考
- `wrapper.py`: 官方 bio/fastqc 骨架（行为参考拷贝），用于本地阅读/自测
- `README.md`: 集成步骤

## 使用方式

```python
rule fastqc:
    input:  "raw/{sample}.fq.gz"
    output:
        html="qc/{sample}_fastqc.html",
        zip="qc/{sample}_fastqc.zip",
    log:    "logs/fastqc/{sample}.log"
    params: extra="", outdir=lambda w, c: os.path.dirname(w.output.html) + "/.."
    threads: 4
    wrapper: "v3.13.0/bio/fastqc"
```
