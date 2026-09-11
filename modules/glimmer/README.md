# glimmer 软件模块（Glimmer3 · 原核生物基因预测）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（均无，不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。
>
> 官网：<http://ccb.jhu.edu/software/glimmer/> ｜ 别名：**glimmer3**（Glimmer 3.02）

***

## native 实现

# glimmer / native — Glimmer3 原核基因预测驱动

Glimmer3（**G**ene **L**ocator and **I**nterpolated **M**arkov **M**odelER，别名 glimmer3）是**原核生物基因组基因预测系统**：先用长 ORF 训练集构建**插值上下文模型（ICM）**，再据 ICM 预测编码基因，输出每条基因的坐标与打分（`<tag>.predict` / `<tag>.detail`）。它**不是一步式流程**——上游以「一组命令行程序」发布，标准教学链路为**四步**：

```
long-orfs  →  extract  →  build-icm  →  glimmer3
 (选训练ORF)  (提训练序列)   (建ICM模型)   (预测基因)
```

Glimmer3 是**旧版 antiSMASH 的基因预测依赖**；现代 antiSMASH 已改用 prodigal / glimmerhmm（见文末「依赖语境」）。上游 3.02 为**最终版本**（2013 起停更）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/glimmer / bioconda glimmer）提供：

## 能力

| 子命令         | 包装命令（官方 usage）                                              | 作用                                   | 线程            |
| ----------- | ----------------------------------------------------------- | ------------------------------------ | ------------- |
| `long_orfs` | `long-orfs [options] <sequence-file> <output-file>`         | 在基因组 FASTA 中挑选长且不重叠的 ORF → 训练集坐标（第 1 步） | ⛔ 单线程（`--threads` 仅协议位） |
| `build_icm` | `build-icm [options] output_file < input-file`              | 从训练序列（stdin）构建插值上下文模型 ICM（第 3 步）      | ⛔ 单线程（`--threads` 仅协议位） |
| `glimmer3`  | `glimmer3 [options] <sequence-file> <icm-file> <tag>`       | 用 ICM 在基因组中预测基因 → `<tag>.predict` / `<tag>.detail`（第 4 步） | ⛔ 单线程（`--threads` 仅协议位） |

> 💡 教学链路第 2 步 `extract`（`extract [options] <sequence-file> <coords>` → stdout 多序列 FASTA）为**同包原生程序**，本驱动未单列子命令；`longorfs_coords` 坐标文件可直接交给 `extract`（见「实战示例」）。
>
> 💡 包内实际二进制清单（按 glimmer302b 源码 `src/{Glimmer,Util,ICM}/Makefile` 的 `PROGS` 核实）：`glimmer3`、`long-orfs`、`build-icm`、`extract`、`multi-extract`、`anomaly`、`test`、`entropy-profile`、`entropy-score`、`start-codon-distrib`、`uncovered`、`window-acgt`、`build-fixed`、`score-fixed`，另附 `g3-from-scratch.csh` / `g3-from-training.csh` / `g3-iterated.csh` 等脚本。

## 用法

