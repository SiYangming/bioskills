# gstama / snakemake / snakemake-wrappers

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 gstama 的引用说明。

> ⚠️ **本目录仅为说明 + Schema 挂载层**。更重要的是：
> **官方 `bio/gstama` 目录不存在**（`https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/gstama` 返回 404，2026-08 抓取），
> 因此 `wrapper: "vX.Y.Z/bio/gstama/<sub>"` 句柄必然解析失败。
> Snakemake 场景请直接使用 **`../local/`**（已从 isoseq.smk 迁移 4 条规则）或 **`../../native/`**。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导（官方缺失声明） |
| `wrapper.py` | 占位桥：封装 `wrapper_path()` / `defaults()` / `rule()` 三 API（恒提示降级） |
| `README.md` | 本说明 |

## 子模块清单

`bio/gstama/` 官方不存在（404），子模块列表为空。

## 在 Snakemake 中使用（降级路径）

```python
# 官方 wrapper 不可用，改用 ../local/ 迁移规则：
include: "skills/gstama/snakemake/local/gstama_polyacleanup.smk"
include: "skills/gstama/snakemake/local/gstama_collapse.smk"
include: "skills/gstama/snakemake/local/gstama_filelist.smk"
include: "skills/gstama/snakemake/local/gstama_merge.smk"
```

或直接调用 native 驱动：

```python
rule gstama_collapse:
    input:
        bam="aln/{sample}.bam",
        fasta="ref/ref.fa"
    output:
        bed="gstama/{sample}_collapsed.bed"
    shell:
        "python skills/gstama/native/main.py collapse --bam {input.bam} "
        "--fasta {input.fasta} --outdir gstama --prefix {wildcards.sample}"
```

## 桥接脚本能力

```bash
python wrapper.py collapse
# 输出降级指引（官方 wrapper 不存在）
```

## 子模块清单刷新（curl 样例，预期 404）

```bash
curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/gstama \
  | python3 -c "import sys,json; print('\n'.join(sorted(x['name'] for x in json.load(sys.stdin))))"
```

## 若官方缺失 / 需定制

官方 gstama 必然缺失：使用 `../local/` 目录的自维护 Snakemake rule（`source_type: custom`、`type: snakemake_local`），
已在软件级 `meta.yaml` 的 `implementations` 登记 `gstama_snakemake_local`。

## 何时选择本实现

本目录**不可直接用于执行**（官方缺失）；仅为 Schema 登记与降级指引。
非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
