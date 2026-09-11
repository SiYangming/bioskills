# recon 软件模块（RECON · 从头重复序列家族识别与分类）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# recon / native — 从头重复序列家族识别驱动

RECON（**RE**peat **CON**structor，Zhirong Bao & Sean R. Eddy，2002；现由 [Dfam-consortium/RECON](https://github.com/Dfam-consortium/RECON) 维护）是基因组重复序列家族的**从头（de novo）识别与分类**工具：以全基因组自身比对（all-vs-all）产出的 **MSP**（Maximum Scoring Pairs，最大打分片段对）为输入，经 **eledef → eleredef → edgeredef → famdef 四阶段**聚类与图分析，把相互相似的重复拷贝归并为**重复家族（repeat family）**，输出 `summary/eles`（家族-元素成员表）与 `summary/families`（家族统计）。

> ⚠️ **依赖语境（重要）**：RECON 通常**作为 [RepeatModeler](https://github.com/Dfam-consortium/RepeatModeler) 的组成部分**使用——RepeatModeler 会自行调用 RECON 完成「元素 → 家族」聚类步骤（bioconda `repeatmodeler` 包已内含 RECON）。**多数场景不必单独运行 RECON**，请优先使用 `modules/repeatmodeler`（其 README/安装文档已覆盖完整依赖链）；仅在需要单独复现/调参 RECON 聚类、或自定义上游 MSP 时使用本模块。本模块只负责 RECON 本体，不管理 RepeatModeler/RepeatScout/RMBlast 等依赖。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/recon / bioconda recon）提供；`bin/` 内含主驱动脚本与四阶段 C 程序：

## 能力

| 子命令        | 包装命令                                                                                   | 作用                                                  | 线程               |
| ---------- | -------------------------------------------------------------------------------------- | --------------------------------------------------- | ---------------- |
| `pipeline` | `run_recon.sh <bin_dir> <seq_list> <msp_file> [num_sections] [work_dir]`                  | 跑完整四阶段流水线，输出 `summary/eles` + `summary/families`   | 串行，`--threads` 不注入 |
| `eledef`   | `eledef <seq_list> <msp_file> single\|double [cutoff] [-l level]`                         | 仅阶段 1：MSP → 初始元素库 `ele_store/` + `summary/naive_eles` | 串行，`--threads` 不注入 |

> 说明：RECON 的四个阶段（`eledef`/`eleredef`/`edgeredef`/`famdef`）由 `run_recon.sh` 以共享目录 + `tmp`/`tmp2` 软链接编排串联，**单独调用其中间阶段易误用**，故本驱动只暴露 `pipeline`（官方全流程）与 `eledef`（自足的第 1 阶段，官方文档明确支持直接调用）。
> 包内另有 `imagespread`（RECON **1.08 兼容 shim**，新版 `eledef` 已把 imagespread 逻辑合并进来，由 `run_recon.sh` 自动调用），以及 `00README`。

## 用法

```bash
# CLI 直跑（合成/真实 MSP；-o 指定工作目录，产物与其下 summary/ 均写在该目录）
python main.py pipeline seqnames msps.msp -o recon_out
python main.py pipeline seqnames msps.msp -o recon_out --sections 1     # num_sections（旧 1.08 用，新版忽略）
python main.py pipeline seqnames msps.msp                                # 不指定 -o 则在临时目录新建并回显路径

# 仅阶段 1（在目标工作目录下执行；产出 ele_store/ 与 summary/naive_eles）
python main.py eledef seqnames msps.msp --method single -o recon_out
python main.py eledef seqnames msps.msp --method double --cutoff 0.9 -l 3 -o recon_out

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR`）。**RECON 四阶段为串行 C 程序，无并行参数——`--threads` 仅作接口一致保留，不会被注入。**

> ⚠️ **工作目录约定**：RECON 各阶段在**当前工作目录**读写中间文件与 `summary/`；`run_recon.sh` 的 `work_dir` 参数要求目录**已存在**（脚本内 `realpath` 解析）。本驱动在 `-o/--workdir` 下会自动 `mkdir -p` 并 `cd` 到位（输入路径先解析为绝对路径），无需手工建目录。

## 实战示例：从头重复家族识别（all-vs-all MSP → RECON → 家族）

RECON 用于**无参考重复库**的从头分类链路：先把基因组自身比对得到的 MSP 聚类成「元素」，再按相似性图把元素归并为「家族」。以下为原生 CLI 的典型用法；**等价能力由 `native/main.py` 的 `pipeline` / `eledef` 子命令提供**（见上「用法」）。

### 1. 准备 MSP 与序列名清单

RECON 的输入是 MSP 文件与序列名清单（首行为计数，其后每行一个序列名，须**字典序排序**）：

```bash
# MSP 每行一条局部比对：score %iden q_start q_end q_name s_start s_end s_name
head -2 msps.msp
# 009562 98.8 000001 001077 seq-1 000965 002054 seq-1082

# 序列名清单：从 MSP 出现的名字（第 5、8 列）去重排序生成
awk '{print $5; print $8}' msps.msp | sort -u > names.tmp
wc -l < names.tmp | cat - names.tmp > seqnames
rm names.tmp

# 上游另附 MSPCollect.pl（脚本目录），可把 BLAST 输出转换为 MSP 格式
```

### 2. 跑四阶段流水线

```bash
mkdir -p recon_out
run_recon.sh "$(dirname "$(command -v eledef)")" seqnames msps.msp 1 recon_out
# 参数：bin_dir seq_list msp_file [num_sections] [work_dir]
# 产物写在 recon_out/：
ls recon_out/summary/
# eles  families  fam_no  ele_no  naive_eles  ...（其余为中间计数）
```

### 3. 读取家族结果

```bash
# summary/eles：family_index element_index strand sequence start end
head recon_out/summary/eles
# #  fam    ele   dir  sequence    start     end
#      1      2  1       ChrI  2845875  2846523
#      1      4  1       ChrI 10447600 10448327

# summary/families：family_index copy_count unknown
cat recon_out/summary/families
# # fam  cp-no name
# 1 2 unknown

# 取某个家族的全部成员（如家族 1）
awk '$1==1' recon_out/summary/eles
```

> 元素坐标可回表到原基因组做注释/屏蔽；重复家族常作为 `RepeatMasker -lib` 的候选库来源（更完整的建模请走 `modules/repeatmodeler`）。

### 4. 参数说明

| 参数                    | 说明                                                                         |
| --------------------- | -------------------------------------------------------------------------- |
| `<bin_dir>`（run_recon.sh） | 四阶段可执行文件所在目录（本驱动默认取 `run_recon.sh` 所在目录）                                    |
| `<seq_list>`          | 序列名清单（首行计数 + 字典序序列名）                                                       |
| `<msp_file>`          | MSP 比对文件（`score %iden q_start q_end q_name s_start s_end s_name`）             |
| `[num_sections]`      | 仅旧版（1.08）`imagespread` 使用；新版（>=1.09）`eledef` 已合并该逻辑、忽略此值                     |
| `[work_dir]`          | 工作目录（须已存在；产物写此处 `summary/`）                                                 |
| `--method`（eledef）    | 聚类方法 `single`\|`double`（对应官方 usage；默认 `single`）                            |
| `[cutoff]`（eledef）    | 可选聚类 cutoff（官方 usage 的 `[cutoff]`；缺省用内建默认）                                  |
| `-l <level>`          | 日志级别：0=silent 1=error 2=warn 3=info(默认) 4=debug（四阶段通用）                        |
| `-v`（eledef）          | 打印版本后退出（注：bioconda 构建因 CFLAGS 覆盖丢失版本宏，自报 `RECON version unknown`）         |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（镜像内含 `run_recon.sh` 与四阶段程序）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n recon-native -c conda-forge -c bioconda recon=1.10
conda activate recon-native
eledef        # 断言（无参打印 usage：usage: eledef seq_list msp_file single|double [cutoff] [-l level]）
```

> Homebrew：homebrew-core 与 brewsci/bio 均无 `recon` 公式（2026-09-10 核实 formulae.brew.sh 与 `Formula/recon.rb` 均 404）→ 无公式，不登记 brew 安装块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/recon:1.10--hab16a5f_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/recon:1.10--hab16a5f_1 \
    run_recon.sh /usr/local/bin /data/seqnames /data/msps.msp 1 /data/recon_out
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull recon.sif docker://depot.galaxyproject.org/singularity/recon:1.10--hab16a5f_1
apptainer run -B $PWD:/data -H /data recon.sif \
    run_recon.sh /usr/local/bin /data/seqnames /data/msps.msp 1 /data/recon_out
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

RECON 为 **C 源码程序（自带 Makefile）**，官方 GitHub release **无预编译二进制资产**（tag `1.10` 仅源码归档），需本地 `make` 编译（仅需 C 编译器 + make，无第三方库依赖）——**常规使用请优先走上方 Conda 或官方容器**；确需源码路线时拉到用户前缀编译：

```bash
# 源码 tag 归档（解压到用户目录后 make，无需 root）
wget https://github.com/Dfam-consortium/RECON/archive/refs/tags/1.10.tar.gz -P ~/software/
tar zxf ~/software/1.10.tar.gz -C ~/software/          # -> ~/software/RECON-1.10/
cd ~/software/RECON-1.10
make                                                    # bin/ 下生成 eledef/eleredef/edgeredef/famdef + run_recon.sh
echo 'export PATH=$PATH:~/software/RECON-1.10/bin' >> ~/.bashrc && source ~/.bashrc
eledef                                                  # 断言（打印 usage）
```

## 测试

```bash
cd modules/recon/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与参数契约（缺 msp 报错）必跑；
# PATH 含 run_recon.sh/eledef 时追加 eledef usage 轻量探测 + 合成 MSP（2 组同源拷贝）全流程真跑，
#   断言 summary/eles 与 summary/families 生成（真跑失败仅 [WARN] 不阻断）；无二进制时 [SKIP]。
```

## 版本

* recon **1.10**（bioconda::recon=1.10，现行版本；1.08 亦存于该频道）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/recon / depot.galaxyproject.org；本地不再自建容器）

* 上游 GitHub 为 [Dfam-consortium/RECON](https://github.com/Dfam-consortium/RECON)（官网 <http://eddylab.org/software/recon/> 为原始 1.01–1.05 发布页）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（官方缺失说明）

nf-core **无** `modules/nf-core/recon`（2026-09-10 抓取 `https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/recon` 返回 **404**）。Nextflow 场景暂无官方 recon 子模块可登记；若流程需要重复家族识别，请使用 nf-core `repeatmodeler` 子模块（见 `modules/repeatmodeler`，RECON 为其内部组件）。

> 抓取命令：`curl -sO /dev/null -w "%{http_code}\n" https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/recon`

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/recon`（2026-09-10 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/recon` 返回 **404**）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `recon_native` 为兜底，或在项目内按本 README「用法」自建本地规则。

> 抓取命令：`curl -sO /dev/null -w "%{http_code}\n" https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/recon`

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | recon 版本            | 来源                                                                          |
| ------------------ | ------------------- | --------------------------------------------------------------------------- |
| native（官方容器/conda） | **1.10**            | official biocontainer：quay.io/biocontainers/recon:1.10--hab16a5f\_1 / bioconda recon=1.10 |
| nf-core master     | 官方无 recon 子模块       | modules/nf-core/recon 404（2026-09）                                          |
| snakemake-wrappers | 官方无 wrapper         | bio/recon 404（2026-09）                                                       |

> RECON 无官方 nf-core/snakemake 封装：跨引擎迁移时统一以 `recon_native`（官方镜像/conda，1.10）为准；重复建模场景优先走 nf-core `repeatmodeler`。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# recon native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 recon-native.yml 后 mamba env create -f recon-native.yml；
# 在线推荐上方 mamba create 直装命令。recon=1.10 含 run_recon.sh + eledef/eleredef/edgeredef/famdef。
name: recon-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - recon=1.10
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/recon>

* **Docker**：`docker pull quay.io/biocontainers/recon:1.10--hab16a5f_1`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/recon%3A1.10--hab16a5f_1>

* 安装方式（本地）：`mamba create -n recon-native -c conda-forge -c bioconda recon=1.10`

* 上游 GitHub：<https://github.com/Dfam-consortium/RECON>（release tag 1.10，源码归档；`make` 生成 bin/）· 官网：<http://eddylab.org/software/recon/>
