# workflow/isoseq — PacBio Iso-Seq 全长转录组复合流程

从 subreads 到转录本注释的 PacBio Iso-Seq 全长转录组流程：CCS 生成 HiFi 全长序列 → 去引物/拆分 → refine 去除 polyA 与接头 → BAM 转 FASTA → gstama polyA 清理 → 比对（minimap2 / uLTRA 双路径）→ gstama collapse / filelist / merge 出注释 bed。

* 元数据：同级 [meta.yaml](meta.yaml)（stages / inputs / outputs / execution）。

* 本流程为**目录形态**（对齐 nanoseq/、riboseq/）：含 [native/main.py](native/main.py) 编排入口 + [meta.yaml](meta.yaml) + 本文档。

## 原始来源与致谢

* 工具拆分为原子模块技能（`modules/`），本目录只保留**流程编排层**。

* **Nextflow**：nf-core 官方已有 [nf-core/isoseq](https://github.com/nf-core/isoseq)（Genome annotation with PacBio Iso-Seq，v2.0.0）——按「官方已有流程不建目录」规则**不建本地 nextflow/ 目录**，需 Nextflow 时直接用官方流程，或经各模块 `nextflow/local` 自行组装。

* 参考数据（水稻 Oryza\_rufipogon）：FASTA <https://ftp.ensemblgenomes.ebi.ac.uk/pub/plants/release-62/fasta/oryza_rufipogon/dna/Oryza_rufipogon.OR_W1943.dna.toplevel.fa.gz> ；GTF <https://ftp.ensemblgenomes.ebi.ac.uk/pub/plants/release-62/gtf/oryza_rufipogon/Oryza_rufipogon.OR_W1943.62.gtf.gz> ；gstama（python3 fork）<https://github.com/SiYangming/gs-tama。>

## 形态说明

本流程为**目录形态**（对齐 `riboseq/`、`nanoseq/`），代码资产与文档统一存放于 `workflow/isoseq/`：

* `isoseq.md`：本文件（含「附录」：pyflow 详细用法全文）

* `meta.yaml`：流程级元数据（stages / inputs / outputs / execution）

* `native/main.py`：流程编排入口（约 309 行样本循环编排器；`--list-stages` / `--dry-run` / `--real`）

本目录不含 `testdata/`、`LEGACY_README.md` 与 `snakemake/` 集成层（相关内容并入本文档）；各阶段工具能力由 `modules/` 原子模块承载。

## 依赖的原子模块（modules/）

| 阶段                          | 软件       | 模块实现（native 入口）                                             |
| --------------------------- | -------- | ----------------------------------------------------------- |
| CCS                         | pbccs    | `modules/pbccs`（`python main.py ccs`，chunk 并行）              |
| 去引物/拆分                      | lima     | `modules/lima`（`python main.py lima --isoseq --peek-guess`） |
| refine                      | isoseq3  | `modules/isoseq3`（`python main.py refine --require-polya`）  |
| BAM→FASTA                   | bamtools | `modules/bamtools`（`python main.py convert -format fasta`）  |
| polyA 清理                    | gstama   | `modules/gstama`（`python main.py polyacleanup`）             |
| 比对 A                        | minimap2 | `modules/minimap2`（`-x splice -uf -k14`）                    |
| 比对 B                        | ultra    | `modules/ultra`（index + align，需 GTF）                        |
| collapse / filelist / merge | gstama   | `modules/gstama`                                            |

各模块另含流程级规则（`<sw>/snakemake/`）与 Python 封装/并发批处理脚本（`<sw>/native/`：ccs\_analysis / lima\_analysis / isoseq3\_refine / bamtools\_convert / gs\_tama / tama\_polyacleanup / minimap2\_align / ULTRA\_align 的 `.py` 及对应 `run_*.sh`）。

## 执行方式

### A. 编排入口 main.py（dry-run 预览；--real 执行）

流程编排入口：`python workflow/isoseq/native/main.py --list-stages | --dry-run（默认）| --real`（仓库根执行）。逐 stage 手工串联亦可：每个样本沿固定阶段链调用 `modules/<sw>/native/main.py`，前一阶段输出即后一阶段输入：

```
subreads ──[pbccs/ccs]──> 01PBCCS/{sample}.chunk{n}.bam
  ──[lima]──> 02LIMA/{sample}.chunk{n}.bam
  ──[isoseq3 refine]──> 03ISOSEQ_REFINE/{sample}.chunk{n}.bam
  ──[bamtools convert -format fasta]──> 04BAMTOOLS_CONVERT/{sample}.chunk{n}.fasta
  ──[gstama polyacleanup]──> 05TAMA_POLYACLEANUP/{sample}.chunk{n}_gstama.fa.gz
  ──[minimap2 | uLTRA]──> 06_{aligner}/{sample}.chunk{n}.bam
  ──[gstama collapse]──> 07TAMA_COLLAPSE/{aligner}/{sample}/{sample}.chunk{n}_gstama_collapsed.bed
  ──[gstama filelist]──> 08TAMA_FILELIST/filelist.tsv
  ──[gstama merge]──> 09TAMA_MERGE/merged.bed
```

```bash
# 调用形态（先查看各模块参数）：
python modules/pbccs/native/main.py ccs --help
python modules/gstama/native/main.py collapse --help
```

**编排要点（原编排器逻辑，已记录于此）**：

* 每个样本循环执行；自 CCS 起按 `--chunk-num/--chunk-total` 分块，`chunk{n}` 编号**贯穿** lima → refine → bamtools → polyA → 比对 → collapse；

* 输出目录固定为 `01PBCCS … 09TAMA_MERGE`（与 meta.yaml outputs 的 path\_pattern 一致），后阶段从上阶段目录取输入；

* 支持 `start_from`（ccs|lima|refine|bamtools|gstama|mapping）从中间环节续跑，跳过此前阶段；

* 比对器二选一：`minimap2`（`-x splice -uf -k14`）或 `uLTRA`（index + align，需 GTF，先对 GTF sort）；aligner 名进入 `06_/07_` 目录；

* gstama collapse → filelist → merge 完成跨样本/跨比对器汇总；filelist 的 `order`/`source` 由 `chunk<N>` 与目录名自动生成，避免 `tama_merge.py` duplicate trans id 报错。

> [native/main.py](native/main.py)（约 309 行样本循环编排器）的串联逻辑即上文编排要点。

### B. Snakemake（按需在项目内重建；仓库不再内置 snakemake/ 目录）

本 workflow 不内置 `snakemake/` 集成层；Snakefile.template / config.yaml / config\_schema.yaml / samples\_schema.yaml 等文件清单与要点见下。需要 Snakemake 执行时，在**项目目录**内重建集成层：

1. 以 `Snakefile.template` 逻辑为骨架建立项目 `Snakefile`，`configfile: "config.yaml"`，并 `include:` 各原子模块规则（模块内路径相对仓库）：`../../../modules/{pbccs,lima,isoseq3,bamtools,gstama,minimap2,ultra}/snakemake/*.smk`（pbccs/lima/isoseq3\_refine/bamtools\_convert/gstama\_polyacleanup/gstama\_collapse/gstama\_filelist/gstama\_merge/minimap2\_align/ultra 等）；
2. `config.yaml` 关键项：`exec_mode: native`（规则直调本地二进制；docker 需按模块容器自行扩展）、01..09 输出目录（PBCCS\_DIR…TAMA\_MERGE）；
3. `config_schema.yaml` / `samples_schema.yaml`：`validate()` 用 schema。
4. 运行（执行入口为仓库共享 [scripts/run\_smk.sh](../../scripts/run_smk.sh)）：

```bash
cd project/snakemake
bash <repo>/scripts/run_smk.sh -n        # dry-run（预演）
bash <repo>/scripts/run_smk.sh           # 执行（exec_mode 见 config.yaml，默认 native）
```

> 重建文件清单与作用：Snakefile.template 逻辑（流程组装骨架）、config.yaml（exec\_mode=native 等流程参数）、config\_schema.yaml / samples\_schema.yaml（校验 schema）。各步骤规则在 `modules/<sw>/snakemake/` 下维护；独立部署时请一并带入对应模块规则（缺失时可用官方 `wrapper:` 句柄兜底）。

### C. Nextflow（nf-core 官方已有 → 不建本地目录）

直接运行 [nf-core/isoseq](https://github.com/nf-core/isoseq)（`nextflow run nf-core/isoseq -profile test,docker`）；本地需定制时用各模块 `nextflow/local` 自组装。

## 历史留存与详细用法

pyflow 封装（ccs\_analysis / lima / isoseq3\_refine / bamtools\_convert / tama\_polyacleanup / minimap2\_align / ULTRA\_align 的 Python 实现与 ParaFly→GNU parallel→xargs 并发批处理、`--*-bin` 路径注入、chunk 处理）现存放于各模块 `native/`（与 main.py 并列），**完整用法文档见本文档「附录」**。要点：

* **并发**：批处理脚本优先 ParaFly，其次 GNU parallel，最后 xargs -P；`CPUS_PER_TASK × PARA_CPU` 不超过机器总线程并预留 1-2 线程。

* **路径注入**：各封装支持 `--*-bin`（ccs/lima/isoseq3/bamtools/samtools/minimap2/uLTRA/namfinder）强制指定可执行绝对路径（支持 `~`），避免依赖 PATH。

* **uLTRA 路径**：`REFERENCE_FA` 必须为基因组 FASTA（勿用 cdna）；依赖 minimap2 与 namfinder（ultra\_bioinformatics 环境）；GTF 在 index 前需 sort。

* **filelist**：`cap` 仅支持 capped/no\_cap（Iso-Seq 默认 no\_cap）。

* **传参**：向 `--args` 传以 `-` 开头的值时用等号风格（`--args="--lde"`）。

## 容器与执行注意

* docker 模式经共享 `modules/docker_wrapper.py`（docker\_run 含 `-u $(id -u):$(id -g)` 与 `$(pwd)` 挂载）；`docker run` 必须带 `-u` 参数。

* uLTRA 未安装时使用 `--aligner minimap2`。

* Snakemake 按需重建见上文「执行方式 B」。

***

## 附录：pyflow 详细用法（历史留存全文）

> 注意：以下为原 pyflow 历史操作文档（其中路径 / 环境变量 / 并发参数为当时真实示例）。ccs\_analysis / lima\_analysis / isoseq3\_refine / bamtools\_convert / gs\_tama / tama\_polyacleanup / minimap2\_align / ULTRA\_align 等封装与批处理脚本现存放于 `modules/<sw>/native/`，正文中的 `pyflow/` 路径、conda 环境名（如 `pacbio_iso_seq`、`ultra_bioinformatics`）与 `--*-bin` 注入方式请按当前模块实际参数使用。

Genome Fasta: <https://ftp.ensemblgenomes.ebi.ac.uk/pub/plants/release-62/fasta/oryza_rufipogon/dna/Oryza_rufipogon.OR_W1943.dna.toplevel.fa.gz>

Gtf: <https://ftp.ensemblgenomes.ebi.ac.uk/pub/plants/release-62/gtf/oryza_rufipogon/Oryza_rufipogon.OR_W1943.62.gtf.gz>

Gs-tama for python3: <https://github.com/SiYangming/gs-tama>

一个基于Python调用PacBio CCS工具的脚本实现，结合了Nextflow流程中PBCCS模块的核心参数和逻辑：

```python
import os
import subprocess
import argparse
import json
from pathlib import Path

def run_ccs_analysis(subreads_bam, output_dir, chunk_num, chunk_total, 
                    min_rq=0.9, min_passes=3, min_snr=2.5, 
                    min_length=10, max_length=50000, top_passes=60, cpus=4):
    """
    调用PacBio CCS工具进行分析
    
    参数:
        subreads_bam: 输入subreads BAM文件路径
        output_dir: 输出文件目录
        chunk_num: 当前分块编号 (1-based)
        chunk_total: 总分块数
        min_rq: 最小读取质量阈值
        min_passes: 最小subread通过次数
        min_snr: 最小信噪比
        min_length: 最小序列长度
        max_length: 最大序列长度
        top_passes: 最大使用的subread通过次数
        cpus: 线程数
    """
    # 创建输出目录
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # 解析样本名
    sample_name = Path(subreads_bam).stem.replace('.subreads', '')
    prefix = output_dir / f"{sample_name}.chunk{chunk_num}"
    
    # 构建CCS命令
    cmd = [
        "ccs",
        str(subreads_bam),
        f"{prefix}.bam",
        f"--report-file {prefix}.report.txt",
        f"--report-json {prefix}.report.json",
        f"--metrics-json {prefix}.metrics.json.gz",
        f"--chunk {chunk_num}/{chunk_total}",
        f"--min-rq {min_rq}",
        f"--min-passes {min_passes}",
        f"--min-snr {min_snr}",
        f"--min-length {min_length}",
        f"--max-length {max_length}",
        f"--top-passes {top_passes}",
        f"-j {cpus}"
    ]
    
    # 拼接命令字符串
    cmd_str = ' \\\n    '.join(cmd)
    print(f"执行命令:\n{cmd_str}\n")
    
    # 执行命令
    try:
        result = subprocess.run(
            cmd_str,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        print("CCS分析完成")
        
        # 生成版本信息文件
        with open(output_dir / "versions.yml", "w") as f:
            version_output = subprocess.run(
                "ccs --version 2>&1 | grep 'ccs' | sed 's/^.*ccs //; s/ .*$//'",
                shell=True,
                stdout=subprocess.PIPE,
                text=True
            ).stdout.strip()
            f.write(f"PBCCS:\n    pbccs: {version_output}\n")
            
        return {
            "bam": f"{prefix}.bam",
            "pbi": f"{prefix}.bam.pbi",
            "report_txt": f"{prefix}.report.txt",
            "report_json": f"{prefix}.report.json",
            "metrics": f"{prefix}.metrics.json.gz"
        }
        
    except subprocess.CalledProcessError as e:
        print(f"命令执行失败: {e.stderr}")
        raise

def main():
    parser = argparse.ArgumentParser(description="PacBio CCS分析工具")
    parser.add_argument("--subreads", required=True, help="输入subreads BAM文件路径")
    parser.add_argument("--outdir", required=True, help="输出目录")
    parser.add_argument("--chunk-num", type=int, required=True, help="当前分块编号 (1-based)")
    parser.add_argument("--chunk-total", type=int, required=True, help="总分块数")
    parser.add_argument("--min-rq", type=float, default=0.9, help="最小读取质量阈值 (0-1)")
    parser.add_argument("--min-passes", type=int, default=3, help="最小subread通过次数")
    parser.add_argument("--min-snr", type=float, default=2.5, help="最小信噪比")
    parser.add_argument("--min-length", type=int, default=10, help="最小序列长度")
    parser.add_argument("--max-length", type=int, default=50000, help="最大序列长度")
    parser.add_argument("--top-passes", type=int, default=60, help="最大使用的subread通过次数")
    parser.add_argument("--cpus", type=int, default=4, help="线程数")
    
    args = parser.parse_args()
    
    # 运行CCS分析
    run_ccs_analysis(
        subreads_bam=args.subreads,
        output_dir=args.outdir,
        chunk_num=args.chunk_num,
        chunk_total=args.chunk_total,
        min_rq=args.min_rq,
        min_passes=args.min_passes,
        min_snr=args.min_snr,
        min_length=args.min_length,
        max_length=args.max_length,
        top_passes=args.top_passes,
        cpus=args.cpus
    )

if __name__ == "__main__":
    main()
```

### 脚本特点说明：

1. **参数映射**：完全对应Nextflow流程中PBCCS模块的核心参数（如`--min-rq`、`--min-passes`等），保持与原流程的一致性

2. **分块处理**：通过`--chunk-num`和`--chunk-total`参数实现数据分块处理，与PacBio CCS工具的分块要求匹配

3. **输出文件**：生成与Nextflow流程相同的输出文件集合，包括：

   * CCS序列BAM文件（含PBI索引）

   * 文本格式报告（.report.txt）

   * JSON格式报告（.report.json）

   * ZMW统计数据（.metrics.json.gz）

   * 软件版本信息（versions.yml）

4. **使用方法**：

   ```bash
   python ccs_analysis.py \
       --subreads input.subreads.bam \
       --outdir ccs_output \
       --chunk-num 1 \
       --chunk-total 40 \
       --min-rq 0.9 \
       --cpus 8
   ```

5. **批量处理**：可结合循环实现多块处理，例如处理40个分块：

   ```bash
   for i in {1..40}; do
       python ccs_analysis.py \
           --subreads input.subreads.bam \
           --outdir ccs_output \
           --chunk-num $i \
           --chunk-total 40
   done
   ```

该脚本保留了Nextflow流程中PBCCS模块的核心功能和参数逻辑，同时提供了更灵活的Python调用方式，便于集成到其他分析流程中。

### 基于目录的批量调用示例（C8TF/all）

已知数据目录结构：

```
C8TF/all/
├── FISO24H001386_1A/
│   ├── m64291e_240605_123752.subreads.bam
│   ├── m64291e_240605_123752.subreads.bam.pbi
│   └── m64291e_240605_123752.subreadset.xml
└── FISO24H001389_1A/
    ├── m64268e_240609_122603.subreads.bam
    ├── m64268e_240609_122603.subreads.bam.pbi
    └── m64268e_240609_122603.subreadset.xml
```

在上述目录下批量遍历每个样本并调用脚本（可选择分块或不分块）：

```bash
#!/bin/bash

# 可选：激活运行环境
# conda activate pacbio_iso_seq

DATA_DIR="C8TF/all"       # 指向包含样本子目录的路径
OUT_BASE="ccs_output"     # 输出根目录
CPUS=8
CHUNK_TOTAL=40            # 若不分块，将其设为 1

mkdir -p "$OUT_BASE"

for bam in "$DATA_DIR"/*/*.subreads.bam; do
  sample_dir=$(basename "$(dirname "$bam")")
  for i in $(seq 1 "$CHUNK_TOTAL"); do
    python ccs_analysis.py \
      --subreads "$bam" \
      --outdir "$OUT_BASE/$sample_dir" \
      --chunk-num "$i" \
      --chunk-total "$CHUNK_TOTAL" \
      --cpus "$CPUS"
      --ccs-bin "~/miniconda3/envs/pacbio_iso_seq/bin/ccs"
  done
done
```

* 将 `CHUNK_TOTAL` 设为 `1` 即表示不分块，只运行一次（`--chunk-num 1 --chunk-total 1`）。

* 输出文件将写入 `ccs_output/<样本目录>/`，包含 BAM、报告、metrics 和 `versions.yml`。

### 更新说明：并发批处理脚本（ParaFly/parallel/xargs）

* 新增 `pyflow/run_ccs_analysis.sh`，先生成所有命令到 `ccs_output/ccs_commands.txt`，再并发执行。

* 并发执行优先使用 `ParaFly`，其次 `GNU parallel`，最后降级为 `xargs -P`。

* 关键参数（均可通过环境变量覆盖）：

  * `DATA_DIR`：输入目录，默认 `C8TF/all`

  * `OUT_BASE`：输出根目录，默认 `ccs_output`

  * `CHUNK_TOTAL`：分块总数（不分块设为 `1`）

  * `CPUS_PER_TASK`：每个 `ccs` 任务使用的线程数（传入脚本的 `--cpus`）

  * `PARA_CPU`：并发任务数（总占用约为 `CPUS_PER_TASK * PARA_CPU`）

  * `CMD_FILE`：命令列表文件路径，默认 `ccs_output/ccs_commands.txt`

示例：每任务 8 线程，同时运行 28 个任务（总约 224 线程）

```bash
CPUS_PER_TASK=8 PARA_CPU=28 CHUNK_TOTAL=40 bash pyflow/run_ccs_analysis.sh
```

更保守的并发示例：

```bash
CPUS_PER_TASK=8 PARA_CPU=16 bash pyflow/run_ccs_analysis.sh
# 或者：CPUS_PER_TASK=4 PARA_CPU=32
```

### 更新说明：强制指定 ccs 绝对路径（--ccs-bin）

* `pyflow/ccs_analysis.py` 现支持 `--ccs-bin` 参数，使用你指定的 `ccs` 可执行路径（支持 `~` 展开），用于主命令与版本信息获取。

* `pyflow/run_ccs_analysis.sh` 也支持通过环境变量 `CCS_BIN` 为所有生成的命令统一注入 `--ccs-bin`。

示例：单次运行指定绝对路径

```bash
python3 pyflow/ccs_analysis.py \
  --subreads input.subreads.bam \
  --outdir ccs_output \
  --chunk-num 1 \
  --chunk-total 40 \
  --ccs-bin "~/miniconda3/envs/pacbio_iso_seq/bin/ccs"
```

## gs-TAMA 封装：polyacleanup / collapse / filelist / merge

新增 `pyflow/gs_tama.py` 提供对 TAMA 流程四个环节的轻量封装，并配套批处理脚本 `pyflow/run_gs_tama.sh`（collapse→filelist→merge）与 polyA 清理独立批处理脚本 `pyflow/run_gs_tama_polyacleanup.sh`。整体链路：

* polyacleanup：清理 FLNC FASTA（可衔接 BamTools convert 输出）

* collapse：基于对齐后的 BAM/SAM 与参考基因组 FASTA 进行转录本去冗余

* filelist：聚合多个 collapsed bed 为 TSV。每行四列：`bed_path`、`cap`、`order`、`source`。

  * `cap`：仅支持 `capped`/`no_cap`（Iso-Seq 默认 `no_cap`）

  * `order`：自动从文件名中的 `chunk<N>` 提取并写为 `<N>,<N>,<N>`（无则回退 `1,1,1`）

  * `source`：自动设置为唯一的来源标签，格式为 `<source>:<sample>:<file_tag>`：

    * `<source>`：软件来源（`ultra` 或 `minimap2`），取自 `--bed-dir` 的目录名

    * `<sample>`：bed 文件的上级目录名（样本名）

    * `<file_tag>`：去掉扩展名的文件基名（例如包含 `chunk1_tama_collapsed`），用于避免多个文件内的转录本 ID 冲突

    * 这样可以在同时合并多个样本与 chunk 的情况下避免 `tama_merge.py` 出现 “Error with duplicate trans id”。

* merge：按照 filelist 进行来源保留的合并

依赖：

* TAMA 脚本位于仓库内 `pyflow/gs-tama-1.0.3`，可直接调用；若系统已通过 `conda install -c bioconda gs-tama` 安装，也可不传脚本路径。

* 某些脚本可能包含 `xrange` 等 Python2 语法，封装内已通过 in-process 运行与垫片兼容。如遇到环境冲突，可改用系统 PATH 中的 `tama_collapse.py` / `tama_merge.py`。

示例（单样本命令）：

* polyacleanup：

  * `python3 pyflow/gs_tama.py polyacleanup --fasta bamtools_convert_output/sample1/sample1.fasta --outdir tama_polyacleanup_output/sample1 --args="--some-flag"`

  * 可选指定脚本：`--tama-script pyflow/gs-tama-1.0.3/tama_go/sequence_cleanup/tama_flnc_polya_cleanup.py`

* collapse：

  * `python3 pyflow/gs_tama.py collapse --bam ultra_align_output/sample1.bam --fasta /path/to/genome.fa --outdir gstama_collapse_output/sample1 --args="--lde --sj_filter"`

  * 可选指定脚本：`--tama-collapse-script pyflow/gs-tama-1.0.3/tama_collapse.py`

  * 强制指定 samtools 路径：`--samtools-bin "~/miniconda3/envs/pacbio_iso_seq/bin/samtools"`（封装会将该路径所在目录优先加入 `PATH`，确保 TAMA 内部调用的 `samtools` 使用该版本）

* filelist：

  * `python3 pyflow/gs_tama.py filelist --bed-dir gstama_collapse_output --cap no_cap --outdir gstama_filelist_output --prefix tama_merge_sources`

* merge：

  * `python3 pyflow/gs_tama.py merge --filelist gstama_filelist_output/tama_merge_sources.tsv --outdir gstama_merge_output --prefix merged --args="--some-merge-flag"`

  * 可选指定脚本：`--tama-merge-script pyflow/gs-tama-1.0.3/tama_merge.py`

批处理脚本：

* `bash pyflow/run_gs_tama.sh` 按顺序执行 2) collapse → 3) filelist → 4) merge；polyA 清理已拆分为独立脚本（见下）。可通过以下环境变量调整：

  * `COLLAPSE_BAM_DIR`、`GENOME_FA`、`COLLAPSE_OUT_BASE`、`COLLAPSE_ARGS`、`TAMA_COLLAPSE_SCRIPT`、`COLLAPSE_CPU`

  * `FILELIST_BED_DIR`、`FILELIST_CAP`、`FILELIST_OUT_BASE`、`FILELIST_PREFIX`

  * `MERGE_OUT_BASE`、`MERGE_ARGS`、`TAMA_MERGE_SCRIPT`

  * `SAMTOOLS_BIN`：为所有 collapse 子任务统一指定 `samtools` 绝对路径（例如 `~/miniconda3/envs/pacbio_iso_seq/bin/samtools`）；脚本将为每条命令注入 `--samtools-bin`，并在封装内将其目录前置到 `PATH`

  * 双来源合并（ULTRA + minimap2）：

    * 新增 `COLLAPSE_BAM_DIR_SECOND`（默认 `minimap2_align_output`），同时收集 `COLLAPSE_BAM_DIR`（默认 `ultra_align_output`）与第二来源的对齐结果。

    * collapse 输出按来源分目录：`gstama_collapse_output/ultra/<样本>` 与 `gstama_collapse_output/minimap2/<样本>`，避免同名覆盖。

