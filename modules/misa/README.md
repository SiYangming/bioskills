# misa 软件模块（SSR / 微卫星检测）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 经在线核实均不存在（404，仅说明层登记）。安装方式见「环境安装」节，容器与官方源码包信息记录于文末。
>
> SSR 侧翼**引物设计**（Primer3）不在本模块内 —— 见组合流程 [subworkflow/misa_primer3/](../../subworkflow/misa_primer3/misa_primer3.md)（MISA + Primer3 SSR 检测与引物设计）。

***

## 官方登记（不建目录，仅说明 + 引用）

| 官方渠道 | 核实结果（2026-09） | 处理 |
| ---- | ---- | ---- |
| bioconda | **无** `misa` 包（`api.anaconda.org/package/bioconda/misa` → 404 `"misa" could not be found`；`misa-web` / `misa-tools` 等别名同 404） | 不登记 conda 包，走自建兜底 |
| quay.io/biocontainers | **无**（quay API 401 = 仓库不存在；对照 `fastuniq` 200） | 无官方镜像 |
| depot.galaxyproject.org | **无**预构建 sif | 无官方镜像 |
| brew（homebrew-core / brewsci/bio） | **无** `misa` 公式（`formulae.brew.sh/api/formula/misa.json` → 404） | README 不写 brew 块 |
| nf-core modules | **无** `modules/nf-core/misa`（404） | 不建 `nextflow/`，Nextflow 场景以 `misa_native` 兜底 |
| snakemake-wrappers | **无** `bio/misa`（404） | 不建 `snakemake/`，Snakemake 场景以 `misa_native` 兜底 |

> 官方发布物只有源码包：<https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip>（v2.1，2020-08-25；内含 `misa.pl` + `misa.ini`，**纯 Perl，无需编译**）。GitHub 备份 <https://github.com/SiYangming/SSR_marker_design>（v2.1 升级版 `misa.pl`/`misa.ini`，sha256 与官方包一致，并附 `misa_primer3.pl`）。

***

## native 实现

# misa / native — misa.pl SSR 检测驱动

