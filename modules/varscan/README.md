# varscan 软件模块

> 汇总说明：本 README 合并各实现（native + 官方 nf-core / snakemake-wrappers 登记）的用法；
> 安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# varscan / native — 自包含变异检测驱动（Java CLI 驱动）

VarScan 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

VarScan 是一个基于 Java 的变异检测工具，支持从 mpileup 格式数据中检测 SNP 和 INDEL，具有变异检测、体细胞变异检测、拷贝数变异分析等功能。

七个子命令对应 VarScan 的检测与分析链路（名称与 VarScan 实际子命令一致）：

| 子命令             | 命令（驱动构造）                                                                                                        | 作用                       |
| --------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `mpileup2snp`   | `varscan mpileup2snp <mpileup> --min-coverage 8 --min-reads2 2 --min-avg-qual 15 --min-var-freq 0.1 --p-value 0.05 --output-vcf 1` | 从 mpileup 检测 SNP         |
| `mpileup2indel` | 同上（INDEL）                                                                                                        | 从 mpileup 检测 INDEL       |
| `mpileup2cns`   | 同上（一致性序列）                                                                                                       | 一步输出 SNP+INDEL 一致性序列     |
| `somatic`       | `varscan somatic <paired/normal mpileup> [--tumor <tumor mpileup>] --output-vcf 1 <前缀>`                            | 肿瘤-正常配对体细胞变异检测           |
| `copynumber`    | `varscan copynumber <paired/normal mpileup> [--tumor <tumor mpileup>] <前缀>`                                        | 拷贝数变异分析                  |
| `processSomatic`| `varscan processSomatic <somatic 前缀> --min-tumor-freq ... --max-normal-freq ...`                                 | somatic 结果筛选             |
| `fpfilter`      | `varscan fpfilter --vcf-file <vcf> --bam-file <bam> --output-file <out>`                                         | 基于 BAM 的假阳性过滤            |

> 入口定位：优先 PATH 上的 `varscan` wrapper（bioconda/biocontainer 提供）；缺失时用
> `VARSCAN_JAR` 或 conda share / `~/software` 下的 `VarScan.jar`，以 `java $JAVA_OPTS -jar` 调用。
> VarScan 单线程，`--threads` 仅作接口统一；JVM 堆内存经 `JAVA_OPTS` 注入。

## 用法

```bash
# CLI 直跑
python main.py mpileup2snp V1.mpileup --min-coverage 8 --min-reads2 2 --min-avg-qual 15 \
    --min-var-freq 0.1 --p-value 0.05 --output-vcf 1 -o V1.snp.vcf
python main.py mpileup2indel V1.mpileup --min-coverage 8 --output-vcf 1 -o V1.indel.vcf
python main.py somatic paired.mpileup --min-coverage 8 --min-var-freq 0.05 \
    --somatic-p-value 0.05 --output-vcf 1 somatic_output
python main.py somatic normal.mpileup --tumor tumor.mpileup --output-vcf 1 somatic_output
python main.py fpfilter --vcf-file V1.snp.vcf --bam-file tumor.bam --output-file filtered.vcf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：mpileup → SNP/INDEL/CNS → 体细胞变异

文档（07 变异检测 §8）给出 VarScan 的典型用法；等价能力由 `native/main.py` 的
`mpileup2snp` / `mpileup2indel` / `mpileup2cns` / `somatic` 子命令提供（见上「用法」）。

```bash
mkdir -p varscan && cd varscan
ln -s ../genome.* . && ln -s ../V1.bam . && ln -s ../V2.bam .

# 生成 mpileup 文件
samtools mpileup -f genome.fasta V1.bam > V1.mpileup

# 检测 SNP
java -jar VarScan.jar mpileup2snp V1.mpileup \
    --min-coverage 8 --min-reads2 2 --min-avg-qual 15 --min-var-freq 0.1 \
    --p-value 0.05 --output-vcf 1 > V1.snp.vcf

# 检测 INDEL
java -jar VarScan.jar mpileup2indel V1.mpileup \
    --min-coverage 8 --min-reads2 2 --min-avg-qual 15 --min-var-freq 0.1 \
    --p-value 0.05 --output-vcf 1 > V1.indel.vcf

# 一步完成 SNP 和 INDEL 检测（一致性序列）
samtools mpileup -f genome.fasta V1.bam | \
    java -jar VarScan.jar mpileup2cns --min-coverage 5 --min-reads2 2 \
    --min-avg-qual 15 --p-value 0.05 --output-vcf 1 > V1.vcf

# 肿瘤-正常配对样本体细胞变异检测
samtools mpileup -f genome.fasta normal.bam tumor.bam > paired.mpileup
java -jar VarScan.jar somatic paired.mpileup \
    --min-coverage 8 --min-reads2 2 --min-var-freq 0.05 \
    --somatic-p-value 0.05 --output-vcf 1 somatic_output