* 生成 filelist 时分别聚合两个来源并合并为一个总 TSV，脚本内部已使用 `--pattern "**/*collapsed.bed"` 递归匹配嵌套样本目录，仅纳入最终 `collapsed.bed`（避免将 `trans_read.bed` 也纳入）。

  * 分来源仅配置 `cap`：`FILELIST_CAP_ULTRA`、`FILELIST_CAP_MINIMAP2`（默认沿用通用 `FILELIST_CAP`）。

  * 不再需要手动设置来源优先级 `order`；脚本会按每个 `*_collapsed.bed` 的 `chunk<N>` 自动生成 `<N>,<N>,<N>`。

示例：统一指定 samtools 绝对路径运行批处理 collapse：

```bash
SAMTOOLS_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/samtools \
GENOME_FA=/data/genome/hg38.fa \
bash pyflow/run_gs_tama.sh
```

* `bash pyflow/run_gs_tama_polyacleanup.sh` 并发执行 1) polyA 清理（独立脚本）：

  * 环境变量：

    * `DATA_DIR` 输入 FASTA 根目录（默认 `bamtools_convert_output`）

    * `OUT_BASE` 输出根目录（默认 `tama_polyacleanup_output`）

    * `ARGS` 透传给 TAMA 清理脚本的参数（例如 `--max_3p_mismatch=2 --trim_min_len=10`）

    * `PARA_CPU` 并发任务数（默认 28）

    * `CMD_FILE` 命令列表文件（默认 `tama_polyacleanup_commands.txt` 位于输出目录下）

    * `TAMA_SCRIPT` 指定 `tama_flnc_polya_cleanup.py` 的绝对路径（不设置则使用仓库内默认）

  * 说明：支持 ParaFly、GNU parallel、xargs 并发，优先 ParaFly；`--args` 建议使用等号风格传参。

