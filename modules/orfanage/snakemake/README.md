# orfanage / snakemake / local

从 `flrnaseq.smk/orfrange_archive/orfanage.smk` 迁移的 `orfanage.smk`：

```bash
include: "modules/orfanage/snakemake/orfanage.smk"
```

规则自动在 `query_dir` 中选取 `*.transdecoder.gff3`（回退 `*.gff3`），
调用 `orfanage --query ... --output ... --threads N [--reference REF] <templates>`。
