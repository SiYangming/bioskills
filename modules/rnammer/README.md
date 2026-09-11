# rnammer 软件模块（HMM 法 rRNA 基因预测）

> 汇总说明：RNAmmer 1.2（CBS DTU 出品）是基于 **HMM（隐马尔可夫模型）** 的 **rRNA 基因预测工具**，
> Perl 编写（主命令 `rnammer`，配套 `xml2gff` 等），对细菌/古菌/真核基因组预测
> **5S/5.8S、16S/18S、23S/28S rRNA** 基因，输出 rRNA 序列 FASTA（`-f`）、HMMER 搜索报告（`-h`）、
> XML（`-xml`）与 GFF2（`-gff`）；域由 `-S` 指定（`bac`/`arc`/`euk`），`-multi` 双链并行预测全部
> rRNA 类型。运行须搭配 **HMMER 2.x**（教学用 hmmer-2.2g；安装见 [`modules/hmmer`](../hmmer/README.md) 的「HMMER 2.x 遗留版（native2 实现）」章节）与 Perl 模块 **XML::Simple**。
> 本模块仅 native 一路（`source_type: custom`）；官方 nf-core / snakemake-wrappers 均无（仅说明层，
> 见文末），安装方式见「环境安装（官方渠道无镜像：宿主机安装）」。
>
> 官网（注册制源码下载页 / 在线服务入口）：<https://services.healthtech.dtu.dk/services/RNAmmer-1.2/>
>
> 源码替代来源（自建归档镜像仓库，**已归档/只读**、私有需授权）：<https://github.com/SiYangming/rnammer>

***

## native 实现

# rnammer / native — HMM 法 rRNA 基因预测驱动

本地自包含驱动（`source_type: custom`、`type: native`），`native/main.py` 的 `scan` 子命令包装
宿主机的 `rnammer` 命令，完成 rRNA 基因预测：

```
基因组 FASTA
  → rnammer -S <bac|arc|euk> -multi                HMM 搜索（双链并行，全部 rRNA 类型）
  → -f rRNA.fasta       预测 rRNA 序列 FASTA
  → -h rRNA.hmmreport   HMMER2 hmmsearch 搜索报告
  → -xml rRNA.xml       预测结果 XML
  → -gff rRNA.gff2      rRNA 基因注释 GFF2
```

> rnammer 二进制需宿主机安装：RNAmmer 1.2 源码为 CBS DTU 官网**注册制下载**，
> HMMER2 与 Perl XML::Simple 为运行硬依赖（安装步骤见下）。

## 能力

| 子命令  | 包装命令                                                                               | 作用                                                        | 线程 |
| ---- | ---------------------------------------------------------------------------------- | --------------------------------------------------------- | -- |
| `scan` | `rnammer -S <bac\|arc\|euk> [-multi] [-m tsu,ssu,lsu] -f/-h/-xml/-gff ... genome.fasta` | HMM 法 rRNA 基因预测 → rRNA 序列 FASTA + HMM 报告 + XML + GFF2 | 协议位（`-multi` 自带双链并行，rnammer 无线程参数） |

## 用法

