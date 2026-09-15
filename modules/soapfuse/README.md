# soapfuse 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器渠道信息记录于此（2026-09 逐渠道核实）。
> SOAPfuse 是华大基因（BGI）开发的融合基因检测工具，从双端 RNA-seq 数据中检测融合转录本（Perl 实现，仅支持 Linux，全流程约需 8G 内存）。

***

## native 实现

# soapfuse / native — SOAPfuse 融合检测驱动

SOAPfuse 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对齐官方 SOAPfuse wiki
「Run SOAPfuse」与教学文档「3.14.2 SOAPfuse」及「12.2 SOAPfuse」。v1.27 起部分功能打包为 SOAPfuse
perl 模块，运行前需把模块目录加入 `PERL5LIB`（镜像/安装脚本已处理）。

## 功能

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `run` | `perl SOAPfuse-RUN.pl -c <config> -fd <data_dir> -l <sample_list> -o <out_dir> [-fs N] [-es N] [-tp <postfix>]` | 双端 RNA-seq 融合基因检测主流程 |

参数说明（对齐官方 wiki）：

| 参数 | 说明 |
| --- | --- |
| `-c` | 配置文件（官方包内 `config/config.txt`，需按 `TOOL_DIR`/`DATABASE_DIR` 修改） |
| `-fd` | 存放双端测序 reads 文件的目录（FASTQ/FASTA，可 gzip） |
| `-l` | 样本信息列表文件（建议每个列表文件只含一个样本） |
| `-o` | 输出目录（优先级高于 config 的 `PD_all_out`） |
| `-fs` / `-es` | 起始 / 结束步骤（默认 1 / 9，9 为最后一步） |
| `-tp` | 临时目录名后缀（不同样本列表文件不要用相同字符串） |

> SOAPfuse 无命令行线程参数（线程在 `config.txt` 内配置），`--threads` 仅为接口对齐而接受。
> 运行依赖：`perl`（>=5.8.5）+ `samtools` + `bedtools`。

## 用法

```bash
# CLI 直跑（官方 wiki 示例参数）
python main.py run -c config/config.txt -fd raw_data -l sample.list -o out_dir
python main.py run -c config.txt -fd raw_data -l sample.list -o out_dir -fs 3 -es 9

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 对 SOAPfuse 不生效）。

## 实战示例：双端 RNA-seq 融合基因检测

教学文档「12.2 SOAPfuse」说明 SOAPfuse 配置较复杂，需先配置数据库与依赖（具体用法参见官方文档）。
典型用法如下（等价能力由 `native/main.py` 的 `run` 子命令提供，见上「用法」）。

```bash
# 1) 准备：解压官方包 → 修改 config/config.txt 的 DB_db_dir / PG_pg_dir / PS_ps_dir / PD_all_out
#    （v1.27 起需 export PERL5LIB=<包>/source:<包>/source/bin:<包>）
# 2) 运行（-fd 为双端 reads 目录，-l 为样本列表，-o 为输出目录）
perl SOAPfuse-RUN.pl -c ~/software/soapfuse-1.27/config/config.txt \
    -fd ~/data/raw_data \
    -l ~/data/sample.list \
    -o ~/data/soapfuse_out

# 3) 结果
#    融合基因：  <out>/final_fusion_genes/<sample>/<sample>.final.Fusion.specific.for.genes
#    融合转录本：<out>/final_fusion_genes/<sample>/<sample>.final.Fusion.specific.for.trans
```

> 桥接 native 驱动：`python main.py run -c config.txt -fd raw_data -l sample.list -o out_dir`
> （驱动按 `perl SOAPfuse-RUN.pl …` 拼装；`-fs/-es` 可裁剪起止步骤）。

## 环境安装（自建兜底：SOAPfuse 无官方镜像 / conda 包，apt 最小化 + 官方预编译包 + perl/samtools/bedtools）

> ⚠️ **版本现状（2026-09 逐渠道核实）**：官方渠道 bioconda → quay.io/biocontainers →
> depot.galaxyproject.org **全部没有** SOAPfuse（`api.anaconda.org/package/bioconda/soapfuse` → 404；
> quay `biocontainers/soapfuse` 未授权/不存在；`depot.../soapfuse:1.27` → 404）；
> nf-core / snakemake-wrappers 无模块；Homebrew 无公式。
> 官方发布为 SourceForge 预编译包 `SOAPfuse-v1.27.tar.gz`（最新发布 2016-01-19），因此走**自建兜底**：
> `native/Dockerfile` + `native/Apptainer.def`（debian:bookworm-slim + apt 最小化 perl/samtools/bedtools
> + 官方预编译包，禁 miniconda），宿主机本地部署见「### 4」。

### 1. Conda / brew（包管理器安装）

**不提供 conda / brew 路线，理由（2026-09 核实）**：

```bash
# ❌ bioconda 无 soapfuse 包（api.anaconda.org/package/bioconda/soapfuse → 404）
# ❌ Homebrew：homebrew-core（formulae.brew.sh/api/formula/soapfuse.json → 404）与
#    brewsci/bio（Formula/soapfuse.rb → 404）均无公式
```

> 依赖（perl/samtools/bedtools）可用 conda 备齐：`mamba create -n sofa -c conda-forge -c bioconda perl samtools bedtools`
> （但 SOAPfuse 本体仍需自建/官方预编译包）。

### 2. Docker（自建镜像，官方渠道无）

```bash
# 构建（context=modules/ 层，携带 base.py + 软件级 meta.yaml）
docker build -t bioskills/soapfuse:1.27 -f modules/soapfuse/native/Dockerfile modules/
# 运行：注意必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root（数据库/config 另行挂载）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/soapfuse:1.27 \
    -c /data/config.txt -fd /data/raw_data -l /data/sample.list -o /data/out