注意：

* collapse 必须提供参考基因组 FASTA（`GENOME_FA` 或 `--fasta`）。

* 当向 `--args` 传递值且该值以连字符开头（例如 `--lde`）时，请使用等号风格：`--args="--lde --sj_filter"`，以避免被 argparse 误判为顶层参数。

Python3 兼容修复（dict\_keys 排序）：

* 旧写法（Python2）：`start_gene_list = start_gene_dict.keys(); start_gene_list.sort()` 在 Python3 中会报错：`AttributeError: 'dict_keys' object has no attribute 'sort'`。

* 统一替换为：`start_gene_list = sorted(start_gene_dict.keys())`；对于 `tama_collapse.py` 中汇总所有起始位点的逻辑，修复为：`all_start_list = sorted(all_start_gene_dict.keys())` 并使用该列表遍历。

## Lima 分析（Python实现 + 并发批处理）

`pyflow/lima_analysis.py` 复刻了 `modules/nf-core/lima` 的核心行为：

* 接受 `reads`（支持 `bam/fasta/fasta.gz/fastq/fastq.gz`）与 `primers.fasta`

* 输出文件扩展名随输入类型自动匹配（如输入 `bam` 则输出 `prefix.bam`）

* 支持 `-j` 线程参数自动/手动配置，并记录 `versions.yml`

