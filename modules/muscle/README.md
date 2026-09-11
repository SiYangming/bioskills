# muscle 软件模块（多序列比对）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# muscle / native — 多序列比对驱动

MUSCLE（[drive5.com/muscle](https://www.drive5.com/muscle/) ・ [rcedgar/muscle](https://github.com/rcedgar/muscle)，MUltiple Sequence Comparison by Log-Expectation）是**多序列比对（MSA）工具**：把多条核酸或氨基酸序列**比对为等长序列**（FASTA）。它有一条重要的代际分界线——

* **v3（3.8.x，公共领域）**：2003-04 年的迭代精化算法（draft progressive → improved progressive → refinement），命令行是单文件风格 `muscle -in <fa> -out <aln>`；**旧版 antiSMASH 的比对依赖**，教学课件常安装 **muscle 3.8.31**。
* **v5（5.x，GPL-3.0-only）**：2021 年从零重写，PPP 算法 + Super5 大规模算法，支持对准集成（ensemble）与结构比对（MUSCLE-3D），命令行改为**子命令式** `muscle -align <fa> -output <aln> -threads N`。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/muscle / bioconda muscle）提供，登记 **bioconda 现行版本 5.3**。驱动会**先探测安装版本（v3/v5），再拼对应参数**，因此同一份 `main.py` 既能在教学 v3（3.8.31 / 3.8.1551）上跑，也能在现代 v5（5.1–5.3）上跑——**依赖方文档只需指向本模块「环境安装」小节即可复用其安装方式**。

## 能力

| 子命令    | 包装命令（按探测版本自适应）                                                       | 作用                                        | 线程                |
| ------ | --------------------------------------------------------------------- | ----------------------------------------- | ----------------- |
| `align` | v3：`muscle -in <fa> -out <aln>`；v5：`muscle -align <fa> -output <aln> -threads N` | 多序列比对：输入 FASTA → **等长比对 FASTA**（缺省 stdout，`-o` 写文件） | ✅ v5 默认 8（注入 `-threads`）；v3 单线程 |

## 用法

```bash
# CLI 直跑（驱动自动探测 v3/v5 并映射 -in/-out 或 -align/-output；教学/常规链路）
python main.py align input.fa -o aligned.fa --threads 8        # 写文件（v3 忽略 --threads）
python main.py align input.fa --threads 8                       # 缺省 stdout（v5 由驱动临时文件承接后回显）
python main.py align -i input.fa -o aligned.fa                  # -i/--input 与位置参数等价
python main.py align --in input.fa -o aligned.fa                # --in/--align 亦作输入别名（对齐原生命名）

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。

> 💡 **版本探测注**：驱动先跑 `muscle -version`（回退 `--version`）判据——输出含 `MUSCLE v3.`（如 `MUSCLE v3.8.1551 by Robert C. Edgar`）判为 **v3**；含 `5.x`（如 `muscle 5.3.osxarm64 []`）判为 **v5**；两者皆不匹配时回退按 v5（native 登记版本）构建。**v3 不接受 `-threads`（会报 `Invalid command line option "threads"`，故驱动对 v3 不注入线程）**；**v5 的 `-output` 必填（缺省会报错退出），故驱动在未给 `-o` 时用临时文件承接后退回 stdout 语义**。`--extra-args` 为高级透传（v5 的 `-super5` 等模式选项会替换 `-align` 语义，慎用）。

> 💡 **依赖语境**：MUSCLE 是 **旧版 antiSMASH 的序列比对依赖**（MUSCLE v3 代际）；这类流程文档的安装说明指向本模块「环境安装」即可，本模块不承载依赖方的其它说明。另一多序列比对工具见 `modules/mafft`。

## 版本差异说明（v3 与 v5 CLI 完全不同，重要）

MUSCLE **v3（教学 3.8.31 / 3.8.1551）与 v5（5.1–5.3）命令行完全不兼容**，是两套独立程序：

| 维度             | MUSCLE v3（教学 3.8.31 / 3.8.1551）                    | MUSCLE v5（native 登记 5.3）                                |
| -------------- | ------------------------------------------------ | ------------------------------------------------------ |
| 比对命令           | `muscle -in <fa> -out <aln>`                     | `muscle -align <fa> -output <aln>`                     |
| 大规模算法          | 无（单机算法；另有 `-maxiters`/`-diags` 等调参）              | `muscle -super5 <fa> -output <aln>`（Super5 算法）         |
| 多线程            | 单线程（**无 `-threads`，传入即报错**）                       | `-threads N`（默认 CPU 核数，>20 核时为 20）                      |
| 输出文件选项         | `-out`（FASTA，缺省 stdout）；另有 `-fastaout/-clwout/-msfout/-phyiout/-phyout/-htmlout` | `-output`（**必填**）；对准集成写 EFA（`-stratified`/`-diversified` 等） |
| 版本串            | `MUSCLE v3.8.1551 by Robert C. Edgar`            | `muscle 5.3.osxarm64 []`                               |
| 许可             | 公共领域（public domain）                              | GPL-3.0-only                                           |

> 本模块 `main.py` **自动兼容两代**：教学课件里的 `muscle -in x.fa -out x.aln` 与现代 `muscle -align x.fa -output x.aln` 均可由 `python main.py align <fa> -o <aln>` 统一驱动。

## 实战示例：多序列比对（v3 / v5 两种原生命令对照）

以下为原生 CLI 的典型用法（教学 v3 与现代 v5 对照）；**等价能力由 `native/main.py` 的 `align` 子命令提供**（见上「用法」）。

### 1. 基础比对（教学 v3 vs 现代 v5）

```bash
mkdir -p muscle_out && cd muscle_out

# —— v3（教学课件 muscle 3.8.31，单线程）——
muscle -in ../input.fa -out aligned_v3.fa            # 等价教学命令

# —— v5（bioconda 现行 5.3，多线程）——
muscle -align ../input.fa -output aligned_v5.fa -threads 8

# —— 驱动等价写法（自动探测版本，同一命令两代通用）——
python ../modules/muscle/native/main.py align ../input.fa -o aligned.fa --threads 8
```

### 2. 大规模序列集（v5 专属 Super5）

```bash
# v5 的 Super5 算法适合上千至数千条序列；v3 无等价命令
muscle -super5 big_input.fa -output big_aligned.fa -threads 8
# 驱动透传：python ../modules/muscle/native/main.py align big_input.fa -o big_aligned.fa --extra-args "-super5"
```

### 3. 批量多样本比对（每样本一个结果文件，按版本分支）

```bash
for fa in ../seqsets/*.fa; do
    name=$(basename "$fa" .fa)
    if muscle -version 2>&1 | grep -qiE 'muscle +v?3\.'; then
        muscle -in "$fa" -out ${name}.aligned.fa                 # v3
    else
        muscle -align "$fa" -output ${name}.aligned.fa -threads 8  # v5
    fi
done
# 产物：<name>.aligned.fa（等长比对，可直接送入进化树构建/一致性分析）
```

### 4. 参数说明

| 参数                             | 说明                                                                       |
| ------------------------------ | ------------------------------------------------------------------------ |
| `-in`（v3）/ `-align`（v5）        | 输入序列 FASTA（多序列核酸/氨基酸）；驱动由 `-i/--input`（位置参数亦可）统一映射                      |
| `-out`（v3）/ `-output`（v5）      | 比对结果输出文件（等长 FASTA）；v3 缺省 stdout，v5 必填 → 驱动由 `-o` 统一映射，缺省走临时文件回显 stdout |
| `-threads N`（仅 v5）             | CPU 线程数（驱动由 `--threads` 注入，默认 8；v3 单线程无此选项）                                |
| `-super5`（仅 v5）                | 大规模序列集的 Super5 算法（经 `--extra-args` 透传；会替换 `-align` 语义）                     |
| `-maxiters` / `-diags`（v3）、`-perturb`/`-stratified`/`-diversified`（v5 集成） | 精度/速度调参，经 `--extra-args` 透传（高级用法，慎用）                       |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n muscle-native -c conda-forge -c bioconda muscle=5.3
conda activate muscle-native
muscle -version      # 断言（v5；输出形如 "muscle 5.3..."）

# 教学旧版 v3（如需复现课件/旧版 antiSMASH 依赖）：
# mamba create -n muscle3 -c conda-forge -c bioconda muscle=3.8.31   # 或 muscle=3.8.1551
# conda activate muscle3 && muscle -version                            # "MUSCLE v3.8.1551 ..."
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
# brew 版本 5.3，与 meta 登记 5.3 一致
brew tap brewsci/bio     # 首次使用需要
brew install muscle
muscle -version          # 断言（v5）
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/muscle:5.3--h9948957_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/muscle:5.3--h9948957_3 \
    muscle -align /data/input.fa -output /data/aligned.fa -threads 8

# 教学 v3 镜像（旧版 antiSMASH 依赖代际）：
# docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
#     quay.io/biocontainers/muscle:3.8.1551--h9948957_9 \
#     muscle -in /data/input.fa -out /data/aligned.fa
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull muscle.sif docker://depot.galaxyproject.org/singularity/muscle:5.3--h9948957_3
apptainer run -B $PWD:/data -H /data muscle.sif muscle -align /data/input.fa -output /data/aligned.fa -threads 8
```

### 4. 二进制包安装（官方 release，自包含单文件）

MUSCLE v5 官方发布**自包含单文件二进制**（无依赖、无安装器）；v3 官网亦提供预编译二进制。解压/拷到用户前缀（免 root，禁 `/opt/biosoft`、`/home/train`）后即可用：

```bash
# v5（bioconda 登记 5.3 对应官方 release tag v5.3；按平台选 linux / osx / win 资产）
mkdir -p ~/software && cd ~/software
wget https://github.com/rcedgar/muscle/releases/download/v5.3/muscle5.3_linux64 -O ~/software/muscle-5.3
chmod +x ~/software/muscle-5.3
echo 'export PATH=$PATH:~/software' >> ~/.bashrc && source ~/.bashrc
muscle -version      # 断言（v5）

# v3（教学 3.8.31 / 3.8.1551）官方下载页：https://drive5.com/muscle/downloads_v3.htm
#   源码归档：https://drive5.com/muscle/muscle_src_3.8.1551.tar.gz（需自行 make 编译）
```

> 官网下载页：v5 <https://github.com/rcedgar/muscle/releases> ・ v3 <https://drive5.com/muscle/downloads_v3.htm>（版本与 `software_versions` 对齐 v5.3）。

## 测试

```bash
cd modules/muscle/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ 参数契约（align --help）必跑；
# PATH 含 muscle 时按 --version 探测的版本走 v3/v5 分支追加真跑最小链路
#   （合成多序列 → align -o 断言 6 条等长比对 + stdout/-i 模式；真跑失败仅 [WARN] 提示不阻断）；无 muscle 时 [SKIP]。
```

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/muscle/` **存在**（单模块**扁平结构**：`environment.yml` + `main.nf` + `meta.yml` + `tests/`，无子目录；2026-09 在线核实，以官方在线目录为准），**pin 的是 v3**：

| 模块       | environment.yml 关键 pin      | 容器                                                | 作用（据 nf-core meta）                     |
| -------- | -------------------------- | ------------------------------------------------- | -------------------------------------- |
| `muscle` | bioconda::muscle=3.8.1551  | quay.io/biocontainers/muscle:3.8.1551--h7d875b9_6 | 输入 fasta → 等长比对（v3 CLI：`-in`/`-fastaout`/`-clwout`/`-loga`） |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core muscle`（安装到项目自身 `modules/nf-core/`，
> 不要直接 include 本仓库文件），随后：
>
> ```nextflow
> include { MUSCLE } from '../modules/nf-core/muscle/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/muscle | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方存在，扁平 wrapper）

官方 snakemake-wrappers **有** `bio/muscle`（**扁平 wrapper**：`wrapper.py` + `environment.yaml` + `environment.linux-64.pin.txt` + `meta.yaml` + `test/`，无子目录；2026-09 在线核实，v9.17.1 tag 含该 wrapper；`environment.yaml` **pin `muscle=5.3`（v5）**）。params 契约：`super5`（布尔，True 时改用 `-super5` 算法）+ `extra`；`input.fasta` → `output.alignment`（v5 CLI：`muscle -threads N -align <fa> -output <aln>`）。可直接粘贴的规则示例：

```python
rule muscle:
    input:
        fasta="input.fa"
    output:
        alignment="aligned.fa",
    params:
        super5=False,        # True → 改用 -super5 算法（大规模序列集）
        extra="",            # 如 "-perturb 3 -perm abc"
    threads: 8
    wrapper: "v9.17.1/bio/muscle"
```

> ⚠️ 运行时靠 Snakemake 在线解析 `wrapper:` 句柄（`v9.17.1/bio/muscle`），不要把本地示例当 wrapper_path；本模块未建 `snakemake/` 目录。

## 版本差异声明（native / nf-core / snakemake-wrappers / brew）

| 实现                    | muscle 版本     | CLI 代际           | 来源                                                                                                    |
| --------------------- | ------------- | ---------------- | ----------------------------------------------------------------------------------------------------- |
| native（官方容器/conda）     | **5.3**       | v5（`-align/-output`） | official biocontainer：quay.io/biocontainers/muscle:5.3--h9948957\_3 / bioconda muscle=5.3                |
| native 亦兼容（教学旧版，可选）     | 3.8.31 / 3.8.1551 | v3（`-in/-out`）   | bioconda muscle=3.8.31 / 3.8.1551（v3 公共领域；教学 3.8.31）                                                   |
| nf-core master        | 3.8.1551      | v3（`-in/-fastaout`） | bioconda::muscle=3.8.1551（modules/nf-core/muscle/environment.yml，扁平模块）                                  |
| snakemake-wrappers    | 5.3           | v5（`-align/-output`） | bioconda muscle=5.3（bio/muscle/environment.yaml，扁平 wrapper；v9.17.1 tag）                                 |
| brew（brewsci/bio tap） | 5.3           | v5               | brewsci/bio `muscle` 公式（`brew tap brewsci/bio && brew install muscle`；license GPL-3.0-only）              |

> ⚠️ **v3 与 v5 CLI 不兼容（重要，见上「版本差异说明」）**：`-in/-out`（v3）↔ `-align/-output/-threads`（v5）；v3 单线程、v3 可省 -out 写 stdout，v5 的 -output 必填。**本模块 `main.py` 自动探测并适配两代**，故 native 一路可同时覆盖教学 v3 与 nf-core/brew 的 v3/v5 选择；跨引擎迁移时请注意 nf-core 子模块 pin 的是 v3、snakemake-wrappers pin 的是 v5——不同环境可共存，切换后请按对应代际撰写采样命令。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# muscle native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 muscle-native.yml 后 mamba env create -f muscle-native.yml；
# 在线推荐上方 mamba create 直装命令。教学 v3 可把 muscle=5.3 换成 3.8.31 或 3.8.1551。
name: muscle-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - muscle=5.3
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/muscle>（现行 5.3；亦含 3.8.31 / 3.8.1551）

* **Docker**：`docker pull quay.io/biocontainers/muscle:5.3--h9948957_3`（bioconda 自动构建；教学 v3 为 `muscle:3.8.1551--h9948957_9`；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/muscle%3A5.3--h9948957_3>

* 安装方式（本地）：`mamba create -n muscle-native -c conda-forge -c bioconda muscle=5.3`（或 `brew tap brewsci/bio && brew install muscle`）

* 上游：v3 官网 <https://www.drive5.com/muscle/>（v3 手册 <https://www.drive5.com/muscle/manual/>、v3 二进制 <https://drive5.com/muscle/downloads_v3.htm>）· v5 仓库 <https://github.com/rcedgar/muscle>（v5 手册 <https://drive5.com/muscle5/manual/>）

## 版本

* muscle **5.3**（bioconda::muscle=5.3，linux-64 build `h9948957_3`，2025-07；conda_platforms linux-64 / linux-aarch64 / osx-64 / osx-arm64）

* 许可：**v5 = GPL-3.0-only**（rcedgar/muscle / brewsci/bio 公式）；**v3 = 公共领域**（drive5.com/muscle/license.htm）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/muscle / depot.galaxyproject.org；本地不再自建容器）

* 教学旧版：bioconda muscle=**3.8.31**（2015）与 **3.8.1551**（最新 build `h9948957_9`）仍可安装（v3 CLI，见下「版本差异声明」）

* nf-core 官方模块 pin muscle=**3.8.1551**（v3），snakemake-wrappers pin muscle=**5.3**（v5）；brew（brewsci/bio）为 5.3

***

## 官方实现登记与差异（汇总）

* Nextflow：官方存在 `modules/nf-core/muscle`（扁平，pin 3.8.1551，v3 CLI）→ 不建目录，`nf modules install` 安装（见上「官方实现登记」）。

* Snakemake：官方存在 `bio/muscle`（扁平 wrapper，pin 5.3，v5 CLI，v9.17.1）→ 不建目录，`wrapper:` 句柄运行时解析（见上「官方实现登记」）。

* 版本/CLI 三方差异逐条见上「版本差异声明」；native 一路由 `main.py` 版本探测自动兼容 v3/v5。
