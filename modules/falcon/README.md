# falcon 软件模块

> 汇总说明：本 README 合并各实现（native 等）的用法；安装方式见「环境安装」，容器与 conda 信息记录于「容器与 Conda 链接」。

***

## native 实现

# falcon / native — 自包含 PacBio 三代组装驱动

FALCON（FALcon Assembly Line，Pacific Biosciences；OLC 算法）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

| 子命令     | 命令                        | 作用                                     |
| ------- | ------------------------- | -------------------------------------- |
| `run`   | `fc_run.py <fc_run.cfg>`   | FALCON 主组装（overlap-layout-consensus）    |
| `unzip` | `fc_unzip.py <fc_unzip.cfg>` | FALCON-Unzip 分型组装（primary + haplotigs） |

FALCON 由 INI 配置驱动，**无 `--threads` 旗标**；本驱动把线程经环境变量 **`NPROC`** 注入（对应 `fc_run.cfg` 的 `[job.defaults] NPROC`），临时目录经 `TMPDIR` 注入。线程优先级：用户 `--threads` > `per_subcommand_threads` > `default_cpus`。

## 用法

```bash
# CLI 直跑（在含 fc_run.cfg 的工作目录）
python main.py run fc_run.cfg --threads 8
python main.py unzip fc_unzip.cfg --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

## 实战示例：PacBio 数据的 FALCON 组装（Lambda 基因组）

FALCON 以 `input.fofn`（每行一个 fasta 路径）与 `fc_run.cfg`（INI 配置）驱动，是 PacBio 三代数据 OLC 组装的经典工具。以下为文档示例；等价能力由 `native/main.py` 的 `run` / `unzip` 子命令提供（见上「用法」）。

```bash
mkdir -p 04.genome_assembling/FALCON
cd 04.genome_assembling/FALCON

# Lambda 基因组组装
mkdir lamda; cd lamda
#（用 SMRT Link 的 bam2fasta 生成 subreads.fasta，此处略）
ls *.fasta > input.fofn

# 创建 fc_run.cfg（关键项；完整见下）
cat > fc_run.cfg <<'CFG'
[General]
input_fofn = input.fofn
input_type = raw

length_cutoff = -1
genome_size = 48000
seed_coverage = 35
pa_daligner_option = -k14 -w6 -h35 -e.70 -l500 -T4
pa_HPCdaligner_option = -v -B4 -M16
falcon_sense_option = --output-multi --min-idt 0.70 --min-cov 4 --max-n-read 500
length_cutoff_pr = 1000
ovlp_daligner_option = -k20 -w6 -h60 -e.96 -l500 -T4
ovlp_HPCdaligner_option = -v -B4 -M16
overlap_filtering_setting = --max-diff 100 --max-cov 100 --min-cov 2 --bestn 10
fc_ovlp_to_graph_option = --min-len 500 --min-idt 0.96

[job.defaults]
job_type = local
pwatcher_type = blocking
submit = bash -C ${CMD} >| ${STDOUT_FILE} 2>| ${STDERR_FILE}
MB=32768
NPROC=4
njobs=2
[job.step.da]
[job.step.pda]
[job.step.la]
[job.step.pla]
[job.step.cns]
[job.step.asm]
CFG

# 运行 FALCON（本驱动：python main.py run fc_run.cfg --threads 4）
fc_run.py fc_run.cfg &> FALCON.log
```

### 配置文件参数说明

| 参数                      | 说明                          |
| ----------------------- | --------------------------- |
| `input_fofn`            | 输入文件列表（每行一个 fasta 文件路径）      |
| `input_type`            | 输入数据类型（raw / corrected）      |
| `genome_size`           | 估计的基因组大小                    |
| `seed_coverage`         | 种子序列覆盖度                     |
| `length_cutoff`         | 种子序列长度阈值                    |
| `length_cutoff_pr`      | 校正后序列长度阈值                   |
| `pa_daligner_option`    | 种子序列比对参数                    |
| `ovlp_daligner_option`  | 重叠比对参数                      |

> 💡 FALCON-Unzip 分型组装用 `fc_unzip.py <fc_unzip.cfg>`（本驱动 `unzip` 子命令），产出 primary contigs 与 haplotigs。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具；main.py 驱动在宿主机跑。**包名核实**：bioconda 无 `falcon` 包（404；同名 `falcon` 是 Web 框架），FALCON 由 **`pb-falcon`**（当前维护，2.2.4）提供，另有官方 meta-package **`pb-assembly`**（0.0.8，即文档方法二所述整套三代工具链）。

### 1. Conda / brew（包管理器安装）

```bash
# 文档方法二：官方 meta-package（FALCON + Unzip 整套三代组装工具链）
mamba create -n pb-assembly -c conda-forge -c bioconda pb-assembly
conda activate pb-assembly
which fc_run.py && fc_run.py --help    # 断言

