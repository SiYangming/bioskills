# primer3 软件模块（PCR / SSR 引物设计）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 经在线核实均不存在（404，仅说明层登记）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# primer3 / native — primer3_core 引物设计驱动

Primer3（[primer3-org/primer3](https://github.com/primer3-org/primer3)，[primer3.org](https://primer3.org/)）是**通用 PCR / 测序引物设计的开源引擎**：`primer3_core` 从 **stdin 读入 Primer3 设置文本**（每行 `TAG=VALUE`，块尾 `=` 结束；核心键 `SEQUENCE_ID` / `SEQUENCE_TEMPLATE` / `PRIMER_TASK` / `PRIMER_PRODUCT_SIZE_RANGE`），在 **stdout 输出**满足 Tm / GC / 产物大小约束的引物对（`PRIMER_LEFT_0_SEQUENCE` / `PRIMER_RIGHT_0_SEQUENCE` / `PRIMER_PAIR_PRODUCT_SIZE` …）。生物信息教学课件中典型用法是 **MISA 检测 SSR 后由 `misa_primer3.pl` 调用 `primer3_core` 批量设计 SSR 侧翼引物**。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/primer3 / bioconda primer3）提供：

## 能力

| 子命令 | 包装命令 | 作用 | 线程 |
| ---- | ---- | ---- | ---- |
| `design` | `primer3_core < settings`（settings 文件经 stdin 喂入；或 `--template` 等便捷参数组装最小 settings） | Primer3 引物设计：设置文本 → 引物对结果（stdout / `-o` 文件） | ✅ 协议位（primer3_core 单线程，不强加；批量并行用 GNU parallel 拆分） |

## 用法

```bash
# CLI 直跑——方式 A：喂入 settings 文件（教学 p3_settings_file 即此类，等价 primer3_core < p3_settings_file > primer3.out）
python main.py design p3_settings_file -o primer3.out
python main.py design --input p3_settings_file > primer3.out     # 同上（结果走 stdout）

# CLI 直跑——方式 B：便捷参数（无 settings 文件时驱动组装最小 settings 后喂给 primer3_core）
python main.py design --template ATGCCG...TTG --id CL1 --product-min 100 --product-max 300 -o primer3.out

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）；`--extra-args` 可透传 `primer3_core` 原生选项（如 `--strict_tags` / `--io_version=4` 切纯 `TAG=VALUE` 输出便于脚本解析）。

## 实战示例：MISA 检测 SSR → primer3_core 批量设计 SSR 侧翼引物（教学链路）

> 该链路的**组合流程已归档**：[subworkflow/misa_primer3/](../../subworkflow/misa_primer3/misa_primer3.md)（MISA 检测 + Primer3 批量引物设计，
> 含 `misa_primer3.pl` 桥接脚本、Primer3 设置文件生成与 GFF3 输出）；SSR 检测工具本身见 [modules/misa/](../misa/README.md)。

以下为课件教学链路与独立用法；**等价能力由 `native/main.py` 的 `design` 子命令提供**（见上「用法」）。

### 1. 教学链路总览：MISA → misa_primer3.pl → primer3_core

MISA（MicroSAtellite，`misa.pl`）从基因组/EST FASTA 中检测 SSR（`misa.ini` 定义 1-6 bp 基序与最少重复数），产出 `*.misa` 位点表（含基序、重复次数、起止坐标）。随后用 MISA 发行包自带的 Perl 脚本 `misa_primer3.pl` 批量设计每个 SSR 位点的侧翼（flanking）引物：

```bash
# Step 1: MISA 检测 SSR（产出 genome.misa；misa.ini 为基序/重复数阈值配置）
perl misa.pl genome.fasta misa.ini

# Step 2: misa_primer3.pl 批量设计 SSR 侧翼引物（对每个位点提取两侧侧翼序列、
#         生成含 SEQUENCE_ID（位点名）/ SEQUENCE_TEMPLATE（侧翼+SSR）的设置文本 p3_settings_file，
#         再调用 primer3_core 逐位点设计）
perl misa_primer3.pl genome.misa sample_name

# 其内部对每个 SSR 位点的等价核心调用（settings 由 p3_settings_file 提供）：
primer3_core < p3_settings_file > primer3.out
```

`primer3.out` 逐位点包含设计键：`PRIMER_LEFT_0_SEQUENCE`（上游引物）/ `PRIMER_RIGHT_0_SEQUENCE`（下游引物）/ `PRIMER_PAIR_PRODUCT_SIZE`（产物长度）等，可用下方「结果解析」小节提取成表格或 FASTA。

### 2. 独立重现：settings 文件逐位点设计（驱动方式 A）

不依赖 MISA 环境时，可手工构造 settings（一个位点一个文件/块），再批量喂给 `design`：

```bash
# 构造单个位点的 p3 设置文本（模板 = SSR 左侧翼 + SSR + 右侧翼；= 为块结束标记）
cat > CL1.p3settings <<'EOF'
SEQUENCE_ID=CL1
SEQUENCE_TEMPLATE=TCGCATCGTACGATCGTAGATCGTAGCTAGCATCGATCGTAGCTAGCTAGCTAG(AT)18GCTAGCTAGCATCGATCGTAGCTAGCATCGATCGTAGCTAGCATCGATCGATCGTAGCTAGCATCG
PRIMER_TASK=generic
PRIMER_PRODUCT_SIZE_RANGE=100-300
=
EOF

# 等价 primer3_core < CL1.p3settings：经驱动 stdin 喂入、-o 写结果文件
python main.py design CL1.p3settings -o CL1.primer3.out

# 全位点批量（GNU parallel：primer3_core 单线程，按位点并发即可）
for f in *.p3settings; do python main.py design "$f" -o "${f%.p3settings}.primer3.out"; done
```

### 3. 独立重现：--template 便捷参数（驱动方式 B）

无 settings 文件时由驱动自动组装最小 settings（`SEQUENCE_ID` / `SEQUENCE_TEMPLATE` / `PRIMER_TASK=generic` / `PRIMER_PRODUCT_SIZE_RANGE` / `=`），适合快速验证一段序列能否出引物：

```bash
python main.py design --template "$(cat seq.txt)" --id CL1 \
    --product-min 100 --product-max 300 -o primer3.out
```

### 4. 结果解析（primer3.out → 引物表 / FASTA）

```bash
# 提取每对引物（默认返回多对时按 PRIMER_LEFT_N_SEQUENCE / PRIMER_RIGHT_N_SEQUENCE 取 N）
grep -E "^(PRIMER_LEFT|PRIMER_RIGHT)_0_SEQUENCE|^PRIMER_PAIR_0_PRODUCT_SIZE" primer3.out

# 转成 FASTA（教学常见做法：上游引物正向、下游引物反向互补后做 PCR 上机）
awk -F= '/^PRIMER_LEFT_0_SEQUENCE=/{print ">CL1_F"; print $2}
         /^PRIMER_RIGHT_0_SEQUENCE=/{print ">CL1_R"; print $2}' primer3.out
```

> 提示：产物引物特异性可用 NCBI Primer-BLAST 逐条复核（课件教学步骤）；`--extra-args "--strict_tags --io_version=4"` 可让输出变为纯 `TAG=VALUE`，上述 `grep/awk` 解析更稳。

### 5. 参数说明

`design` 子命令（驱动层）参数：

| 参数 | 说明 |
| ---- | ---- |
| `settings_file`（positional）/ `--input` | Primer3 设置文本路径（`TAG=VALUE`，`=` 结尾；与 `--template` 互斥，二选一） |
| `--template` | `SEQUENCE_TEMPLATE` 模板序列（内部空白自动去除并转大写；无 settings 文件时使用） |
| `--id` | `SEQUENCE_ID`（便捷模式默认 `seq`；建议写位点名如 `CL1` 便于结果回溯） |
| `--product-min` / `--product-max` | 产物大小范围（组装 `PRIMER_PRODUCT_SIZE_RANGE`；默认 `100-300`） |
| `-o` / `--output` | 结果写文件（默认 stdout；驱动把捕获的 stdout 写入，等价 `> file`） |
| `--extra-args` | 透传 `primer3_core` 原生选项（如 `--strict_tags`，高级用法，慎用） |
| `--threads` | 协议位：primer3_core 单线程，不强加；批量并行请用 GNU parallel 按位点拆分 |

常用的 Primer3 输入键（写进 settings 文件的高级约束，教学/定制常用）：

| settings 键 | 说明 |
| ---- | ---- |
| `PRIMER_TASK=generic` | 设计 PCR 引物对（默认；也可 `pick_pcr_primers` 等） |
| `PRIMER_PRODUCT_SIZE_RANGE=100-300` | 产物大小范围（可写多行取并集） |
| `PRIMER_NUM_RETURN=5` | 每模板返回引物对数上限（默认 5） |
| `PRIMER_OPT_SIZE / MIN_SIZE / MAX_SIZE` | 引物长度（默认 20 / 18 / 25） |
| `PRIMER_OPT_TM / MIN_TM / MAX_TM` | 引物 Tm（默认 60 / 57 / 63 ℃） |
| `PRIMER_MIN_GC / MAX_GC` | 引物 GC 含量范围 |
| `PRIMER_PICK_ANYWAY=1` | 找不到理想引物时放宽条件返回（教学 SSR 位点常加） |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n primer3-native -c conda-forge -c bioconda primer3=2.6.1
conda activate primer3-native
primer3_core --help < /dev/null   # 断言（打印 primer3_core usage）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 当前 2.6.1，与 meta 登记 2.6.1 一致（brew 一并装入 primer3_core / oligotm / ntdpal / ntthal / primer3_masker 等）
brew install primer3
primer3_core --help < /dev/null   # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/primer3:2.6.1--pl5321h503566f_7
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/primer3:2.6.1--pl5321h503566f_7 \
    primer3_core < /data/p3_settings_file > /data/primer3.out
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull primer3.sif docker://depot.galaxyproject.org/singularity/primer3:2.6.1--pl5321h503566f_7
apptainer exec -B $PWD:/data -H /data primer3.sif primer3_core < /data/p3_settings_file > /data/primer3.out
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

Primer3 官方 release 为**源码归档**（C 程序，无预编译二进制资产）；编译依赖仅标准 C 编译器（`src/` 下 `make` 即可，随包自带 `primer3_config/` 默认参数）：

```bash
wget https://github.com/primer3-org/primer3/archive/refs/tags/v2.6.1.tar.gz -P ~/software/
tar zxf ~/software/v2.6.1.tar.gz -C ~/software/     # -> ~/software/primer3-2.6.1/
cd ~/software/primer3-2.6.1/src
make && make test                                    # 产出 ./primer3_core
echo 'export PATH=$PATH:~/software/primer3-2.6.1/src' >> ~/.bashrc
source ~/.bashrc
primer3_core --help < /dev/null                      # 断言
```

> 亦可在 bioconda 包内直接取用编译好的 `primer3_core`（conda 路径下 `bin/primer3_core`）；教学/常规使用优先上方 Conda 或官方容器。

## 测试

```bash
cd modules/primer3/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema/design --help 契约）必跑；
# PATH 含 primer3_core 时追加真跑最小链路（合成 settings.txt 喂入 + --template 便捷模式，断言 exit 0；
#   输出命中 PRIMER 键作为 [ok] 佐证；真跑失败仅 [WARN] 提示不阻断）；无 primer3_core 时 [SKIP]。
```

## 版本

* primer3 **2.6.1**（bioconda::primer3=2.6.1，现行 build `2.6.1-7`；上游 2019-04 发布 v2.6.1 后长期未 bump，bioconda 多次重建。官方仓库 LICENSE 为 **GPL-2.0**（1991 v2 全文），bioconda 亦记 GPLv2；brew formula 标 `GPL-2.0-or-later AND GPL-3.0-or-later`（源内个别文件），SPDX 以官方主 LICENSE 登记 `GPL-2.0`）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/primer3:2.6.1--pl5321h503566f_7 / depot.galaxyproject.org；本地不再自建容器）

* nf-core / snakemake-wrappers 官方层：**均不存在**（2026-09 在线核实 404，见下「官方实现登记」）

***

## 官方实现登记（nf-core / snakemake-wrappers 均无，不建目录）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 **无** `modules/nf-core/primer3`（2026-09 抓取 `https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/primer3` 返回 404）。Nextflow 场景暂无官方 nf-core 子模块可登记；需要时以 `primer3_native` 为兜底（或自行 `nf modules install` 引入第三方模块）。

### snakemake-wrappers（说明层）

官方 snakemake-wrappers **无** `bio/primer3`（2026-09 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/primer3` 返回 404）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `primer3_native` 为兜底（或参照同库其它模块自建本地规则，`snakemake/` 目录未建）。

## 版本差异声明（native / nf-core / snakemake-wrappers / brew）

| 实现 | primer3 版本 | 来源 |
| ---- | ---- | ---- |
| native（官方容器/conda） | **2.6.1** | official biocontainer：quay.io/biocontainers/primer3:2.6.1--pl5321h503566f\_7 / bioconda primer3=2.6.1 |
| nf-core master | 官方无模块 | modules/nf-core/primer3 404（2026-09） |
| snakemake-wrappers | 官方无 wrapper | bio/primer3 404（2026-09） |
| brew（homebrew-core） | 2.6.1 | 与 meta 登记一致（公式 version 以 formula 为准） |

> 三条路线上游均为 primer3 2.6.1 单一版本（上游多年未 bump），无跨实现 CLI 代际差异；并行设计靠按位点拆分（primer3_core 单线程）。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# primer3 native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 primer3-native.yml 后 mamba env create -f primer3-native.yml；
# 在线推荐上方 mamba create 直装命令。primer3=2.6.1 提供 primer3_core / oligotm / ntdpal / ntthal / primer3_masker。
name: primer3-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - primer3=2.6.1
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/primer3>

* **Docker**：`docker pull quay.io/biocontainers/primer3:2.6.1--pl5321h503566f_7`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/primer3%3A2.6.1--pl5321h503566f_7>

* **Homebrew**：`brew install primer3`（homebrew-core，2.6.1）

* 安装方式（本地）：`mamba create -n primer3-native -c conda-forge -c bioconda primer3=2.6.1`

* 上游 GitHub：<https://github.com/primer3-org/primer3>（v2.6.1 release 为源码归档，无预编译 assets；官方文档 <https://primer3.org/manual.html>）
