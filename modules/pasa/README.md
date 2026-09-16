# pasa 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方「环境安装」，容器与 conda 信息记录于文末。
> 本模块仅登记 native 实现（官方 nf-core / snakemake-wrappers 均无 pasa，见文末「官方实现登记」）。

***

## native 实现

# pasa / native — 自包含转录本辅助基因预测驱动

PASA（PASApipeline）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

PASA（Program to Assemble Spliced Alignments）是一个用于基因结构注释的综合工具，主要利用转录本序列（如 RNA-seq 组装结果）来辅助基因预测。

三个子命令的 PASA 链路：

| 子命令                   | 命令                                                                                                          | 作用                              |
| --------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------- |
| `align_assemble`      | `Launch_PASA_pipeline.pl -c <config> -R -g <genome> -t <transcripts> -T [-u <unclean>] [--TDN <tdn>] --ALIGNERS <list> --CPU N [...]` | 转录本→基因组比对并组装                    |
| `build_comprehensive` | `build_comprehensive_transcriptome.dbi -c <config> -t <transcripts>`                                          | 构建综合转录组数据库                      |
| `asmbls_to_training`  | `pasa_asmbls_to_training_set.dbi --pasa_transcripts_fasta <fasta> --pasa_transcripts_gff3 <gff3>`             | ORF 预测 + 生成可训练基因模型 GFF3          |

## 用法

```bash
# CLI 直跑
python main.py align_assemble -c alignAssembly.config -g genome.fasta -t transcripts.fasta.clean \
    -u transcripts.fasta --ALIGNERS gmap,blat --stringent_alignment_overlap 30.0 \
    --MAX_INTRON_LENGTH 20000 --TRANSDECODER --threads 8
python main.py build_comprehensive -c alignAssembly.config -t transcripts.fasta.clean
python main.py asmbls_to_training \
    --pasa_transcripts_fasta DB.assemblies.fasta --pasa_transcripts_gff3 DB.pasa_assemblies.gff3

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`align_assemble` 注入 `--CPU N`）。

## 实战示例：转录本辅助基因预测（PASA）

PASA 利用 RNA-seq 组装转录本辅助真核基因预测，主要步骤包括序列预处理（seqclean）、比对配置、数据库创建与主程序运行。以下为典型用法；比对组装 / 综合库 / 训练集三段等价能力由 `native/main.py` 的 `align_assemble` / `build_comprehensive` / `asmbls_to_training` 子命令提供（见上「用法」）。

```bash
mkdir -p pasa && cd pasa
ln -s ../Malassezia_sympodialis.genome_V01.fasta genome.fasta

# 1) 合并 RNA-Seq 组装序列并做 end-trimming（去载体/接头/polyA）
cat ../Trinity*fasta > transcripts.fasta
seqclean transcripts.fasta -v /path/to/PASApipeline/UniVec/UniVec

# 2) 生成比对配置文件 + 创建 MySQL 库表
cp /path/to/PASApipeline/pasa_conf/pasa.alignAssembly.Template.txt alignAssembly.config
perl -p -i -e "s/DATABASE=.*/DATABASE=pasa_db_\$(whoami)/" alignAssembly.config
create_mysql_cdnaassembly_db.dbi -r -c alignAssembly.config \
    -S /path/to/PASApipeline/schema/cdna_alignment_mysqlschema

# 3) 运行 PASA 主程序（转录本比对到基因组并组装）
Launch_PASA_pipeline.pl -c alignAssembly.config -R -g genome.fasta -t transcripts.fasta.clean \
    -T -u transcripts.fasta --ALIGNERS gmap,blat --CPU 8 --stringent_alignment_overlap 30.0 \
    --TDN tdn.accs --MAX_INTRON_LENGTH 20000 --TRANSDECODER &> pasa.log

# 4) 构建综合转录组数据库 + ORF/基因预测
build_comprehensive_transcriptome.dbi -c alignAssembly.config -t transcripts.fasta.clean
pasa_asmbls_to_training_set.dbi --pasa_transcripts_fasta DB.assemblies.fasta \
    --pasa_transcripts_gff3 DB.pasa_assemblies.gff3