# 驱动 main.py（镜像内已放 base.py + 软件级 meta；--entrypoint 切到 python3）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint /usr/bin/python3 bioskills/soapfuse:1.27 \
    /opt/skill/main.py run -c /data/config.txt -fd /data/raw_data -l /data/sample.list -o /data/out
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 无预构建 soapfuse sif（`soapfuse:1.27` → 404）→ 本地自建：

```bash
cd modules && apptainer build ../soapfuse.sif soapfuse/native/Apptainer.def && cd ..
apptainer run -B $PWD:/data -H /data soapfuse.sif \
    -c /data/config.txt -fd /data/raw_data -l /data/sample.list -o /data/out
```

### 4. 官方预编译包 + 本地部署（宿主机，免 root）

官方 SourceForge 预编译包（解压 → 用户前缀，`native/install.sh` 会创建 `bin/SOAPfuse-RUN.pl` 软链并设置
`PERL5LIB`）：

```bash
# 一键：下载官方包 → ~/software/soapfuse-1.27（含 bin/SOAPfuse-RUN.pl 与 PERL5LIB 配置）
bash native/install.sh
# 或用本地包：
bash native/install.sh --tarball ~/Downloads/SOAPfuse-v1.27.tar.gz

# 依赖（perl>=5.8.5 + samtools + bedtools）：Debian/Ubuntu：apt install perl samtools bedtools
#                                          conda：mamba create -n sofa -c conda-forge -c bioconda perl samtools bedtools
```

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言恒跑；已部署 SOAPfuse-RUN.pl 时做冒烟
```

## 版本与来源（2026-09 逐渠道核实，禁止臆造）

| 渠道 | 状态 | 说明 |
| --- | --- | --- |
| SourceForge soapfuse（官方） | ✅ 最新 `SOAPfuse-v1.27.tar.gz` | 2016-01-19 发布，42,827,101 bytes；md5 `4f85e1cc8fe82eebd70fa377b9452e36`（SourceForge best_release.json） |
| 官方 wiki | ✅ <https://sourceforge.net/p/soapfuse/wiki/> | Run_SOAPfuse / Installation / System_Requirements 页；主脚本 `SOAPfuse-RUN.pl`（perl 运行） |
| GitHub（文档所述 aquaskyline） | ❌ 404 | 2026-09 抓取 `github.com/aquaskyline/SOAPfuse` 已失效；活跃 perl 模块仓库为 <https://github.com/Nobel-Justin/SOAPfuse_PM>（GPL-3.0） |
| bioconda | ❌ 404 | `api.anaconda.org/package/bioconda/soapfuse` |
| quay.io/biocontainers | ❌ 无 | 未授权/不存在（biocontainers 由 bioconda 自动构建，bioconda 无包） |
| depot.galaxyproject.org | ❌ 404 | `singularity/soapfuse:1.27` |
| nf-core modules | ❌ 404 | `modules/nf-core/soapfuse` |
| snakemake-wrappers | ❌ 404 | `bio/soapfuse` |
| Homebrew（core / brewsci/bio） | ❌ 均无 | 无公式 |

* 判定：官方渠道（bioconda → quay biocontainers → depot）全无 →「无官方维护」→ 自建配方
  （版本差异与依据在 `meta.yaml software_versions` 中声明）。
* 运行要求：Perl >= 5.8.5；samtools + bedtools；约 8G 内存；仅 Linux；当前仅针对人类 RNA-seq。
* 参考文献：Jia W, et al. SOAPfuse: an algorithm for identifying fusion transcripts from paired-end
  RNA-Seq data. Genome Biology 14(2):R12 (2013)。

## 容器与 Conda 链接

* **官方发布页**：<https://sourceforge.net/projects/soapfuse/>（预编译包 <https://sourceforge.net/projects/soapfuse/files/SOAPfuse_Package/>）
* **官方 wiki（用法/参数）**：<https://sourceforge.net/p/soapfuse/wiki/>
* **Bioconda 页面（无此包）**：<https://anaconda.org/bioconda/soapfuse>（404）
* **自建配方**：`modules/soapfuse/native/Dockerfile` + `Apptainer.def`（debian:bookworm-slim + perl/samtools/bedtools + 官方预编译包）
* **宿主一键安装**：`bash modules/soapfuse/native/install.sh --help`（部署到 `~/software/soapfuse-1.27`）

## 版本

* SOAPfuse 1.27（官方 SourceForge 预编译包；无官方镜像/conda 包，自建兜底）
* 构建路线：自建（native/Dockerfile + Apptainer.def，debian:bookworm-slim + apt 最小化 perl/samtools/bedtools + 官方预编译包）
