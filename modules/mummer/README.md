# mummer 软件模块

> 汇总说明：本 README 合并 native 实现用法；安装方式见下方各节，容器与 conda 信息记录于此。
>
> **版本提示**：本模块以文档采用的 **MUMmer v4（4.0.0beta2）** 为准。⚠️ bioconda 的 **`mummer` 包是旧版 MUMmer3.23**；
> MUMmer4 的包名是 **`mummer4`**。nf-core 官方 `mummer` 模块 pin 的仍是 `mummer=3.23`（跨引擎迁移注意参数差异）。

***

## native 实现

# mummer / native — 自包含全基因组比对驱动

MUMmer v4 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

MUMmer（Maximal Unique Matches）用于全基因组比对，包括nucmer比对、delta-filter过滤、show-coords坐标展示和mummerplot可视化等多个工具，广泛应用于基因组比对、共线性分析、SNP 检测等。五个子命令的 MUMmer 全流程：

| 子命令            | 命令                                                                                   | 作用                            |
| -------------- | ------------------------------------------------------------------------------------ | ----------------------------- |
| `nucmer`       | `nucmer [--threads N] [-p out] [-c 200] [-g 200] <ref> <qry>`                          | 全基因组比对 → `<prefix>.delta`     |
| `para_nucmer`  | `para_nucmer --CPU N --nucmer " <opts>" <ref> <qry>`                                  | 并行比对 → `out.delta`（stdout）    |
| `delta_filter` | `delta-filter [-i 95] [-r] [-q] <delta>`                                              | 过滤比对结果 → `out.rq.delta`（stdout） |
| `show_coords`  | `show-coords [-c] [-d] [-l] [-I 95] [-L 10000] [-r] <delta>`                          | 展示坐标/相似度/覆盖率（stdout）        |
| `mummerplot`   | `mummerplot [-f] [-l] [-p out] [-s large] [-t png] [-r sub] [-S] <delta>`             | gnuplot 点阵图 → `out.png`        |

> 写 stdout 的子命令（`para_nucmer` / `delta_filter` / `show_coords`）提供 `-o/--output` 时由驱动把 stdout 落盘。

## 用法

```bash
# CLI 直跑
python main.py nucmer ref.fasta qry.fasta -p out -c 200 -g 200 --threads 8
python main.py para_nucmer ref.fasta qry.fasta --CPU 8 --nucmer-args " -p out -l 100" -o out.delta
python main.py delta_filter out.delta -i 95 -r -q -o out.rq.delta
python main.py show_coords out.rq.delta -c -d -l -I 95 -L 10000 -r -o out.show
python main.py mummerplot out.delta -f -l -p out -s large -t png

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（`nucmer` 注入 `--threads`、`para_nucmer` 注入 `--CPU`）/ `--tmpdir` 运行期覆盖。

## 实战示例：MUMmer v4 全基因组比对

```bash
mkdir -p Mummer && cd Mummer
cp Malassezia_sympodialis.genome_V01.fasta IDBA.fasta ./

# 10.3 运行 nucmer 比对（para_nucmer 并行版）
para_nucmer --CPU 8 Malassezia_sympodialis.genome_V01.fasta IDBA.fasta > out.delta
# 或单线程：nucmer -c 200 -g 200 -p out Malassezia_sympodialis.genome_V01.fasta IDBA.fasta

# 10.4 delta-filter 过滤（-i 最小相似度 95%，-r/-q 保留参考/查询最佳匹配）
delta-filter -i 95 -r -q out.delta > out.rq.delta

# 10.5 show-coords 展示坐标（-c 覆盖率 -d 差异数 -l 长度 -I 95 -L 10000 -r 按参考排序）
show-coords -c -d -l -I 95 -L 10000 -r out.rq.delta > out.show