```

### 参数说明

| 参数                  | 说明                        |
| ------------------- | ------------------------- |
| `--min-coverage`    | 最小覆盖深度                    |
| `--min-reads2`      | 支持变异的最小 reads 数           |
| `--min-avg-qual`    | 最小平均碱基质量（默认 15）           |
| `--min-var-freq`    | 最小变异等位基因频率                |
| `--p-value`         | 显著性 p 值阈值                 |
| `--somatic-p-value` | 体细胞变异 p 值阈值               |
| `--output-vcf`      | 是否输出 VCF 格式（1 为是，0 为否）     |

### 注意事项

* VarScan 基于 Java，需要 Java 运行环境
* 输入为 samtools mpileup 格式，需先生成 mpileup 文件
* 支持体细胞变异检测（肿瘤-正常配对），适合低深度测序数据

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），可直接拉取官方
镜像运行工具二进制；VarScan 官方同时提供**预编译 jar**与**源码**两条路线，均保留如下。

### 1. 官方预编译二进制包（jar，首选）

* **官网**：<https://dkoboldt.github.io/varscan/>

* **jar 直链**：<https://github.com/dkoboldt/varscan/raw/master/VarScan.v2.4.6.jar>

```bash
# 下载 jar 到用户目录并建 wrapper（免 root；禁 /opt/biosoft）
mkdir -p ~/software/varscan-2.4.6/bin
curl -fsSL -o ~/software/varscan-2.4.6/bin/VarScan.jar \
    https://github.com/dkoboldt/varscan/raw/master/VarScan.v2.4.6.jar
cat > ~/software/varscan-2.4.6/bin/varscan <<'EOF'
#!/usr/bin/env bash
exec java ${JAVA_OPTS:-} -jar "$HOME/software/varscan-2.4.6/bin/VarScan.jar" "$@"
EOF
chmod 755 ~/software/varscan-2.4.6/bin/varscan
export PATH="$HOME/software/varscan-2.4.6/bin:$PATH"

varscan --version   # 断言（需宿主 JRE）
```

> 💡 一键安装：`bash native/install.sh --method binary`（内嵌该版本 jar sha256，自动生成 wrapper）。
> 注意：文档 07 §8 示例使用历史版本 `VarScan.v2.3.9.jar`；本模块以当前 2.4.6 为准（bioconda
> 最新、quay/depot tag、官方 jar 直链与 brewsci/bio 公式均为 2.4.6）。

### 2. 官方源码编译（并列保留）

VarScan 源码在 <https://github.com/dkoboldt/varscan>（Java 工程，含 `src/`）：

```bash
git clone https://github.com/dkoboldt/varscan.git
cd varscan
# 按官方仓库说明以 JDK 编译打包为 VarScan.jar；生产建议直接用 §1 官方 jar
```

### 3. Conda / brew（包管理器安装）

```bash
mamba create -n varscan-native -c conda-forge -c bioconda varscan=2.4.6
conda activate varscan-native
varscan --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install varscan
varscan --version        # 断言（brewsci/bio varscan 取 VarScan.v2.4.6.jar，与 meta 登记一致）
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `varscan`，
> 无 conda 时下载官方 jar 到 `~/software/varscan-<ver>`；版本默认 2.4.6，与下方
> `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/varscan:2.4.6--hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/varscan:2.4.6--hdfd78af_0 \
    varscan mpileup2snp /data/V1.mpileup --output-vcf 1 > V1.snp.vcf
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull varscan.sif docker://depot.galaxyproject.org/singularity/varscan:2.4.6--hdfd78af_0
apptainer run -B $PWD:/data -H /data varscan.sif mpileup2snp /data/V1.mpileup --output-vcf 1 > V1.snp.vcf
```

## 官方实现登记（不建目录，仅说明 + Schema）

* **nf-core modules（官方）**：`modules/nf-core/varscan/{somatic,fpfilter,processsomatic}`
   三个子模块，均 pin `bioconda::varscan=2.4.6`（+ `htslib=1.22.1`）。执行前请
   `nf modules install nf-core varscan somatic fpfilter processsomatic` 安装到项目自身目录，
   **不要直接引用本仓库示例**；缺失时以本模块 `native/` 兜底。

* **snakemake-wrappers（官方）**：`bio/varscan/{mpileup2snp,mpileup2indel,somatic}` 三个
   wrapper，environment.yaml pin `varscan=2.4.6` + `snakemake-wrapper-utils=0.9.0`。
   运行靠 Snakemake 解析 `wrapper: "v9.17.1/bio/varscan/mpileup2snp"` 句柄，
   **不要把本地示例当 `wrapper_path`**；缺失时以本模块 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch _resolve_binary，不依赖已安装 varscan）
```

## 版本

* varscan 2.4.6（bioconda::varscan=2.4.6；quay tag 2.4.6--hdfd78af_0）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/varscan / depot.galaxyproject.org；本地不再自建容器）

* 文档 07 §8 示例用 2.3.9（历史 jar）；本模块统一到当前 2.4.6

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/varscan/overview>

* **Docker**：`docker pull quay.io/biocontainers/varscan:2.4.6--hdfd78af_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/varscan%3A2.4.6--hdfd78af_0>

* 安装方式（本地）：`mamba create -n varscan -c conda-forge -c bioconda varscan=2.4.6`
