# subworkflow/fastp_bwa_samtools — QC → 比对 → sort/index（登记层）

无 `native/main.py`。按序调用各模块 CLI；可选 QC（multiqc）由项目自行加。

- 元数据：[fastp_bwa_samtools.yaml](fastp_bwa_samtools.yaml)
- 模块：[fastp](../modules/fastp/README.md) · [bwa-mem2](../modules/bwa-mem2/README.md) · [samtools](../modules/samtools/README.md)

## 串联示例（仓库根）

```bash
SAMPLE=s1 R1=r1.fq.gz R2=r2.fq.gz REF=ref.fa OUT=results THREADS=8

python modules/fastp/native/main.py run \
  -i "$R1" -I "$R2" \
  -o "$OUT/fastp/${SAMPLE}_R1.clean.fq.gz" \
  -O "$OUT/fastp/${SAMPLE}_R2.clean.fq.gz" \
  -h "$OUT/fastp/${SAMPLE}_fastp.html" \
  -j "$OUT/fastp/${SAMPLE}_fastp.json" \
  --threads "$THREADS"

# bwa-mem2 mem → BAM（具体管道见 modules/bwa-mem2 --help）
python modules/bwa-mem2/native/main.py mem --help

python modules/samtools/native/main.py sort "$OUT/bam/${SAMPLE}.bam" \
  -o "$OUT/bam/${SAMPLE}.sorted.bam" --threads "$THREADS"
python modules/samtools/native/main.py index "$OUT/bam/${SAMPLE}.sorted.bam"
```

```
fastp → bwa-mem2 mem → samtools sort → samtools index → (optional multiqc)
```