* 允许透传附加参数到 `lima`（`--args "..."`）

* 支持强制指定 `lima` 绝对路径（`--lima-bin`）

### 单样本使用示例

```bash
python3 pyflow/lima_analysis.py \
  --reads ccs_output/SAMPLE/m64291e_ccs.chunk1.bam \
  --primers pyflow/primers.fasta \
  --outdir lima_output/SAMPLE \
  --cpus 8 \
  --args "--isoseq --peek-guess" \
  --lima-bin "~/miniconda3/envs/pacbio_iso_seq/bin/lima"
```

不指定 `--prefix` 时，前缀将从 `reads` 文件名推断（自动去除 `.bam`/`.fasta(.gz)`/`.fastq(.gz)` 后缀）。

### 并发批处理脚本（run\_lima\_analysis.sh）

已新增 `pyflow/run_lima_analysis.sh`：

* 先写入所有待执行命令到 `lima_output/lima_commands.txt`

* 并发执行优先使用 `ParaFly`，其次 `GNU parallel`，最后 `xargs -P` 降级

* 自动遍历 `DATA_DIR` 下的 `*.bam/*.fasta/*.fastq/*.fasta.gz/*.fastq.gz`

关键参数（均可通过环境变量覆盖）：

* `DATA_DIR`：输入目录，默认 `ccs_output`

