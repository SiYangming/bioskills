# isolasso 软件模块

> 汇总说明：本 README 记录 isolasso native 实现的用法与环境安装。官方 **无 bioconda 包、无官方容器、
> 无预编译二进制**（2026-09 逐渠道核实全无），故走**官方源码编译优先 + 自建容器兜底**；官方 nf-core /
> snakemake-wrappers 亦无（仅登记于 `meta.yaml software_versions` 与本文档）。

***

## native 实现

# isolasso / native — 自包含转录本组装驱动

IsoLasso v2.6.1 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

isolasso 是一个转录本组装工具，SpliceGrapher 使用它进行转录本预测。

三个子命令覆盖官方 `bin/` 的端到端入口与两个原语：

| 子命令          | 命令                                                        | 作用                                             |
| ------------ | --------------------------------------------------------- | ---------------------------------------------- |
| `assemble`   | `runlasso.py [-o <prefix>] <input.sam\|.bam\|.instance>`   | 端到端组装（processsam -> isolasso -> pred2gtf\|sortgtf），产出 `<prefix>.pred.gtf` |
| `processsam` | `processsam [-o <instance>] <input.sam>`                  | SAM/BAM -> `.instance`                          |
| `isolasso`   | `isolasso [-o <prefix>] <input.instance>`                 | LASSO 二次规划求解 -> `.pred`                        |

> **编译依赖（务必先装）**：CGAL / GSL / GLPK / GMP（源码 `src/Makefile` 链接 `-lglpk -lCGAL -lgsl
> -lgslcblas -lm`）；历史 CentOS 6 文档另提及 `boost_thread`。BAM 输入需系统 PATH 中有 **samtools**
> （`runlasso.py` 用 `samtools view` 管道）。IsoLasso 求解为**单线程**，`--threads` 仅接口兼容（不注入）。

## 用法

```bash
# 端到端组装（SAM/BAM/instance -> <prefix>.pred.gtf）
python main.py assemble alignments.bam -o sample
python main.py assemble alignments.sam -o sample

# 分步：SAM -> instance -> .pred -> GTF（GTF 转换由 bin/ 内的 pred2gtf|sortgtf 完成）
python main.py processsam alignments.sam -o sample      # -> sample.instance
python main.py isolasso   sample.instance -o sample      # -> sample.pred

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir`（`--threads` 不注入，IsoLasso 单线程）。

## 实战示例：参考引导转录本组装

IsoLasso 用 LASSO 回归在预测精度与稀疏性之间取平衡，常作为 SpliceGrapherXT 的可选转录本预测后端。
典型用法（等价能力由 `native/main.py` 的 `assemble` 子命令提供，见上「用法」）：

```bash
# 0. 准备比对（BAM 或 SAM；BAM 需 samtools 在 PATH）
samtools sort -@ 8 -O bam -o alignments.bam alignments.sam

# 1. 端到端组装：BAM -> <prefix>.pred.gtf
python main.py assemble alignments.bam -o sample1

# 2. （可选）分步以观察中间产物
python main.py processsam alignments.sam -o sample1   # sample1.instance
python main.py isolasso   sample1.instance -o sample1  # sample1.pred
# 再经 bin/ 内 pred2gtf|sortgtf 转 GTF（assemble 已自动串联）

# 3. 得到 sample1.pred.gtf（组装转录本 + 表达量）
```

### 参数说明

| 参数     | 说明                                                     |
| ------ | ------------------------------------------------------ |
| input  | 主输入（assemble：SAM/BAM/instance；processsam：SAM/BAM；isolasso：instance） |
| `-o`   | 输出前缀（runlasso.py 支持 `-o`/`--prefix`；产出 `<prefix>.pred` / `<prefix>.pred.gtf`） |
| `--threads` | 接口兼容（IsoLasso 单线程，不注入命令行）                              |

## 环境安装（无官方镜像/conda；官方源码编译优先，自建容器兜底）

官方 **无 bioconda 包、无 quay/depot 镜像、无预编译二进制**（2026-09 核实全无）→ 只能**官方源码编译**或**自建容器**。

### 1. 官方源码编译（首选）

