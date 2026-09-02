# fastqc 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# fastqc / native 自包含实现

基于 bioconda `fastqc=0.12.1` + OpenJDK 17 的 Python 驱动包装：

- 自动注入 `-t` 线程（默认 4，可 CPU 核数协商）
- 通过 `JAVA_OPTS` 注入 JVM 最大堆内存（默认 8 GB）与 `TMPDIR`
- `-o` 不存在时自动创建
- `--nogroup` / `--extract` / `-f` / `-c` / `-a` / `-k` 等常见参数透传
- 运行时仍需本地安装 `fastqc` + `java`：推荐 `mamba env create -f environment.yml`

## CLI 用法示例

```bash
python main.py run sample_R1.fq.gz sample_R2.fq.gz -o qc_out --threads 8 --java-mem-mb 16384
python main.py run sample.fastq -f fastq --nogroup
python main.py --list-commands
python main.py --schema
```

## Docker 调用（推荐）

```bash
docker build -t bioskills/fastqc:0.12.1-v1.0 .
docker run --rm -u $(id -u):$(id -g) \
    -v "$PWD":/work -w /work \
    bioskills/fastqc:0.12.1-v1.0 \
    -c "python /work/main.py run sample_R1.fq.gz -o /work/qc_out --threads 8"
```

## 运行测试

```bash
bash test/run_test.sh
```


---

## snakemake 实现

# fastqc snakemake local 自定义实现占位

仅作为占位：当 snakemake-wrappers 的官方 bio/fastqc 不满足特定需求（如强制 -f fastq_bismark、定制 contaminant/adapter 列表等）时使用。

## 启用步骤

1. 打开本目录 `rule.smk.template`，按实际 IO/参数复制到 Snakefile 或打包的 `rules/fastqc.smk`；
2. 在软件级 meta.yaml 中把 `fastqc_snakemake_local.enabled` 设为 `true`；
3. 完成后执行：
   ```
   snakemake -p --cores 4 qc/{sample}_fastqc.html
   ```


---

## nextflow 实现

# fastqc nextflow local 自定义实现

仅作为占位：当 nf-core 官方 FASTQC 不符合特殊参数需求（例如自定义 -k / -c 污染序列、强制 format 等）时使用。

## 启用步骤

1. 打开本目录下的 `main.nf.template`，按参数需求定制为 `main.nf`；
2. 将本目录复制到用户项目的 `modules/local/fastqc/`；
3. 在 workflow 中：

```nextflow
include { FASTQC_LOCAL } from './modules/local/fastqc/main'
FASTQC_LOCAL( reads_ch )
```

4. 在本目录写好 `meta.yaml` / `module.json`（已预置骨架）。


---

## Conda 环境（原 native/environment.yml）

```yaml
name: fastqc
channels:
  - conda-forge
  - bioconda
  - defaults
dependencies:
  - conda-forge::python>=3.10
  - bioconda::fastqc=0.12.1
  - conda-forge::openjdk=17.*
  - conda-forge::pigz
  - conda-forge::perl
  - conda-forge::coreutils
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/fastqc/overview
- **Docker**：`docker pull quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0`
- **Singularity**：https://depot.galaxyproject.org/singularity/fastqc%3A0.12.1--hdfd78af_0
- 安装方式（本地）：`mamba create -n fastqc -c conda-forge -c bioconda fastqc=0.12.1`
