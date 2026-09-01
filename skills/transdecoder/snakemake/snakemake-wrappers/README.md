# transdecoder / snakemake / snakemake-wrappers

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 `bio/transdecoder/*` 的引用说明与桥接脚本。

> ⚠️ **本目录仅为说明 + Schema 挂载层 + 本地桥接脚本**。真正的 wrapper 由
> Snakemake 运行时根据 `wrapper: "vX.Y.Z/bio/transdecoder/<subcommand>"` 句柄从中央仓库或
> 本地缓存解析执行；wrapper.py 脚本本身不运行 TransDecoder，只生成 rule 模板。
>
> 若官方 wrapper 缺失或需要定制，请使用 `../local/`。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、wrapper 模板 |
| `wrapper.py` | 桥接脚本：封装 `wrapper_path()` / `defaults()` / `rule()` |
| `README.md` | 本说明 |

## 子模块清单

`bio/transdecoder/`（2026-09-01 抓取官方目录）：

| 子模块 | 作用 |
|--------|------|
| `longorfs` | TransDecoder.LongOrfs：转录本 FASTA → 候选最长 ORF |
| `predict` | TransDecoder.Predict：预测最终 CDS（pep/cds/gff3/bed） |

两个 wrapper 的 `environment.yaml` 均 pin `transdecoder=5.7.1`。

## 在 Snakemake 中使用

```python
# 官方 wrapper 引用（Snakemake 运行时自动解析）
rule transdecoder_longorfs:
    input:
        "transcripts/{sample}.fa"
    output:
        directory("transdecoder/{sample}/longorfs")
    params:
        extra="-m 50 -G Universal -S"
    threads: 4
    wrapper:
        "v3.13.0/bio/transdecoder/longorfs"

rule transdecoder_predict:
    input:
        fasta="transcripts/{sample}.fa",
        td_dir="transdecoder/{sample}/longorfs"
    output:
        "transdecoder/{sample}/predict/{sample}.pep"
    params:
        extra="--no_refine_starts"
    threads: 8
    wrapper:
        "v3.13.0/bio/transdecoder/predict"
```

桥接脚本（生成 rule 模板）：

```bash
python wrapper.py longorfs --tag v3.13.0
python wrapper.py predict  --tag v3.13.0
```

## 抓取子模块清单（更新时执行）

```bash
curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/transdecoder \
  | python3 -c "import sys,json; print([e['name'] for e in json.load(sys.stdin) if e['type']=='dir'])"
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录的自维护 rule（`source_type: custom`、`type: snakemake_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `transdecoder_snakemake_local`。

## 何时选择本实现

- 目标流程语言为 **Snakemake**
- 需要复用中央 wrapper 缓存 / 官方维护的 rule 逻辑

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