[MISA](https://webblast.ipk-gatersleben.de/misa/)（MIcroSAtellite identification tool，IPK Gatersleben）用 Perl 实现，从 FASTA 中识别**完美 SSR**（unit size 1–6）与**复合 SSR**（两个 SSR 间距不超过 `interruptions` 阈值），引用 Thiel et al. 2003 / Beier et al. 2017（MISA-web）。

## 能力

| 子命令 | 包装命令 | 作用 | 线程 |
| ---- | ---- | ---- | ---- |
| `detect` | `misa.pl <fasta>`（cwd=`--outdir`；`misa.ini` 由驱动准备） | SSR 检测：FASTA → `<fasta>.misa` 位点表 + `<fasta>.statistics` 统计报告（`--gff` 时改为逐序列 `<序列 ID>.gff`） | ✅ 协议位（misa.pl 单线程，不强加） |

## 用法

```bash
# CLI 直跑（默认参数：definition 1-10 2-6 3-5 4-5 5-5 6-5 / interruptions 100 / GFF false）
python main.py detect genome.fasta --outdir misa_out

# 自带 misa.ini（misa.pl 只从当前工作目录读 misa.ini，驱动负责把它落到 --outdir）
python main.py detect genome.fasta --outdir misa_out --ini my.misa.ini

# 调整搜索参数（由驱动生成 misa.ini）
python main.py detect genome.fasta --outdir misa_out \
    --min-repeats "1-12 2-7 3-5 4-5 5-5 6-5" --interruptions 50

# 逐序列 GFF3（⚠️ 与 .misa 互斥，详见下「产物与关键行为」）
python main.py detect genome.fasta --outdir misa_out --gff

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量；misa.pl 单线程，`--threads` 仅作协议位）。

## 产物与关键行为（务必了解）

1. **`misa.ini` 只从当前工作目录读** —— `misa.pl` 没有任何 ini 命令行参数。驱动统一在 `--outdir` 内写 `misa.ini`，再以 `cwd=outdir` + 相对文件名调用 `misa.pl`。
2. **产出位置**：`misa.pl` 把 `<ARGV[0]>.misa` / `<ARGV[0]>.statistics` 写在「传入路径」旁、把逐序列 `<序列 ID>.gff` 写在**当前工作目录**。驱动在 `--outdir` 内建立指向输入 FASTA 的**同名软链**并以相对名调用，因此**全部产物落在 `--outdir`，输入 FASTA 所在目录零写入**（回归测试有断言）。
3. **⚠️ `.misa` 与 GFF 输出互斥（v2.1 实测）**：`misa.ini` 写 `GFF: true` 时 `misa.pl` 只写逐序列 `<序列 ID>.gff`，**不再产出 `.misa`**；`GFF: false` 时才写 `.misa` + `.statistics`。下游 `misa_primer3.pl` / `p3_in.pl` 需要 `.misa`，故 **MISA→Primer3 链路必须 `GFF: false`（本驱动默认）**；GFF3 结果由引物设计步骤的 `--gff3_out` 产出（见 [subworkflow/misa_primer3](../../subworkflow/misa_primer3/misa_primer3.md)）。
4. **`.misa` 列含义**：`ID` / `SSR nr.`（该序列内 SSR 记录序号）/ `SSR type` / `SSR` / `size` / `start` / `end`（1-based 闭区间）。SSR type：`p1`–`p6` = 完美 SSR 且基序长度 1–6；`c` = 复合 SSR（相邻两 SSR 直接相连）；`c*` = 复合 SSR（两 SSR 之间含间隔碱基）。
5. **id 处理差异**：`GFF: false` 时 FASTA 头整行保留、空白替换为 `_`（`>seq1 test` → `seq1_test`）；`GFF: true` 时只取头行首个 token（`seq1`）。
6. **同名文件保护**：若 `--outdir` 内已存在内容不同的 `misa.ini`，或已存在指向**其它**文件的同名输入文件，驱动**报错拒绝**（避免覆盖你的配置 / 误写）；换成 `--outdir` 或对齐参数即可。
7. **perl 遗留正则告警**：v2.1 源码正则含 `{n.m}` 形式，新 perl（≥5.22）会在 stderr 打 `Unescaped left brace in regex` 告警。驱动把该类告警折叠为一条 `[NOTE]`；**不影响 SSR 检测结果**。

## 实战示例：SSR 检测（教学链路 Step 1）

课件链路为 `misa.pl`（检测）→ `misa_primer3.pl`（引物设计）；**本模块等价能力由 `native/main.py` 的 `detect` 子命令提供**（先 CLI 后 main.py），引物设计部分见 [subworkflow/misa_primer3](../../subworkflow/misa_primer3/misa_primer3.md)。

### 1. 准备输入

```bash
mkdir -p SSR_detecting_and_primer_design && cd SSR_detecting_and_primer_design
# 教学链路会用 clean_fasta_header.sh 先去描述（可选）：sed 's/\(>\w*\)\s*.*/\1/' genome.fasta > genome.clean.fasta
ln -sf ~/data/Malassezia_sympodialis.genome_V01.fasta genome.fasta
```

### 2. 检测 SSR（本模块）

```bash
# 方式 A：CLI 直跑（等价教学 `misa.pl genome.fasta`，但产物集中到 outdir）
python ~/GitHub/bioskills/modules/misa/native/main.py detect genome.fasta --outdir .

# 方式 B：等价的原始命令（misa.ini 需已在当前目录）
misa.pl genome.fasta        # → genome.fasta.misa（位点表）+ genome.fasta.statistics（统计）
```

### 3. 查看结果

```bash
head -5 genome.fasta.misa
# ID      SSR nr. SSR type        SSR     size    start   end
# seq1_.. 1       p2      (AG)12  24      122     145

# SSR 类型分布（p1..p6 / c / c*）
tail -n +2 genome.fasta.misa | cut -f3 | sort | uniq -c | sort -rn
# 按基序类别统计与含 SSR 序列数见 genome.fasta.statistics
```

### 4. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `fasta`（positional）/ `--input` | 输入 FASTA（单文件可含多条序列） |
| `--outdir` | 输出目录（默认当前目录）；`misa.ini`、`<fasta>.misa`、`<fasta>.statistics`、逐序列 `.gff` 全落其中 |
| `--ini` | 自定义 `misa.ini`（`definition` / `interruptions` / `GFF` 三行；与 `--gff` 互斥） |
| `--min-repeats` | `definition(unit_size,min_repeats)`（默认官方 v2.1 `1-10 2-6 3-5 4-5 5-5 6-5`） |
| `--interruptions` | 复合 SSR 中两 SSR 之间允许的最大碱基数（默认 `100`） |
| `--gff` | 生成 `misa.ini` 时写 `GFF: true`（逐序列 `.gff`；⚠️ 不再产出 `.misa`） |
| `--threads` | 协议位（misa.pl 单线程） |

> `misa.ini` 写法（`misa.pl` 按行首关键字解析，大小写不敏感、名称可截断为 `def`/`int`/`GFF`）：
> ```
> definition(unit_size,min_repeats):          1-10 2-6 3-5 4-5 5-5 6-5
> interruptions(max_difference_for_2_SSRs):   100
> GFF:                                        false
> ```

## 环境安装（自建兜底：MISA 无官方镜像 / 无 conda 包，apt 最小化 + 官方源包）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）2026-09 核实**全无**，故本模块**自建**容器配方（`native/Dockerfile` / `native/Apptainer.def`，debian:bookworm-slim + perl + 官方源包，禁 miniconda）；宿主机安装见 `native/install.sh`（官方源码包部署到用户前缀，无需 root）。

### 1. Conda / brew（包管理器安装）

```bash
# ⚠️ 官方无 MISA conda 包（bioconda misa 404）——conda 只能提供 perl 运行时，
#    misa.pl / misa.ini 仍须取自官方源码包；一键安装直接 `bash native/install.sh`
mamba create -n misa-native -c conda-forge perl
conda activate misa-native
# 取官方源包并部署到环境内
curl -fsSL -o /tmp/misa.zip https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip
unzip -o /tmp/misa.zip -d /tmp/misa_src
install -m 0755 /tmp/misa_src/misa.pl "$CONDA_PREFIX/bin/misa.pl"
mkdir -p "$CONDA_PREFIX/share/misa" && install -m 0644 /tmp/misa_src/misa.ini "$CONDA_PREFIX/share/misa/misa.ini"
misa.pl -help          # 断言（打印 Program name / Release date: 25/08/20 (version 2.1)）
```

> 无 brew 块：homebrew-core 与 brewsci/bio **均无** `misa` 公式（2026-09 核实 404）。

### 2. Docker（自建镜像，context = `modules/`）

```bash
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）
docker build -t bioskills/misa:2.1 -f modules/misa/native/Dockerfile modules/
# 跑工具本体：镜像内 /opt/misa/misa.ini 是**官方原样** misa.ini（v2.1 默认 GFF: true → 逐序列 .gff，无 .misa）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint sh bioskills/misa:2.1 \
    -c 'cp /opt/misa/misa.ini . && misa.pl genome.fasta'
# 要 .misa（下游引物设计需要）就写 GFF: false 的 misa.ini（slim 镜像无 heredoc 依赖，用 printf）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint sh bioskills/misa:2.1 \
    -c 'printf "definition(unit_size,min_repeats): 1-10 2-6 3-5 4-5 5-5 6-5\ninterruptions(max_difference_for_2_SSRs): 100\nGFF: false\n" > misa.ini && misa.pl genome.fasta'
# 跑驱动（自动准备 misa.ini（GFF: false）与输入软链；必须 -u $(id -u):$(id -g)，否则产物归 root）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint /usr/bin/python3 bioskills/misa:2.1 \
    /opt/skill/main.py detect /data/genome.fasta --outdir /data/misa_out
```

### 3. Apptainer / Singularity（自建 sif，无官方预构建）

```bash
# 在仓库 modules/ 层构建（%files 源路径相对构建 cwd=modules/）
cd modules && apptainer build misa-2.1.sif misa/native/Apptainer.def && cd ..
apptainer run -B $PWD:/data -H /data modules/misa-2.1.sif -help
# 驱动：apptainer exec -B $PWD:/data -H /data modules/misa-2.1.sif python3 /opt/skill/main.py detect /data/genome.fasta --outdir /data/misa_out
```

### 4. 源码包安装（官方 zip，纯 Perl 无需编译）

一键（推荐）：

```bash
bash modules/misa/native/install.sh                  # auto：有 conda/mamba 走 conda(perl + 官方源包)，否则用户前缀
bash modules/misa/native/install.sh --method binary  # 强制官方源包 + ~/software/misa-2.1（只需系统 perl）
```

手工等价：

```bash
curl -fsSL -o ~/software/misa_sourcecode_25082020.zip \
    https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip
unzip -o ~/software/misa_sourcecode_25082020.zip -d ~/software/misa-2.1/
mkdir -p ~/software/misa-2.1/bin ~/software/misa-2.1/share/misa
install -m 0755 ~/software/misa-2.1/misa.pl  ~/software/misa-2.1/bin/misa.pl
install -m 0644 ~/software/misa-2.1/misa.ini ~/software/misa-2.1/share/misa/misa.ini
echo 'export PATH=$PATH:~/software/misa-2.1/bin' >> ~/.bashrc && source ~/.bashrc
misa.pl -help        # 断言（v2.1；-help 走 perl die，退出码 255 属正常）
```

## 测试

```bash
cd modules/misa/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema/detect --help 契约）必跑；
# PATH 含 misa.pl 时追加真跑最小链路（默认参数 → .misa+.statistics 且断言命中 (AG)12/(A)12/(GAA)7、
#   输入目录零写入、重复运行幂等、同 outdir 换参数被拒、--gff 产物互斥、--ini 透传）；无 misa.pl 时 [SKIP]。
```

## 版本与来源（2026-09 在线核实）

* MISA **2.1**（`misa.pl` Release date **25/08/20**；官方源码包 `misa_sourcecode_25082020.zip` 仅含 `misa.pl` 20148 B + `misa.ini` 158 B）
  * 源包 sha256：`43d90953489dbf428f4ed051a099a942314d3ccbea6226a7c72fd44216b243b8`
  * `misa.pl` sha256：`4712f29a0c57ff4aee1cc248cba20bcc879ef5d3b2ea6f5f1162cbc391c59abb`（与 GitHub `SiYangming/SSR_marker_design` v2.1 备份一致）
  * `misa.ini` sha256：`2dc25894c4d85314ae53eb7e615474285424c667e3b985d2ccde9b31edb4a6a2`
* 构建路线：**自建兜底**（官方渠道全无）→ `debian:bookworm-slim` + apt `perl`（bookworm stable，perl 5.36） + 官方源包；容器配方 `native/Dockerfile` / `native/Apptainer.def`
* 许可：官方源包与站点**未声明 SPDX 许可**（SPDX NOASSERTION），免费学术使用；引用 Thiel et al. 2003（*Theor Appl Genet* 106:411-422）/ Beier et al. 2017（*Bioinformatics* 33:2583-2585）

## 性能优化约定

* `misa.pl` 单线程（`default_cpus: 1`）；检测本身很快（30 Mb 级真菌基因组约数秒），瓶颈在 I/O 与 perl 正则
* 超大基因组建议按序列/染色体拆分 FASTA 后并行多次 `detect`（各进程独立 `--outdir`），再合并 `.misa`
* 真正耗时的 SSR **引物设计**（`misa_primer3.pl` → `primer3_core` × 每位点）靠 `--CPU N` + ParaFly 并行，见 [subworkflow/misa_primer3](../../subworkflow/misa_primer3/misa_primer3.md)

## 容器与 Conda 链接

* **官方镜像 / conda 包**：**无**（bioconda 404、quay.io/biocontainers 401 = 不存在、depot.galaxyproject.org 无、brew 无）
* **自建容器配方**：`native/Dockerfile`（`docker build -t bioskills/misa:2.1 -f modules/misa/native/Dockerfile modules/`）、`native/Apptainer.def`（`cd modules && apptainer build misa-2.1.sif misa/native/Apptainer.def`）
* **宿主机安装**：`bash modules/misa/native/install.sh`（`--method conda` 用 conda 提供 perl + 官方源包；`--method binary` 官方源包部署到 `~/software/misa-2.1`）
* **官方上游**：<https://webblast.ipk-gatersleben.de/misa/>（MISA-web v2.1；源码包 <https://webblast.ipk-gatersleben.de/misa/misa_sourcecode_25082020.zip>）
* **GitHub 备份（含引物设计 helper）**：<https://github.com/SiYangming/SSR_marker_design>（`misa.pl` / `misa.ini` / `misa_primer3.pl`）
