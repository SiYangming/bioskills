# snogps 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器信息记录于此。
> 来源：非编码RNA预测教程——snoRNA 预测工具 snoScan / snoGPS。
>
> ⚠️ **官方渠道全无（2026-09 核实）**：bioconda `snogps` 未找到、quay.io/biocontainers/snogps 401（不存在）、
> depot.galaxyproject.org/singularity/snogps 404，nf-core / snakemake-wrappers / brew 均无。
> 本模块按「自建兜底」提供 `native/Dockerfile` 与 `native/Apptainer.def`（官方源码编译）。

***

## native 实现

# snogps / native — 自包含 H/ACA snoRNA 预测驱动

snoGPS 的本地自包含实现（`source_type: custom`、`type: native`）。

snoGPS 是 Lowe 实验室（UCSC）开发的 **H/ACA box 假尿苷化引导 snoRNA** 预测程序：基于确定性筛选算法 + 概率打分模型，在基因组序列中搜索 H/ACA snoRNA（Schattner et al., *NAR* 2004, 32:4281）。程序由 C 源码编译（依赖内置 SQUID 库），核心二进制为 `pseudoU_test`（软链为 `snoGPS`）。

## 功能

| 子命令      | 命令                                                                                                          | 作用                              |
| -------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------- |
| `search` | `snoGPS [-D N] [-S S] [-T <target>] [-F <out>] [-t N] [-L <table>] [-W] [-C] [-q] <sequence.fa> <descriptor>` | H/ACA 假尿苷化引导 snoRNA 搜索           |
| `sort`   | `sortHits.pl <hits file>`                                                                                   | 命中结果整理（辅助 Perl 脚本）                |

> 以上命令行依据上游 `src/pseudoU_test.c` 的 usage 块与 README 整理。
> snoGPS 为**单进程**程序，无并行参数；`--threads` 仅记录，不注入命令行。

## 用法

```bash
# CLI 直跑：以待查序列 + descriptor + target 文件运行 snoGPS
python main.py search genome.fa desc/MamGUs2.v3.desc \
    -T targs/human.targ -t 135 -S 5 -F hits.fa

# 仅搜索 Watson 链 + 安静模式
python main.py search genome.fa desc/haca2stemv7.desc -W -q -T targs/yeast.targ -t 44

# 命中整理
python main.py sort results/hits.txt

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

参数（依据上游 usage，完整见源码 `src/pseudoU_test.c`）：

| 参数          | 说明                                                       |
| ----------- | -------------------------------------------------------- |
| 位置 1 / 位置 2 | 待查序列文件（FASTA，可为基因组）/ descriptor 文件（定义搜索测试与参数）           |
| `-T`        | target 文件（目标假尿苷位点局部序列，见源码 `targs/`）                       |
| `-t`        | 从 target 文件读取的靶位点数量（多个 target 时需指定）                        |
| `-S`        | 总分阈值                                                     |
| `-F`        | 命中序列 FASTA 输出文件（默认 `results/pseudoU_fa/hits.fa`）          |
| `-L`        | 自定义打分表文件（默认用内置 `scoretables/`）                             |
| `-W` / `-C` | 仅搜索 Watson 链 / Crick 链                                     |
| `-q` / `-D` | 安静模式 / 调试级别（0/1/2）                                        |

## 实战示例：酵母 H/ACA snoRNA 全基因组扫描

```bash
# 官方源码包自带 demos/（singleGenomeDemo.sh 等）演示完整用法；
# 下列为独立目录下的等价手工用法
mkdir -p snogps_out && cd snogps_out

# 以酿酒酵母为例：descriptor 用双发夹模型，target 用已知 rRNA 假尿苷位点
snoGPS ../S_cerevisiae/genome.fa \
    /path/to/snoGPS/desc/haca2stemv7.desc \
    -T /path/to/snoGPS/targs/Sc-rRNA.targ -t 44 -S 5 -F hits.fa > hits.txt 2> hits.log