```bash
# CLI 直跑（原核 rRNA 预测；-multi 双链并行全部类型）
python main.py scan genome.ecoli.fasta --kingdom bac --multi \
    -f rRNA.fasta -h rRNA.hmmreport -xml rRNA.xml -gff rRNA.gff2

# 真核 rRNA 预测
python main.py scan genome.fasta --kingdom euk --multi \
    -f rRNA.fasta -h rRNA.hmmreport -xml rRNA.xml -gff rRNA.gff2

# 仅预测指定分子类型（tsu=5S/8S、ssu=16S/18S、lsu=23S/28S；逗号可组合）
python main.py scan genome.fasta --kingdom bac -m ssu \
    -f rRNA.ssu.fasta -gff rRNA.ssu.gff2

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（协议位）：**rnammer 原生无线程参数**，
`--threads` 不注入命令行（`-multi` 已自带双链并行）；`--tmpdir` 注入 `TMPDIR` 环境变量。

> 也可跳过 main.py 直接调用 rnammer（原生 CLI）：
>
> ```bash
> rnammer -S euk -multi -f rRNA.fasta -h rRNA.hmmreport -xml rRNA.xml -gff rRNA.gff2 genome.fasta
> ```

## 实战示例：真核 / 原核 rRNA 基因预测（教学用法）

RNAmmer 1.2 的典型教学用法（`-multi` 双链并行预测全部 rRNA 类型）；**等价能力由 `native/main.py`
的 `scan` 子命令提供**（先 CLI 后 main.py，见上「用法」）。

### 1. 真核基因组 rRNA 预测（`-S euk`）

```bash
mkdir -p rnammer_out && cd rnammer_out
rnammer -S euk -multi -f rRNA.fasta -h rRNA.hmmreport -xml rRNA.xml -gff rRNA.gff2 ../genome.fasta
```

### 2. 原核基因组 rRNA 预测（`-S bac`）

```bash
mkdir -p rnammer_out && cd rnammer_out
rnammer -S bac -multi -f rRNA.fasta -h rRNA.hmmreport -xml rRNA.xml -gff rRNA.gff2 ../genome.ecoli.fasta
```

### 3. 用 `-m` 限定分子类型（可选）

```bash
# tsu=5S/8S、ssu=16S/18S、lsu=23S/28S；逗号可组合，如 -m tsu,ssu,lsu
rnammer -S bac -multi -m ssu -f rRNA.ssu.fasta -gff rRNA.ssu.gff2 ../genome.ecoli.fasta
```

### 4. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-S` / `--kingdom` | 域模型（**必填**）：`arc`（古菌）/ `bac`（细菌）/ `euk`（真核） |
| `-multi` / `--multi` | 双链并行预测全部 rRNA 类型（本驱动默认开启；`--no-multi` 关闭，仅按 `-m` 预测） |
| `-m` / `--molecules` | 分子类型（逗号分隔）：`tsu`（5S/8S）/ `ssu`（16S/18S）/ `lsu`（23S/28S）/ `tsu,ssu,lsu` |
| `-f` / `--out-fasta` | 预测 rRNA 序列输出 FASTA |
| `-h` / `--hmmreport` | HMMER 搜索报告输出文件（rnammer 原生 `-h`；驱动以 `--hmmreport` 暴露，避免与 `--help` 冲突） |
| `-xml` | 预测结果 XML 输出文件 |
| `-gff` | 预测结果 GFF2 输出文件 |
| `genome_fasta` | 输入基因组 FASTA（位置参数） |
| `--threads` | 协议位；rnammer 无线程参数，不注入命令行 |
| `--tmpdir` | 协议位；注入 `TMPDIR` 环境变量 |

> 桥接句：以上 CLI 用法等价于 `python main.py scan genome.fasta --kingdom <bac|euk> --multi -f ... -h ... -xml ... -gff ...`。

## 依赖模块（安装见对应模块文档）

| 依赖         | 作用                                          | 安装文档                                  |
| ---------- | ------------------------------------------- | ------------------------------------- |
| HMMER 2.x  | rRNA HMM 搜索（RNAmmer 必须用 2.x，`$HMMSEARCH_BINARY` 指向它） | [modules/hmmer](../hmmer/README.md)（2.x 遗留版章节，`native2/` 实现） |

> HMMER 的 2.x 与 3.x 属**同一软件**，已合并为一个模块 `modules/hmmer`：3.x 为默认实现（`native/`，见「HMMER 3.x 现行版」章节），2.x 为遗留版实现（`native2/`，见「HMMER 2.x 遗留版（native2 实现）」章节）。
>
> Perl 模块 XML::Simple / XML::Parser 属语言级依赖（非独立软件模块），安装见下「环境安装」①。

