# viennarna 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 来源：`docs/10.md` 第十九节（非编码RNA预测）——miRNA 预测相关工具；文档写作「miRNAFold」。
> **命名核实**见下「关于 miRNAFold 的命名核实」。

***

## native 实现

# viennarna / native — 自包含 RNA 二级结构预测驱动

ViennaRNA（核心程序 `RNAfold`）的本地自包含实现（`source_type: custom`、`type: native`）。

ViennaRNA 是 RNA 二级结构预测与比较的标准工具包（Lorenz et al., *Algorithms Mol Biol* 2011）：`RNAfold` 计算最小自由能（MFE）结构与配分函数，广泛用于 ncRNA / miRNA precursor 二级结构分析（结构与 ΔG 评估）。

## 功能

| 子命令       | 命令                                                                        | 作用                        |
| --------- | ------------------------------------------------------------------------- | ------------------------- |
| `rnafold` | `RNAfold [-p] [--MEA] [--noLP] [-4] [-C] [-T <temp>] [--noPS] <input.fa>`  | 计算 MFE 结构 / 配分函数          |
| `rnaeval` | `RNAeval [-4] [-C] [-T <temp>] <input>`                                    | 评估给定结构的自由能                |
| `rnaplot` | `RNAplot [-t <format>] [-o <out>] <input>`                                 | 绘制二级结构图（ps/eps/svg/xrna）  |

> ViennaRNA 主程序为**单进程**（部分程序 OpenMP 可选）；`--threads` 仅记录，不注入命令行。
> 同包另有 `RNAsubopt` / `RNAplfold` / `RNAcofold` / `RNAalifold` 等程序，需要时用 `--extra-args` 或直接调用。

## 用法

```bash
# CLI 直跑：折叠 pre-miRNA 序列（MFE + 配分函数）
python main.py rnafold pre_mirna.fa -p --noLP -T 37
python main.py rnafold pre_mirna.fa --MEA --noPS

# 评估给定结构的能量 / 绘制结构图
python main.py rnaeval structure.txt
python main.py rnaplot structure.txt -t svg -o struct

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

参数（节选）：

| 参数            | 说明                                    |
| ------------- | ------------------------------------- |
| `-p`          | 同时计算配分函数与碱基配对概率矩阵（RNAfold）            |
| `--MEA`       | 计算最大期望精度（MEA）结构                       |
| `--noLP`      | 禁止孤立碱基对（lonely pairs）                 |
| `-4`          | 输入按 DNA 处理（T 而非 U）                    |
| `-T`          | 折叠 / 评估温度（默认 37 ℃）                    |
| `--noPS`      | 不输出 PostScript 结构图                    |
| `-t` / `-o`   | RNAplot：输出图形格式 / 输出文件                |

## 实战示例：批量折叠 miRNA precursor 序列

```bash
mkdir -p viennarna_out && cd viennarna_out

