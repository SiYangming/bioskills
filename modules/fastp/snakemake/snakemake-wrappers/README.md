# fastp / snakemake / snakemake-wrappers

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 `bio/fastp/*` 的引用说明与桥接脚本。

> ⚠️ **本目录仅为说明 + Schema 挂载层 + 本地桥接脚本**。真正的 wrapper 由
> Snakemake 运行时根据 `wrapper: "vX.Y.Z/bio/fastp"` 句柄从中央仓库或
> 本地缓存解析执行；wrapper.py 脚本本身不运行 fastp，只生成 rule 模板。
>
> 缺失时用 `../local/`（`fastp.smk`）兜底。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、wrapper 模板 |
| `wrapper.py` | 桥接脚本：封装 `wrapper_path()` / `defaults()` / `rule()` |
| `README.md` | 本说明 |

## 子模块清单

`bio/fastp/`（2026-09-01 抓取）：单 wrapper，目录内为
`environment.linux-64.pin.txt` / `environment.yaml` / `meta.yaml` / `test` / `wrapper.py`。

`environment.yaml` 当前 pin `fastp=1.3.6`（⚠️ 比 native 的 0.24.0 新；0.20+ 线程参数为 `-w/--thread`）。

## 在 Snakemake 中使用

```python
rule fastp:
    input:
        reads=["reads/{sample}_R1.fastq.gz", "reads/{sample}_R2.fastq.gz"]
    output:
        reads=["results/fastp/{sample}_R1.clean.fastq.gz",
               "results/fastp/{sample}_R2.clean.fastq.gz"],
        html="results/fastp/{sample}_fastp.html",
        json="results/fastp/{sample}_fastp.json"
    params:
        extra="--detect_adapter_for_pe"
    threads: 8
    wrapper:
        "v3.13.0/bio/fastp"
```

桥接脚本：

```bash
python wrapper.py --tag v3.13.0
# 输出可粘贴的 rule 模板
```

## 抓取 wrapper 清单（更新时执行）

```bash
curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/fastp \
  | python3 -c "import sys,json; print([e['name'] for e in json.load(sys.stdin)])"
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录的自维护规则（`source_type: custom`、`type: snakemake_local`，
见 `../local/fastp.smk`），并在软件级 `meta.yaml` 的 `implementations` 登记 `fastp_snakemake_local`。

## 何时选择本实现

- 目标流程语言为 **Snakemake**，且可访问中央 wrapper 缓存 / 已配置本地缓存

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
