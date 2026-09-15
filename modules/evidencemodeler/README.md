# evidencemodeler 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# evidencemodeler / native — 自包含基因预测证据整合驱动

EVidenceModeler (EVM) 的本地自包含实现（`source_type: custom`、`type: native`；驱动 EVM 1.1.1 脚本链）。

## 功能

EVM（EVidenceModeler）是一个用于整合多个基因预测工具结果的工具，可以综合不同工具的预测结果生成更准确的基因集。

七个子命令对应 EVM 的证据整合链路（脚本位于 `$EVM_HOME/EvmUtils` 或 PATH，`main.py` 统一驱动）：

| 子命令              | 命令                                                                                          | 作用                                   |
| ---------------- | ------------------------------------------------------------------------------------------- | ------------------------------------ |
| `partition`      | `partition_EVM_inputs.pl --genome ... --segmentSize 500000 --overlapSize 10000 --partition_listing partitions_list.out` | 按坐标把基因组与证据切成可并行的分区             |
| `write_commands` | `write_EVM_commands.pl --partitions ... --weights ... --output_file_name evm.out`（stdout）      | 生成每个分区的 EVM 运行命令列表                  |
| `parallel`       | `ParaFly -c commands.list -CPU N`                                                            | 并行执行各分区 EVM                          |
| `recombine`      | `recombine_EVM_partial_outputs.pl --partitions ... --output_file_name evm.out`                | 合并各分区结果                              |
| `convert_gff3`   | `convert_EVM_outputs_to_GFF3.pl --partitions ... --output_file_name evm.out --genome ...`     | 转换为基因结构 GFF3                          |
| `weights`        | `create_weights_file.pl -A <abinitio> -P <protein> -T <transcript>`（stdout）                   | 生成证据权重文件                             |
| `evm`            | `evidence_modeler.pl --genome ... --weights ...`（stdout）                                     | 单次运行 EVM 主程序（小基因组免分区）                 |

## 用法

```bash
# CLI 直跑（EVM_HOME 指向 EVM 安装目录，或脚本在 PATH 中）
python main.py partition --genome genome.fasta --gene_predictions gene_predictions.gff3 \
    --protein_alignments protein_alignments.gff3 --transcript_alignments transcript_alignments.gff3 \
    --repeats genome.repeat.gff3 --segmentSize 500000 --overlapSize 10000 \
    --partition_listing partitions_list.out
python main.py write_commands --partitions partitions_list.out --weights weights.txt \
    --genome genome.fasta -o commands.write_EVM_commands.list
python main.py parallel -c commands.write_EVM_commands.list --threads 8
python main.py recombine --partitions partitions_list.out --output_file_name evm.out
python main.py convert_gff3 --partitions partitions_list.out --output_file_name evm.out --genome genome.fasta

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`parallel` 的 `--threads` 透传给 `ParaFly -CPU`）。

## 实战示例：AUGUSTUS + GeneWise + PASA 证据整合

EVM 按权重整合从头预测（ABINITIO_PREDICTION）与蛋白（PROTEIN）/转录本（TRANSCRIPT）比对证据；转录本证据权重通常最高（最直接反映真实基因结构），蛋白证据次之。以下为教学流程的典型用法，等价能力由 `native/main.py` 的 `partition` / `write_commands` / `parallel` / `recombine` / `convert_gff3` 子命令提供（见上「用法」）。

### 1. 配置权重文件

```bash
echo -e "ABINITIO_PREDICTION\tAUGUSTUS\t1
PROTEIN\tGeneWise\t5
TRANSCRIPT\tpasa_transcript_alignments\t10" > weights.txt
# 等价：python main.py weights -A AUGUSTUS -P GeneWise -T pasa_transcript_alignments -o weights.txt
```

### 2. 分区 + 生成命令 + 并行执行

```bash
partition_EVM_inputs.pl --genome genome.fasta --gene_predictions gene_predictions.gff3 \
    --protein_alignments protein_alignments.gff3 --transcript_alignments transcript_alignments.gff3 \
    --repeats genome.repeat.gff3 --segmentSize 500000 --overlapSize 10000 \
    --partition_listing partitions_list.out

write_EVM_commands.pl --genome genome.fasta --gene_predictions gene_predictions.gff3 \
    --protein_alignments protein_alignments.gff3 --transcript_alignments transcript_alignments.gff3 \
    --repeats genome.repeat.gff3 --weights `pwd`/weights.txt \
    --partitions partitions_list.out --output_file_name evm.out > commands.write_EVM_commands.list