```bash
# 1) long-orfs：结果 → tag.longorfs（-n 去表头；-t 1.15 熵距离截断，官方脚本默认参数）
python main.py long_orfs --sequence genome.fna -o tag.longorfs -n -t 1.15

# 2) extract（同包原生程序，非本驱动子命令）：坐标 → 训练序列多 FASTA
extract -t genome.fna tag.longorfs > tag.train

# 3) build-icm：训练序列（stdin 由驱动重定向）→ ICM 模型（-r 用反向序列建模，官方脚本默认）
python main.py build_icm tag.train -o tag.icm -r

# 4) glimmer3：基因组 + ICM → tag.predict / tag.detail（-o50 -g110 -t30 为官方脚本默认选项）
python main.py glimmer3 genome.fna tag.icm -o tag --max-olap 50 -g 110 -t 30

# 只打印将执行的命令行（不真跑，可用于核查/调试）
python main.py glimmer3 genome.fna tag.icm -o tag --dry-run

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量；Glimmer3 各程序**单线程**，`--threads` 仅作协议位、不注入命令行）。

> 💡 **参数命名注**：驱动层 `-o/--output` 表示**主产物**（坐标文件 / ICM 模型 / 输出前缀 `<tag>`）；`long-orfs`、`glimmer3` 原生的 `-o`（最大允许重叠长度）改由 `--max-olap` 暴露。

## 实战示例：原核基因组基因预测（教学四步链）

Glimmer3 是原核基因预测的经典工具（与 prodigal / GeneMark 并列，早期 NCBI 注释常同时给出三者结果）。它以**基因样**的长 ORF 自助训练 ICM，无需外部训练集即可预测单个基因组。以下为原生 CLI 的典型批量用法；**等价能力由 `native/main.py` 的 `long_orfs` / `build_icm` / `glimmer3` 子命令提供**（`extract` 为同包原生程序，见下）。

### 1. （可选）把多序列基因组并成单序列

`long-orfs` 以「单条序列」为输入，多 contig 基因组需先拼接（去掉 `>` 行连成一整条）：

```bash
mkdir -p glimmer_out && cd glimmer_out
sed -e '/>/d' ../genome.fasta | tr -d '\n' | awk 'BEGIN{print ">genome"}{print}' > genome.fna
```

### 2. 四步链：long-orfs → extract → build-icm → glimmer3

```bash
# 第 1 步：挑长而且不重叠的 ORF 作为训练集（-n 去表头；-t 1.15 熵距离截断）
long-orfs -n -t 1.15 genome.fna tag.longorfs
# 第 2 步：按坐标提取训练序列（-t 去掉终止密码子；多序列 FASTA 走 stdout）
extract -t genome.fna tag.longorfs > tag.train
# 第 3 步：从训练序列构建 ICM 模型（-r 用反向序列建模，官方脚本默认）
build-icm -r tag.icm < tag.train
# 第 4 步：用 ICM 预测基因 → tag.predict / tag.detail
glimmer3 -o50 -g110 -t30 genome.fna tag.icm tag
```

### 3. 批量分析多个基因组（bash 循环）

```bash
for fa in ../genomes/*.fasta; do
    name=$(basename "$fa" .fasta)
    sed -e '/>/d' "$fa" | tr -d '\n' | awk 'BEGIN{print ">genome"}{print}' > ${name}.fna
    long-orfs -n -t 1.15 ${name}.fna ${name}.longorfs
    extract -t ${name}.fna ${name}.longorfs > ${name}.train
    build-icm -r ${name}.icm < ${name}.train
    glimmer3 -o50 -g110 -t30 ${name}.fna ${name}.icm ${name}
done
# 结果解读：<name>.predict 为预测基因坐标（<orfID> <start> <stop> <frame> <score>）；
#           <name>.detail 为打分细节；下游可据坐标从基因组提取 CDS 并翻译蛋白
```

### 4. 参数说明

| 参数                    | 所属程序        | 说明                                                                 |
| --------------------- | ----------- | ------------------------------------------------------------------ |
| `-sequence` / `--sequence` | long_orfs | 输入基因组 FASTA（映射 long-orfs 的 `<sequence-file>` 位置参数）                 |
| `-o` / `--output`（驱动）  | 全部          | 主产物：long_orfs 坐标文件 / build_icm 的 ICM / glimmer3 的输出前缀 `<tag>`      |
| `train`（位置参数）        | build_icm   | 训练序列 FASTA（由 `extract` 产出；驱动重定向到 build-icm 的 stdin）               |
| `genome` / `icm`（位置参数） | glimmer3    | 输入基因组 FASTA / ICM 模型文件（对应 `<sequence-file>` / `<icm-file>`）        |
| `-n` / `--no-header`  | long_orfs   | 输出不含表头等说明（long-orfs `-n`）                                          |
| `-t` / `--cutoff`     | long_orfs   | 熵距离截断（long-orfs `-t`，官方脚本常用 1.15）                                  |
| `-g` / `--min-len`    | long_orfs   | 只考虑长度 ≥ n 的 ORF（long-orfs `-g`）                                     |
| `-r` / `--reverse`    | build_icm   | 用反向序列构建模型（build-icm `-r`，官方脚本默认）                                 |
| `-g` / `--gene-len`   | glimmer3    | 最小基因长度（glimmer3 `-g`，官方脚本常用 110）                                  |
| `-t` / `--threshold`  | glimmer3    | 判定为基因的分数阈值（glimmer3 `-t`，官方脚本常用 30）                               |
| `--max-olap`          | long_orfs / glimmer3 | 最大允许重叠长度（原生 `-o`，官方脚本常用 50；驱动 `-o` 保留给 `--output`）              |
| `-l` / `--linear`     | long_orfs / glimmer3 | 假定线性基因组（不做环形 wraparound）                                           |
| `-z` / `--trans-table` | long_orfs / glimmer3 | 终止密码子所用的 Genbank 翻译表编号（默认 11）                                      |
| `--extra-args`        | 全部          | 透传其余原生参数（如 long_orfs 的 `-E`/`-i`、glimmer3 的 `-b`/`-A`/`-Z` 等，高级用法） |

> 💡 `long-orfs -t`（熵距离截断）与 `glimmer3 -t`（打分阈值）**含义不同、取值量级不同**，注意区分。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。**本地源码安装见 §4**（注意：官方源码包解压后 `bin/` 为空，必须先编译，否则没有可执行程序）。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n glimmer -c conda-forge -c bioconda glimmer=3.02
conda activate glimmer
glimmer3            # 无参数时打印 usage（程序无 --version；在 PATH 即安装成功）
long-orfs           # 同上
```

> 💡 **Homebrew：无官方公式**（2026-09 核实）——homebrew-core 无 `glimmer`（`formulae.brew.sh` API 404），`brewsci/bio` 亦无 `glimmer`（仅有 `glimmerhmm`）；旧 `homebrew-science/glimmer3` 配方已随该 tap 归档、不再维护，故本模块**不登记 brew 块**。macOS 请走上方 conda。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/glimmer:3.02--h87f3376_6
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/glimmer:3.02--h87f3376_6 \
    long-orfs -n -t 1.15 /data/genome.fna /data/tag.longorfs
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/glimmer:3.02--h87f3376_6 \
    glimmer3 -o50 -g110 -t30 /data/genome.fna /data/tag.icm /data/tag
```

> ⚠️ `build-icm` 从 **stdin** 读训练序列，容器内需自行重定向，如
> `docker run --rm -i -u $(id -u):$(id -g) -v $PWD:/data -w /data quay.io/biocontainers/glimmer:3.02--h87f3376_6 build-icm -r /data/tag.icm < tag.train`。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull glimmer.sif docker://depot.galaxyproject.org/singularity/glimmer:3.02--h87f3376_6
apptainer run -B $PWD:/data -H /data glimmer.sif \
    long-orfs -n -t 1.15 /data/genome.fna /data/tag.longorfs
apptainer run -B $PWD:/data -H /data glimmer.sif \
    glimmer3 -o50 -g110 -t30 /data/genome.fna /data/tag.icm /data/tag
```

### 4. 官方源码编译（官方源码包，**bin/ 为空，必须编译**）

**官网**：[http://ccb.jhu.edu/software/glimmer/](http://ccb.jhu.edu/software/glimmer/)

Glimmer3 官方**只发源码包** `glimmer302b.tar.gz`（无预编译二进制资产）。⚠️ **解压后 `bin/` 是空目录**（实测：官方 tar 内 `glimmer3.02/bin/` 文件数 = 0）——可执行文件全部由 `src/` 编译产出（`src/{Common,Glimmer,ICM,Util}` → `obj/` → `lib/` → `bin/`），**所以只解压不编译会没有程序可用**。编译到**用户前缀**（免 root）：

```bash
# 1) 下载官方源码包（.edu 站点偶有 TLS 老证书问题，失败时用 curl -kL 或换 conda/容器）
wget https://ccb.jhu.edu/software/glimmer/glimmer302b.tar.gz -P ~/software/
tar zxf ~/software/glimmer302b.tar.gz -C ~/software/     # -> ~/software/glimmer3.02/
cd ~/software/glimmer3.02/src

# 2) 编译（关键：现代工具链需覆盖 CXXDEFS）
make CXXDEFS= -j4     # 见下方「为什么要 CXXDEFS=」
# 产物：../bin/ 下 14 个程序

# 3) 加入 PATH 并自检
echo 'export PATH=$PATH:~/software/glimmer3.02/bin:~/software/glimmer3.02/scripts' >> ~/.bashrc
source ~/.bashrc
ls ~/software/glimmer3.02/bin | wc -l    # 断言：14
glimmer3  2>&1 | head -2                 # 打印 "USAGE: glimmer3 ..." 即成功
long-orfs 2>&1 | head -2                 # 打印 "USAGE: long-orfs ..."
```

**为什么要 `CXXDEFS=`**：`src/c_make.gen` 里写死了 `CXXDEFS = -D__cplusplus`（2006 年代写法）。该宏与**现代 libc++/libstdc++ 头文件冲突**，直接 `make` 会报 `error: cannot combine with previous 'char16_t' declaration specifier`（头文件内 `__config` 处）等错误并以 `Error 1` 中断；在命令行覆盖为空（`make CXXDEFS=`）即可正常编译（**macOS Apple clang 与现代 GCC 均实测通过**，2026-09；产出 14 个程序，四步链 `long-orfs → extract → build-icm → glimmer3` 端到端跑通）。

```bash
# 等价做法：改 Makefile 而不是传参（二选一）
perl -p -i -e 's/^CXXDEFS.*=.*-D__cplusplus/CXXDEFS =/' src/c_make.gen && cd src && make -j4
```

> 💡 **课件旧路线（CentOS + GCC 4.4.3 时代）**：当时报错源于同类 K&R/新版 GCC 兼容问题，课件用补丁解决——`cd ~/software/glimmer3.02 && patch -p1 < ~/software/Allow-glimmer-to-compile-on-g-4.4.3.patch && cd src && make -j 4`。**该补丁文件为课件私有产物（无公开下载地址）**，现代环境优先用上面的 `make CXXDEFS=`（原因同源，无需补丁）；若你手上正好有该补丁，两种方式都可行。
>
> 💡 `elph` 仅 `g3-iterated.csh` 等脚本需要，**上面四步链不需要**；`scripts/`（`g3-from-scratch.csh` / `g3-from-training.csh` / `g3-iterated.csh`）也一并加入 PATH 可省事。
>
> 💡 教学/常规使用**优先走上方 Conda 或官方容器**（已由 bioconda 编译好，省去本地构建）；仅在无容器/无 conda 或需完全本地化时用本节源码编译。

## 测试

```bash
cd modules/glimmer/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：
#   自省（--list-commands/--schema）+ 子命令 --help 契约 + --dry-run 命令行构造断言（必跑）；
#   PATH 含 long-orfs 时追加教学链路真跑（long-orfs 小链路 → extract → build-icm → glimmer3；
#     后续步骤失败仅 [WARN] 不阻断）；无 glimmer 时 [SKIP]。
```

## 版本

* glimmer **3.02**（bioconda::glimmer=3.02，build `h87f3376_6`；上游源码包 `glimmer302b.tar.gz`，**最终版本**，2013 起停更，bioconda 2015 年入库、2022 年最后重建）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/glimmer / depot.galaxyproject.org；本地不再自建容器）

* License：**Artistic-1.0**（包内 LICENSE 为经典 Artistic License；bioconda recipe 记为 `Custom`，`license_file: LICENSE`）

* 官方已**无** nf-core 模块、**无** snakemake-wrappers（均 404，见下）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow）——官方无

nf-core 官方 **无** `modules/nf-core/glimmer`（2026-09 在线核实，`.../modules/nf-core/glimmer` 返回 404）。Nextflow 场景暂无官方模块可登记；需要时以 `glimmer_native` 为兜底（在流程内 `shell:`/`script:` 直接调 `long-orfs` / `build-icm` / `glimmer3`，或 `run` 调本模块 `main.py`）。

> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/glimmer`

### snakemake-wrappers ——官方无

官方 snakemake-wrappers **无** `bio/glimmer`（2026-09 在线核实，返回 404）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `glimmer_native` 为兜底，或在本模块 `native/` 基础上自建本地 `snakemake/` 规则。

> 抓取命令：`curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/glimmer`

## 版本差异声明（native / nf-core / snakemake-wrappers）

| 实现                 | glimmer 版本        | 来源                                                                    |
| ------------------ | ----------------- | --------------------------------------------------------------------- |
| native（官方容器/conda） | **3.02**          | official biocontainer：quay.io/biocontainers/glimmer:3.02--h87f3376\_6 / bioconda glimmer=3.02 |
| nf-core master     | 官方无               | modules/nf-core/glimmer 404（2026-09）                                   |
| snakemake-wrappers | 官方无               | bio/glimmer 404（2026-09）                                               |
| brew               | 官方无               | homebrew-core 404 / brewsci/bio 无 glimmer（2026-09）                      |

> Glimmer3 上游已停更，三条路线（native/conda/官方容器）版本一致，均为 3.02。

***

## 依赖语境（旧版 antiSMASH 的基因预测依赖）

* Glimmer3 是**旧版 antiSMASH 的基因预测依赖**（早期 antiSMASH 在细菌模式下用 Glimmer3 找基因）；**现代 antiSMASH（v7/v8）已改用 prodigal（细菌默认）/ glimmerhmm（真菌可选）**，通过 `--genefinding-tool` 选择——需要现代 antiSMASH 基因预测时见 `modules/antismash`。
* glimmer 家族另有基于**广义隐马尔可夫模型（GHMM）** 的真核/真菌基因预测器 **GlimmerHMM**（与 Glimmer3 同源不同物）：见 `modules/glimmerhmm`。
* Glimmer3 亦常与 prodigal / GeneMark 并列为原核基因预测教学对照工具。

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# glimmer native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 glimmer-native.yml 后 mamba env create -f glimmer-native.yml；
# 在线推荐上方 mamba create 直装命令。
name: glimmer-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - glimmer=3.02
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/glimmer>

* **Docker**：`docker pull quay.io/biocontainers/glimmer:3.02--h87f3376_6`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/glimmer%3A3.02--h87f3376_6>

* 安装方式（本地）：`mamba create -n glimmer -c conda-forge -c bioconda glimmer=3.02`

* 上游官网/源码：<http://ccb.jhu.edu/software/glimmer/>（源码包 `glimmer302b.tar.gz`，无预编译资产）
