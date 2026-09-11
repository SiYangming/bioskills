# subworkflow/misa_primer3 — MISA + Primer3 SSR 检测与引物设计组合

把经典的 **SSR 分子标记开发**链路（MISA 检测 → Primer3 批量设计侧翼引物）提炼为可复用组合流程：

```
genome.fasta
   │  stage 1  misa.pl（modules/misa/native/main.py detect）
   ▼
<genome>.misa（SSR 位点表）+ <genome>.statistics（统计）
   │  stage 2  p3_settings.txt → p3_settings_file（去注释/空行 + 修正热力学参数目录）
   ▼
   │  stage 3  misa_primer3.pl（逐位点截取侧翼 → ParaFly --CPU N 并行 primer3_core）
   ▼
misa_primer3.out（TSV 引物表，每 SSR 最多 5 对引物）+ misa_primer3.gff3
```

- 元数据：同级 [meta.yaml](meta.yaml)（stages / inputs / outputs / execution）。
- 本组合为**目录形态**：`misa_primer3.md` + `meta.yaml` + `native/`（`main.py` 编排入口 + vendored 桥接脚本与设置模板 + `test/`）。
- 依赖原子技能：[modules/misa](../../modules/misa/README.md)（检测）、[modules/primer3](../../modules/primer3/README.md)（`primer3_core` 二进制）。
- 官方层核实（2026-09）：nf-core / snakemake-wrappers **均无** misa 模块（404），故本组合为 **custom** 自建（`source_type: custom`）。

## Stage 图（DAG）

```
genome.fasta ──► [1] misa_detect（misa.pl，GFF: false）
                        │  ▼ <genome>.misa + <genome>.statistics
                        │
                  [2] prepare_p3_settings（native/p3_settings.txt → p3_settings_file）
                        │
                        ▼
                  [3] misa_primer3_design（misa_primer3.pl）
                        │   每 SSR：截取两侧翼 300 bp → 生成 Primer3 设置（SEQUENCE_TARGET 锁定 SSR）
                        │   ParaFly --CPU N 并行 ──► primer3_core（每行一条命令）
                        ▼
                  misa_primer3.out（TSV）+ misa_primer3.gff3
                  misa_primer3/misa_primer3.tmp/<ID>[.out]（中间产物，便于逐位点排查）
```

stages 声明见 [meta.yaml](meta.yaml)：`misa_detect` → `prepare_p3_settings` → `misa_primer3_design`。

## 环境准备（`--real` 需要）

| 组件 | 用途 | 安装 |
| ---- | ---- | ---- |
| `misa.pl` | stage 1 SSR 检测 | `bash modules/misa/native/install.sh`（官方源包，见 [misa README](../../modules/misa/README.md)） |
| `primer3_core` | stage 3 引物设计引擎（由 `misa_primer3.pl` 直接调用） | `mamba create -n primer3-native -c conda-forge -c bioconda primer3=2.6.1`（或官方容器 `quay.io/biocontainers/primer3`） |
| `ParaFly` | stage 3 `--CPU N` 并行调度 | `mamba create -n parafly -c conda-forge -c bioconda parafly` |
| `perl` | 运行 `misa_primer3.pl` | 随 misa 安装（conda 路线自带）或系统 perl |

一条命令建好（示例）：

```bash
mamba create -n ssr -c conda-forge -c bioconda perl primer3=2.6.1 parafly
conda activate ssr
bash modules/misa/native/install.sh --method conda --conda-env ssr   # 把 misa.pl 装进同一环境
misa.pl -help | head -3 && primer3_core --help < /dev/null | head -2 && ParaFly 2>&1 | head -2
```

## 资产来源（vendored，2026-09-10 取自上游并核对）

