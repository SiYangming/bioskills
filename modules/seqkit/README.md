# seqkit 软件模块

> 汇总说明：seqkit（[shenwei356/seqkit](https://github.com/shenwei356/seqkit)，Go 编写）是跨平台、
> 超快的 FASTA/Q 处理工具集，提供 stats / fx2tab / grep / sample / rmdup / sort / split / split2 /
> translate / seq / fq2fa / fa2fq / head / sliding / concat / replace / common / duplicate / sana /
> restart 等数十个原子子命令，覆盖序列统计、格式转换、检索、抽样、去重、排序、分割、翻译等日常操作；
> 原生支持 gzip/xz/zstd/bzip2/lz4 压缩与 stdin/stdout 管道。官网
> <https://bioinf.shenwei.me/seqkit/>，usage 文档 <https://bioinf.shenwei.me/seqkit/usage/>；
> 引用论文：Wei Shen et al. **iMeta 2024**（SeqKit2，10.1002/imt2.191，旧论文 PLoS ONE 2016
> 10.1371/journal.pone.0163962）。
> 本模块仅实现 `native/`（9 个高频子命令驱动）。**官方登记**：nf-core `modules/nf-core/seqkit`
> 存在（17 个子模块）与 snakemake-wrappers `bio/seqkit` 存在（扁平 wrapper）→ **不建
> nextflow/、snakemake/ 目录**；官方渠道（bioconda → quay.io/biocontainers →
> depot.galaxyproject.org）均有维护镜像 → `native/` **不维护 Dockerfile/Apptainer.def**
> （官方镜像优先；2026-09-08 核实）。

***

## 官方登记（不建目录，仅说明 + 引用）

### nf-core（Nextflow）

`modules/nf-core/seqkit/` **存在**，17 个子模块（2026-09-08 GitHub API 抓取，与官方目录严格一致）：

`concat` · `fq2fa` · `fx2tab` · `grep` · `head` · `pair` · `replace` · `rmdup` · `sample` · `sana` ·
`seq` · `sliding` · `sort` · `split2` · `stats` · `tab2fx` · `translate`

> ⚠️ 官方目录里分割子模块是 **`split2`**（没有 `seqkit/split`）；官方 pin 当前
> `bioconda::seqkit=2.13.0`（以 `modules/nf-core/seqkit/stats/environment.yml` 为锚点）。
> 本目录仅说明 + Schema；执行前请把官方子模块安装到项目自身目录，不要直接引用仓库示例 main.nf：

```bash
nf modules install nf-core seqkit/stats seqkit/fx2tab seqkit/grep seqkit/split2   # 按需选子模块
```

### snakemake-wrappers（Snakemake）

`bio/seqkit` **存在**，但为**扁平 wrapper**（无子目录）：`wrapper.py` + `environment.yaml` +
`meta.yaml` + `test/`（2026-09-08 GitHub API 抓取）。运行时靠 Snakemake 解析 `wrapper:` 句柄分派
seqkit 子命令（params 传 subcommand 等）：

```yaml
# 当前 wrapper_tag v9.17.1；environment.yaml pin：seqkit =2.13.0 + htslib =1.24
# + snakemake-wrapper-utils =0.9.0（2026-09-08 抓取 raw 核实）
wrapper: "v9.17.1/bio/seqkit"
```

可直接粘贴的调用（扁平 wrapper 以 `params.command` 指定子命令、`extra` 追加 flags，
`--out-file` 写第一个 output；seqkit 官方 wrapper.py v9.17.1 契约）：

```python
rule seqkit_stats:                 # 序列统计（含 -a 全字段 / -T 制表）
    input:  "reads/{sample}.fastq.gz"
    output: "qc/{sample}.stats.tsv"
    params:
        command="stats"
        extra="-a -T"
    threads: 4
    wrapper: "v9.17.1/bio/seqkit"

rule seqkit_rmdup:                 # 去重（wrapper 自动注入 --threads）
    input:  "reads/{sample}.fastq.gz"
    output: "dedup/{sample}.dedup.fq.gz"
    params:
        command="rmdup"
    threads: 4
    wrapper: "v9.17.1/bio/seqkit"
```

> 官方本模块无本地 snakemake 修订 → Snakemake 场景直接复用官方 wrapper（缺失时才考虑自建）。

> ⚠️ 不要把本地示例 wrapper 当 wrapper_path；句柄 `v9.17.1/bio/seqkit` 由运行时解析。
> Snakemake 场景直接复用官方 wrapper，无需本地规则（缺失时才考虑自建）。

***

## native 实现

# seqkit / native — FASTA/Q 工具集高频子命令驱动

seqkit 2.13.0 的本地自包含实现（`source_type: custom`、`type: native`）。上游是「多原子子命令」
形态（`seqkit <sub> [flags] <files>`），本驱动收敛高频子集为 9 个技能子命令，白名单参数对齐
官方 usage 页 v2.13.0 flags（不臆造 flag；白名单外的参数经 `--extra-args` 原样透传）：

| 子命令 | seqkit 命令形态 | 作用 |
| --- | --- | --- |
| `stats` | `seqkit stats [-a] [-T] [-b] [-e] [-S] [-N 50,90] <files...>` | 序列文件统计（num_seqs / sum_len / GC / N50 等） |
| `fx2tab` | `seqkit fx2tab [-n] [-l] [-g] [-i] [-H] <file>` | FASTA/Q → 制表；反向还原用 `tab2fx`（表格 → FASTA/Q，见实战示例 §2；`tab2fx` 未内置驱动，经 `--extra-args` 透传 `seqkit tab2fx`） |
| `grep` | `seqkit grep [-p <pat> \| -f <file>] [-v] [-n \| -s] [-i] [-r] <file>` | 按 ID/名称/序列检索 |
| `sample` | `seqkit sample [-n N \| -p 0.1] [-s seed] [-r] <file>` | 随机抽样（默认确定性、种子 11） |
| `rmdup` | `seqkit rmdup [-s \| -n] [-i] [-P] [-d <dup>] <file>` | 去重（默认按 ID；`-s` 按序列、`-n` 按全名） |
| `sort` | `seqkit sort [-n \| -l \| -s] [-r] [-N] [-i] <file>` | 序列排序（名称/长度/序列） |
| `split` | `seqkit split [-s N \| -p N \| -i] [-O <dir>] [-f] <file>` | 分割（按条数/份数/ID） |
| `translate` | `seqkit translate [-f frame] [-T table] [--trim] [-M] [-x] <file>` | DNA → 蛋白翻译 |
| `fq2fa` | `seqkit fq2fa <file>` | FASTQ → FASTA（纯转换） |

* 每个子命令自动注入 `-j <N>`（seqkit 线程；缺省取 meta `optimization`：stats/sort/split 8、其余 4）
  与 `-o/--out-file`（缺省 stdout，后缀 `.gz` 自动 gzip）。
* `--tmpdir` 覆盖技能层临时目录并透传 `TMPDIR` 环境变量（`sort`/`split` 两遍模式等写临时文件时生效）。
* 输入可多文件或读 stdin（`files` 省略时）。

### 上游更多常用子命令（参考；未内置驱动时直调 `seqkit` 或经 `--extra-args` 透传）

下表为 seqkit 上游常用子命令的补充参考（完整 flags 见官方 usage：
<https://bioinf.shenwei.me/seqkit/usage/>）：

| 子命令 | 作用 |
| --- | --- |
| `common` / `duplicate` | 找共同序列 / 重复序列 |
| `concat` | 序列拼接 |
| `replace` | 序列替换 |
| `translate` / `trans` | DNA 翻译为蛋白质（`trans` 为别名；驱动内置 `translate`） |
| `restart` | 从起始密码子开始翻译 |
| `sra` | SRA 数据统计 |
| `fq` | FASTQ 质量值操作 |
| `fa` | FASTA 相关操作 |

## 用法

```bash
# CLI 直跑（等价官方命令；main.py 只构造/执行 seqkit <sub> …）
python main.py stats -a -T reads_1.fq.gz reads_2.fq.gz -o fastq_stats.tsv
python main.py fx2tab -n -l -g -i -H hairpin.fa.gz
python main.py grep -f id_list.txt input.fasta -v -o filtered.fasta
python main.py sample -n 1000 -s 42 input.fastq.gz -o subsample.fastq
python main.py rmdup -s input.fasta -o unique.fasta
python main.py sort -l -r input.fasta -o sorted_by_len.fasta
python main.py split -s 1000 input.fasta --out-dir split_out
python main.py translate input.cds.fa -o proteins.fa --threads 8
python main.py fq2fa reads_1.fq.gz -o reads_1.fa.gz

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands

# 只打印构造的命令不执行（调试）
python main.py stats -a -T x.fq.gz --dry-run
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（放在子命令后）。

## 实战示例：批量统计 + 常用序列操作

> 官方文档（<https://bioinf.shenwei.me/seqkit/usage/>）典型链路；等价能力由
> `native/main.py` 的 `stats` / `fx2tab` / `grep` / `sample` / `rmdup` / `sort` / `split` /
> `translate` / `fq2fa` 子命令提供（见上「用法」）。容器内运行必须加 `-u $(id -u):$(id -g)`，
> 否则输出文件归 root 持有。

### 1. 批量序列统计（stats，全量字段 + 制表）

```bash
# 单个/多个 fastq.gz（支持通配符）
seqkit stats input.fastq.gz
seqkit stats *.fq.gz

# 全量统计 + Tab 制表（便于导入 R/Excel；N50 在 -a 内，N90 等其它 N50-like 需显式 -N 90）
seqkit stats -a -T *.fq.gz > fastq_stats.tsv
seqkit stats -a -T -N 50,90 *.fq.gz > fastq_stats_withN90.tsv

# 批量统计目录下所有 fastq.gz（find + xargs）
find /data1/users/siyangming/eccDNA -type f \
    \( -name "*.fq.gz" -o -name "*.fastq.gz" \) \
    | xargs seqkit stats -a -T > fastq_stats.tsv
```

**stats 参数说明**：

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `-a` / `--all` | 全量统计：长度四分位 Q1/Q2/Q3、sum_gap、N50/N50_num(L50)、Q20(%)、Q30(%)、AvgQual、GC(%)、sum_n | 关 |
| `-T` / `--tabular` | Tab 分隔表格输出（机器友好） | 关（人类可读对齐表） |
| `-b` / `--basename` | 仅显示文件名不显示路径 | 关 |
| `-N` / `--N` | 追加其它 N50-like 列（如 `-N 90` 得 N90；v2.5.0+） | 无 |
| `-e` / `--skip-err` | 跳过错误文件仅告警 | 关 |
| `-S` / `--skip-file-check` | 跳过输入文件预检查 | 关 |
| `-j` / `--threads` | 线程数（stats 大量小文件时调大并行计数） | 4 |

> `-a` 全量输出字段：file / format / type / num_seqs / sum_len / min_len / avg_len / max_len /
> Q1 / Q2 / Q3 / sum_gap / N50 / N50_num / Q20(%) / Q30(%) / AvgQual / GC(%) / sum_n
> （默认列仅为 file/format/type/num_seqs/sum_len/min_len/avg_len/max_len）。

### 2. 格式转换（fq2fa / fx2tab⇄tab2fx）

```bash
# FASTQ 转 FASTA
seqkit fq2fa input.fastq.gz -o output.fasta

# FASTA 与 FASTQ 按 ID 互查（v2.2.0+ fa2fq：按 FASTA 文件 ID 从 FASTQ 检索对应记录）
seqkit fa2fq -f input.fasta reads.fastq.gz -o matched.fastq.gz

# FASTA/Q 与表格互转（管道）
seqkit fx2tab hairpin.fa.gz | head -n 2
seqkit fx2tab -n -l -g -i -H hairpin.fa.gz      # 仅名称 + 长度/GC 列 + 表头
zcat reads_1.fq.gz | seqkit fx2tab | seqkit tab2fx    # fx2tab⇄tab2fx 往返
```

> ⚠️ 注意：v2.2.0 起官方 **`fa2fq` 语义 = 按 FASTA 文件 ID 从 FASTQ 中检索对应记录**
> （`seqkit fa2fq -f input.fasta reads.fastq`），**不是**「FASTA 转带固定质量的 FASTQ」；
> 旧文档（v2.3.1 时代）的 fa2fq 用法已过时，见「历史留存」。

### 3. 按序列名检索 / 抽取（grep）

```bash
# 按 ID 列表提取 / 单模式检索 / 反向排除
seqkit grep -f id_list.txt input.fasta > output.fasta
seqkit grep -p "gene001" input.fasta > output.fasta
seqkit grep -f id_list.txt -v input.fasta > output.fasta
# 默认匹配 ID 整词；匹配完整 header 用 -n/--by-name；正则部分匹配用 -r/--use-regexp；按序列用 -s
```

### 4. 随机抽样（sample，双端同种子）

```bash
seqkit sample -n 1000 input.fastq.gz > subsample.fastq     # 按条数（大文件载入内存，慎用）
seqkit sample -p 0.1 input.fastq.gz > subsample.fastq       # 按比例（推荐大文件）
seqkit sample -n 1000 -s 42 input.fastq.gz > subsample.fastq  # 固定种子可复现（默认 11）
# 双端数据：两个文件用同一 -s 种子抽样保持 read 配对
seqkit sample -p 0.1 -s 11 R1.fq.gz > sub_R1.fq.gz
seqkit sample -p 0.1 -s 11 R2.fq.gz > sub_R2.fq.gz
```

### 5. 去重（rmdup）

```bash
seqkit rmdup input.fasta > unique.fasta      # 默认按 ID 去重（只保留首条）
seqkit rmdup -s input.fasta > unique.fasta   # 按序列内容去重（正负链都算；-P 只看正链）
seqkit rmdup -n input.fasta > unique.fasta   # 按完整名称去重
seqkit rmdup -s -d duplicated.fa -D dup.detail.txt input.fasta   # 同时导出重复序列/明细
```

### 6. 排序（sort）

```bash
seqkit sort -n input.fasta > sorted.fasta         # 按名称（-N 自然序：1,2,3,10 而非 1,10,2,3）
seqkit sort -l -r input.fasta > sorted_by_len.fasta  # 按长度降序
seqkit sort -s input.fasta > sorted_by_seq.fasta  # 按序列字典序
```

### 7. 分割（split）

```bash
seqkit split -s 1000 input.fasta          # 每文件 ≤1000 条 → 默认输出目录 input.fasta.split/
seqkit split -p 10 input.fasta            # 均分成 10 份
seqkit split -i input.fasta               # 按序列 ID 分割（如按染色体，默认输出目录 $infile.split）
seqkit split -s 1000 -O split_out input.fasta    # 指定输出目录
# 官方推荐：仅按条数/份数分割（含双端 FASTQ）用更快省内存的 seqkit split2（本驱动白名单未含，可透传或直调）
```

### 8. 翻译（translate）

```bash
seqkit translate input.cds.fa -o proteins.fa            # 默认框 1 + 标准密码子表
seqkit translate input.fa -f 6 --trim -o all_orfs.fa    # 六框翻译 + 去右端 X/*
seqkit translate input.fa -f -1 -T 2 -o mito.fa         # 反向框 1 + 脊椎动物线粒体码（表 2）
```

### 9. 参数表（v2.13.0 官方 flags 摘录，main.py 白名单与之一致）

| 子命令 | 白名单参数（→ seqkit flag） |
| --- | --- |
| stats | `-a/--all` · `-T/--tabular` · `-b/--basename` · `-e/--skip-err` · `-S/--skip-file-check` · `-N/--N`（如 `50,90`） |
| fx2tab | `-n/--name` · `-l/--length` · `-g/--gc` · `-i/--only-id` · `-H/--header-line` |
| grep | `-p/--pattern`（可多次）· `-f/--pattern-file` · `-v/--invert-match` · `-n/--by-name` · `-s/--by-seq` · `-i/--ignore-case` · `-P/--only-positive-strand` · `-r/--use-regexp` |
| sample | `-n/--number` · `-p/--proportion` · `-s/--rand-seed`（默认 11）· `-r/--non-deterministic` |
| rmdup | `-s/--by-seq` · `-n/--by-name` · `-i/--ignore-case` · `-P/--only-positive-strand` · `-d/--dup-seqs-file` |
| sort | `-n/--by-name` · `-l/--by-length` · `-s/--by-seq` · `-r/--reverse` · `-N/--natural-order` · `-i/--ignore-case` |
| split | `-s/--by-size` · `-p/--by-part` · `-i/--by-id` · `-O/--out-dir`（默认 `$infile.split`）· `-f/--force` |
| translate | `-f/--frame` · `-T/--transl-table`（默认 1）· `--trim` · `-M/--init-codon-as-M` · `-x/--allow-unknown-codon` · `-F/--append-frame` · `--clean` · `-m/--min-len` |
| fq2fa | （无子命令特有参数；`-o/--out-file` 与 `-j/--threads` 通用） |

> 全量 flag 以 `seqkit <sub> -h` 为准；本驱动不臆造，白名单外参数经 `--extra-args` 透传
> （如 `--extra-args "-w 80"`）。

## 性能特点与同类工具对比（参考）

### 性能特点

1. **速度快**：用 Go 语言编写，原生支持并发，处理大文件速度显著快于 Perl/Python 脚本
2. **内存效率高**：流式处理，无需将整个文件读入内存
3. **跨平台**：支持 Linux、macOS、Windows，提供预编译二进制包
4. **功能丰富**：数十个子命令，覆盖日常序列处理的大部分需求
5. **格式支持好**：支持 gzip 压缩的 FASTA/Q 文件，支持标准输入输出，便于管道操作

### 与其他工具的对比

| 特性 | SeqKit | FASTX-Toolkit | seqtk |
| --- | --- | --- | --- |
| 开发语言 | Go | C | C |
| 速度 | 快 | 快 | 快 |
| 功能丰富度 | 高 | 中 | 低 |
| 跨平台支持 | 好 | 一般 | 一般 |
| 文档完善度 | 高 | 中 | 低 |

> 💡 **使用建议**：SeqKit 功能全面、速度快、易用性好，推荐作为日常序列处理的首选工具。
> 对于简单的格式转换和截取操作，seqtk 也很轻量高效。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org 2026-09-08 核实），直接拉取
官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n seqkit-native -c conda-forge -c bioconda seqkit=2.13.0   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate seqkit-native
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# 同名核对：homebrew-core seqkit desc="Cross-platform and ultrafast toolkit for FASTA/Q file
# manipulation in Golang"，确为本软件本体（2026-09-08 formulae.brew.sh API 核实）
# brew 当前 2.13.0，与 meta 登记 2.13.0 一致
brew install seqkit
seqkit version   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `seqkit`
> （2.13.0），无 conda 时自动下载官方 GitHub release 二进制到 `~/software/seqkit-2.13.0` 并写 PATH；
> `bash native/install.sh --help` 看全部参数）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/seqkit:2.13.0--he881be0_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/seqkit:2.13.0--he881be0_0 stats -a -T reads_1.fq.gz
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull seqkit.sif docker://depot.galaxyproject.org/singularity/seqkit:2.13.0--he881be0_0
apptainer run -B $PWD:/data -H /data seqkit.sif stats -a -T /data/reads_1.fq.gz
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

* **官网**：<https://bioinf.shenwei.me/seqkit/>
* **GitHub release**：<https://github.com/shenwei356/seqkit/releases>（当前最新 **v2.13.0**，2026-02-27）
* **下载页**：<https://bioinf.shenwei.me/seqkit/download/>

```bash
# Linux x86_64（官方命名 seqkit_linux_amd64.tar.gz；macOS x86_64 用 seqkit_darwin_amd64.tar.gz）
wget https://github.com/shenwei356/seqkit/releases/download/v2.13.0/seqkit_linux_amd64.tar.gz -P ~/software/

# 解压安装到用户前缀并加 PATH（无需 root；不写 /opt/biosoft 教学全局路径）
mkdir -p ~/software/seqkit-2.13.0
tar zxf ~/software/seqkit_linux_amd64.tar.gz -C ~/software/seqkit-2.13.0 --strip-components=1
echo 'export PATH=$PATH:~/software/seqkit-2.13.0' >> ~/.bashrc
source ~/.bashrc

# 验证安装（输出形如 "seqkit v2.13.0"）
seqkit version
```

> 💡 release 包内含 `seqkit` 可执行文件与 LICENSE 等；官方资产另附 `*.md5.txt` 摘要（无
> sha256sum 文件，sha256 可查 GitHub release API digest）。一键脚本走 `native/install.sh`
> （binary 路线内嵌官方 sha256 校验 + `seqkit version` 断言；`--version` 覆盖非默认版本时跳过
> 内嵌校验并提示）。

## 测试

```bash
bash modules/seqkit/native/test/run_test.sh   # seqkit 不在 PATH 时退化为 argv 构造断言，同样通过
```

## 版本

* seqkit **2.13.0**：GitHub latest release v2.13.0（2026-02-27，「10-year-old birthday version」；
  bioconda latest_version=2.13.0；homebrew-core 2.13.0；nf-core 与 snakemake-wrappers 均 pin
  2.13.0；quay tag `2.13.0--he881be0_0` —— 五源对齐）。CHANGELOG 顶部已列 v2.14.0 占位（2026-xx-xx
  未发布），以 releases/latest=v2.13.0 为准（2026-09-08 核实）。
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/seqkit / depot.galaxyproject.org；
  local 不再自建容器）。
* 官方二进制（仅 linux-x64 / macos-x64 / linux-arm64 等由官方 release 分发）：
  `seqkit_linux_amd64.tar.gz` sha256=`7d686de448464fada1b1988e2e07d693bec68768312da62846bc0e2b502bfc46`、
  `seqkit_darwin_amd64.tar.gz` sha256=`7db4264a1a49d9ad7cc6d02f572c8573469d6f91881da2a2420b7f5426d63951`
  （来源：GitHub release API digest，2026-09-08 抓取；勿与 `*.md5.txt` 混淆）。

## 历史留存（旧文档 v2.3.1 方法与过时点摘要）

本模块录入的用户文档「## 2. SeqKit 安装与使用」基于 **v2.3.1**（2021 前后），部分内容已过时，
归档摘要如下（正式用法以上文各节为准）：

* **旧安装法（已弃用，仅归档）**：`wget .../download/v2.3.1/seqkit_linux_amd64.tar.gz -P ~/software/`
  → `tar zxf ... -C /opt/biosoft/` → `export PATH=/opt/biosoft/seqkit_linux_amd64:$PATH`。
  ⚠️ 教学/服务器全局路径 `/opt/biosoft/` 已不再作为推荐安装位置（新装一律用户前缀
  `~/software/seqkit-<ver>` 免 root）；版本 v2.3.1 过时（当前 2.13.0），URL 模板更新为
  `.../download/v2.13.0/seqkit_linux_amd64.tar.gz`。
* **旧 conda / brew / go 安装**：conda `-c bioconda seqkit` 与 `brew install seqkit` 两法仍有效
  （brew 走 homebrew-core，**无需**再 `brew tap brewsci/bio`——旧文档要求 tap brewsci/bio 是
  早期做法，brewsci/homebrew-bio `Formula/seqkit.rb` 现 404，2026-09-08 核实）；`go install
  github.com/shenwei356/seqkit/v2/seqkit@latest` 源码路线官方仍支持（需 Go 环境）。
* **旧 stats 语义差异**：v2.3.1 文档字段表把 N90 视为 `-a` 内置列 → v2.5.0 起 N50-like 扩展列
  改由 `-N/--N` 显式追加（`seqkit stats -a -T -N 90` 才出 N90）；`stats` 默认线程旧文档写 2，
  现官方默认 4。
* **旧 fa2fq 语义差异**：v2.3.1 文档「`fa2fq input.fasta` 把 FASTA 转成固定质量 FASTQ」与 v2.x
  实际行为不符——v2.2.0 起官方 `fa2fq` =「按 FASTA 文件 ID 从 FASTQ 检索对应记录」，不要再按旧
  文档把 FASTA 当唯一输入来造质量值。
* **旧 rmdup 语义差异**：v2.3.1 文档「默认按序列内容去重」与 v2.13 不符——v2.13 `rmdup` 默认
  去重键为 ID，按序列需显式 `-s/--by-seq`（按全名 `-n/--by-name`）。
* 子命令与 `-a/-T/-j` 等高频参数跨版本稳定（v2.3.1 → v2.13.0 基本兼容），新功能（sample2 /
  split2 / lz4 / -r 真随机 / -P 输出前缀等）以上文官方 usage 页为准。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# seqkit native Conda 环境配方
# 离线兜底：可另存为 seqkit-native.yml 后 mamba env create -f seqkit-native.yml；在线推荐上方 mamba create 直装命令
# 说明：seqkit 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      官方镜像（quay.io/biocontainers/seqkit）即由 bioconda 本环境构建；本地不再自建 Dockerfile/Apptainer.def（见上「环境安装」）。
name: seqkit-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - seqkit=2.13.0
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

* **官方**：官网 <https://bioinf.shenwei.me/seqkit/>；usage <https://bioinf.shenwei.me/seqkit/usage/>；
  GitHub <https://github.com/shenwei356/seqkit>；引用 iMeta 2024（10.1002/imt2.191）。

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/seqkit/overview>
  （latest_version=2.13.0，2026-09-08）

* **Docker**：`docker pull quay.io/biocontainers/seqkit:2.13.0--he881be0_0`

* **Singularity**（depot 预构建 sif）：
  <https://depot.galaxyproject.org/singularity/seqkit%3A2.13.0--he881be0_0>
  （直拉命令见上「### 3. Apptainer」）

* **Homebrew**：homebrew-core 公式（stable 2.13.0，desc 已核对为本软件）；brewsci/bio 无
  `seqkit.rb`（404，2026-09-08）→ 无需 tap，`brew install seqkit` 即可

* **nf-core**：<https://github.com/nf-core/modules/tree/master/modules/nf-core/seqkit>
  （17 个子模块，见上「官方登记」）

* **snakemake-wrappers**：<https://github.com/snakemake/snakemake-wrappers/tree/master/bio/seqkit>
  （扁平 wrapper，tag v9.17.1）

* 安装方式（本地）：`mamba create -n seqkit -c conda-forge -c bioconda seqkit=2.13.0` 或
  `bash modules/seqkit/native/install.sh`