* `OUT_BASE`：输出根目录，默认 `lima_output`

* `PRIMERS`：引物 fasta，默认 `pyflow/primers.fasta`

* `CPUS_PER_TASK`：每个 `lima` 任务使用线程数（传入 `--cpus`），默认 `8`

* `PARA_CPU`：并发任务数，默认 `28`

* `CMD_FILE`：命令列表文件路径，默认 `lima_output/lima_commands.txt`

* `LIMA_BIN`：可选，`lima` 绝对路径，若设置则为所有命令注入 `--lima-bin`

示例：批量处理 `ccs_output/*/*.bam` 并发执行

```bash
PRIMERS=pyflow/primers.fasta \
CPUS_PER_TASK=8 PARA_CPU=28 \
bash pyflow/run_lima_analysis.sh
```

更保守的并发示例：

```bash
CPUS_PER_TASK=6 PARA_CPU=12 bash pyflow/run_lima_analysis.sh
```

### 关于线程自动选择

`lima_analysis.py` 与 `ccs_analysis.py` 一致：默认自动选择“合理线程数”（在可能情况下预留 1 个线程，避免完全占满机器）。可通过 `--cpus` 手动覆盖，并在批处理脚本中用 `CPUS_PER_TASK` 控制每个任务的线程数与总体并发。

示例：批量运行统一指定绝对路径

```bash
CCS_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/ccs \
CPUS_PER_TASK=8 PARA_CPU=28 bash pyflow/run_ccs_analysis.sh
```

可选替代方案：通过调整 `PATH` 优先级使用环境中的 `ccs`

```bash
export PATH=~/miniconda3/envs/pacbio_iso_seq/bin:$PATH
```

## IsoSeq3 Refine（Python实现 + 并发批处理）

`pyflow/isoseq3_refine.py` 复刻了 `modules/nf-core/isoseq3/refine` 的核心行为：

* 输入为 Lima 产出的 bam 与引物 fasta

* 输出包含：`<prefix>.bam`、`<prefix>.bam.pbi`、`<prefix>.consensusreadset.xml`、`<prefix>.filter_summary.report.json`、`<prefix>.report.csv`、`versions.yml`

* 支持 `-j` 线程自动/手动配置，并记录版本信息

* 支持透传 refine 参数（`--args "..."`），例如 `--require-polya --min-polya-length 20`

* 支持强制指定 `isoseq3` 绝对路径（`--isoseq3-bin`）

### 单样本使用示例

```bash
python3 pyflow/isoseq3_refine.py \
  --bam lima_output/SAMPLE/m64291e_ccs.chunk1.bam \
  --primers pyflow/primers.fasta \
  --outdir refine_output/SAMPLE \
  --cpus 8 \
  --args "--require-polya --min-polya-length 20" \
  --isoseq3-bin "~/miniconda3/envs/pacbio_iso_seq/bin/isoseq3"
```

不指定 `--prefix` 时，前缀从输入 bam 文件名推断（去除 `.bam` 后缀），输出写到独立 `refine_output/<样本>` 目录，避免与输入文件同路径冲突。

### 并发批处理脚本（run\_isoseq3\_refine.sh）

已新增 `pyflow/run_isoseq3_refine.sh`：

* 先写入所有待执行命令到 `refine_output/refine_commands.txt`

* 并发执行优先使用 `ParaFly`，其次 `GNU parallel`，最后 `xargs -P` 降级

* 自动遍历 `DATA_DIR` 下的 `*.bam`（默认指向 `lima_output`）

关键参数（均可通过环境变量覆盖）：

* `DATA_DIR`：输入目录，默认 `lima_output`

* `OUT_BASE`：输出根目录，默认 `refine_output`

* `PRIMERS`：引物 fasta，默认 `pyflow/primers.fasta`

* `CPUS_PER_TASK`：每个 refine 任务使用线程数（传入 `--cpus`），默认 `8`

* `PARA_CPU`：并发任务数，默认 `28`

* `CMD_FILE`：命令列表文件路径，默认 `refine_output/refine_commands.txt`

* `ISOSEQ3_BIN`：可选，`isoseq3` 绝对路径，若设置则为所有命令注入 `--isoseq3-bin`

示例：批量处理 `lima_output/*/*.bam` 并发执行

```bash
PRIMERS=pyflow/primers.fasta \
CPUS_PER_TASK=8 PARA_CPU=28 \
bash pyflow/run_isoseq3_refine.sh
```

#### 修正说明：避免 “/bin/sh: isoseq3: 未找到命令”

* 现象：主命令完成后控制台出现上述错误信息。

* 原因：旧版本在写出 `versions.yml` 时调用 `isoseq3 refine --version` 依赖系统 `PATH`，当 `PATH` 中没有 `isoseq3` 时会输出错误。

* 修正：`pyflow/isoseq3_refine.py` 现已使用相同的可执行路径（通过 `--isoseq3-bin` 或自动解析出的绝对路径）进行版本检测，并捕获 `stderr`，避免噪声输出。

* 建议：

  * 单样本：在命令中加入 `--isoseq3-bin "~/miniconda3/envs/pacbio_iso_seq/bin/isoseq3"`

  * 批处理：在运行脚本前设置 `ISOSEQ3_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/isoseq3`，脚本会为所有命令注入该路径

### 完整流程串联（CCS → Lima → IsoSeq3 Refine）

以下示例展示如何将三步流程串联并合理控制并发：

1. CCS（目录批处理并发）

```bash
DATA_DIR=C8TF/all \
OUT_BASE=ccs_output CHUNK_TOTAL=40 \
CPUS_PER_TASK=8 PARA_CPU=28 \
CCS_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/ccs \
bash pyflow/run_ccs_analysis.sh
```

1. Lima（目录批处理并发）