ParaFly -c commands.write_EVM_commands.list -CPU 8
```

### 3. 合并 + 转 GFF3

```bash
recombine_EVM_partial_outputs.pl --partitions partitions_list.out --output_file_name evm.out
convert_EVM_outputs_to_GFF3.pl --partitions partitions_list.out --output_file_name evm.out --genome genome.fasta
cat */evm.out.gff3 > evm_out.gff3
```

### 4. 参数说明

| 参数                  | 说明                    |
| ------------------- | --------------------- |
| `--segmentSize`     | 每个分区的大小 bp（默认 500000） |
| `--overlapSize`     | 分区重叠大小 bp（默认 10000）    |
| `CPU`（ParaFly）      | 并行线程数                 |
| `--weights`         | 证据权重文件                |
| `--output_file_name` | 分区输出基名（默认 evm.out）     |

> 说明：教学文档中的 `evm_genes_filtering.pl`（低质量模型过滤）经核实**不属于** EVM 官方仓库（v1.1.1 与 v2.1.0 的 `EvmUtils/` 均无此脚本），本模块不登记该脚本；如需过滤请使用上游提供的其它脚本或自行实现。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑（conda/mamba 装 EVM）。

### 1. Conda / brew（包管理器安装）

```bash
# 按教学文档登记版本 1.1.1（亦可省略 =1.1.1 取当前最新 2.1.0）
mamba create -n evidencemodeler-native -c conda-forge -c bioconda evidencemodeler=1.1.1
conda activate evidencemodeler-native
# conda 安装后 EVM 脚本位于环境 bin/ 与 share 下（EVM_HOME 由激活脚本设置）
```

```text
brew：无公式（homebrew-core 与 brewsci/bio 均未收录 evidencemodeler，2026-09 核实）→ 不提供 brew 块。
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境；无 conda 时走官方源码 tarball 部署到 `~/software/EVidenceModeler-1.1.1`）。

conda 安装的 EVM 工具脚本位于 conda 环境的 bin 目录下，可直接调用。常用工具如 `partition_EVM_inputs.pl`、`write_EVM_commands.pl`、`recombine_EVM_partial_outputs.pl` 等均可直接使用。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/evidencemodeler:1.1.1--hdfd78af_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/evidencemodeler:1.1.1--hdfd78af_3 \
    partition_EVM_inputs.pl --genome /data/genome.fasta \
    --gene_predictions /data/gene_predictions.gff3 --partition_listing /data/partitions_list.out
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull evidencemodeler.sif docker://depot.galaxyproject.org/singularity/evidencemodeler:1.1.1--hdfd78af_3
apptainer run -B $PWD:/data -H /data evidencemodeler.sif \
    partition_EVM_inputs.pl --genome /data/genome.fasta \
    --gene_predictions /data/gene_predictions.gff3 --partition_listing /data/partitions_list.out
```

### 4. 官方源码（并列保留）

官方同时提供源码归档（GitHub tag `v1.1.1`），可作为无容器/无 conda 场景的并列路线：

```bash
wget https://github.com/EVidenceModeler/EVidenceModeler/archive/v1.1.1.tar.gz -O ~/software/EVidenceModeler-1.1.1.tar.gz
tar zxf ~/software/EVidenceModeler-1.1.1.tar.gz -C ~/software/
export EVM_HOME=~/software/EVidenceModeler-1.1.1
export PATH="$EVM_HOME/EvmUtils:$PATH"

EVidenceModeler.pl --help
```

> ⚠️ 官方源码归档为 GitHub 动态打包 tarball（摘要不稳定），`install.sh --method source` 会跳过内嵌 sha256 校验；并行工具 ParaFly 不在 v1.1.1 源码内，需另行获取（EVM ≥2.0 的 `plugins/ParaFly` 或历史 `EVM_r2012-06-25` 发行包）。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch 脚本解析，覆盖 7 个子命令）；ParaFly 已安装时额外冒烟
```

## 版本

* evidencemodeler 1.1.1（bioconda `evidencemodeler=1.1.1` / GitHub tag `v1.1.1`）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/evidencemodeler / depot.galaxyproject.org；本地不再自建容器）
* bioconda 亦登记最新 2.1.0（tag `2.1.0--h9948957_5`）；2.x 主脚本为 `EVidenceModeler`（1.1.1 为 `evidence_modeler.pl`），详见 `software_versions`

## 容器与 Conda 链接

* **GitHub**：https://github.com/EVidenceModeler/EVidenceModeler/
* **文档**：https://github.com/EVidenceModeler/EVidenceModeler/wiki
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/evidencemodeler/overview>
* **Docker**：`docker pull quay.io/biocontainers/evidencemodeler:1.1.1--hdfd78af_3`
* **Singularity**：<https://depot.galaxyproject.org/singularity/evidencemodeler%3A1.1.1--hdfd78af_3>
* 安装方式（本地）：`mamba create -n evidencemodeler -c conda-forge -c bioconda evidencemodeler=1.1.1`
