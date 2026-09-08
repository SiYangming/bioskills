# genetribe 软件模块

> 汇总说明：GeneTribe（chenym1/genetribe，Chen et al. 2020 *Molecular Plant* 13:1694-1708）是
> collinearity-incorporating homology inference（共线性整合同源推断）流水线，主程序形态为
> `genetribe <command> [options]`（python3 入口 + `bin/` 下 core/corenog/sameassembly/RBH/coreCBS/
> longestfasta 等内部脚本，上游 `./install.sh` 以符号链接生成 `bin/`）。
> 本模块仅实现 `native/`（core/corenog/sameassembly/RBH/CBS/longestcds 六子命令驱动）。
> 官方登记：**nf-core `modules/genetribe` 404、snakemake-wrappers `bio/genetribe` 404**（2026-09-07
> GitHub API 核实）→ 不建 nextflow/、snakemake/ 目录，官方渠道（bioconda → quay.io/biocontainers →
> depot.galaxyproject.org）亦无维护镜像 → `native/` 提供**自建** Dockerfile / Apptainer.def
> （apt 最小化，linux/amd64，仅录入不实构建）；社区/个人渠道 `quay.io/bioinfortools/genetribe:1.2.1`
> 与 YangmingSi conda 频道 `genetribe=1.2.1` 并列登记备用。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/genetribe/` **不存在**（2026-09-07 抓取
  <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/genetribe> 返回 404）。
  Nextflow 场景请容器化后走 native 子命令或社区镜像（quay.io/bioinfortools/genetribe）。

* **snakemake-wrappers**：`bio/genetribe` **不存在**（2026-09-07 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/genetribe> 返回 404）。
  Snakemake 场景请用 conda（bioconda blast/bedtools/jcvi + YangmingSi 频道 genetribe）或容器内
  PATH 直调 `genetribe`；确需本地规则时按 td2 式自建 `snakemake/` 并登记 meta。

## native 实现

# genetribe / native — 共线性同源推断驱动

GeneTribe 1.2.1 的本地自包含实现（`source_type: custom`、`type: native`）。驱动代理上游
`genetribe` 入口脚本，pipeline 类子命令运行于**当前工作目录**（要求前缀文件就地就位，见「实战示例」），
tool 类子命令结果打印 stdout：

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `core` | `genetribe core -l <A> -f <B> [-d dir] [-r] [-c] [-s sep] [-e E] [-n th] [-b BSR] [-m]` | 主流程（按染色体组计分；内部 BLASTP 四连 + MCScan + CBS） |
| `corenog` | `genetribe corenog -l <A> -f <B> [-d dir] [-c] [-s sep] [-e E] [-n th] [-b BSR]` | 不分染色体组的 core 变体 |
| `sameassembly` | `genetribe sameassembly -l <A> -f <B>` | 同一组装内（bedtools intersect 重叠打分）同源推断 |
| `RBH` | `genetribe RBH -a <in1> -b <in2>` | 双向最佳命中（两份 q\ts\tscore 表 → stdout） |
| `CBS` | `genetribe CBS -i <anchors> -a <bed1> -b <bed2> -o <out>` | MCScan anchors 共线性块得分（产出 `<out>.collinearity_info`） |
| `longestcds` | `genetribe longestcds -i <pep.fa> [-s sep]` | 每基因最长转录本蛋白 FASTA（→ stdout） |

## 用法

```bash
# CLI 直跑（core：在含 aet.bed/aet.fa/aet.chrlist 与 rice.bed/rice.fa/rice.chrlist 的目录）
python main.py core -l aet -f rice --threads 16
python main.py corenog -l aet -f rice -d blast_out/ --threads 16
python main.py sameassembly -l IWGSCv1p1 -f IWGSCv1
# tool 类（结果打 stdout，可重定向）
python main.py RBH -a A_B.score -b B_A.score > RBH.out
python main.py CBS -i aet.rice.lifted.anchors -a aet.bed -b rice.bed -o aet_rice
python main.py longestcds -i A.pep.all.fa -s . > A.longest.fa

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。上游 `-n`（blastp 线程）默认 36，本驱动仅在显式
给出 `--threads` 时注入 `-n`（缺省不传、沿用上游默认）；sameassembly/RBH/CBS/longestcds 上游无
`-n`，其 `--threads` 不注入（供调度器统一读取）。