# 10.6 mummerplot 可视化（-f 过滤后 -l 标签 -s large -t png）
mummerplot -f -l -p out -s large -t png out.delta
gnuplot out.gp
```

等价能力由 `native/main.py` 的 `nucmer` / `para_nucmer` / `delta_filter` / `show_coords` / `mummerplot`
子命令提供（见上「用法」），对 stdout 型子命令用 `-o` 直接落盘即可替代 shell 重定向。

### 参数说明

| 参数                  | 子命令                  | 说明                    |
| ------------------- | -------------------- | --------------------- |
| `-c`                | nucmer               | 最小匹配簇长度（文档示例 200）     |
| `-g`                | nucmer               | 最大 gap 长度（文档示例 200）   |
| `--CPU`             | para_nucmer          | 并行核数                  |
| `--nucmer`          | para_nucmer          | 透传给内部 nucmer 的参数字符串   |
| `-i`                | delta-filter         | 最小相似度（文档示例 95）        |
| `-r` / `-q`         | delta-filter         | 保留参考/查询最佳匹配           |
| `-I` / `-L`         | show-coords          | 最小相似度 / 最小比对长度        |
| `-s` / `-t`         | mummerplot           | 图尺寸 / 输出终端（png）       |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
`main.py` 驱动在宿主机跑。官方 release **仅提供源码归档**（v4.0.0beta2 无预编译二进制资产，2026-09 核实；
v4.0.0/v4.0.1 release 另附 `mummer-alpine.sif`）。

### 1. Conda / brew（包管理器安装）

```bash
# v4：bioconda 包名 mummer4（mummer 包是旧版 MUMmer3.23）
mamba create -n mummer -c conda-forge -c bioconda mummer4=4.0.0beta2
conda activate mummer
nucmer --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install mummer
nucmer --version   # brew 当前 4.0.1，与 meta 登记 4.0.0beta2 略有差异（版本以 formula 为准）
```

> 一键安装直接 `bash native/install.sh`（默认 auto：有 conda/mamba 走 bioconda `mummer4`，无 conda 时回退官方源码 `./configure && make && make install`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/mummer4:4.0.0beta2--pl526he1b5a44_5
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/mummer4:4.0.0beta2--pl526he1b5a44_5 \
    nucmer -p out -c 200 -g 200 /data/ref.fasta /data/qry.fasta
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull mummer4.sif docker://depot.galaxyproject.org/singularity/mummer4:4.0.0beta2--pl526he1b5a44_5
apptainer run -B $PWD:/data -H /data mummer4.sif \
    nucmer -p out -c 200 -g 200 /data/ref.fasta /data/qry.fasta
```

### 4. 官方源码编译（并列保留）

```bash
wget https://github.com/mummer4/mummer/releases/download/v4.0.0beta2/mummer-4.0.0beta2.tar.gz -P ~/software
tar zxf ~/software/mummer-4.0.0beta2.tar.gz -C ~/software/
cd ~/software/mummer-4.0.0beta2
./configure --prefix=$HOME/software/mummer-4.0.0beta2 && make -j 8 && make install
echo 'export PATH=$PATH:~/software/mummer-4.0.0beta2/bin' >> ~/.bashrc && source ~/.bashrc
nucmer --version   # 断言
```

> 一键安装：`bash native/install.sh --method source`（下载 v4.0.0beta2 源码 → configure/make/make install
> 到 `~/software/mummer-4.0.0beta2` 并写 PATH；版本断言 `nucmer --version`。官方 release 未提供摘要，
> 脚本不内嵌 sha256、跳过校验并提示自行核对）。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（五子命令）+ 自省；二分制未安装时跳过真实冒烟
```

## 容器与 Conda 链接

* **Github**：https://github.com/mummer4/mummer

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/mummer4/overview>

* **Docker**：`docker pull quay.io/biocontainers/mummer4:4.0.0beta2--pl526he1b5a44_5`

* **Singularity**：<https://depot.galaxyproject.org/singularity/mummer4%3A4.0.0beta2--pl526he1b5a44_5>

* 安装方式（本地）：`mamba create -n mummer -c conda-forge -c bioconda mummer4=4.0.0beta2`

## 版本

* MUMmer **4.0.0beta2**（官方 GitHub release v4.0.0beta2；bioconda 包名 **mummer4**）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/mummer4:4.0.0beta2--pl526he1b5a44_5 / depot.galaxyproject.org；本地不自建容器）

* 2026-09 核实：nf-core 有 `modules/nf-core/mummer` 单模块（pin `bioconda::mummer=3.23`＝MUMmer3）；snakemake-wrappers `bio/mummer` 404；homebrew-core `mummer` 公式为 4.0.1