```bash
# 编译依赖（Debian/Ubuntu 示例；Ubuntu 亦可用 libcgal-dev libgsl-dev libglpk-dev libgmp-dev）
sudo apt-get install -y build-essential libcgal-dev libgsl-dev libglpk-dev libgmp-dev

# 下载并编译（官方说明：进入 src 目录 make -j）
wget http://alumni.cs.ucr.edu/~liw/isolasso-2.6.1.tar.gz -P ~/software/
tar zxf ~/software/isolasso-2.6.1.tar.gz -C ~/software/
cd ~/software/isolasso-2.6.1/src
make -j 4
# 编译产物在 ../bin/：isolasso / processsam / sortgtf / pred2gtf 等（runlasso.py 为其主入口）
echo 'export PATH=$HOME/software/isolasso-2.6.1/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

> 历史 CentOS 6 说明：需 `gsl*`/`gmp*`，并将 `libboost_thread.so` 建立兼容符号链接（本模块在 README 注明，
> 现代 Debian/Ubuntu 走系统 CGAL/GSL/GLPK/GMP 即可）。
>
> 一键安装可直接运行 `native/install.sh`（有 conda/mamba 时用 conda-forge 编译器 + CGAL/GSL/GLPK/GMP
> 编译；否则用系统编译器；版本默认 2.6.1，内嵌官方源码包 sha256 校验）。用法：`bash native/install.sh --help`。

### 2. Conda（备选；**官方无 bioconda 包**）

官方无 conda 包；可用 conda-forge 提供编译器与编译依赖后自行编译官方源码：

```bash
mamba create -n isolasso -c conda-forge cxx-compiler make cgal gsl glpk gmp python=3
conda activate isolasso
# 再按上方「官方源码编译」在本环境内 make
```

> Homebrew：homebrew-core 与 brewsci/bio 均无 isolasso 公式（2026-09 核实），故不提供 brew 安装块。

### 3. Docker（自建镜像）

官方无镜像，本模块提供自建配方（`native/Dockerfile`；debian:bookworm-slim + CGAL/GSL/GLPK/GMP + 官方源码 make）：

```bash
# 构建（context 必须是 modules/ 层）
docker build -t bioskills/isolasso:2.6.1 -f modules/isolasso/native/Dockerfile modules/
# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/isolasso:2.6.1 assemble /data/alignments.bam -o /data/sample
```

### 4. Apptainer / Singularity（自建 sif）

```bash
cd modules && apptainer build isolasso-2.6.1.sif isolasso/native/Apptainer.def
apptainer run -B $PWD:/data -H /data isolasso-2.6.1.sif assemble /data/alignments.bam -o /data/sample
```

## 测试

```bash
bash test/run_test.sh   # assemble/processsam/isolasso 为 argv 构造验证；二进制已编译时做存在性探测
```

## 版本

* isolasso 2.6.1（官方源码包 isolasso-2.6.1.tar.gz，2012-11-17 发布）
* 构建路线：**自建容器/源码编译**（官方渠道 bioconda→quay.io/biocontainers→depot.galaxyproject.org 2026-09
  核实全无：bioconda API 404、quay API 401、depot 无）
* 编译依赖：CGAL / GSL / GLPK / GMP（历史 CentOS 6 文档另提及 boost_thread）

## 官方实现登记（不建目录）

* **nf-core**：`modules/nf-core/isolasso` 不存在（2026-09 核实 `meta.yml` 404）。
* **snakemake-wrappers**：`bio/isolasso` 不存在（2026-09 核实 `environment.yaml` / `wrapper.py` 均 404）。

## 容器与 Conda 链接

* **官方站点**：<http://alumni.cs.ucr.edu/~liw/isolasso.html>
* **源码包**：<http://alumni.cs.ucr.edu/~liw/isolasso-2.6.1.tar.gz>
* **Bioconda**：（无——api.anaconda.org/package/bioconda/isolasso 404，2026-09 核实）
* **Docker/Singularity**：（官方无）本仓库自建：`native/Dockerfile` + `native/Apptainer.def`
* **Homebrew**：（无——homebrew-core 与 brewsci/bio 均 404）
* 安装方式（本地）：`bash native/install.sh`（官方源码编译，见上）