# 批量折叠所有 pre-miRNA 序列，输出 MFE 结构（.fold）
for i in ../pre_mirna/*.fa
do
    sample=$(basename "$i" .fa)
    RNAfold --noPS < "$i" > "${sample}.fold"
done

# 汇总每个 precursor 的 MFE 自由能（第二列括号内数值）
grep -h "(" *.fold | sed 's/.*(//; s/)//' > mfe.txt
```

> 上述批量用法与 `native/main.py` 的 `rnafold` 子命令等价：单条调用走 `main.py rnafold <input.fa>`，批量循环时对每个文件调用一次（见上「用法」）。

## 关于 miRNAFold 的命名核实

`docs/10.md` 第十九节把 miRNA 预测工具列为「miRDeep、**miRNAFold**」。为确定本模块 canonical 名，按任务要求做了 curl 核实（禁止臆断）：

| 核实项                                        | 结果                                                                                        |
| ------------------------------------------ | ----------------------------------------------------------------------------------------- |
| 任务/文档所指 URL `http://biwww2.informatik.uni-freiburg.de` | **000（不可达）**；`https://biwww2.informatik.uni-freiburg.de` 亦 000                            |
| bioconda `mirnafold`                        | **未找到**（api.anaconda.org 返回 `"mirnafold" could not be found`）                            |
| quay.io/biocontainers/mirnafold             | **401（不存在）**                                                                             |
| depot.galaxyproject.org/singularity/mirnafold | **404**                                                                                   |
| 真实的 miRNAFold（Tempel & Tahi, *NAR* 2012，ab-initio pre-miRNA 预测器） | 托管于 <http://EvryRNA.ibisc.univ-evry.fr>（**200**），但**非** freiburg 站点，且无 conda / 官方镜像 |
| ViennaRNA（提供 RNAfold）                      | bioconda **viennarna=2.7.2**、quay / depot 官方镜像、nf-core **viennarna/rnafold** 均有维护          |

**结论**：文档 alias「miRNAFold」存在歧义——其所引 freiburg URL 不可达、且无 `mirnafold` 官方包；而 ViennaRNA（提供 `RNAfold`，是 RNA 二级结构预测的事实标准、有完整官方渠道）可稳定构建与分发。故本模块 canonical 采用 **`viennarna`**（RNAfold）；真实的 **miRNAFold**（Evry，ab-initio pre-miRNA 预测器）为相关但不同的工具，此处登记其主页以备参考。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n viennarna-native -c conda-forge -c bioconda viennarna=2.7.2
conda activate viennarna-native
RNAfold --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先 tap）
brew tap brewsci/bio
brew install brewsci/bio/viennarna
RNAfold --version   # 断言
```

> ⚠️ brew 的 `viennarna` 公式当前构建 2.7.0，与 meta 登记 2.7.2 略有差异（以 formula 为准）。

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `viennarna`，无 conda 时下载 TBI 官方源码 `ViennaRNA-2.7.2.tar.gz` 编译到 `~/software/viennarna-<ver>` 并写 PATH；默认版本 2.7.2，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/viennarna:2.7.2--py311pl5321h7f785ea_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/viennarna:2.7.2--py311pl5321h7f785ea_0 RNAfold \
    --noPS < /data/pre_mirna.fa
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull viennarna.sif docker://depot.galaxyproject.org/singularity/viennarna:2.7.2--py311pl5321h7f785ea_0
apptainer run -B $PWD:/data -H /data viennarna.sif RNAfold --noPS < /data/pre_mirna.fa
```

### 4. 官方源码编译（并列保留）

* **官网**：<https://www.tbi.univie.ac.at/RNA/>

* **源码归档**：<https://www.tbi.univie.ac.at/RNA/download/sourcecode/2_7_x/ViennaRNA-2.7.2.tar.gz>（sha256 `ffb98b2d…df0b91`）

```bash
wget https://www.tbi.univie.ac.at/RNA/download/sourcecode/2_7_x/ViennaRNA-2.7.2.tar.gz -P ~/software/
tar zxf ~/software/ViennaRNA-2.7.2.tar.gz -C ~/software/
cd ~/software/ViennaRNA-2.7.2
./configure --prefix=$HOME/software/viennarna-2.7.2 --without-perl --without-python
make && make install
export PATH=$HOME/software/viennarna-2.7.2/bin:$PATH
RNAfold --version   # 断言
```

## 测试

```bash
bash test/run_test.sh   # rnafold/rnaeval/rnaplot 为 argv 构造验证；装了 RNAfold 时另跑真实折叠回归
```

## 版本

* ViennaRNA 2.7.2（bioconda::viennarna=2.7.2）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/viennarna / depot.galaxyproject.org；本地不再自建容器）

* 与 nf-core 子模块 viennarna/{rnafold,rnacofold,rnalfold} 的 bioconda pin（2.6.4）相差一个 minor

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/viennarna/overview>

* **Docker**：`docker pull quay.io/biocontainers/viennarna:2.7.2--py311pl5321h7f785ea_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/viennarna%3A2.7.2--py311pl5321h7f785ea_0>

* 安装方式（本地）：`mamba create -n viennarna -c conda-forge -c bioconda viennarna=2.7.2`
