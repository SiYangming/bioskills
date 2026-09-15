# clustalw 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# clustalw / native — 自包含多序列比对驱动

ClustalW 2.1 的本地自包含实现（`source_type: custom`、`type: native`）：经典渐进式多序列
比对（Larkin 2007 / Thompson 1994），适用于核酸与蛋白质序列，可产出比对结果与系统发育树。

## 功能

**ClustalW** 是经典的多序列比对工具，采用渐进式比对算法，适用于核酸和蛋白质序列比对。虽然速度较慢，但在某些场景下仍有应用价值。

| 子命令 | 实际命令 | 作用 |
| ---- | ---- | ---- |
| `align` | `clustalw -infile=<in> -outfile=<out> -output=<fmt> -type=<PROTEIN\|DNA> -align [-quicktree] [-matrix=] [-gapopen=] [-gapext=] [-outorder=] [-quiet] [-stats=] [-newtree=]` | 多序列比对 |
| `tree` | `clustalw -infile=<in> -tree -outfile=<out> [-newtree=] [-outputtree=nj\|phylip\|dist\|nexus] [-clustering=NJ\|UPGMA] [-bootstrap=n]` | 系统发育树（NJ/UPGMA，可 bootstrap） |
| `profile` | `clustalw -profile1=<a> -profile2=<b> -profile -outfile=<out> -output=<fmt> [-usetree1=] [-usetree2=]` | 两比对合并（profile alignment） |
| `help` | `clustalw -help` | 打印帮助 |

> **注意**：ClustalW 为**单线程**程序，`--threads` 仅作接口占位（被接受但不注入 argv）。

## 用法

```bash
# CLI 直跑
python main.py align -infile=seqs.fasta -outfile=aln.fasta -output=FASTA -type=PROTEIN
python main.py tree -infile=aln.fasta -outfile=tree.ph -outputtree=phylip -clustering=NJ
python main.py tree -infile=aln.fasta -outfile=boot.ph -bootstrap=1000
python main.py profile -profile1=a.aln -profile2=b.aln -outfile=merged.aln -output=CLUSTAL
python main.py help

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir`（`--threads` 为单线程占位）。

## 参数说明（对照 clustalw man page；选项大小写不敏感）

| 参数 | 子命令 | 说明 |
| ---- | ---- | ---- |
| `-infile=` | align/tree | 输入序列/比对文件（FASTA/PIR/Clustal/MSF 等，格式自动识别） |
| `-outfile=` | align/tree/profile | 输出文件 |
| `-output=` | align/profile | 输出格式：CLUSTAL / FASTA / PHYLIP / NEXUS / PIR / GDE / GCG（默认 CLUSTAL） |
| `-type=` | 全部 | 序列类型 PROTEIN 或 DNA（省略则自动识别） |
| `-quicktree` | align | 用快速近似算法构建引导树（加速） |
| `-matrix=` | align | 蛋白权重矩阵（BLOSUM/PAM/GONNET/ID/文件） |
| `-gapopen=` / `-gapext=` | align | 多序列比对开 gap / gap 延伸罚分 |
| `-outorder=` | align | 输出序列顺序：INPUT（按输入）/ ALIGNED（按比对） |
| `-quiet` / `-stats=` | 全部 | 减少控制台输出 / 比对统计输出文件 |
| `-profile1=` / `-profile2=` | profile | 两组比对 |
| `-usetree1=` / `-usetree2=` | profile | profile 各自的旧引导树 |
| `-newtree=` | align/tree | 写出新引导树 |
| `-clustering=` | tree | NJ（默认）或 UPGMA |
| `-bootstrap=` | tree | NJ 树 bootstrap 重复次数（默认 1000） |
| `-outputtree=` | tree | 树输出格式：nj / phylip / dist / nexus |

## 实战示例：单拷贝同源基因多序列比对

ClustalW 常用于把 OrthoFinder/OrthoMCL 得到的单拷贝同源基因逐组比对上，再衔接 trimAl
修剪与系统发育树构建：

```bash
# 对每个单拷贝同源基因组做比对（FASTA 输出便于下游 trimAl）
for fa in Single_Copy_Orthologue_Sequences/*.fa
do
    base=$(basename $fa .fa)
    clustalw -INFILE=$fa -OUTFILE=msa/${base}.aln -OUTPUT=FASTA -TYPE=PROTEIN -QUICKTREE -ALIGN
done

# 生成 NJ 树（可选 bootstrap）
clustalw -INFILE=msa/OG0001.aln -TREE -OUTFILE=tree/OG0001.ph -OUTPUTTREE=phylip
```

上述命令等价能力由 `native/main.py` 的 `align` / `tree` / `profile` 子命令提供：

```bash
python main.py align -infile=OG0001.fa -outfile=OG0001.aln -output=FASTA -quicktree
python main.py tree -infile=OG0001.aln -outfile=OG0001.ph -outputtree=phylip
```

## 测试