## 环境安装（官方渠道无镜像：宿主机安装）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**均无** rnammer 的 conda 包与
镜像（2026-09 在线核实：bioconda rnammer 404、quay.io/biocontainers 无 rnammer、depot 无；
nf-core / snakemake-wrappers 子模块亦无）。RNAmmer 1.2 源码为 **CBS DTU 官网注册制下载**
（需 edu 邮箱申请下载链接），采用**宿主机安装路线**：宿主 conda/perl 提供 HMMER2 + Perl + XML::Simple
运行依赖，RNAmmer 源码由用户注册下载后本地配置。一键安装：`bash native/install.sh`。
HMMER 2.x 与 3.x 属**同一软件**，已合并为本仓库的 [`modules/hmmer`](../hmmer/README.md)
（3.x = `native/` 默认实现；2.x = `native2/` 遗留版实现，RNAmmer 用后者）。

### 1. Conda / 宿主依赖（HMMER2 + Perl + XML::Simple）

```bash
# 路线 A：conda 装 HMMER2 + Perl + XML::Simple（bioconda hmmer2 为 2.3.2）
mamba create -n rnammer -c conda-forge -c bioconda \
    python=3.11 pyyaml hmmer2 perl perl-xml-simple perl-xml-parser
conda activate rnammer
hmmsearch2 -h         # 断言 HMMER2 可用（bioconda hmmer2 包内二进制带 2 后缀：hmmsearch2）
perl -MXML::Simple -e1 && echo OK    # 断言 Perl 模块可加载
```

```bash
# 路线 B：无 conda 时用系统 perl + cpanm 补 XML::Simple（HMMER2 见 ② 源码编译）
cpanm XML::Simple     # 或 cpan -i XML::Simple（会一并装 XML::Parser / XML::SAX::Expat）
perl -MXML::Simple -e1 && echo OK
```

> ⚠️ 教学用 HMMER 版本为 **hmmer-2.2g**，而 bioconda `hmmer2` 为 **2.3.2**（包内可执行文件名为
> `hmmsearch2`，与 HMMER3 的无后缀 `hmmsearch` 区分）——**RNAmmer 对 HMMER
> 版本敏感**，如需严格对齐教学环境请用 ② 源码编译 hmmer-2.2g。

### 2. HMMER 2.x 安装（源码编译；推荐直接用 `modules/hmmer` 的 native2 实现）

> 首选：直接用本仓库 [`modules/hmmer`](../hmmer/README.md) 的 2.x 遗留版实现 `native2/`（conda `bioconda::hmmer2`=2.3.2 或官方容器 `quay.io/biocontainers/hmmer2:2.3.2--h87e0c26_12`，安装后二进制带 `2` 后缀如 `hmmsearch2`）。仅当需与教学环境严格对齐（hmmer-2.2g，源码自编译无后缀）时，按本节编译：

```bash
mkdir -p ~/software && cd ~/software
wget http://eddylab.org/software/hmmer/hmmer-2.2g.tar.gz
tar zxf hmmer-2.2g.tar.gz && cd hmmer-2.2g
./configure --prefix=$HOME/software/hmmer-2.2g && make && make install
export PATH=$HOME/software/hmmer-2.2g/bin:$PATH
hmmsearch -h          # 断言
```

### 3. RNAmmer 注册下载与路径配置

```bash
mkdir -p ~/software && cd ~/software
# 到官网注册申请后获得下载链接，下载 rnammer-1.2 源码包
#   https://services.healthtech.dtu.dk/services/RNAmmer-1.2/
# 替代来源：自建归档镜像仓库（已归档/只读、私有仓库需授权）
#   https://github.com/SiYangming/rnammer-1.2
tar zxf rnammer-1.2.tar.gz -C ~/software/          # -> ~/software/rnammer-1.2/
cd ~/software/rnammer-1.2 && chmod +x rnammer

# 就地替换脚本内两处路径（教学用 perl -p -i -e）
export INSTALL_PATH="$HOME/software/rnammer-1.2"                     # 指向 rnammer-1.2 安装目录
export HMMSEARCH_BINARY="$HOME/software/hmmer-2.2g/bin/hmmsearch"    # 指向 HMMER2 的 hmmsearch
perl -p -i -e '
    s{^(\s*(?:my\s+)?\$INSTALL_PATH\s*=\s*).*$}{$1"$ENV{INSTALL_PATH}";};
    s{^(\s*(?:my\s+)?\$HMMSEARCH_BINARY\s*=\s*).*$}{$1"$ENV{HMMSEARCH_BINARY}";};
' rnammer
# 亦可手工把脚本内的 my $INSTALL_PATH 与 $HMMSEARCH_BINARY 改为上述实际路径

# 冒烟测试
perl -c rnammer                       # 语法 + 依赖检查（需 XML::Simple）
export PATH="$INSTALL_PATH:$PATH"
rnammer -S bac -multi -f rRNA.fasta -h rRNA.hmmreport -xml rRNA.xml -gff rRNA.gff2 genome.fasta
```