# 或只装 FALCON/Unzip 本体（当前维护、版本更新）
mamba create -n pb-falcon -c conda-forge -c bioconda pb-falcon=2.2.4
```

> Homebrew：homebrew-core（`formulae.brew.sh/api/formula/falcon.json`）与 brewsci/bio（`Formula/falcon.rb`）均 404（2026-09 核实）→ 无公式，不登记 brew 块（且 core 同名 `falcon` 亦非本工具）。
>
> 一键安装：`bash native/install.sh`（默认 `--pkg pb-assembly`；`--pkg pb-falcon` 改本体；无 conda 时 `--method source` 走官方 release 源码 pip 安装）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/pb-falcon:2.2.4--py311h384fd50_7
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/pb-falcon:2.2.4--py311h384fd50_7 \
    fc_run.py fc_run.cfg
# 文档所述的整套 meta-package 镜像（历史）：
#   quay.io/biocontainers/pb-assembly:0.0.8--hdfd78af_1
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull falcon.sif docker://depot.galaxyproject.org/singularity/pb-falcon:2.2.4--py311h0152c62_6
apptainer run -B $PWD:/data -H /data falcon.sif fc_run.py /data/fc_run.cfg
# 或文档所述 meta-package：docker://depot.galaxyproject.org/singularity/pb-assembly:0.0.8--hdfd78af_1
```

## 测试

```bash
bash test/run_test.sh   # argv 构造 + 线程优先级 + NPROC env 注入 + parser + schema（不下载/不编译）；
                        # FALCON 已装时附 fc_run.py --help 冒烟
```

## 容器与 Conda 链接

* **GitHub（FALCON）**：<https://github.com/PacificBiosciences/FALCON>
* **GitHub（pb-assembly）**：<https://github.com/PacificBiosciences/pb-assembly>
* **Bioconda 页面**：<https://anaconda.org/bioconda/pb-falcon>（本体）/ <https://anaconda.org/bioconda/pb-assembly>（meta-package）
* **Docker**：`docker pull quay.io/biocontainers/pb-falcon:2.2.4--py311h384fd50_7`
* **Singularity**：<https://depot.galaxyproject.org/singularity/pb-falcon%3A2.2.4--py311h0152c62_6>
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* 安装方式（本地）：`mamba create -n pb-assembly -c conda-forge -c bioconda pb-assembly`（或 `pb-falcon=2.2.4`）

## 版本

* FALCON **2.2.4**（`pb-falcon`，当前维护；主程序 `fc_run.py`）
* 文档所述 **`pb-assembly`=0.0.8**（PacBio 官方 meta-package，依赖 pb-falcon>=2.2.2 + Unzip/nim-falcon/pb-dazzler/racon/blasr/minimap2 等整套三代工具；2019–2020 后停更）
* License：**BSD-3-Clause-Clear**（bioconda recipe `about.license`）
* 渠道：官方镜像/conda 优先（quay.io/biocontainers/pb-falcon / depot.galaxyproject.org；本地不再自建容器）；bioconda `falcon` 不存在（2026-09 核实 404）
* nf-core / snakemake-wrappers：无官方子模块（2026-09 核实 `modules/nf-core/` 与 `bio/` 均 404）→ 不登记官方说明层
