# microbiomeutil 软件模块

> 汇总说明：本 README 说明 microbiomeutil（含 ChimeraSlayer）native 实现的用法；安装方式见下方各节，
> 容器与依赖信息记录于此。许可：BSD-3-Clause（Broad Institute，见 `ChimeraSlayer/LICENSE`）。

***

## native 实现

# microbiomeutil / native — 自包含 16S 嵌合体检测驱动

MicrobiomeUtilities 的本地自包含实现（`source_type: custom`、`type: native`）。覆盖套件三个组件：

| 子命令            | 对应程序              | 命令（核心参数）                                                                                | 作用                       |
| -------------- | ----------------- | ---------------------------------------------------------------------------------------- | ------------------------ |
| `chimeraslayer` | `ChimeraSlayer.pl` | `ChimeraSlayer.pl --query_NAST <q.NAST> [--db_NAST <r> --db_FASTA <r>] [-n N -R X -P N ...]` | 基于 BLAST 的 16S 嵌合体检测       |
| `nastier`      | `run_NAST-iEr.pl` | `run_NAST-iEr.pl --query_FASTA <q.fa> [--db_NAST <r> --db_FASTA <r>] [--num_top_hits N]`     | 把未比对序列转为 NAST 比对格式         |
| `wigeon`       | `run_WigeoN.pl`   | `run_WigeoN.pl --query_NAST <q.NAST> [--db_NAST <r> --db_FASTA <r>] [--num_top_hits N]`      | Pintail 类 16S 序列异常（含嵌合）检测 |

> 说明：microbiomeutil 三个程序均为**单线程**，不接受线程参数；`--threads` 作为契约字段被接受但不注入命令行。

## 用法

```bash
# CLI 直跑（ChimeraSlayer 嵌合体检测；db 默认走随包 RESOURCES）
python main.py chimeraslayer --query-nast rep_set_aligned.fasta.NAST \
    --db-nast RESOURCES/rRNA16S.gold.NAST_ALIGNED.fasta \
    --db-fasta RESOURCES/rRNA16S.gold.fasta --exec-dir ./

# 未比对序列 -> NAST 比对
python main.py nastier --query-fasta seqs.fasta --num-top-hits 10

# Pintail 类异常检测
python main.py wigeon --query-nast rep_set_aligned.fasta.NAST

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

> **注意**：上游 Perl 脚本用 `FindBin` 定位自身目录（`/usr/lib/ChimeraSlayer` 或相对路径
> `../../ChimeraSlayer`），因此需在脚本所在目录或其父目录下运行；本驱动提供 `--exec-dir` 供显式
> 指定工作目录。`RESOURCES/` 随安装一同部署，`--db-nast` / `--db-fasta` 不传时使用套件内置参考库。

## 实战示例：QIIME 1.x 嵌合体检测

ChimeraSlayer 是 QIIME 1.x 默认的嵌合体检测方法之一（`identify_chimeric_seqs.py -m ChimeraSlayer`），
基于 BLAST 比对：先用查询序列两端搜索参考库找潜在亲本，再做「chimera-aware」NAST 重比对，最后用进化
框架判断是否比任何 in-silico 嵌合体更接近亲本。等价能力由 `native/main.py` 的 `chimeraslayer` 子命令提供。

```bash
# 1) 已有 PyNAST 比对结果 rep_set_aligned.fasta（QIIME 输出），ChimeraSlayer 直接消费
python main.py chimeraslayer \
    --query-nast rep_set_aligned.fasta \
    --db-nast RESOURCES/rRNA16S.gold.NAST_ALIGNED.fasta \
    --db-fasta RESOURCES/rRNA16S.gold.fasta \
    --exec-dir ./