> 一键完成 ①/②/③：`bash native/install.sh --method manual --rnammer-tarball ~/software/rnammer-1.2.tar.gz`

### 4. 二进制 / 源码包说明（注册制下载）

RNAmmer **无官方预编译二进制**，官方仅提供**注册制源码包**（官网填 edu 邮箱申请下载链接）：
<https://services.healthtech.dtu.dk/services/RNAmmer-1.2/>。**替代来源**：自建归档镜像仓库
<https://github.com/SiYangming/rnammer-1.2>（**已归档/只读**；私有仓库，访问需仓库授权）。
HMMER2 安装见本仓库 [`modules/hmmer`](../hmmer/README.md) 的 2.x 遗留版实现（`native2/`）；
亦可 bioconda `hmmer2`（<https://anaconda.org/bioconda/hmmer2>）或官方源码 hmmer-2.2g
（<http://eddylab.org/software/hmmer/hmmer-2.2g.tar.gz>）。

> Docker / Apptainer：官方渠道无公开镜像，如需容器请自备注册下载的源码包后本地构建。

## 容器与 Conda 链接

* **Bioconda**：<https://anaconda.org/bioconda/rnammer>（**不存在**，2026-09 核实 404）
* **Docker / quay.io/biocontainers**：无 rnammer 镜像（2026-09 核实）
* **上游官网（注册制源码）**：<https://services.healthtech.dtu.dk/services/RNAmmer-1.2/>
* **源码替代来源（归档镜像）**：<https://github.com/SiYangming/rnammer-1.2>（**已归档/只读**；私有仓库需授权访问）
* **HMMER2（可选依赖）**：本仓库模块 [`modules/hmmer`](../hmmer/README.md)（2.x 遗留版实现 `native2/`，见「HMMER 2.x 遗留版（native2 实现）」章节）；conda <https://anaconda.org/bioconda/hmmer2>；源码 <http://eddylab.org/software/hmmer/hmmer-2.2g.tar.gz>
* **nf-core modules**：无 `modules/nf-core/rnammer`（2026-09 核实 404）
* **snakemake-wrappers**：无 `bio/rnammer`（2026-09 核实 404）
* 安装方式（本地）：`bash native/install.sh`（auto/conda/manual 双路线；manual 需 `--rnammer-tarball`）

## 版本

* RNAmmer **1.2**（官网现行版，注册制源码）
* HMMER **2.x**：教学用 **hmmer-2.2g**；bioconda `hmmer2` 为 **2.3.2**（RNAmmer 对 HMMER 版本敏感，按需选择）
* Perl 依赖：**XML::Simple**（经 XML::Parser / XML::SAX::Expat）
* 官方渠道（bioconda / quay.io/biocontainers / depot.galaxyproject.org）与 nf-core / snakemake-wrappers
  均无 RNAmmer（2026-09 在线核实）

## 测试

```bash
cd modules/rnammer/native && bash test/run_test.sh
# 任何环境 exit 0 并打印 ALL TESTS PASSED：
#   - 自省（--list-commands / --schema / scan --help 参数契约）必跑；
#   - 参数校验契约必跑（缺 rnammer 时给出注册下载 + INSTALL_PATH/HMMSEARCH_BINARY 指引；非法 --kingdom 被拒绝）；
#   - PATH 含 rnammer 时追加真跑最小链路（-S bac -multi -f/-h/-xml/-gff 四件套），真跑失败仅 [WARN] 不阻断；
#   - 无 rnammer 时 [SKIP]。
```
