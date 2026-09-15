# table2asn 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；容器与 conda 环境信息记录于文末「容器与 Conda 链接」。
>
> ⚠️ **现役后继提示**：table2asn 是 NCBI 现役的 GenBank 提交文件生成工具，**取代**已停用（Obsolete）的 **tbl2asn**。
> NCBI 官方文档原文：**"table2asn is the replacement of the older now-obsolete tool tbl2asn"**（<https://www.ncbi.nlm.nih.gov/genbank/table2asn/>，2026-09-15 核实；旧的 `/genbank/tbl2asn2/` 已 301 跳转至此页）。
> NCBI 已停用 tbl2asn 并下架其官方二进制（旧下载页 `ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/tbl2asn/` 现仅剩 `DOCUMENTATION/` 与 `README`，`linux64.tbl2asn.gz` 已 404）。据此，本仓库的 **`tbl2asn` 模块已按官方停用移除**（其能力由本模块承接），新项目请直接使用 table2asn。
> 官方 nf-core / snakemake-wrappers / Homebrew 均无 table2asn 实现（2026-09-15 实测均 404，见「版本」），故本模块仅登记 native。

***

## native 实现

# table2asn / native — NCBI ASN.1 提交文件生成驱动

table2asn 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

table2asn 是 NCBI 提供的命令行工具，用于把 FASTA 序列文件（+ Feature Table `.tbl` 注释）转换为 ASN.1 格式的提交文件（`.sqn`），是向 GenBank 提交基因组数据的核心工具（tbl2asn 的现役后继）。

四个子命令覆盖 ASN.1 生成链路：

| 子命令        | 命令                                                                                                                          | 作用                                     |
| ---------- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `wgs`      | `table2asn -t <sbt> -indir <dir> -a r1k -l paired-ends -V vb -M n -Z`                                                         | 不完整基因组（WGS）提交（原核，产出 .sqn/.val/.stats/.dr） |
| `complete` | `table2asn -t <sbt> -indir <dir> -a a -V vb -M n -Z`                                                                          | 完整基因组（带注释）提交（产出 .sqn/.gbf）               |
| `validate` | `table2asn -t <sbt> -indir <dir> -V v -M n -Z`                                                                                | 仅生成验证/差异报告（提交前自检）                      |
| `run`      | `table2asn -t <sbt> -indir <dir> [-i <fsa>] [-a <type>] [-l paired-ends] [-gaps-min <n>] -V <opt> -M n -Z [extra...]`          | 通用调用，参数自行指定                            |

> table2asn 本体**单线程**，`--threads` 为统一接口/上层调度保留，不注入命令行；`--indir` 是**输入目录**（不是线程）。

## 用法

```bash
# CLI 直跑
python main.py wgs -t ecoli.sbt --indir ./ --outdir ./out --validate-level vb
python main.py complete -t Malassezia_sympodialis.sbt --indir ./
python main.py validate -t ecoli.sbt --indir ./          # 只出 .val/.stats/.dr
python main.py run -t ecoli.sbt --indir ./ -i ecoli.fsa -a r1u --gaps-min 10

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 仅调度参考；`--tmpdir` 会注入 `TMPDIR` 环境变量）。

### 与 tbl2asn 的参数差异

官方文档「table2asn command line argument changes from tbl2asn」表格明示（本模块已按新参数实现）：

| table2asn（现役）  | tbl2asn（已停用）  | 说明                                                                                              |
| -------------- | ------------- | ----------------------------------------------------------------------------------------------- |
| `-indir <dir>` | `-p <dir>`    | 输入文件所在目录；当前目录写 `-indir .`                                                                        |
| `-outdir <dir>` | `-r <dir>`    | 生成 `.sqn` 的输出目录；不用时 `.sqn` 落在源目录。与 `-M n` / `-V v` / `-Z` 同用时，输出目录名会成为 `.stats` 与 `.dr` 的 basename |
| `-Z`（无参数开关）    | `-Z <name>`   | table2asn 的 `-Z` **不再接受文件名参数**，仅作开关：运行差异报告并输出 `.dr` 后缀文件（tbl2asn 时代写作 `-Z discrep` 产出 `.discrep`）   |
| 沿用             | —             | `-t <template.sbt>` / `-i <x.fsa>` / `-a <type>` / `-V <v\|vb>` / `-M <n>` / `-l <paired-ends>` / `-gaps-min <n>` |

> 因此旧脚本里的 `tbl2asn -t x.sbt -p ./ -r ./out -Z discrep` 必须改写为
> `table2asn -t x.sbt -indir ./ -outdir ./out -Z`（`main.py` 已自动按新参数拼装）。

## 实战示例：WGS 提交文件生成

```bash
# 1) 准备工作目录与同名两件套（前缀必须一致）：<name>.fsa / <name>.tbl / <name>.sbt
ln -s scaffolds.fasta ecoli.fsa