# 整理命中（辅助 Perl 脚本；需设置 MYPERLMODULEDIR 指向源码 perlModules/）
sortHits.pl hits.txt > hits.sorted
```

> 上述命令与 `native/main.py` 的 `search` / `sort` 子命令等价：搜索走 `main.py search ...`，整理走 `main.py sort ...`（见上「用法」）。

## 环境安装（官方源码编译；官方渠道全无 → 自建容器兜底）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**均无** snoGPS（2026-09 核实），
故本模块走**官方源码编译**为主路线，并提供自建容器配方 `native/Dockerfile` / `native/Apptainer.def`。

### 1. 官方源码编译（首选）

* **官网**：<https://lowelab.ucsc.edu/snoGPS/>

* **源码归档**：<https://trna.ucsc.edu/software/snoGPS-0.2.tar.gz>（0.2 beta，sha256 `184abd9c…845027`）

```bash
# 下载并解压官方源码
wget https://trna.ucsc.edu/software/snoGPS-0.2.tar.gz -P ~/software/
tar zxf ~/software/snoGPS-0.2.tar.gz -C ~/software/
cd ~/software/snoGPS-0.2

# 编译核心程序（产物 pseudoU_test，并软链为 snoGPS）
cd src && make            # 需要 gcc / make
ls snoGPS || ln -s pseudoU_test snoGPS   # 若 make 未生成软链则手工创建

# 运行期数据（descriptor / target / scoretable / perlModules / scripts）
export MYPERLMODULEDIR="$PWD/../perlModules/"
export PATH="$PWD:$PATH"
snoGPS -h    # 断言（输出 usage）
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：官方渠道全无 → binary 路线源码编译到
> `~/software/snogps-<ver>`，内嵌官方源码 sha256 校验，安装脚本 + 运行期数据并写 PATH；
> 版本默认 0.2，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。
> 注意：`--method conda` 会明确报错（bioconda 无 snogps）。

### 2. Docker（自建镜像）

```bash
# 无官方镜像 → 用本模块自建配方构建（debian:bookworm-slim + apt 最小化 + 官方源码编译）
docker build -t snogps:0.2 modules/snogps/native

# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    snogps:0.2 /data/genome.fa /opt/snogps/share/desc/haca2stemv7.desc \
    -T /opt/snogps/share/targs/Sc-rRNA.targ -t 44 -F /data/hits.fa
```

### 3. Apptainer / Singularity（自建 def）

```bash
# 无 depot 预构建 sif → 本地从自建 def 构建
apptainer build snogps.sif modules/snogps/native/Apptainer.def
apptainer run -B $PWD:/data snogps.sif /data/genome.fa /opt/snogps/share/desc/haca2stemv7.desc
```

### 4. Conda / brew

* **Conda**：bioconda 无 `snogps` 包（2026-09 核实 api.anaconda.org 未找到）→ 不可用。
* **brew**：homebrew-core 与 brewsci/bio 均无 `snogps`（2026-09 核实 404）→ 不提供 brew 块。

## 测试

```bash
bash test/run_test.sh   # search/sort 为 argv 构造验证；snoGPS 未安装时跳过真实冒烟
```

## 版本

* snoGPS 0.2 beta（2004-08-01；官方现存可下载源码归档）

* 构建路线：官方源码编译（官方渠道全无 → 自建容器 `native/Dockerfile` / `native/Apptainer.def`）

* nf-core / snakemake-wrappers 均无 snogps 官方模块（2026-09 核实 404）

## 容器与 Conda 链接

* **官方镜像**：无（bioconda / quay.io/biocontainers / depot.galaxyproject.org 均无 snoGPS）

* **替代方案（自建）**：`modules/snogps/native/Dockerfile` + `modules/snogps/native/Apptainer.def`（官方源码编译）

* **上游源码**：<https://trna.ucsc.edu/software/snoGPS-0.2.tar.gz>

* 安装方式（本地）：`bash modules/snogps/native/install.sh`（源码编译到 `~/software/snogps-0.2`）
