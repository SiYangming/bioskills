# stringtie / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/stringtie`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `stringtie.smk` — 三个 rule，对应 nanoseq STRINGTIE 三段链路：
  - `stringtie_assemble`：`stringtie <bam> --conservative -L -R -G <gtf> -o <out> -l <sample> -m 200 -p N`
  - `stringtie_fix_gtf`：`awk -F'\t' '$4>$5{交换}'`（坐标修复，纯文本）
  - `stringtie_merge`：`stringtie --merge -G <gtf> -o <merged> -l MSTRG -m 200 <gtf_list>`

规则迁移自 `snakemake.smk/nanoseq.smk/nanoseq.sh/run_stringtie.sh`，去除
nohup/PID/LOCK 后台运行封装、绝对路径与 GNU parallel 依赖；`gtf_annotation` 走
`config.get(...)` 内联默认值。

## 用法

```python
# Snakefile 中
include: "modules/stringtie/snakemake/stringtie.smk"

# 运行
snakemake -j 8 merged/stringtie_merged_nonredundant.gtf
```

## 依赖环境

规则内 `conda: "envs/stringtie.yaml"`，需要自备：

```yaml
# envs/stringtie.yaml
channels: [conda-forge, bioconda]
dependencies:
  - stringtie=3.0.3
```

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/stringtie 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