```bash
DATA_DIR=ccs_output \
OUT_BASE=lima_output \
PRIMERS=pyflow/primers.fasta \
CPUS_PER_TASK=8 PARA_CPU=28 \
LIMA_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/lima \
bash pyflow/run_lima_analysis.sh
```

1. IsoSeq3 refine（目录批处理并发）

```bash
DATA_DIR=lima_output \
OUT_BASE=isoseq3_refine_output \
PRIMERS=pyflow/primers.fasta \
CPUS_PER_TASK=8 PARA_CPU=28 \
ISOSEQ3_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/isoseq3 \
bash pyflow/run_isoseq3_refine.sh
```

并发与线程建议：

* 将每任务线程（`CPUS_PER_TASK`）与并发数（`PARA_CPU`）相乘不要超过机器总线程；预留 1-2 线程给系统更稳妥

* 如果 `ccs` 任务本身较重，建议降低 `PARA_CPU` 或将 `CPUS_PER_TASK` 设为比自动选取更低的值

提示：若后续需要进一步进行 polyA 清理（`gstama/polyacleanup`），可在 refine 之后将 FLNC 序列转换为 fasta 并调用 TAMA 的清理脚本；当前文档与实现聚焦于 `isoseq3 refine`，保持与 nf-core 模块输出一致，便于衔接下游环节。

## BamTools Convert（Python实现 + 并发批处理）

`pyflow/bamtools_convert.py` 封装了 `modules/nf-core/bamtools/convert` 的行为：

* 输入：`BAM`（对接 `isoseq3 refine` 输出）

* 必选格式：`-format`（支持 `bed/fasta/fastq/json/pileup/sam/yaml`，默认 `fasta`）

* 输出：`<prefix>.<format>` 与 `versions.yml`（版本号来源于 `bamtools --version`）

* 允许透传附加参数到 `bamtools convert`（`--args "..."`），如 `-region chr1:100-200`

* 支持强制指定 `bamtools` 绝对路径（`--bamtools-bin`）

### 单样本使用示例

```bash
python3 pyflow/bamtools_convert.py \
  --bam isoseq3_refine_output/SAMPLE/m64291e_ccs.chunk1.bam \
  --outdir bamtools_convert_output/SAMPLE \
  --format fasta \
  --bamtools-bin "~/miniconda3/envs/pacbio_iso_seq/bin/bamtools"
```

不指定 `--prefix` 时，前缀将从输入 `bam` 文件名推断（去除 `.bam`）。默认输出 `fasta`，方便下游 polyA 清理或 TAMA 处理。

### 并发批处理脚本（run\_bamtools\_convert.sh）

已新增 `pyflow/run_bamtools_convert.sh`：

* 先写入所有待执行命令到 `bamtools_convert_output/bamtools_convert_commands.txt`

* 并发执行优先使用 `ParaFly`，其次 `GNU parallel`，最后 `xargs -P` 降级

* 自动遍历 `DATA_DIR` 下的 `*.bam`（默认指向 `isoseq3_refine_output`）

关键参数（均可通过环境变量覆盖）：

* `DATA_DIR`：输入目录，默认 `isoseq3_refine_output`

* `OUT_BASE`：输出根目录，默认 `bamtools_convert_output`

* `FORMAT`：输出格式，默认 `fasta`

* `ARGS`：透传给 `bamtools convert` 的附加参数（如 `-region`），默认空

* `PARA_CPU`：并发任务数，默认 `28`

* `CMD_FILE`：命令列表文件路径，默认 `bamtools_convert_output/bamtools_convert_commands.txt`

* `BAMTOOLS_BIN`：可选，`bamtools` 绝对路径，若设置则为所有命令注入 `--bamtools-bin`

示例：批量将 refine 输出转换为 FASTA 并发执行

```bash
FORMAT=fasta PARA_CPU=28 \
BAMTOOLS_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/bamtools \
bash pyflow/run_bamtools_convert.sh
```

### 完整流程串联（CCS → Lima → IsoSeq3 Refine → BamTools Convert）

在前三步基础上追加 BamTools 转换：

1. BamTools convert（目录批处理并发，默认转 FASTA）

```bash
DATA_DIR=isoseq3_refine_output \
OUT_BASE=bamtools_convert_output \
FORMAT=fasta PARA_CPU=28 \
BAMTOOLS_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/bamtools \
bash pyflow/run_bamtools_convert.sh
```

## TAMA PolyA Cleanup（Python实现 + 并发批处理）

`pyflow/tama_polyacleanup.py` 封装了 `modules/nf-core/gstama/polyacleanup` 的行为：

* 输入：`FASTA`（对接 `bamtools convert` 的输出）

* 输出：`<prefix>.fa.gz`、`<prefix>_polya_flnc_report.txt.gz`、`<prefix>_tails.fa.gz` 与 `versions.yml`

* 允许透传附加参数到 `tama_flnc_polya_cleanup.py`（`--args "..."`）

* 支持强制指定 `tama_flnc_polya_cleanup.py` 绝对路径（`--tama-script`，默认使用仓库内 `gs-tama-1.0.3` 路径）

* 未显式指定 `--prefix` 时，会在输入文件名基础上追加 `_tama`（与 nf-core 模块输出一致）

### 单样本使用示例

```bash
python3 pyflow/tama_polyacleanup.py \
  --fasta bamtools_convert_output/SAMPLE/m64291e_ccs.chunk1.fasta \
  --outdir tama_polyacleanup_output/SAMPLE \
  --tama-script \
  "pyflow/gs-tama-1.0.3/tama_go/sequence_cleanup/tama_flnc_polya_cleanup.py"
```

不指定 `--prefix` 时，输出前缀将自动在输入文件名基础上追加 `_tama`，并将三个核心结果文件以 `gzip` 压缩写出。

### 并发批处理脚本（run\_tama\_polyacleanup.sh）

已新增 `pyflow/run_tama_polyacleanup.sh`：

* 先写入所有待执行命令到 `tama_polyacleanup_output/tama_polyacleanup_commands.txt`

* 并发执行优先使用 `ParaFly`，其次 `GNU parallel`，最后 `xargs -P` 降级

* 自动遍历 `DATA_DIR` 下的 `*.fa/*.fasta`（默认指向 `bamtools_convert_output`）

关键参数（均可通过环境变量覆盖）：

* `DATA_DIR`：输入目录，默认 `bamtools_convert_output`

* `OUT_BASE`：输出根目录，默认 `tama_polyacleanup_output`

* `ARGS`：透传给 TAMA 脚本的附加参数，默认空

* `PARA_CPU`：并发任务数，默认 `28`

* `CMD_FILE`：命令列表文件路径，默认 `tama_polyacleanup_output/tama_polyacleanup_commands.txt`

* `TAMA_SCRIPT`：可选，`tama_flnc_polya_cleanup.py` 绝对路径，若设置则为所有命令注入 `--tama-script`

示例：批量清理 BamTools 转换得到的 FASTA 并发执行

```bash
DATA_DIR=bamtools_convert_output \
OUT_BASE=tama_polyacleanup_output \
PARA_CPU=28 \
TAMA_SCRIPT=pyflow/gs-tama-1.0.3/tama_go/sequence_cleanup/tama_flnc_polya_cleanup.py \
bash pyflow/run_tama_polyacleanup.sh
```

