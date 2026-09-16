# orthomcl 软件模块（OrthoMCL v2.0.9 — 同源基因聚类）

> # ⚠️ DEPRECATED — 已停止维护，仅历史参考登记
>
> **OrthoMCL v2.0.9** 是经典的直系同源基因聚类流程（Orthologous Groups via MCL）：
> 规范化蛋白序列 → 过滤 → BLAST/DIAMOND all-vs-all → 解析比对 → 导入 MySQL →
> 找 ortholog/in-paralog 对 → 导出 mclInput → MCL 聚类（OCG）→ 编号。
> 上游已**停止维护**，官方**推荐 OrthoFinder 替代**；流程还**依赖 MySQL**，
> 安装与运行繁琐。
>
> **新项目请改用 `modules/orthofinder/`（OrthoFinder）**——速度更快、准确性更高、无需数据库。
> 本模块只做「录入」：方法/命令/链接准确登记、**不产出自建容器配方**
> （Dockerfile/Apptainer.def），仅供复现历史 OrthoMCL 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按官方流程构造 OrthoMCL 各步骤
命令行并打印，**不实际执行**（软件 deprecated、依赖 MySQL、无新用场景）。八个子命令对应
OrthoMCL 官方脚本：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `adjust_fasta` | `orthomclAdjustFasta <species> <fasta> <id_length>` | 规范化蛋白 FASTA（序列头 `>物种\|基因ID`） |
| `filter_fasta` | `orthomclFilterFasta <input_dir> [<min_len>] [<max_percent_stop>]` | 过滤低质量序列 → `goodProteins.fasta` |
| `blast_parser` | `orthomclBlastParser <blast_output> <compliant_dir>` | 解析 BLAST/DIAMOND（stdout → `similarSequences.txt`） |
| `load_blast` | `orthomclLoadBlast <orthomcl.config> <similarSequences.txt>` | 相似序列对导入 MySQL |
| `pairs` | `orthomclPairs <orthomcl.config> <pairs.log> <cleanup>` | 寻找 ortholog / in-paralog 对 |
| `dump_pairs` | `orthomclDumpPairsFiles <orthomcl.config>` | 导出 `mclInput` + `pairs/` |
| `mcl_to_groups` | `orthomclMclToGroups <prefix> <start>` | MCL 结果编号（stdin → stdout `groups.txt`） |
| `install_schema` | `orthomclInstallSchema <orthomcl.config> <schema.log> [<install.log>]` | 安装 OrthoMCL 数据库表 |

```bash
# CLI 直跑（构造历史流程命令，仅供复现；先装 OrthoMCL 2.0.9 + MySQL，见「环境安装」）
python main.py install_schema orthomcl.config schema.log
python main.py adjust_fasta ncra proteome.fasta 10
python main.py filter_fasta compliantFasta 30 20
python main.py blast_parser blast.out compliantFasta > similarSequences.txt
python main.py load_blast orthomcl.config similarSequences.txt
python main.py pairs orthomcl.config pairs.log yes
python main.py dump_pairs orthomcl.config
python main.py mcl_to_groups OCG 1 < mclOutput > groups.txt

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir`。**注意**：OrthoMCL 各脚本无多线程选项，
`--threads` 被接受但不注入 argv（仅接口占位）；重计算（MCL 聚类）走 `modules/mcl/`。
构造命令通过 stderr 打印 deprecated 提示，stdout 只输出命令本身。

## 实战示例：OrthoMCL 完整流程（命令级对照）

```bash
# 0) 数据库 schema（需 MySQL）
orthomclInstallSchema orthomcl.config schema.log

# 1) 序列规范化 + 过滤（compliantFasta/ 放各物种 FASTA；命名规则 属名前2+种名前3）
orthomclAdjustFasta ncra ncra.pep.fasta 10
orthomclFilterFasta compliantFasta 30 20        # 最短长度 30、终止密码子比例 20%

# 2) all-vs-all（DIAMOND 推荐；或 BLAST）
diamond makedb --in goodProteins.fasta -d goodProteins
diamond blastp -d goodProteins -q goodProteins.fasta -o blast.out --outfmt 6
orthomclBlastParser blast.out compliantFasta >> similarSequences.txt

# 3) 导入 DB → 找 pairs → 导出 mclInput
orthomclLoadBlast orthomcl.config similarSequences.txt
orthomclPairs orthomcl.config pairs.log yes
orthomclDumpPairsFiles orthomcl.config

# 4) MCL 聚类（用 modules/mcl/）→ 编号
mcl mclInput --abc -I 1.5 -o mclOutput
orthomclMclToGroups OCG 1 < mclOutput > groups.txt
```

上述第 4 步的 MCL 聚类等价能力由 `modules/mcl/` 的 `cluster` 子命令提供
（`python main.py cluster mclInput --abc -I 1.5 -o mclOutput`）。

## 测试