## 实战示例：批量 BLAST 建索引/比对 + 共线性同源推断

> 官方 Quick Start / File Formats 教程（<https://chenym1.github.io/genetribe/tutorial/>）里的典型链路；
> 等价能力由 `native/main.py` 的 `core` / `corenog` / `sameassembly` 子命令提供（见上「用法」）。
> 容器内运行（任意 genetribe 镜像）必须加 `-u $(id -u):$(id -g)`，否则输出文件归 root 持有。

### 1. 输入准备（core 需要 `<前缀>.bed/.fa/.chrlist`；官方命令）

```bash
# 蛋白 FASTA：Ensembl/NCBI 下载 name.pep.all.fa.gz → gunzip 后重命名 name.fa
#   （genetribe 会先用自带 longestcds 逻辑抽每基因最长转录本；含 'gene:' 头或靠 -s 分隔符切基因 ID）
gunzip aet.pep.all.fa.gz && mv aet.pep.all.fa aet.fa
gunzip rice.pep.all.fa.gz && mv rice.pep.all.fa rice.fa

# 注释 bed：gff3 → 六列 gene bed（jcvi 或 gff2bed 两条官方路线任选）
python -m jcvi.formats.gff bed --type=gene --key=ID aet.gff3 -o aet.bed
sed -i 's/gene://g' aet.bed
# 或：gff2bed < aet.gff3 | gawk -vOFS="\t" '{if($8=="gene")print $1,$2,$3,$4,$5,$6}' | sed 's/gene://g' > aet.bed

# 染色体组信息（多倍体按亚基因组分组；同源染色体组串一行，如小麦 IWGSC：chrNA,chrNB,chrND）
cat aet.chrlist      # 例：chrNA,chrNB,chrND   （name.chrlist，染色体名须能被 bed 第 1 列包含）
cat rice.chrlist     # 例：N                 （水稻单倍型写作 N）

# （可选）-c 置信度分：两列 name.confidence（gene ID + HC/LC）
```

### 2. 批量 BLAST 建索引与比对（可选预计算；不预计算则 core 内部自动执行同一组命令）

```bash
# 上游 coredetectFileExist 缺省会自动做：longestfasta 抽长转录本 → makeblastdb →
# blastp -outfmt 6，产出 4 份 blast（交叉 2 + 自身 2）；也可手工批量预计算后放同一目录并加 -d：
makeblastdb -in aet_long.fa -parse_seqids -hash_index -dbtype prot -out aet_db/aet
makeblastdb -in rice_long.fa -parse_seqids -hash_index -dbtype prot -out rice_db/rice
blastp -query aet_long.fa -db rice_db/rice -evalue 1e-5 -num_threads 16 -outfmt 6 -out aet_rice.blast
blastp -query rice_long.fa -db aet_db/aet   -evalue 1e-5 -num_threads 16 -outfmt 6 -out rice_aet.blast
blastp -query aet_long.fa  -db aet_db/aet   -evalue 1e-5 -num_threads 16 -outfmt 6 -out aet_aet.blast
blastp -query rice_long.fa -db rice_db/rice -evalue 1e-5 -num_threads 16 -outfmt 6 -out rice_rice.blast
```

### 3. 跑共线性同源推断（输出存当前工作目录）

```bash
# core：主流程（示例同官方 Quick Start：cd test/ && ../genetribe core -l aet -f rice）
python main.py core -l aet -f rice -d . --threads 16

# 同组装：IWGSCv1 与 IWGSCv1p1 两个版本注释重叠推断
python main.py sameassembly -l IWGSCv1p1 -f IWGSCv1

ls
aet_rice.one2many rice_aet.one2many aet_rice.one2one rice_aet.one2one
aet_rice.RBH aet_rice.SBH rice_aet.SBH aet_rice.singleton rice_aet.singleton
aet_rice.block_pos rice_aet.block_pos aet_rice.collinearity_info ...
```

