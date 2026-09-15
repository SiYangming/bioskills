# mcscanx 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 无 mcscanx 实现（2026-09 核实 404），故仅登记 native 实现。

***

## native 实现

# mcscanx / native — 共线性分析驱动

MCScanX（含 `duplicate_gene_classifier` 与 `downstream_analyses` 绘图组件）的本地自包含实现
（`source_type: custom`、`type: native`）。

## 功能

MCScanX用于检测基因组间的共线性区域，包括种间共线性和种内共线性分析，以及基因类型鉴定和可视化。

MCScanX 以「输入前缀」方式运行——`MCScanX <prefix>` 读取 `<prefix>.blast`（BLAST/DIAMOND m8 比对）
与 `<prefix>.gff`（基因位置），输出共线性区块与 HTML 可视化；绘图组件为 Java 程序。

| 子命令        | 命令                                                                        | 作用                                                    |
| ---------- | ------------------------------------------------------------------------- | ----------------------------------------------------- |
| `scan`     | `MCScanX <prefix>`                                                        | 检测共线性区块（`<prefix>.collinearity` / `<prefix>.html`） |
| `classify` | `duplicate_gene_classifier <prefix>`                                      | 基因类型鉴定（0 singleton / 1 dispersed / 2 proximal / 3 tandem / 4 WGD） |
| `dual`     | `java dual_synteny_plotter -g <gff> -s <collinearity> -c <control> -o <png>` | 种间共线性点线图                                              |
| `circle`   | `java circle_plotter -g <gff> -s <collinearity> -c <control> -o <png>`    | 种内共线性圈图                                               |

> 说明：MCScanX 本体为单线程 C++ 程序；并行体现在上游 DIAMOND/BLAST all-vs-all 步骤。
> 每个子命令接受 `--threads` / `--tmpdir` 仅为接口统一；Java 绘图内存调优走 `JAVA_OPTS`。

## 用法

```bash
# 共线性检测（读取 data/input.blast + data/input.gff）
python main.py scan data/input

# 基因类型鉴定
python main.py classify data/input

# 绘图（Java）
python main.py dual   -g data/nc_cp.gff -s data/nc_cp.collinearity -c control -o data/nc_cp.dual.png
python main.py circle -g data/nc_cp.gff -s data/nc_cp.collinearity -c control -o data/nc_cp.circle.png

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

## 实战示例：BLAST/DIAMOND → MCScanX 共线性 → 种间/种内 → 基因类型 → 可视化

MCScanX 用于检测基因组间/基因组内的共线性区域，并做基因类型鉴定与可视化。以下为 14.md 教程流程；
等价能力由 `native/main.py` 的 `scan` / `classify` / `dual` / `circle` 子命令提供（见上「用法」）。

### 1. 合并蛋白序列并做 all-vs-all 比对

```bash
cat laame.pep.fasta plost.pep.fasta > all.fasta
perl -p -i -e 's/\*$//; s/\*/X/g;' all.fasta

diamond makedb --in all.fasta --db all
diamond blastp --db all --query all.fasta --out diamond.out \
    --outfmt 5 --sensitive --max-target-seqs 100 --evalue 1e-5 \
    --id 10 --tmpdir /dev/shm --threads 8
```

### 2. 生成 MCScanX 输入（.blast + .gff）

```bash
mkdir data
parsing_blast_result.pl --no-header --max-hit-num 100 --evalue 1e-6 \
    --identity 0.5 --subject-coverage 0.5 --query-coverage 0.5 \
    diamond.out > data/input.blast

perl -e 'while (<>) {
            if (m/^(\S+)\t.*\tgene\t(\d+)\t(\d+).*ID=([^\s;]+)/) {
                print "$1\t$4\t$2\t$3\n"
            }
         }' plost.geneModels.gff3 laame.geneModels.gff3 > data/input.gff
```

### 3. 运行 MCScanX 与基因类型鉴定

```bash
python main.py scan data/input          # -> data/input.collinearity / data/input.html
python main.py classify data/input      # -> 基因类型统计
```

### 4. 种间 / 种内共线性拆分与绘图

```bash
grep -v -P "plost.*plost" data/input.collinearity | grep -P "plost" > data/input.collinearity_interspecific
grep -P "plost.*plost" data/input.collinearity > data/input.collinearity_intraspecific