| 资产 | 上游 | sha256（上游） | 本仓库改动 |
| ---- | ---- | ---- | ---- |
| `native/misa_primer3.pl` | [SiYangming/SSR_marker_design](https://github.com/SiYangming/SSR_marker_design/blob/master/misa_primer3.pl)（MISA 衍生 helper，Chen Lianfu 版 `p3_settings` 配套） | `c451d1d00aee00d2f7a1ac3c03b297bcc9ed7cd1dcddceec4f665abbaed80d60` | 仅 1 行可移植性修补：ParaFly 重定向 ``&> /dev/null`` → ``> /dev/null 2>&1``（`&>` 是 bash 扩展，Debian 的 `/bin/sh`=dash 会 Syntax error，而 perl `system()` 走 `/bin/sh`）；另加来源头注 |
| `native/p3_settings.txt` | 同上仓库 `p3_settings.txt` | `3222c34aab3accf8d937600cb39bd1c50618ee4259fba8abfc5ca572f7e1d53b` | **原样**（注释与 `PRIMER_THERMODYNAMIC_PARAMETERS_PATH=/opt/biosoft/primer3-2.4.0/...` 由 stage 2 在生成时清理/重写） |
| `<genome>.misa` | [modules/misa](../../modules/misa/README.md)（官方 `misa_sourcecode_25082020.zip`，v2.1） | 上游 `misa.pl` `4712f29a...` | 不 vendor：由 `native/install.sh` 安装 |

## 编排入口（native/main.py）

入口：`python subworkflow/misa_primer3/native/main.py --list-stages | --dry-run（默认）| --real`（仓库根执行）。

```bash
# 0) 看 stage 清单
python subworkflow/misa_primer3/native/main.py --list-stages

# 1) dry-run（默认）：只打印三个 stage 将执行的命令，不需要装任何外部工具
python subworkflow/misa_primer3/native/main.py --dry-run \
    --genome Malassezia_sympodialis.genome_V01.fasta --outdir results --threads 8

# 2) 真实执行（PATH 内需有 misa.pl / primer3_core / ParaFly / perl）
python subworkflow/misa_primer3/native/main.py --real \
    --genome Malassezia_sympodialis.genome_V01.fasta --outdir results --threads 8 \
    --gff3-out results/misa_primer3.gff3
```

编排器实际执行的动作（等价于你在 shell 里手敲）：

```bash
# stage 1（modules/misa/native/main.py detect → 输出全部落在 outdir，输入目录零写入）
python modules/misa/native/main.py detect genome.fasta --outdir results/misa
# stage 2（去注释/空行；把 PRIMER_THERMODYNAMIC_PARAMETERS_PATH 指向真实 primer3_config）
python - <<'PY'
from pathlib import Path
import sys; sys.path.insert(0, "subworkflow/misa_primer3/native")
from main import prepare_p3_settings, resolve_primer3_config
info = prepare_p3_settings("subworkflow/misa_primer3/native/p3_settings.txt",
                           "results/p3_settings_file", resolve_primer3_config())
print(info)
PY
# stage 3（primer3_core 由 ParaFly 并行调度；命令文件与中间产物落在 cwd=results/misa_primer3）
cd results/misa_primer3 && perl ../../native/misa_primer3.pl \
    --CPU 8 --flanking_length 300 --min_product_length 100 --max_product_length 250 \
    --gff3_out ../misa_primer3.gff3 --p3_setting_file ../p3_settings_file \
    ../misa/genome.fasta.misa ../../genome.fasta > ../misa_primer3.out
```

> `misa_primer3.pl` 的 `--CPU N` 依赖 `ParaFly`（`ParaFly -c misa_primer3.commands -CPU N`）；`--CPU 1` 同样走 ParaFly。

## 参数说明

| 参数（编排器） | 透传目标 | 默认 | 说明 |
| ---- | ---- | ---- | ---- |
| `--genome` | misa detect / misa_primer3.pl | — | 输入 FASTA（必填） |
| `--outdir` | 全 stage | `results` | 输出根目录（`misa/`、`misa_primer3/`、`p3_settings_file`、`misa_primer3.out`、`misa_primer3.gff3`） |
| `--threads` / `--cpu` | `misa_primer3.pl --CPU` | `8` | 并行数（ParaFly；对应教学命令的 `--CPU 8`） |
| `--p3-setting-file` | `misa_primer3.pl --p3_setting_file` | 自动生成 | 自定义 Primer3 设置文件；不给则用 `native/p3_settings.txt` 生成 |
| `--gff3-out` / `--no-gff3` | `misa_primer3.pl --gff3_out` | `<outdir>/misa_primer3.gff3` | GFF3 输出路径 / 关闭 |
| `--misa-ini` | `modules/misa detect --ini` | 内置默认 | 自定义 `misa.ini`（须 `GFF: false`，否则没有 `.misa`） |
| `--flanking-length` | `--flanking_length` | `300` | 每条 SSR 截取的侧翼长度（模板长度 = SSR 长度 + 2×侧翼） |
| `--min-product-length` / `--max-product-length` | `--min/max_product_length` | `100` / `250` | 产物长度范围（写入 `PRIMER_PRODUCT_SIZE_RANGE`） |

`misa_primer3.pl` 原始参数：`perl misa_primer3.pl <genome.fasta.misa> <genome.fasta>`（用法头注见脚本内 `USAGE`）。

## 与教学链路对照（用户课件的命令 → 本流程）

| 教学命令 | 本流程等价 |
| ---- | ---- |
| `cp /opt/biosoft/Misa_Primer3/misa.ini . && misa.pl genome.fasta` | stage 1：`main.py detect genome.fasta --outdir <outdir>/misa`（驱动自动在 outdir 准备 `misa.ini`） |
| `perl -p -e 's/\s*#.*//; s/^\s*$//; s/P3_FILE_ID/\nP3_FILE_ID/' p3_settings_from_chenlianfu.txt > p3_settings_file` | stage 2：`prepare_p3_settings()`（内置 `native/p3_settings.txt` 即该模板） |
| `perl -p -i -e 's#^PRIMER_THERMODYNAMIC_PARAMETERS_PATH.*#...#/' p3_settings_file` | stage 2：自动探测 `primer3_config` 并重写；探测不到则**删除该行**（见下「已知坑」） |
| `misa_primer3.pl --CPU 8 --gff3_out misa_primer3.gff3 --p3_setting_file p3_settings_file genome.fasta.misa genome.fasta > misa_primer3.out` | stage 3：编排器以 `cwd=<outdir>/misa_primer3` 执行同一命令 |

## 已知坑（2026-09 实测）

1. **`.misa` 与 GFF 输出互斥**：`misa.ini` 写 `GFF: true` 时 `misa.pl` 只写逐序列 `.gff`，**不产出 `.misa`**，stage 3 会因缺少位点表而失败。本流程 stage 1 固定 `GFF: false`，最终 GFF3 由 stage 3 的 `--gff3_out` 产出。
2. **`PRIMER_THERMODYNAMIC_PARAMETERS_PATH` 必须指向真实目录或直接不写**：若指向不存在的目录，`primer3_core` 直接报
   `PRIMER_ERROR=Unable to open file .../dangle.dh`（每个位点都会失败）。bioconda 的 primer3 容器/包**不带** `primer3_config`（实测 2026-09），此时应删除该行 → `primer3_core` 回退编译内置默认参数（即官方 SantaLucia 参数），结果与显式指定一致。stage 2 已按此逻辑处理并打印 `[WARN]`。
3. **`&>` bash 扩展**：上游 `misa_primer3.pl` 用 `ParaFly ... &> /dev/null`，在 Debian/Ubuntu（`/bin/sh`=dash）必然 `die "Excute Failed"`；本仓库 vendored 副本已改为 `> /dev/null 2>&1`。
4. **`misa_primer3.tmp/` 复用**：`misa_primer3.pl` 只在目录不存在时 `mkdir`，脚本每次运行会重置 `misa_primer3.tmp/` 与 `misa_primer3.commands`（编排器在 `--real` 前主动清理，保证可重复）。
5. **perl 遗留正则告警**：`misa.pl` 在 stderr 打 `Unescaped left brace in regex`（上游 v2.1 正则写法），不影响结果；见 [misa README](../../modules/misa/README.md)。
6. **规模**：真菌基因组（~30 Mb）SSR 数可达数万条，`primer3_core` 每位点一次调用 → 整机耗时由 `--CPU` 与位点数决定（教学数据 8 线程约 10 分钟量级）。全基因组建议先按染色体拆分并行，再合并 `.misa` 与 `misa_primer3.out`。

## 结果解读

`misa_primer3.out`（TSV）：`ID / SSR nr. / SSR type / SSR / size / start / end` + 每记录最多 5 组
`left PRIMER / Tm / size / Right Primer / Tm / size / Product size`（列名与教学输出一致）。

```bash
# 有引物对的记录数 / 总记录数
awk -F'\t' 'NR>1{n++; if($8!="")p++} END{print p"/"n" 条记录设计出引物"}' results/misa_primer3.out
# 抽取全部左引物序列（FASTA）
awk -F'\t' 'NR>1 && $8!=""{print ">"$1"_L"$2"\n"$8}' results/misa_primer3.out
```

`misa_primer3.gff3`：每条记录为 `seqName  misa_primer3  SSR  start  end  .  .  .  ID=<seq>_<n>;Type=<SSR type>;SSR=<motif>;Size=<len>;Primer_N_left_seq=...;Primer_N_left_tm=...;Primer_N_product_size=...`，可直接在 IGV / JBrowse 中查看标记位置。

后续（教学链路）：引物特异性可用 NCBI Primer-BLAST 逐条复核；标记可用性（多态性）需在群体样本中 PCR 验证。

## Snakemake 骨架要点

复制到真实项目，改 `workflow/Snakefile` 使用；规则经 `python <repo>/modules/misa/native/main.py` 与 vendored 脚本直调（工具规则仍存 `modules/<sw>/snakemake/`）：

```python
GENOMES = ["genome"]

rule all:
    input: expand("results/{g}/misa_primer3.out", g=GENOMES)

rule misa_detect:                       # genome fasta -> <g>.misa（GFF: false）
    input:  "data/{g}.fasta"
    output: "results/{g}/misa/{g}.fasta.misa"
    shell:  "python ../../modules/misa/native/main.py detect {input} --outdir results/{wildcards.g}/misa"

rule misa_primer3_design:               # .misa -> 引物表 + GFF3（--CPU {threads}）
    input:  misa="results/{g}/misa/{g}.fasta.misa", fa="data/{g}.fasta"
    output: out="results/{g}/misa_primer3.out", gff="results/{g}/misa_primer3.gff3"
    threads: 8
    shell:  "cd results/{wildcards.g} && perl ../../subworkflow/misa_primer3/native/misa_primer3.pl "
            "--CPU {threads} --gff3_out ../misa_primer3.gff3 --p3_setting_file ../p3_settings_file "
            "{input.misa} {input.fa} > ../misa_primer3.out"
```

## Nextflow 骨架要点

官方无 nf-core misa 模块（404）→ 用 `modules/local` 包一层（primer3 同样官方无模块，见 [primer3 README](../../modules/primer3/README.md)「官方实现登记」）：

```groovy
process MISA_PRIMER3 {
    tag "$meta.id"
    cpus 8
    input:  tuple val(meta), path(fasta)
    output: tuple val(meta), path("misa_primer3.out"), path("misa_primer3.gff3")
    script:
    """
    python ${projectDir}/../modules/misa/native/main.py detect ${fasta} --outdir misa
    perl ${projectDir}/../subworkflow/misa_primer3/native/misa_primer3.pl \
        --CPU ${task.cpus} --flanking_length 300 --min_product_length 100 --max_product_length 250 \
        --gff3_out misa_primer3.gff3 --p3_setting_file p3_settings_file \
        misa/${fasta}.misa ${fasta} > misa_primer3.out
    """
}
```

## 如何把该组合接入真实项目

1. 按「环境准备」装好 `misa.pl` / `primer3_core` / `ParaFly` / `perl`（或直接用各自官方容器/自建镜像）；
2. 用 `--dry-run` 核对命令形态，再 `--real` 小数据试跑（建议先截取一条染色体）；
3. HPC 上按 `--CPU` 与位点数申请资源（`primer3_core` 单线程，内存需求很低）；
4. 复核 `modules/<sw>/meta.yaml` 的 `software_versions` 与容器用法（docker 必须 `-u $(id -u):$(id -g)`）。