### 4. 参数说明（core/corenog，对齐官方）

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `-l <前缀>` | 物种 1 文件前缀（.bed/.fa/.chrlist/.confidence） | 必填 |
| `-f <前缀>` | 物种 2 文件前缀（同上） | 必填 |
| `-d <目录>` | 预计算 BLAST 文件目录（`A_B.blast` 等四份；有则跳过 BLAST 步） | `./` |
| `-r` | 关闭染色体组计分（core） | 计分开 |
| `-c` | 按注释置信度加分（需 `.confidence`） | 关 |
| `-s <串>` | transcript ID 切 gene ID 分隔符 | `.` |
| `-e <e值>` | BLASTP E-value | 1e-5 |
| `-n <int>` | BLASTP 线程 | 36 |
| `-b <float>` | BSR 过滤阈值 0-100 | 75 |
| `-m` | 关闭共线性加权（core） | 加权开 |
| `--threads` / `--tmpdir` | main.py 注入（--threads 映射 `-n`） | — |

## 环境安装（无官方镜像，自建 apt 最小化配方）

官方容器渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）均无 GeneTribe
（2026-09-07 核实），故 `native/` 提供自建配方 `Dockerfile` + `Apptainer.def`（debian:bookworm-slim +
apt `--no-install-recommends` + 清理四连；blast/bedtools 走 apt，jcvi 用 python3-venv + pip，**不引入
miniconda**）。宿主机直跑 `main.py` 时按下面 1/4 安装 genetribe 与依赖。

### 1. Conda（包管理器安装）

GeneTribe **不在 bioconda**（404）；个人频道 YangmingSi 有 `genetribe=1.2.1`（noarch py_0，
2026-07-13 上传）；运行依赖 blast / bedtools / jcvi 均在 bioconda（jcvi 当前 1.6.7）。
brew 两源均无（homebrew-core `genetribe.json` 404、brewsci/bio `genetribe.rb` 404，2026-09-07
核实），故不提供 brew 块。

```bash
# conda（等价于 native/environment.yml；依赖与包均走官方/个人频道）
mamba create -n genetribe -c conda-forge -c bioconda -c yangmingsi \
    genetribe=1.2.1 blast bedtools jcvi
conda activate genetribe
genetribe -h     # 冒烟：输出含 "Program: GeneTribe" 与 "Version: 1.2.1"
```

> 一键安装直接 `bash native/install.sh`（auto：有 conda/mamba 走上面 conda 路线；无 conda 走 git
> clone tag v1.2.1 + 上游 ./install.sh 源码路线并写 PATH；`bash native/install.sh --help` 看参数）。

### 2. Docker（自建镜像；社区镜像备选）

```bash
# 自建（官方渠道无镜像 → 本地配方构建；amd64）
docker build -t genetribe:1.2.1 modules/genetribe/native/

# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data genetribe:1.2.1 \
    core -l aet -f rice --threads 16
```

社区镜像备选（非官方维护、2026-04-17 quay API 核实仅 1.2.1/latest 两 tag 同一 digest）：
`docker pull quay.io/bioinfortools/genetribe:1.2.1`，运行同上。

### 3. Apptainer / Singularity

无 depot.galaxyproject.org 预构建 sif（官方渠道无 GeneTribe），**无法 `apptainer pull` 直拉**，本地构建：

```bash
apptainer build genetribe-1.2.1.sif modules/genetribe/native/Apptainer.def
apptainer run -B $PWD:/data -H /data genetribe-1.2.1.sif \
    core -l aet -f rice --threads 16
```

### 4. 源码安装（官方路线；无预编译资产）

* 上游仅源码分发（python3 + bash），官方文档安装法即「git clone + ./install.sh + PATH」：
  <https://chenym1.github.io/genetribe/tutorial/installation.html>
* 官方文档依赖推荐：BLAST v2.9.0（`conda install blast -c bioconda`）/ MCscan-jcvi v1.0.6
  （`pip install jcvi`）/ BEDTools v2.29.2（`conda install bedtools -c bioconda`）。

```bash
# 前提：blastp / makeblastdb、bedtools、python3 -m jcvi.compara 已在 PATH（上游 install.sh 自检）
mkdir -p ~/software && cd ~/software
git clone --depth 1 --branch v1.2.1 https://github.com/chenym1/genetribe.git genetribe-1.2.1
cd genetribe-1.2.1 && ./install.sh     # 生成 bin/（符号链接）并提示写 PATH
export PATH="$HOME/software/genetribe-1.2.1:$PATH"
genetribe -h   # 冒烟：Program: GeneTribe / Version: 1.2.1
```

> 💡 一键脚本走 `native/install.sh`（源码路线完成 clone tag、commit 锚点核对
> `5aa4fc5d7a2e00129000bd282efc1161b57d023c`、./install.sh、PATH + 版本断言）。
> 上游不发布源码包 sha256 摘要（无官方 digest），故不做 sha256 校验（未核实项，以 tag commit 锚点替代）。