### 完整流程串联（CCS → Lima → IsoSeq3 Refine → BamTools Convert → TAMA PolyA Cleanup）

在前四步基础上追加 TAMA polyA 清理：

1. TAMA polyA cleanup（目录批处理并发）

```bash
DATA_DIR=bamtools_convert_output \
OUT_BASE=tama_polyacleanup_output \
PARA_CPU=28 \
TAMA_SCRIPT=pyflow/gs-tama-1.0.3/tama_go/sequence_cleanup/tama_flnc_polya_cleanup.py \
bash pyflow/run_tama_polyacleanup.sh
```

说明：TAMA 脚本缺少 `-j` 线程参数，故并发由外部脚本控制；如需调整清理细节，请通过 `ARGS` 透传支持的选项（参考 TAMA 文档）。最终清理输出以 `gzip` 压缩，便于后续 TAMA collapse/merge 或其他下游处理。

## Minimap2 Align（Python实现 + 并发批处理）

`pyflow/minimap2_align.py` 封装了 `modules/nf-core/minimap2/align` 的核心行为：

* 接受 `reads`（支持 `fasta/fastq/.gz`）与 `reference`（FASTA）；若不提供 `reference`，退化为 reads vs reads（与 nf-core 逻辑一致）

* 输出：`<prefix>.paf` 或 `<prefix>.bam`（根据是否指定 `--bam`），以及 `versions.yml`

* 选项：`--bam`（BAM输出）、`--cigar-paf`（PAF写CIGAR，`-c`）、`--cigar-bam`（BAM长CIGAR写CG标签，`-L`）

* 透传 minimap2 参数：`--args "-x splice -uf -k14"` 等（适用于转录组长读段）

* 可强制指定可执行路径：`--minimap2-bin` 与 `--samtools-bin`

* 线程：`--cpus`（默认自动选择，避免占满机器）

* 前缀：`--prefix`（默认从 `reads` 文件名去扩展名推断）

### 单样本使用示例（PAF 输出）

```bash
python3 pyflow/minimap2_align.py \
  --reads tama_polyacleanup_output/SAMPLE/m64291e_ccs.chunk1_tama.fa.gz \
  --reference /data/genome/hg38.fa \
  --outdir minimap2_align_output/SAMPLE \
  --cpus 8 \
  --args "-x splice -uf -k14"
```

### 单样本使用示例（BAM 输出 + CG 标签）

```bash
python3 pyflow/minimap2_align.py \
  --reads tama_polyacleanup_output/SAMPLE/m64291e_ccs.chunk1_tama.fa.gz \
  --reference /data/genome/hg38.fa \
  --outdir minimap2_align_output/SAMPLE \
  --cpus 8 \
  --args "-x splice -uf -k14" \
  --bam --cigar-bam \
  --minimap2-bin "~/miniconda3/envs/pacbio_iso_seq/bin/minimap2" \
  --samtools-bin "~/miniconda3/envs/pacbio_iso_seq/bin/samtools"
```

### 并发批处理脚本（run\_minimap2\_align.sh）

已新增 `pyflow/run_minimap2_align.sh`：

* 先写入所有待执行命令到 `minimap2_align_output/minimap2_commands.txt`

* 并发执行优先使用 `ParaFly`，其次 `GNU parallel`，最后 `xargs -P` 降级

* 自动遍历 `DATA_DIR` 下的 `*.fa/*.fa.gz/*.fasta/*.fasta.gz/*.fastq/*.fastq.gz`（默认指向 `tama_polyacleanup_output`）

关键参数（均可通过环境变量覆盖）：

* `DATA_DIR`：输入目录，默认 `tama_polyacleanup_output`

* `OUT_BASE`：输出根目录，默认 `minimap2_align_output`

* `REFERENCE`：参考基因组 FASTA（必填）

* `OUTPUT_FORMAT`：`paf` 或 `bam`（默认 `paf`）

* `MINIMAP2_ARGS`：透传 minimap2 的附加参数（如 `-x splice -uf -k14`）

* `CPUS_PER_TASK`：每个比对任务使用线程数（传入 `--cpus`），默认 `8`

* `PARA_CPU`：并发任务数，默认 `28`

* `CMD_FILE`：命令列表文件路径，默认 `minimap2_align_output/minimap2_commands.txt`

* `MINIMAP2_BIN`：可选，`minimap2` 绝对路径，若设置则为所有命令注入 `--minimap2-bin`

* `SAMTOOLS_BIN`：可选，`samtools` 绝对路径（BAM 输出时使用），若设置则注入 `--samtools-bin`

* `CIGAR_PAF`：若非空则在 PAF 写 CIGAR（`-c`）

* `CIGAR_BAM`：若非空则在 BAM 写 CG 标签（`-L`）

示例：批量生成 PAF 输出并发执行

```bash
DATA_DIR=tama_polyacleanup_output \
OUT_BASE=minimap2_align_output \
REFERENCE=/data/genome/hg38.fa \
OUTPUT_FORMAT=paf \
MINIMAP2_ARGS="-x splice -uf -k14" \
CPUS_PER_TASK=8 PARA_CPU=28 \
bash pyflow/run_minimap2_align.sh
```

示例：批量生成 BAM 输出（写 CG 标签）

```bash
DATA_DIR=tama_polyacleanup_output \
OUT_BASE=minimap2_align_output \
REFERENCE=/data/genome/hg38.fa \
OUTPUT_FORMAT=bam CIGAR_BAM=1 \
MINIMAP2_ARGS="-x splice -uf -k14" \
MINIMAP2_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/minimap2 \
SAMTOOLS_BIN=~/miniconda3/envs/pacbio_iso_seq/bin/samtools \
CPUS_PER_TASK=8 PARA_CPU=28 \
bash pyflow/run_minimap2_align.sh
```

### 完整流程串联（CCS → Lima → IsoSeq3 Refine → BamTools Convert → TAMA PolyA Cleanup → Minimap2 Align）

在前五步基础上追加 Minimap2 比对：

1. Minimap2 align（目录批处理并发）

```bash
DATA_DIR=tama_polyacleanup_output \
OUT_BASE=minimap2_align_output \
REFERENCE=/data/genome/hg38.fa \
OUTPUT_FORMAT=paf \
MINIMAP2_ARGS="-x splice -uf -k14" \
CPUS_PER_TASK=8 PARA_CPU=28 \
bash pyflow/run_minimap2_align.sh
```

## ULTRA Align（Python实现 + 并发批处理）

`pyflow/ULTRA_align.py` 提供四个子模块以复刻与对接 nf-core 模块：

* `gunzip`（对应 `modules/nf-core/gunzip`）：使用 `gzip -cd` 解压 `.fa.gz/.fasta.gz` 到指定目录；写出 `versions.yml`

* `sort`（对应 `modules/nf-core/gnu/sort`）：在 `index` 之前对 `GTF` 排序，支持 `.gtf/.gtf.gz`；默认输出 `<basename>.sorted.gtf`（自动去掉双扩展，如 `genome.gtf.gz → genome.sorted.gtf`）；写出 `versions.yml`

* `index`（对应 `modules/nf-core/ultra/index`）：运行 `uLTRA index` 生成 `*.pickle` 与 `*.db` 索引；写出 `versions.yml`