# 2) 产物 <query_NAST>.CPS.CPC 为嵌合体判定；交给 QIIME filter_fasta.py 过滤
```

### 参数说明（ChimeraSlayer.pl）

| 参数                        | 说明                              |
| ------------------------- | ------------------------------- |
| `--query_NAST`            | 查询序列（NAST 比对格式 FASTA，必填）        |
| `--db_NAST` / `--db_FASTA` | 参考库 NAST / FASTA（默认随包 RESOURCES） |
| `-n`                      | 参与比较的 top N 参考序列（默认 15）          |
| `-R`                      | 最小 divergence ratio（默认 1.007）    |
| `-P`                      | 匹配序列最小百分比一致性（默认 90）             |
| `-M` / `-N` / `-Q` / `-T` | 亲本筛选评分参数（匹配/错配/覆盖度/遍历次数）        |
| `--windowSize` / `--windowStep` | ChimeraPhyloChecker 窗口大小/步长   |
| `--minBS` / `--num_BS_replicates` | 判定嵌合体的最小 bootstrap 支持/重复数 |
| `--printFinalAlignments`  | 输出 query 与候选亲本的比对                |

## 环境安装（自建兜底：官方渠道全无，源码编译）

> ⚠️ **官方渠道核实（2026-09）**：bioconda（`microbiomeutil` / `chimeraslayer`）**404**、
> quay.io/biocontainers **401**（仓库不存在）、depot.galaxyproject.org **404**、
> nf-core / snakemake-wrappers / homebrew 均无 → **无官方镜像 / conda 包**。
> 官方仅提供 **SourceForge 源码包**（无预编译二进制），故本模块走**自建兜底**路线
> （`native/Dockerfile` + `native/Apptainer.def`：debian:bookworm-slim + apt `--no-install-recommends`
> + 官方源码 `make` + 清理四连；Apptainer 含 `%test`）。

### 1. 宿主源码安装（首选）

```bash
# 官方源码归档（SourceForge；133,623,556 bytes；md5=11eaac4b0468c05297ba88ec27bd4b56）
wget https://sourceforge.net/projects/microbiomeutil/files/microbiomeutil-r20110519.tgz -P ~/software/
tar zxf ~/software/microbiomeutil-r20110519.tgz -C ~/software/
cd ~/software/microbiomeutil-r20110519
make      # 编译 NAST-iEr（C）；ChimeraSlayer/WigeoN 为 Perl 无需编译
# 把三个组件目录加入 PATH（上游 Perl 脚本用相对路径定位，建议保留目录结构）
for d in ChimeraSlayer NAST-iEr WigeoN; do
    echo "export PATH=$PATH:$HOME/software/microbiomeutil-r20110519/$d" >> ~/.bashrc
done
source ~/.bashrc
NAST-iEr      # 断言（无参数时会打印用法）
```

一键安装可直接运行 `native/install.sh`（下载 + md5 校验 + `make` + 部署到 `~/software/microbiomeutil-<ver>`
并写 PATH；无需 root；用法：`bash native/install.sh --help`）。

> **运行期外部依赖**（需自行确保在 PATH 中）：
> `megablast`（`apt install ncbi-blast+`）与 `cdbtools`（`cdbfasta`/`cdbyank`，`apt install cdbfasta`）。

### 2. Conda / brew

`microbiomeutil` 在 bioconda / conda-forge **无 conda 包**，homebrew-core 与 brewsci/bio 亦**无公式**
（2026-09 核实 404）→ 本模块**不提供 conda / brew 安装**，请走源码或自建容器。

### 3. Docker（自建镜像）

```bash
# context 必须是 modules/ 层（携带 base.py 与软件级 meta.yaml）
docker build -t bioskills/microbiomeutil:r20110519 -f modules/microbiomeutil/native/Dockerfile modules/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/microbiomeutil:r20110519 \
    chimeraslayer --query-nast /data/q.NAST
```

### 4. Apptainer / Singularity（自建镜像）

```bash
cd modules && apptainer build microbiomeutil-r20110519.sif microbiomeutil/native/Apptainer.def
apptainer run -B $PWD:/data -H /data microbiomeutil-r20110519.sif --list-commands
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（ChimeraSlayer/NAST-iEr/WigeoN 真实运行需重依赖参考库）
```

## 容器与 Conda 链接

* **官网**：<https://microbiomeutil.sourceforge.net/>

* **SourceForge**：<https://sourceforge.net/projects/microbiomeutil/files/>

* **官方镜像 / conda**：无（bioconda 404、quay 401、depot 404）→ 自建 `native/Dockerfile` 与 `native/Apptainer.def`

* **自建镜像**：`bioskills/microbiomeutil:r20110519`（debian:bookworm-slim + apt + 源码 make）

* 安装方式（本地）：`bash native/install.sh`（源码 make 到用户前缀）

## 版本

* microbiomeutil r20110519（SourceForge 源码包；md5=11eaac4b0468c05297ba88ec27bd4b56；上游未公布 sha256）

* 组件：ChimeraSlayer / NAST-iEr / WigeoN（另有 RESOURCES 内置 16S 参考库）

* 构建路线：**自建兜底**（官方渠道全无；debian:bookworm-slim + apt `--no-install-recommends` + 源码 `make`）

* 运行期依赖：ncbi-blast+（megablast）、cdbfasta（cdbtools）、perl

* nf-core / snakemake-wrappers：均无（2026-09 抓取 404）