## 历史留存（旧 miniconda 配方的国内镜像要点）

本模块早期含两份旧式 `Dockerfile_cn` / `Dockerfile_en`（continuumio/miniconda3 重型配方：conda 建
环境 + pip jcvi + git clone genetribe 跑 ./install.sh），已于标准化时**删除并并入本 README 与新
Dockerfile/Apptainer.def**。国内网络关键点保留如下：

* **清华 conda 源**：旧 cn 配方用 Tsinghua TUNA mirror 加速 conda（
  `channels: - https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge ...`）。新配方走
  apt（debian 源）不再依赖 conda 镜像，故不再需要。
* **kkgithub clone 备用**：GitHub 直连不畅时可用镜像站 `git clone https://kkgithub.com/chenym1/genetribe.git`
  （仅备用加速，版本锚点仍以官方 tag v1.2.1 + commit 为准）。
* **blast=2.9.0 冲突教训**：旧配方曾在 conda 环境强锁 blast=2.9.0（官方文档推荐版本），与其他依赖
  C 库冲突并引发 **OOM**；教训 = 不要把 blast 强锁在 2.9.0。新配方不再默认 miniconda，改走 apt
  ncbi-blast+=2.12.0+ds-3（>=2.9 满足上游）；确需 conda 时也**不要**再显式 `blast=2.9.0`。

## 测试

```bash
bash modules/genetribe/native/test/run_test.sh   # 六子命令 argv 构造断言（genetribe 不在 PATH 时同样通过）
```

## 版本

* GeneTribe **1.2.1**：GitHub 最新 release/tag（2022-08-15 发布，commit
  `5aa4fc5d7a2e00129000bd282efc1161b57d023c`，GitHub API 核实）；入口 `genetribe -h` 打印
  "Version: 1.2.1"；各 pipeline 脚本 logo 打印 v1.2.1。
* 构建路线：无官方容器 → **自建 apt 最小化**（native/Dockerfile + Apptainer.def，linux/amd64，仅录入
  不实构建）；社区镜像 `quay.io/bioinfortools/genetribe:1.2.1` 与 YangmingSi conda 频道
  `genetribe=1.2.1`（noarch）为并列备用渠道（差异逐条记录于软件级 `meta.yaml` `software_versions`）。
* 运行依赖：BLAST（blastp/makeblastdb）、BEDTools、jcvi（MCscan）。上游官方文档推荐 blast v2.9.0 /
  bedtools v2.29.2 / jcvi v1.0.6（2020 年实测组合）；自建容器用 apt ncbi-blast+=2.12.0+ds-3 /
  bedtools=2.30.0+dfsg-3（bookworm 版本，>= 官方最低要求），jcvi 走 pip（PyPI 当前 1.6.7）。

***

## 容器与 Conda 链接

* **官方**：GitHub <https://github.com/chenym1/genetribe>；文档站
  <https://chenym1.github.io/genetribe/>（Source Code / Tutorial / Release Log / Q&A）；引用论文：
  Chen et al. (2020) *Molecular Plant* 13:1694–1708。

* **bioconda**：无 genetribe 包（<https://anaconda.org/bioconda/genetribe> 404）；依赖 blast /
  bedtools / jcvi 均有（jcvi 当前 1.6.7）。

* **quay.io/biocontainers / depot.galaxyproject.org**：无 genetribe（2026-09-07 核实）

* **nf-core / snakemake-wrappers**：`modules/nf-core/genetribe` 与 `bio/genetribe` 均 404（2026-09-07）

* **社区镜像（补充登记）**：`quay.io/bioinfortools/genetribe:1.2.1`（tag 仅 1.2.1/latest）

* **个人 conda 频道（补充登记）**：<https://anaconda.org/channels/YangmingSi/packages/genetribe/overview>
  （`conda install -c yangmingsi genetribe=1.2.1`；noarch py_0，2026-07-13 上传）

* **自建容器**：`modules/genetribe/native/Dockerfile`（`docker build -t genetribe:1.2.1
  modules/genetribe/native/`）、`modules/genetribe/native/Apptainer.def`（`apptainer build
  genetribe-1.2.1.sif modules/genetribe/native/Apptainer.def`）