* `align`（对应 `modules/nf-core/ultra/align`）：运行 `uLTRA align` + `samtools sort` 生成 `*.bam`，清理中间 `*.sam`；写出 `versions.yml`

说明：`index` 与 `align` 步骤自动支持压缩参考序列（`.fa.gz/.fasta.gz`），执行前会将参考 FASTA 解压到目标 `outdir`，避免工具拒绝压缩输入。
注意：

* `REFERENCE_FA` 必须为“基因组”FASTA（如 `dna.toplevel.fa.gz`），不要使用转录本 `cdna.all.fa*`。

* 在 `sort` 和 `index` 阶段会校验 GTF 文件存在且非空；若路径错误或解压失败会直接报错，避免生成空文件导致后续异常。

* 向 `--args/--args2` 传递以 `-` 开头的值时，请使用等号样式：例如 `--args="--disable_infer"`，避免被 CLI 误识别为独立选项。

* 依赖要求：`uLTRA` 的预过滤会调用 `minimap2`。请确保 `minimap2` 已安装并可在 PATH 中找到（例如 `conda install -c bioconda minimap2`）。若未在 PATH，可通过 `--minimap2-bin` 显式指定可执行路径，或在批处理脚本中设置 `MINIMAP2_BIN`。

* 依赖要求：`uLTRA` 会调用 `namfinder`（随 `ultra_bioinformatics` 安装）。请确保该二进制可在 PATH 中找到；若未在 PATH，可通过 `--namfinder-bin` 指定，或在批处理脚本中设置 `NAMFINDER_BIN`。

### 单样本使用示例

1. 解压 TAMA 清理输出的 fasta.gz

```bash
python3 pyflow/ULTRA_align.py gunzip \
  --archive tama_polyacleanup_output/SAMPLE/m64291e_ccs.chunk1_tama.fa.gz \
  --outdir ULTRA_align_output/SAMPLE
```

1. 在 index 之前对 GTF 排序（写入 INDEX 目录；支持 `.gtf.gz`）：

```bash
python3 pyflow/ULTRA_align.py sort \
  --gtf results/ULTRA_INDEX/genome.gtf \
  --outdir ULTRA_align_output/INDEX \
  --args "-k1,1 -k4,4n"
```

1. 生成 ULTRA 索引（一次性）。建议把索引写入独立目录（支持 `.fa.gz/.fasta.gz` 自动解压）：

```bash
python3 pyflow/ULTRA_align.py index \
  --fasta /data/genome/hg38.fa.gz \
  --gtf ULTRA_align_output/INDEX/genome.sorted.gtf \
  --outdir ULTRA_align_output/INDEX \
  --args="" \
  --ultra-bin "~/miniconda3/envs/pacbio_iso_seq/bin/uLTRA"
```

1. 使用 ULTRA 进行比对（生成 BAM，支持 `.fa.gz/.fasta.gz` 自动解压）

```bash
python3 pyflow/ULTRA_align.py align \
  --reads ULTRA_align_output/SAMPLE/m64291e_ccs.chunk1_tama.fa \
  --genome /data/genome/hg38.fa.gz \
  --index-dir ULTRA_align_output/INDEX \
  --outdir ULTRA_align_output/SAMPLE \
  --cpus 8 \
  --args="" \
  --args2="" \
  --ultra-bin "~/miniconda3/envs/pacbio_iso_seq/bin/uLTRA" \
  --samtools-bin "~/miniconda3/envs/pacbio_iso_seq/bin/samtools" \
  --minimap2-bin "~/miniconda3/envs/pacbio_iso_seq/bin/minimap2"
  --namfinder-bin "~/miniconda3/envs/ultra_bioinformatics/bin/namfinder"
```

（可选）如果需要对其他文本文件进行排序，可同样使用 `sort` 子命令并自定义 `--prefix` 与 `--args`。

### 并发批处理脚本（run\_ULTRA\_align.sh）

已新增 `pyflow/run_ULTRA_align.sh`：

* 先同步生成索引到 `ULTRA_align_output/INDEX`（若不存在），避免并发依赖

* 为每个样本生成链式命令：`gunzip → align`，并发执行（ParaFly/parallel/xargs）

* 自动遍历 `DATA_DIR` 下的 `*.fa.gz/*.fasta.gz`（默认指向 `tama_polyacleanup_output`）

关键参数（均可通过环境变量覆盖）：

* `DATA_DIR`：输入目录，默认 `tama_polyacleanup_output`

* `OUT_BASE`：输出根目录，默认 `ULTRA_align_output`

* `INDEX_DIR`：索引目录，默认 `ULTRA_align_output/INDEX`

* `REFERENCE_FA`：参考基因组 FASTA（必填，支持 `.fa.gz/.fasta.gz`）

* `GTF`：参考注释 GTF（默认 `results/ULTRA_INDEX/genome.gtf`）

* `ULTRA_INDEX_ARGS`：透传到 `uLTRA index` 的附加参数

* `ULTRA_ALIGN_ARGS`：透传到 `uLTRA align` 的附加参数

* `SAMTOOLS_SORT_ARGS`：透传到 `samtools sort` 的附加参数

* `GZIP_ARGS`：透传到 `gzip -cd` 的附加参数

* `GNU_SORT_ARGS`：透传到 `GNU sort` 的附加参数（在 index 前对 GTF 排序）

* `CPUS_PER_TASK`：每个对齐任务线程数，默认 `8`

* `PARA_CPU`：并发任务数，默认 `28`

* `CMD_FILE`：命令列表文件路径，默认 `ULTRA_align_output/ULTRA_commands.txt`

* `MINIMAP2_BIN`：minimap2 可执行路径（若不在 PATH 中时设定）

* `NAMFINDER_BIN`：namfinder 可执行路径（若不在 PATH 中时设定）

* `ULTRA_BIN`/`SAMTOOLS_BIN`：可选绝对路径，若设置统一注入到所有命令

示例：批量运行 ULTRA 对齐

```bash
DATA_DIR=tama_polyacleanup_output \
OUT_BASE=ULTRA_align_output \
INDEX_DIR=ULTRA_align_output/INDEX \
REFERENCE_FA=/data/genome/hg38.fa.gz \
GTF=results/ULTRA_INDEX/genome.gtf \
ULTRA_ALIGN_ARGS="" CPUS_PER_TASK=8 PARA_CPU=28 \
bash pyflow/run_ULTRA_align.sh
```

### 完整流程串联（… → TAMA PolyA Cleanup → ULTRA Align）

在第 5 步 TAMA 清理后追加 ULTRA：

1. ULTRA 对齐（目录批处理并发）

```bash
DATA_DIR=bamtools_convert_output \
OUT_BASE=tama_polyacleanup_output \
PARA_CPU=28 bash pyflow/run_tama_polyacleanup.sh

# 生成 ULTRA 索引并批量对齐
DATA_DIR=tama_polyacleanup_output \
OUT_BASE=ULTRA_align_output \
INDEX_DIR=ULTRA_align_output/INDEX \
REFERENCE_FA=/data/genome/hg38.fa \
GTF=results/ULTRA_INDEX/genome.gtf \
CPUS_PER_TASK=8 PARA_CPU=28 \
bash pyflow/run_ULTRA_align.sh
```