# 控制文件：首两行为染色体大小，其后为各物种染色体列表
printf '600\n1400\nla1\npl1\n' > control

python main.py dual   -g data/nc_cp.gff -s data/nc_cp.collinearity -c control -o data/nc_cp.dual.png
python main.py circle -g data/nc_cp.gff -s data/nc_cp.collinearity -c control -o data/nc_cp.circle.png
```

### 5. 参数说明

| 参数                   | 说明                                                   |
| -------------------- | ---------------------------------------------------- |
| `<prefix>`           | 输入前缀（`scan`/`classify` 读取 `<prefix>.blast` + `<prefix>.gff`） |
| `-g/--gff`           | 基因位置文件（chr/start/end/gene）                            |
| `-s/--collinearity`  | 共线性文件（`<prefix>.collinearity`）                        |
| `-c/--control`       | 绘图控制文件（染色体大小 + 各物种染色体列表）                              |
| `-o/--output`        | 输出图片路径（`.png`）                                        |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
`main.py` 驱动在宿主机跑。官方**无预编译二进制包**（已核实：仅提供源码归档与 conda 包），故本模块同时保留
「官方源码编译」作为并列官方路线（见 §4）。绘图组件（`dual_synteny_plotter` / `circle_plotter`）为 Java
程序，宿主机需 JDK。

### 1. Conda（包管理器安装）

```bash
mamba create -n mcscanx-native -c conda-forge -c bioconda mcscanx=1.0.0
conda activate mcscanx-native
MCScanX
```

> 说明：Homebrew 两源均未找到 mcscanx 公式（homebrew-core `formulae.brew.sh/api/formula/mcscanx.json`
> 返回 404；brewsci/bio `Formula/mcscanx.rb` 返回 404，2026-09 核实），故不写 brew 小节。
>
> 一键安装也可直接运行 `native/install.sh`（auto：有 conda/mamba 走 bioconda，无 conda 时官方源码 `make`
> 编译到 `~/software/MCScanX-1.0.0/bin`；版本默认 1.0.0。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/mcscanx:1.0.0--h9948957_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/mcscanx:1.0.0--h9948957_0 MCScanX data/input
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull mcscanx.sif docker://depot.galaxyproject.org/singularity/mcscanx:1.0.0--h9948957_0
apptainer run -B $PWD:/data -H /data mcscanx.sif MCScanX data/input
```

### 4. 官方源码编译（并列保留）

官方以源码 zip 分发（无预编译二进制包）；官方下载页 `http://chibba.pgml.uga.edu/mcscan2/MCScanX.zip`
在 2026-09 核实为无法连接（curl 连接失败），请以 GitHub 仓库源码为准：

```bash
wget https://github.com/wyp1125/MCScanX/archive/refs/heads/master.tar.gz -O ~/software/MCScanX.tar.gz
mkdir -p ~/software/MCScanX-1.0.0
tar zxf ~/software/MCScanX.tar.gz -C ~/software/MCScanX-1.0.0 --strip-components=1
cd ~/software/MCScanX-1.0.0
export PATH=/usr/bin/:$PATH
make
echo 'export PATH=$PATH:~/software/MCScanX-1.0.0/' >> ~/.bashrc
source ~/.bashrc
MCScanX
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（MCScanX 未安装时不做真实检测）
```

## 版本

* mcscanx 1.0.0（bioconda::mcscanx=1.0.0；quay tag `1.0.0--h9948957_0`）
* 构建路线：官方镜像 / 官方源码编译（quay.io/biocontainers/mcscanx / depot.galaxyproject.org；本地不再自建容器）
* nf-core / snakemake-wrappers 官方均无 mcscanx 实现（2026-09 核实 404）

## 容器与 Conda 链接

* **Github**：https://github.com/wyp1125/MCScanX
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/mcscanx/overview>
* **Docker**：`docker pull quay.io/biocontainers/mcscanx:1.0.0--h9948957_0`
* **Singularity**：<https://depot.galaxyproject.org/singularity/mcscanx%3A1.0.0--h9948957_0>
* 安装方式（本地）：`mamba create -n mcscanx -c conda-forge -c bioconda mcscanx=1.0.0`