```

| 参数                                | 说明                              |
| --------------------------------- | ------------------------------- |
| `--ALIGNERS gmap,blat`            | 指定比对工具                          |
| `--CPU 8`                         | 并行线程数                           |
| `--stringent_alignment_overlap 30.0` | 严格比对重叠阈值（基因稠密的小基因组建议设置）         |
| `--MAX_INTRON_LENGTH 20000`       | 最大内含子长度                         |
| `--TRANSDECODER`                  | 启用 ORF 预测                       |
| `--transcribed_is_aligned_orient` | 链特异性测序数据需要添加此参数                 |

> 注意事项：PASA 需要 MySQL/MariaDB 支持；建议使用 mask 重复序列后的基因组；链特异性数据加 `--transcribed_is_aligned_orient`。真菌等小基因组，由于基因比较稠密，需要加入参数 `--stringent_alignment_overlap`。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda pasa → quay.io/biocontainers → depot.galaxyproject.org 预构建 sif），直接拉取官方镜像/conda 安装脚本；main.py 驱动在宿主机跑。官方另有源码编译路线（PASApipeline.v2.5.3.FULL.tar.gz，`make`），并列保留如下 §4。

### 1. Conda / brew（包管理器安装，备选）

```bash
mamba create -n pasa-native -c conda-forge -c bioconda pasa=2.5.3
conda activate pasa-native
Launch_PASA_pipeline.pl --version   # 断言（PASA version: 2.5.3）
```

> 说明：brew（homebrew-core / brewsci-bio）**无 pasa 公式**（2026-09-11 核实 404），故不登记 brew 安装块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `pasa`，无 conda 时走官方源码编译（`make -j`）并写 PATH；版本默认 2.5.3，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

⚠️ **注意**：

- PASA 需要 MySQL 数据库支持，请确保系统已安装并配置好 MySQL/MariaDB。
- conda 安装会自动处理大部分依赖（如 GMAP、blat、FASTA 等）。
- 旧版 Blast（formatdb）可能需要单独安装，可使用 `conda install -c bioconda blast-legacy`。
- UniVec 数据库和配置仍需手动设置（参考下方配置 UniVec 数据库章节）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/pasa:2.5.3--h9948957_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/pasa:2.5.3--h9948957_2 \
    Launch_PASA_pipeline.pl -c /data/alignAssembly.config -R -g /data/genome.fasta \
    -t /data/transcripts.fasta.clean -T --ALIGNERS gmap,blat --CPU 8 --TRANSDECODER
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull pasa.sif docker://depot.galaxyproject.org/singularity/pasa:2.5.3--h9948957_2
apptainer run -B $PWD:/data -H /data pasa.sif \
    Launch_PASA_pipeline.pl -c /data/alignAssembly.config -R -g /data/genome.fasta \
    -t /data/transcripts.fasta.clean -T --ALIGNERS gmap,blat --CPU 8 --TRANSDECODER
```

### 4. 官方源码编译

PASA需要依赖 GMAP、blat、FASTA 等工具。

```bash
# 官方 release 源码（FULL 包含第三方依赖）
curl -fSL -o PASApipeline.v2.5.3.FULL.tar.gz \
    https://github.com/PASApipeline/PASApipeline/releases/download/pasa-v2.5.3/PASApipeline.v2.5.3.FULL.tar.gz
tar zxf PASApipeline.v2.5.3.FULL.tar.gz -C ~/software/
cd ~/software/PASApipeline.v2.5.3
make -j 4
echo 'export PATH=$PATH:~/software/PASApipeline.v2.5.3/bin/' >> ~/.bashrc
source ~/.bashrc
```

> 运行依赖（源码路线需自行提供；conda 路线会带入大部分）：GMAP、blat、FASTA、seqclean、TransDecoder、Samtools 等；运行 PASA 主程序还需 MySQL/MariaDB。

## 官方实现登记（nf-core / snakemake-wrappers）

* **nf-core**：`modules/nf-core/pasa` 不存在（2026-09-11 核实 404）→ 未建立 nextflow 说明层，Nextflow 场景请以本模块 `native/` 为兜底。
* **snakemake-wrappers**：`bio/pasa` 不存在（2026-09-11 核实 404）→ 未建立 snakemake 说明层，Snakemake 场景请以本模块 `native/` 为兜底。

## 测试

```bash
bash test/run_test.sh   # align_assemble/build_comprehensive/asmbls_to_training 退化为 argv 构造验证（不依赖已安装 PASA）
```

## 版本

* PASA 2.5.3（bioconda::pasa=2.5.3，容器 tag `2.5.3--h9948957_2`）
* 构建路线：官方镜像/conda 优先（quay.io/biocontainers/pasa / depot.galaxyproject.org；本地不再自建容器）；官方源码编译（FULL release + make）并列保留
* 运行依赖：MySQL/MariaDB + GMAP/blat/FASTA/seqclean/TransDecoder

## 容器与 Conda 链接

* **Github**：https://github.com/PASApipeline/PASApipeline
* **文档**：https://github.com/PASApipeline/PASApipeline/wiki
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/pasa/overview>
* **Docker**：`docker pull quay.io/biocontainers/pasa:2.5.3--h9948957_2`
* **Singularity**：<https://depot.galaxyproject.org/singularity/pasa:2.5.3--h9948957_2>
* **官方源码**：<https://github.com/PASApipeline/PASApipeline/releases/download/pasa-v2.5.3/PASApipeline.v2.5.3.FULL.tar.gz>
* 安装方式（本地）：`mamba create -n pasa -c conda-forge -c bioconda pasa=2.5.3`