# 2) 生成 ASN.1（WGS 示例；与官方文档示例 -t/-indir/-M n/-Z/-gaps-min/-l paired-ends 一致）
table2asn -t ecoli.sbt -indir ./ -M n -Z -gaps-min 10 -l paired-ends

# 3) 完整基因组（带注释）示例
table2asn -t Malassezia_sympodialis.sbt -indir ./ -a a -V vb -M n -Z

# 4) 只做验证/差异自检（提交前必须修复 .stats/.dr 中的 error 级问题）
table2asn -t ecoli.sbt -indir ./ -V v -Z

# 5) 查看报告
cat ecoli.val
cat ecoli.stats
cat ecoli.dr
```

table2asn 执行后会生成以下文件：

| 文件后缀     | 说明                                                            |
| -------- | ------------------------------------------------------------- |
| `.sqn`   | ASN.1 格式的提交文件（主要产物）                                           |
| `.val`   | 逐记录验证报告                                                       |
| `.stats` | 全部 `.val` 的验证汇总（错误数量/严重级别/类型）                                  |
| `.dr`    | 差异报告（`-Z` 开关触发；tbl2asn 时代为 `.discrep`）                         |
| `.gbf`   | GenBank 格式的 flatfile（当使用 `-V b` 或 `-V vb`）                    |

### 参数说明

| 参数            | 说明                                          | 取值                             |
| ------------- | ------------------------------------------- | ------------------------------ |
| `-t`          | 提交模板文件（.sbt）                                | `-t ecoli.sbt`                 |
| `-indir`      | 输入目录（扫描其中的 .fsa/.tbl）                       | `-indir ./`                    |
| `-outdir`     | .sqn 输出目录                                   | `-outdir ./out`                |
| `-i`          | 在多 .fsa 目录中只提交指定文件                          | `-i ecoli.fsa`                 |
| `-a`          | FASTA 文件类型                                  | `a` / `r1k` / `r1u` / `s`      |
| `-l`          | gap 连接证据为 paired-ends                       | `-l paired-ends`               |
| `-gaps-min`   | 最小 gap 长度                                   | `-gaps-min 10`                 |
| `-V`          | 验证选项                                        | `v`(仅 .val/.stats) / `b`(.gbf) / `vb`(两者) |
| `-M`          | master file 选项                              | `n`                            |
| `-Z`          | 差异报告开关（**无参数**）                             | `-Z`                           |

> 等价能力由 `native/main.py` 的 `wgs` / `complete` / `validate` / `run` 子命令提供（见上「用法」）：
> `table2asn -t ... -indir ... -outdir ... -a ... -V ... -Z` 的每段参数都对应一个 `main.py` 选项。

**参数 `-a` 的取值说明**：

| 值     | 说明                                        |
| ----- | ----------------------------------------- |
| `a`   | 任意格式，含单个 FASTA 或 ASN.1（table2asn 默认）     |
| `r1k` | N≥1 时长度不定，连续 N=100 表示估算长度为 100（WGS 常用）  |
| `r1u` | N=100 表示长度未知，其他值表示估算长度                   |
| `s`   | 批量不相关序列（批量基因组组装提交）                        |

**参数 `-V` 的取值说明**：

| 值    | 说明                                        |
| ---- | ----------------------------------------- |
| `v`  | 校验数据记录，输出 `.val`，并生成 `.stats` 汇总          |
| `b`  | 生成 GenBank 格式 flatfile（`.gbf`）            |
| `vb` | 同时生成验证信息与 flatfile（默认）                    |

## 环境安装（官方预编译二进制包优先；官方明示未提供源码）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org，2026-09-15 实测三渠道均可用），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。
官方同时通过 FTP 提供**平台预编译二进制包**（`linux64.table2asn.gz` / `mac.table2asn.gz` / `win64.table2asn.zip`）；**已核实官方未提供源码归档**（该 FTP 目录仅含二进制与 `DOCUMENTATION/`），故无源码编译路线。

### 1. Conda（包管理器安装）

```bash
mamba create -n table2asn-native -c conda-forge -c bioconda table2asn=1.28.1179   # bioconda 当前最新 1.28.1179
conda activate table2asn-native
table2asn -help   # 验证（table2asn 无 --version，-help 打印用法）
```

> Homebrew 无 table2asn 公式（homebrew-core `formulae.brew.sh/api/formula/table2asn.json` 与 brewsci-bio `Formula/table2asn.rb`、`Formula/t/table2asn.rb` 在 2026-09-15 实测均 404），故不登记 brew 块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `table2asn`，无 conda 时从官方 FTP 下载平台预编译二进制到 `~/software/table2asn-<ver>` 并写 PATH；版本默认 1.28.1179，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/table2asn:1.28.1179--he45da00_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/table2asn:1.28.1179--he45da00_1 \
    table2asn -t ecoli.sbt -indir ./ -M n -Z -gaps-min 10 -l paired-ends
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull table2asn.sif docker://depot.galaxyproject.org/singularity/table2asn:1.28.1179--he45da00_1
apptainer run -B $PWD:/data -H /data table2asn.sif \
    table2asn -t ecoli.sbt -indir /data -M n -Z -gaps-min 10 -l paired-ends
```

