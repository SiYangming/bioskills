# NanoSeq Snakemake Workflow

This repository contains a Snakemake workflow converted from the `nanoseq.sh` shell scripts. It implements a complete pipeline for Nanopore RNA-seq analysis, including alignment, consensus generation, transcript assembly, and ORF prediction.

## Workflow Structure

The workflow executes the following steps in strict order:
1.  **Alignment**: Minimap2 alignment and Samtools sorting/indexing.
2.  **QC**: Alignment statistics (flagstat).
3.  **Consensus**: FLAIR consensus sequence generation.
4.  **Assembly**: StringTie transcript assembly and merging.
5.  **ORF Prediction**: TransDecoder/TD2 ORF prediction.

## Directory Structure

```
nanoseq.smk/
├── config/
│   ├── config.yaml          # Main configuration file
│   └── samples.schema.yaml  # Samplesheet schema (optional)
├── workflow/
│   ├── Snakefile            # Main workflow entry point
│   ├── rules/               # Modular Snakemake rules
│   └── envs/                # Conda environment definitions
├── test/                    # Test data
└── run_workflow.sh          # Wrapper script to run the workflow
```

## Requirements

-   **Conda**: Required for environment management.
-   **Snakemake**: The workflow orchestrator.
-   **Docker** (Optional): If running in docker mode.

### Tool Versions (Defined in Envs/Config)

-   minimap2: 2.30
-   samtools: 1.23
-   flair: 3.0.0b1
-   stringtie: 3.0.3
-   transdecoder: 5.7.1
-   td2: 1.0.6

## Usage

### 1. Configure

Edit `config/config.yaml` to set paths and parameters.
Edit `test/samplesheet_local.csv` to define samples.

Samplesheet format:
```csv
group,replicate,barcode,input_file,fasta,gtf
HEK293T-WT,1,,./test/HEK293T-WT-rep1,./test/ref.fa,./test/ref.gtf
```
`input_file` should point to the directory containing the fastq files or the fastq file itself.

### 2. Run

Use the provided wrapper script:

```bash
./run_workflow.sh
```

To run with resume capability:

```bash
./run_workflow.sh --resume
```

To run a dry-run (test configuration):

```bash
./run_workflow.sh -n
```

### 3. Execution Modes

The workflow supports multiple execution modes configurable in `config/config.yaml`:
-   `exec_mode: "conda"`: Uses Conda environments defined in `workflow/envs/`.
-   `exec_mode: "docker"`: Uses Docker containers specified in `config/config.yaml`.
-   `exec_mode: "native"`: Uses tools available in the current system PATH.

## Outputs

Results are saved in the directory specified by `output_dir` (default: `test_results`):
-   `alignment_stats_summary.txt`: Summary of alignment rates.
-   `sorted_bam/`: Sorted BAM files and indices.
-   `flair_consensus/`: FLAIR results (bed12, annotated bed, consensus fasta).
-   `stringtie_results/`: StringTie assemblies and merged GTF.
-   `td2_orf_prediction/`: TransDecoder/TD2 prediction results (pep, cds, gff3, bed) and fix report.
-   `report.html`: Snakemake execution report.

## Verification

The workflow has been verified using test data in `test/`.
To verify:
1.  Ensure test data exists (fastq, samplesheet, reference).
2.  Run `./run_workflow.sh -n` for a dry-run check.
3.  Run `./run_workflow.sh` for full execution (requires installed tools).

## exec_mode 使用与 Docker 集成

- 通过 `config/config.yaml` 的 `exec_mode` 切换运行模式：`conda`、`docker`、`native`
- Docker 模式使用 `workflow/scripts/docker_wrapper.py` 封装器挂载工程目录并在容器内执行工具
- 规则文件在 shell 中根据 `exec_mode`、可选的 `*_bin` 覆盖路径和 `docker_image` 选择执行路径，并记录工具版本到日志

## 单元测试

运行 Python 单元测试：

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```
