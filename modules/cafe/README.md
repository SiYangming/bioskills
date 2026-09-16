# cafe 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core 已有 cafe 模块（pin bioconda::cafe=5.1.0，即 CAFE5）——按「官方已有实现不建目录」规则，
> 其信息仅登记于 `meta.yaml software_versions` / 本 README；本模块 native 以 CAFE **v4.2.1** 为基线。

***

## native 实现

# cafe / native — 基因家族扩张分析驱动（CAFE v4.2.1）

CAFE v4.2.1 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

CAFE（Computational Analysis of gene Family Evolution）用于分析基因家族在物种进化过程中的扩张和收缩。

CAFE 以「命令脚本」方式运行——脚本首行 shebang 指向 `cafe`，脚本体依次为 `version/date/load/tree/lambda/report`
等命令（即官方 `cafe_command`）；`caferror.py` 读取同一脚本（`-i`）做迭代误差模型并行估计。

| 子命令        | 命令                                                       | 作用                                        |
| ---------- | -------------------------------------------------------- | ----------------------------------------- |
| `command`  | 生成 `cafe_command` 脚本（shebang + `load -i ... -t <threads> -p <pvalue>` + `tree` + `lambda -s` + `report`） | 生成 CAFE 命令脚本（不执行）                      |
| `run`      | `cafe <command_script>`                                  | 单次 CAFE 分析（等效直接执行 shebang 脚本方式）    |
| `caferror` | `caferror.py -i <command_script>`                        | 迭代误差模型并行运行（推荐；可校正组装/注释误差）                 |

线程写入生成脚本的 `load -t`（优先级：`--threads` > `per_subcommand_threads` > `default_cpus`）。

## 用法

```bash
# 1) 生成 CAFE 命令脚本（shebang 自动指向解析到的 cafe）
python main.py command --gene-table orthomcl2cafe.tab \
    --tree '(((laame:191.8,plost:191.8):44.9,(parub:107.1,sccit:107.1):129.7):13.7);' \
    -o cafe_command --pvalue 0.01 --threads 8

# 2) 运行 CAFE（单次）
python main.py run --command-file cafe_command

# 3) 迭代误差模型（推荐，可并行）
python main.py caferror --command-file cafe_command --tmp-dir caferror_1 --verbose

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：OrthoMCL 结果 → CAFE 基因家族扩张分析

CAFE 基于生灭过程在系统发育树上建模基因家族的扩张/收缩；输入为基因家族大小表（OrthoMCL 导出）与带枝长
Newick 树。以下为典型流程；等价能力由 `native/main.py` 的 `command` / `run` / `caferror` 子命令提供
（见上「用法」）。

### 1. 从 OrthoMCL 结果得到 CAFE 输入表

```bash
orthomcl_extract_ortholog_seqs.pl --out_directory orthologGroups_CDS \
    --out_tab_for_CAFE orthomcl2cafe.tab \
    --species_ratio 0.4 --single_copy_species_ratio 0.0 \
    --copy_num 1000 --max_seq_length 100000 \
    ../b.orthomcl/groups.txt ../b.orthomcl/compliantFasta_CDS
rm -rf orthologGroups_CDS
```

### 2. 生成并运行 CAFE 命令脚本

```bash
# 命令脚本等价的 CLI：
python main.py command --gene-table orthomcl2cafe.tab \
    --tree '(((laame:191.8242,plost:191.8242):44.9287,(parub:107.055,sccit:107.055):129.6979):13.6525);' \
    -o cafe_command --pvalue 0.01 --threads 8

python main.py run --command-file cafe_command
```

生成的 `cafe_command` 内容（可直接查看 / 手工编辑）：

```
#!/path/to/cafe
version
date