```bash
bash test/run_test.sh   # align/tree/profile/help 均为 argv 构造验证（clustalw 未装时退化为断言）
```

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方
镜像运行工具本体；`main.py` 驱动在宿主机跑。官方同时提供**预编译静态二进制**
（EBI 官方镜像站 `clustalw-2.1-linux-x86_64-libcppstatic.tar.gz`）与**源码**
（`clustalw-2.1.tar.gz`），故宿主安装两条官方路线并列。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n clustalw-native -c conda-forge -c bioconda clustalw=2.1
conda activate clustalw-native
clustalw -help   # 断言：输出含 "CLUSTAL 2.1"
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，公式名 clustal-w）
brew tap brewsci/bio
brew install clustal-w
clustalw -help   # 断言
# 注：brewsci/bio Formula/clustal-w.rb 安装 clustalw2 并软链 clustalw，版本 2.1，与 meta 一致
```

> 一键安装也可直接运行 `native/install.sh`（有 conda 时建 bioconda 环境 `clustalw`；
> linux-x64 无 conda 时下载官方预编译静态二进制，其余平台走源码编译；版本默认 2.1，
> 与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/clustalw:2.1--hc52dbad_13
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/clustalw:2.1--hc52dbad_13 \
    clustalw -INFILE=/data/seqs.fasta -OUTFILE=/data/aln.fasta -OUTPUT=FASTA -ALIGN
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull clustalw.sif docker://depot.galaxyproject.org/singularity/clustalw:2.1--hc52dbad_13
apptainer run -B $PWD:/data -H /data clustalw.sif \
    clustalw -INFILE=/data/seqs.fasta -OUTFILE=/data/aln.fasta -OUTPUT=FASTA -ALIGN
```

### 4. 官方预编译二进制包（首选；仅 linux-x86_64）

官方（EBI 镜像站）提供 2.1 的 Linux x86_64 静态二进制包：

```bash
wget https://ftp.ebi.ac.uk/pub/software/clustalw2/2.1/clustalw-2.1-linux-x86_64-libcppstatic.tar.gz -P ~/software/
tar zxf ~/software/clustalw-2.1-linux-x86_64-libcppstatic.tar.gz -C ~/software/
export PATH="$HOME/software/clustalw-2.1-linux-x86_64-libcppstatic:$PATH"   # 建议写入 ~/.bashrc
clustalw2 -help        # 包内可执行为 clustalw2
ln -s "$HOME/software/clustalw-2.1-linux-x86_64-libcppstatic/clustalw2" \
      "$HOME/software/clustalw-2.1-linux-x86_64-libcppstatic/clustalw"   # 补 clustalw 软链
# sha256(clustalw-2.1-linux-x86_64-libcppstatic.tar.gz) = e8d488db819789642b44945d238a50847f2505a1a0dd43d374fa7f29f9defcac
```

> 官方 macOS 资产为 `.dmg`、Windows 为 `.msi`（非脚本友好）；macOS 建议走 conda 或 brew。
> 注意 **ClustalW 2.1 采用 LGPL 许可，无 `clustalw` 官方预编译 `-version` 旗标**，版本断言用 `-help`。

### 5. 官方源码编译（并列保留）

* **官网**：<http://www.clustal.org/clustal2/>
* **下载**：<http://www.clustal.org/download/>
* **源码（EBI 镜像）**：<https://ftp.ebi.ac.uk/pub/software/clustalw2/2.1/clustalw-2.1.tar.gz>
  （sha256 `e052059b87abfd8c9e695c280bfba86a65899138c82abccd5b00478a80f49486`）

```bash
wget https://ftp.ebi.ac.uk/pub/software/clustalw2/2.1/clustalw-2.1.tar.gz -P ~/software/
tar zxf ~/software/clustalw-2.1.tar.gz -C ~/software/
cd ~/software/clustalw-2.1/src
./configure --prefix=$HOME/software/clustalw-2.1 && make && make install
export PATH="$HOME/software/clustalw-2.1/bin:$PATH"   # 建议写入 ~/.bashrc
clustalw -help
```

> 也可一键运行 `native/install.sh --method binary`（预编译，linux-x64）或 `--method source`（源码编译）。

## 版本

* **2.1**（ClustalW2；官方源码 `clustalw-2.1.tar.gz` 与 Linux x86_64 预编译包均在 EBI 官方镜像站可达）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/clustalw / depot.galaxyproject.org；本地不再自建容器）
* License：**LGPL-3.0-or-later**
* nf-core：无 `modules/nf-core/clustalw`（2026-09 核实 404）；snakemake-wrappers：无 `bio/clustalw`（2026-09 核实 404）
* 引用：Larkin MA et al. Clustal W and Clustal X version 2.0. *Bioinformatics* 2007;23:2947-8.
  doi:10.1093/bioinformatics/btm404；Thompson JD, Higgins DG, Gibson TJ. CLUSTAL W.
  *Nucleic Acids Res.* 1994;22:4673-80.

## 容器与 Conda 链接

* **官网**：<http://www.clustal.org/clustal2/>
* **下载页**：<http://www.clustal.org/download/>
* **在线**：<https://www.genome.jp/tools-bin/clustalw>
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/clustalw/overview>
* **Docker**：`docker pull quay.io/biocontainers/clustalw:2.1--hc52dbad_13`
* **Singularity**：<https://depot.galaxyproject.org/singularity/clustalw%3A2.1--hc52dbad_13>
* **brew**：`brew tap brewsci/bio && brew install clustal-w`（brewsci/bio Formula/clustal-w.rb；版本 2.1）
* 安装方式（本地）：`mamba create -n clustalw -c conda-forge -c bioconda clustalw=2.1`
