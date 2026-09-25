# subworkflow/misa_primer3 — MISA + Primer3 SSR 引物设计

无编排 `main.py`。保留桥接资产：`misa_primer3.pl`、`p3_settings.txt`、`prepare_p3_settings.py`。

- 元数据：[misa_primer3.yaml](misa_primer3.yaml)
- 模块：[misa](../../modules/misa/README.md) · [primer3](../../modules/primer3/README.md)
- 上游 helper：[SiYangming/SSR_marker_design](https://github.com/SiYangming/SSR_marker_design)

## 串联（仓库根）

```bash
GENOME=genome.fa OUT=results CPU=8
NATIVE=subworkflow/misa_primer3/native
mkdir -p "$OUT/misa" "$OUT/misa_primer3"

# 1) SSR 检测（须 GFF:false / 默认 .misa，供下游）
python modules/misa/native/main.py detect "$GENOME" --outdir "$OUT/misa"

# 2) 清洗 Primer3 设置（去掉教学机硬编码热力学路径）
python "$NATIVE/prepare_p3_settings.py" -o "$OUT/p3_settings_file"

# 3) 批量引物（ParaFly + primer3_core 需在 PATH）
perl "$NATIVE/misa_primer3.pl" \
  --CPU "$CPU" \
  --p3_setting_file "$OUT/p3_settings_file" \
  --gff3_out "$OUT/misa_primer3.gff3" \
  "$OUT/misa/$(basename "$GENOME").misa" "$GENOME" \
  > "$OUT/misa_primer3.out"
# 注意：第 3 步建议在 cwd=$OUT/misa_primer3 下跑（脚本写 tmp/commands 到 cwd）
```

```
genome.fa → misa detect → .misa
         → prepare_p3_settings.py → p3_settings_file
         → misa_primer3.pl → TSV + GFF3
```

静态自检：`bash native/test/run_test.sh`（只测 settings 清洗）。

## 环境

| 组件 | 用途 |
|------|------|
| `misa.pl` | stage 1（`modules/misa` install） |
| `primer3_core` | stage 3 |
| `ParaFly` | stage 3 并行 |
| `perl` | 跑 `misa_primer3.pl` |