load -i orthomcl2cafe.tab -t 8 -p 0.01
tree (((laame:191.8242,plost:191.8242):44.9287,(parub:107.055,sccit:107.055):129.6979):13.6525);
lambda -s
report out
```

### 3. 迭代误差模型（推荐）

```bash
python main.py caferror --command-file cafe_command --tmp-dir caferror_1 --verbose
# 结果：caferror_1/cafe_final_report.cafe（分析结果）、错误模型与分数汇总
```

### 4. 参数说明

| 参数             | 说明                                          |
| -------------- | ------------------------------------------- |
| `--gene-table` | 基因家族大小表（Desc + Family ID + 各物种拷贝数）           |
| `--tree`       | 带枝长的 Newick 树字符串（含分号）                       |
| `-p/--pvalue`  | 家族显著性 p 值阈值（`load -p`，默认 0.01）              |
| `--report`     | 报告前缀（`report <name>`，默认 out）                |
| `-t/--threads` | 线程数（写入生成脚本 `load -t`）                        |
| `-d/--tmp-dir` | caferror.py 工作目录（默认 `caferror_X`）           |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
`main.py` 驱动在宿主机跑。官方**无预编译二进制包**（已核实：仅提供源码归档与 conda 包），故本模块同时保留
「官方源码编译」作为并列官方路线（见 §4）。

### 1. Conda（包管理器安装）

```bash
mamba create -n cafe-native -c conda-forge -c bioconda cafe=4.2.1
conda activate cafe-native
cafe --help
```

> 说明：Homebrew 两源均未找到 cafe 公式（homebrew-core `formulae.brew.sh/api/formula/cafe.json` 返回 404；
> brewsci/bio `Formula/cafe.rb` 返回 404，2026-09 核实），故不写 brew 小节。
>
> 一键安装也可直接运行 `native/install.sh`（auto：有 conda/mamba 走 bioconda，无 conda 时官方源码
> `./configure && make` 编译到 `~/software/CAFE-4.2.1/bin`；版本默认 4.2.1。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/cafe:4.2.1--h5ca1c30_6
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/cafe:4.2.1--h5ca1c30_6 cafe /data/cafe_command
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull cafe.sif docker://depot.galaxyproject.org/singularity/cafe:4.2.1--h5ca1c30_6
apptainer run -B $PWD:/data -H /data cafe.sif /data/cafe_command
```

### 4. 官方源码编译（并列保留）

官方仅以源码归档分发（无预编译二进制包）；如需自编译：

```bash
wget https://github.com/hahnlab/CAFE/archive/v4.2.1.tar.gz -O ~/software/CAFE-4.2.1.tar.gz
tar zxf ~/software/CAFE-4.2.1.tar.gz -C ~/software
cd ~/software/CAFE-4.2.1
./configure && make -j 4
mkdir -p ~/software/CAFE-4.2.1/bin
cp cafe/caferror.py release/cafe ~/software/CAFE-4.2.1/bin/
perl -p -i -e 's#/usr/bin/python#/usr/bin/env python#' ~/software/CAFE-4.2.1/bin/caferror.py
echo 'export PATH=$PATH:~/software/CAFE-4.2.1/bin/' >> ~/.bashrc
source ~/.bashrc
cafe --help
```

## 官方 nf-core 模块登记（不建目录）

* **模块**：`modules/nf-core/cafe`（扁平目录，无子模块）
* **版本 pin**：`bioconda::cafe=5.1.0`（即 **CAFE5**，`modules/nf-core/cafe/environment.yml`）
* **差异提示**：nf-core 当前 pin 为 CAFE5（5.1.0），与本模块 native 基线 **4.2.1 属不同大版本**（CAFE5 子命令
  `cafe5` 与报告格式不同），跨引擎迁移时勿混用命令与参数。
* **使用方式**：Nextflow DSL2 流程中请用 `nf-core modules install cafe` 安装到项目自身目录，勿直接引用本仓库。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + 生成脚本内容断言（cafe 未安装时不做真实分析）
```

## 版本

* cafe 4.2.1（bioconda::cafe=4.2.1；quay tag `4.2.1--h5ca1c30_6`）
* 构建路线：官方镜像 / 官方源码编译（quay.io/biocontainers/cafe / depot.galaxyproject.org；本地不再自建容器）
* 与 nf-core `cafe`（bioconda::cafe=5.1.0，CAFE5）为不同大版本，勿混用

## 容器与 Conda 链接

* **Github**：https://github.com/hahnlab/CAFE
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/cafe/overview>
* **Docker**：`docker pull quay.io/biocontainers/cafe:4.2.1--h5ca1c30_6`
* **Singularity**：<https://depot.galaxyproject.org/singularity/cafe%3A4.2.1--h5ca1c30_6>
* 安装方式（本地）：`mamba create -n cafe -c conda-forge -c bioconda cafe=4.2.1`