```bash
bash test/run_test.sh   # 八个子命令 argv 构造 + 线程优先级 + 运行时校验（不下载/不连库）
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09 在线核实，如实记录）：官方站 **orthomcl.org 仍可达（200）**，官方
> tarball `orthomclSoftware-v2.0.9.tar.gz` 可下载；bioconda 存在 **orthomcl=2.0.9** 历史包
> （noarch）→ quay.io/biocontainers 与 depot.galaxyproject.org 有自动构建镜像。但上游
> 停止维护、流程依赖 MySQL → 判定「官方渠道存在但属历史遗留，不建议新项目依赖」；软件
> deprecated → **不维护本地 Dockerfile/Apptainer.def 配方**。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda orthomcl=2.0.9（noarch；依赖 perl/perl-dbi/perl-dbd-mysql/mcl/blast/mysqlclient）
mamba create -n orthomcl-native -c conda-forge -c bioconda orthomcl=2.0.9
conda activate orthomcl-native
orthomclAdjustFasta            # 断言：脚本可达（无 --version，无参运行打印含 EXAMPLE 的用法）
```

> Homebrew：homebrew-core（formulae.brew.sh/api/formula/orthomcl.json）与 brewsci/bio
> （Formula/orthomcl.rb）均 404（2026-09 核实），无公式 → 不登记 brew 安装块。

### 2. Docker（历史镜像）

无「当前维护」官方镜像；仅历史镜像可作复现（bioconda 2.0.9 老包自动构建）：

```bash
docker pull quay.io/biocontainers/orthomcl:2.0.9--hdfd78af_5
# 运行工具本体（产物归当前用户，避免 root 持有）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/orthomcl:2.0.9--hdfd78af_5 \
    orthomclDumpPairsFiles /data/orthomcl.config
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（2026-09 核实存在，与 quay tag 互通）：

```bash
apptainer pull orthomcl.sif docker://depot.galaxyproject.org/singularity/orthomcl:2.0.9--hdfd78af_5
apptainer run -B $PWD:/data -H /data orthomcl.sif \
    orthomclAdjustFasta ncra /data/proteome.fasta 10
```

### 4. 官方 tarball（官方分发形式）

* **官网**：<http://orthomcl.org/orthomcl/>
* **tarball**：<http://orthomcl.org/common/downloads/software/v2.0/orthomclSoftware-v2.0.9.tar.gz>
  （md5 `2e0202ed4e36a753752c3567edb9bba9`，取自 bioconda-recipes orthomcl 配方）

```bash
wget http://orthomcl.org/common/downloads/software/v2.0/orthomclSoftware-v2.0.9.tar.gz -P ~/software/
tar zxf ~/software/orthomclSoftware-v2.0.9.tar.gz -C ~/software/
export PATH="$HOME/software/orthomclSoftware-v2.0.9/bin:$PATH"   # 建议写入 ~/.bashrc
orthomclAdjustFasta   # 断言：脚本可达
```

> 也可一键运行 `native/install.sh`（有 conda 时建环境 `orthomcl`，否则解压官方 tarball 到
> `~/software/orthomclSoftware-v2.0.9`；用法：`bash native/install.sh --help`）。
> **MySQL 需另行安装/配置**（`orthomcl.config` 填连接串与账号）。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **OrthoFinder**（首选） | OrthoMCL 继任者：快 10-100 倍、准确性更高、自动物种树/基因树、无数据库依赖 | <https://github.com/davidemms/OrthoFinder>（本仓库 `modules/orthofinder/`） |
| **MCL** | OrthoMCL 用到的聚类内核；单跑见本仓库 `modules/mcl/` | <https://www.micans.org/mcl/> |

## 版本

* **2.0.9**（OrthoMCL v2.0.9；官方 tarball `orthomclSoftware-v2.0.9.tar.gz`，2026-09 核实
  orthomcl.org 可达 200）
* bioconda 版本号 **2.0.9**（noarch；历史镜像 quay.io/biocontainers/orthomcl:2.0.9--hdfd78af_5）
* License：**EuPathDB Bioinformatics Resource Center**（bioconda 配方 license 字段；官方许可
  文件见 tarball 内 `doc/OrthoMCLEngine/Main/SoftwareLicense.txt`）
* 依赖：MySQL（含 perl-dbi / perl-dbd-mysql）、mcl、blast
* 引用：Li L, Stoeckert CJ Jr, Roos DS. OrthoMCL: identification of ortholog groups for
  eukaryotic genomes. *Genome Res.* 2003;13(9):2178-89. doi:10.1101/gr.1224503
* nf-core / snakemake-wrappers：无官方子模块（2026-09 核实 `modules/nf-core/orthomcl`、
  `bio/orthomcl` 均 404）→ 不登记官方说明层

## 容器与 Conda 链接

* **官网**：<http://orthomcl.org/orthomcl/>
* **conda**：bioconda `orthomcl=2.0.9`（历史包）→ <https://anaconda.org/bioconda/orthomcl>
* **Docker / Singularity**：`quay.io/biocontainers/orthomcl:2.0.9--hdfd78af_5`（历史镜像）/
  depot.galaxyproject.org 同名 sif
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* **官方 tarball**：<http://orthomcl.org/common/downloads/software/v2.0/orthomclSoftware-v2.0.9.tar.gz>
