# kent 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器环境信息记录于此。
> ⚠️ 官方无 kent 整体镜像/conda 包（bioconda/kent=404、quay.io/biocontainers/kent=401、depot 无），
> 故 native 提供**自建** `Dockerfile` / `Apptainer.def`（基于 debian:bookworm-slim + 官方预编译二进制）。

***

## native 实现

# kent / native — 自包含多工具驱动（UCSC kent / jksrc）

UCSC kent（jksrc）源码树的本地自包含实现（`source_type: custom`、`type: native`），覆盖文档用到的代表性二进制。

## 功能

| 子命令            | 命令                                                          | 作用                     |
| -------------- | ----------------------------------------------------------- | ---------------------- |
| `faToTwoBit`   | `faToTwoBit <in.fa> <out.2bit>`                              | FASTA → 2bit           |
| `twoBitToFa`   | `twoBitToFa <in.2bit> <out.fa>`                              | 2bit → FASTA           |
| `twoBitInfo`   | `twoBitInfo <in.2bit> <out.tab>`                             | 2bit → 序列信息表            |
| `blat`         | `blat <db> <query> <out.psl> -threads=N`                     | 快速比对（自动注入线程）           |
| `bedToBigBed`  | `bedToBigBed <in.bed> <chrom.sizes> <out.bigBed> [-type=]`   | BED → bigBed           |

## 用法

```bash
# CLI 直跑
python main.py faToTwoBit genome.fa genome.2bit
python main.py twoBitToFa genome.2bit genome.fa
python main.py twoBitInfo genome.2bit genome.tab
python main.py blat genome.2bit query.fa out.psl --threads 8
python main.py bedToBigBed regions.bed chrom.sizes regions.bigBed --type bed6

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；线程仅对 `blat` 注入 `-threads=N`（优先级：`--threads` > `per_subcommand_threads.blat`=8 > `default_cpus`）。

## 实战示例：kent 工具在基因组可视化中的典型用法

kent 工具按 12.md 用于 GBrowse2 的 `Bio::DB::BigFile`（jkweb.a）与 BigWig 转换；等价能力由 `native/main.py` 的子命令提供（命令装配见上「用法」）。

```bash
# 1. FASTA -> 2bit（blat 建库常用）
faToTwoBit genome.fasta genome.2bit

# 2. blat 比对（多线程）
blat genome.2bit query.fa out.psl -threads=8

# 3. BED -> bigBed（供 GBrowse/WebApollo 轨道）
bedToBigBed regions.bed chrom.sizes regions.bigBed -type=bed6

# 4. 2bit 序列信息
twoBitInfo genome.2bit genome.tab
```

> GBrowse2 的 `Bio::DB::BigFile` 需要 kent **源码编译**得到的 `lib/x86_64/jkweb.a`（文档要求 jksrc v330）；仅用上面的预编译二进制不足以构建该 Perl 模块。

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方无 kent 整体镜像/conda 包，但按工具提供官方预编译二进制，并提供源码树 jksrc v330 供编译。

### 1. 官方预编译二进制（首选）

UCSC 官方按工具分发 Linux 预编译二进制（`hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/<tool>`）：

```bash
mkdir -p ~/software/kent-v330/bin
for t in faToTwoBit twoBitToFa twoBitInfo blat bedToBigBed bigWigToBedGraph; do
    curl -fsSL -o ~/software/kent-v330/bin/$t \
        "https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/$t"
    chmod +x ~/software/kent-v330/bin/$t
done
echo 'export PATH=$PATH:~/software/kent-v330/bin' >> ~/.bashrc && source ~/.bashrc
faToTwoBit genome.fa genome.2bit   # 功能断言
```

> 一键安装：`bash native/install.sh --method binary`（同样部署到 `~/software/kent-v330`）。

### 2. 官方源码编译（jksrc v330，并列保留）

文档要求用 jksrc v330（**不要用最新版 kent**，最新版编译不出 `jkweb.a`）：

```bash
wget http://hgdownload.cse.ucsc.edu/admin/jksrc.archive/jksrc.v330.zip -O ~/software/jksrc.zip
unzip ~/software/jksrc.zip -d ~/software/
cd ~/software/kent/src/
export MACHTYPE=x86_64
mkdir -p ~/bin/x86_64
make CXXFLAGS=-fPIC CFLAGS=-fPIC CPPFLAGS=-fPIC -j 4
cp ./lib/x86_64/jkweb.a ./lib/     # GBrowse Bio::DB::BigFile 需要
```

> 一键编译：`bash native/install.sh --method source`（较慢；构建产物收集到 `~/software/kent-v330/bin`）。

### 3. Conda（bioconda ucsc-* 单工具包）

kent 无整体 conda 包，但代表性工具在 bioconda 有单工具包（官方容器亦按 Ucsc-* 提供）：

```bash
mamba create -n kent -c conda-forge -c bioconda \
    ucsc-fatotwobit ucsc-twobittofa ucsc-twobitinfo ucsc-blat ucsc-bedtobigbed
conda activate kent
faToTwoBit genome.fa genome.2bit
```

> 一键安装：`bash native/install.sh --method conda`；`--method auto` 在有 conda 时走此路线，否则走官方预编译二进制。

### 4. Docker（自建镜像）

官方无 kent 镜像，使用本模块自建配方（`native/Dockerfile`，基于 debian:bookworm-slim + 官方预编译二进制）：

```bash
docker build -t bioskills/kent:jksrc-v330 modules/kent/native
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint faToTwoBit bioskills/kent:jksrc-v330 genome.fa genome.2bit
```

### 5. Apptainer（自建 def）

官方无镜像，从本模块 `native/Apptainer.def` 本地构建 sif：

```bash
apptainer build kent.sif modules/kent/native/Apptainer.def
apptainer exec -B $PWD:/data kent.sif faToTwoBit /data/genome.fa /data/genome.2bit
```

## 测试

```bash
bash test/run_test.sh   # kent 未安装时退化为 argv 构造验证；已安装则做 FASTA↔2bit 往返断言
```

## 版本

* kent jksrc v330（官方源码 jksrc.v330.zip；官方预编译二进制随上游按工具更新）

* 构建路线：无官方整体镜像 → 本地自建（官方预编译二进制 / 源码编译）

* 官方 nf-core modules 无 kent、snakemake-wrappers 无 bio/kent（均为 404），无官方流程实现登记

## 容器与 Conda 链接

* **无 kent 整体官方镜像**（bioconda/kent=404、quay.io/biocontainers/kent=401、depot 无）→ 自建配方：`native/Dockerfile`、`native/Apptainer.def`

* **官方预编译二进制**：<https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/>

* **官方源码树**：<http://hgdownload.cse.ucsc.edu/admin/jksrc.archive/jksrc.v330.zip>

* **ucsc-* 单工具 conda 包**：<https://anaconda.org/channels/bioconda/packages/ucsc-fatotwobit/overview>

* 安装方式（本地）：官方预编译二进制（推荐）或 `bash native/install.sh --method source`（编译 jksrc v330）