### 4. 官方预编译二进制包（官方 FTP，首选）

<https://ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/table2asn/>（2026-09-15 实测：`README`(640B)、`linux64.table2asn.gz`(19M)、`mac.table2asn.gz`(16M)、`win64.table2asn.zip`(13M) + `DOCUMENTATION/`；2025-09-16 更新）：

```bash
# 以 Linux x86_64 为例（无需 root，装到用户目录）
mkdir -p ~/software/table2asn-1.28.1179/bin
curl -fsSL -o /tmp/linux64.table2asn.gz \
  https://ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/table2asn/linux64.table2asn.gz
gunzip -c /tmp/linux64.table2asn.gz > ~/software/table2asn-1.28.1179/bin/table2asn
chmod +x ~/software/table2asn-1.28.1179/bin/table2asn
echo 'export PATH=$PATH:~/software/table2asn-1.28.1179/bin' >> ~/.bashrc
source ~/.bashrc
table2asn -help   # 验证
```

> macOS（Intel x86_64）把文件名换成 `mac.table2asn.gz`；Apple Silicon 走 Rosetta 或用 conda/官方镜像。
> 官方 FTP 二进制为**固定文件名（不含版本号）**，故无法按版本内嵌 sha256；需要校验时请自行 `shasum` 后与官方核对。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + stub 二进制端到端 + 缺二进制报错路径；本机已装 table2asn 时追加 -help 真实冒烟
```

## 版本

* table2asn `1.28.1179`（bioconda::table2asn=1.28.1179；官方镜像 tag `1.28.1179--he45da00_1`）
* 构建路线：官方镜像/conda 提供（`quay.io/biocontainers/table2asn` / `depot.galaxyproject.org`；本地不自建容器）
* 渠道核实（2026-09-15 实测）：bioconda API 200（`latest_version=1.28.1179`，license `Public Domain`）；quay tag API 200（`1.28.1179--he45da00_1`，2024-12-14 构建）；depot sif HEAD 200
* 官方 nf-core module（`modules/nf-core/table2asn`）404、snakemake-wrappers（`bio/table2asn`）404、Homebrew（core + brewsci-bio）404
* 前身 tbl2asn 已 Obsolete：官方二进制下架（旧下载页 404），其 bioskills 模块已按官方停用移除；本模块为唯一现役提交工具

## 容器与 Conda 链接

* **官网（table2asn 文档页）**：<https://www.ncbi.nlm.nih.gov/genbank/table2asn/>
* **官方 FTP 下载**：<https://ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/table2asn/>（README 另注明备用路径 `https://ftp.ncbi.nlm.nih.gov/asn1-converters/by_program/table2asn/`，2026-09-15 实测 200）
* **Bioconda 页面**：<https://anaconda.org/bioconda/table2asn>
* **Docker**：`docker pull quay.io/biocontainers/table2asn:1.28.1179--he45da00_1`
* **Singularity**：<https://depot.galaxyproject.org/singularity/table2asn%3A1.28.1179--he45da00_1>
* 安装方式（本地）：`mamba create -n table2asn-native -c conda-forge -c bioconda table2asn=1.28.1179`
