# annovar 软件模块

> 汇总说明：本 README 合并各实现（native + 官方 nf-core / snakemake-wrappers 登记）的用法；
> 安装方式见下方各节，容器与许可信息记录于此。
>
> ⚠️ **ANNOVAR 需在官网注册获取下载链接（annovar.latest.tar.gz），许可受限**（学术/非营利
> 免费，商用需授权）；且**不在 bioconda / quay.io/biocontainers / depot.galaxyproject.org 分发**
> （2026-09 已核实），故本模块提供自建容器兜底配方。

***

## native 实现

# annovar / native — 自包含变异注释驱动（Perl 脚本驱动）

ANNOVAR 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

ANNOVAR（ANNOtate VARiation）是一个功能强大的变异注释工具，支持对 SNP 和 INDEL 进行基因注释、区域注释、过滤注释等多种类型的注释分析。

五个子命令对应 ANNOVAR 的注释与建库脚本：

| 子命令             | 命令（驱动构造，统一以 `perl <script>` 调用）                                                                               | 作用                    |
| --------------- | ---------------------------------------------------------------------------------------------------------------- | --------------------- |
| `table_annovar` | `perl table_annovar.pl <input> <humandb/> -buildver hg38 -out <前缀> -remove -protocol ... -operation ... -nastring . -vcfinput --otherinfo` | 一次性多数据库完整注释（最常用）      |
| `geneanno`      | `perl annotate_variation.pl -geneanno -buildver hg38 <input> humandb/`                                            | 基于基因的注释               |
| `regionanno`    | `perl annotate_variation.pl -regionanno -buildver hg38 -dbtype cytoBand <input> humandb/`                         | 基于区域的注释               |
| `filter`        | `perl annotate_variation.pl -filter -buildver hg38 -dbtype 1000g2015aug_all -maf 0.01 <input> humandb/`           | 基于数据库频率/致病性的过滤注释      |
| `downdb`        | `perl annotate_variation.pl -downdb -buildver hg38 -webfrom annovar refGene humandb/`                             | 下载 ANNOVAR 注释数据库       |

> 入口定位：优先 `ANNOVAR_HOME` 环境变量（解压后的 annovar 目录），其次 conda share/bin、
> `~/software/annovar*`，最后 PATH；统一以 `perl <script>` 调用（脚本无需可执行位）。
> ANNOVAR 为 Perl 脚本、单线程（`table_annovar` 支持 `-thread`，由 `--threads` 覆盖）。

## 用法

```bash
# CLI 直跑
python main.py table_annovar variants.vcf humandb/ -buildver hg38 \
    -out variants.annovar -remove -protocol refGene,1000g2015aug_all,avsnp150 \
    -operation g,f,f -nastring . -vcfinput --otherinfo
python main.py downdb -buildver hg38 -dbtype refGene -webfrom annovar humandb/
python main.py geneanno variants.vcf humandb/ -buildver hg38

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：下载数据库 → 完整注释

文档（07 变异检测 §9）给出 ANNOVAR 的典型用法；等价能力由 `native/main.py` 的
`table_annovar` / `geneanno` / `regionanno` / `filter` / `downdb` 子命令提供（见上「用法」）。

### 1. 下载注释数据库

```bash
# 查看/下载人类参考基因数据库（hg38）
annotate_variation.pl -buildver hg38 -downdb -webfrom annovar refGene humandb/
# 千人基因组频率库
annotate_variation.pl -buildver hg38 -downdb -webfrom annovar 1000g2015aug humandb/
# dbSNP 库
annotate_variation.pl -buildver hg38 -downdb -webfrom annovar avsnp150 humandb/
# 等价：python main.py downdb -buildver hg38 -dbtype refGene -webfrom annovar humandb/
```

> 💡 非模式生物：用 `--buildver` 指定自定义版本，并自行准备 GFF3/GTF 基因注释与参考基因组。

### 2. 完整注释（table_annovar.pl，最常用）

```bash
table_annovar.pl variants.vcf humandb/ \
    -buildver hg38 \
    -out variants.annovar \
    -remove \
    -protocol refGene,1000g2015aug_all,avsnp150 \
    -operation g,f,f \
    -nastring . \
    -vcfinput \
    --otherinfo
# 等价：
#   python main.py table_annovar variants.vcf humandb/ -buildver hg38 -out variants.annovar \
#       -remove -protocol refGene,1000g2015aug_all,avsnp150 -operation g,f,f \
#       -nastring . -vcfinput --otherinfo
```

### 3. 分步注释（geneanno / regionanno / filter）

```bash
annotate_variation.pl -geneanno -buildver hg38 variants.vcf humandb/
annotate_variation.pl -regionanno -buildver hg38 -dbtype cytoBand variants.vcf humandb/
annotate_variation.pl -filter -buildver hg38 -dbtype 1000g2015aug_all -maf 0.01 variants.vcf humandb/
```

### 4. 参数说明

| 参数            | 说明                       |
| ------------- | ------------------------ |
| `-buildver`   | 参考基因组版本（如 hg38、hg19）     |
| `-protocol`   | 注释数据库列表，用逗号分隔            |
| `-operation`  | 注释类型：g=基因注释，r=区域注释，f=过滤注释 |
| `-out`        | 输出文件前缀                   |
| `-remove`     | 注释完成后删除中间文件              |
| `-nastring`   | 缺失值的表示方式                 |
| `-vcfinput`   | 输入为 VCF 格式               |
| `--otherinfo` | 保留 VCF 文件中的其他信息          |

### 5. 注释结果说明

基因注释类型：`exonic`（外显子区域变异）、`splicing`（剪接位点变异）、`ncRNA`（非编码 RNA 变异）、`intronic`（内含子区域变异）、
`UTR5`/`UTR3`（5' / 3' 非翻译区变异）、`upstream`/`downstream`（基因上游 / 下游变异）、`intergenic`（基因间区变异）；

外显子功能影响：`nonsynonymous SNV`（非同义 SNP，改变氨基酸）、
`synonymous SNV`（同义 SNP，不改变氨基酸）、`stopgain`（获得终止密码子，无义突变）、`stoploss`（丢失终止密码子）、`frameshift insertion/deletion`（移码插入 / 缺失）、
`nonframeshift insertion/deletion`（非移码插入 / 缺失）。

### 6. 注意事项

* ANNOVAR 支持多种输入格式（VCF、pileup、ANNOVAR 输入格式等）
* 使用前需下载对应物种与基因组版本的注释数据库
* 非模式生物需自行准备基因注释文件
* 注释结果为文本表格，便于后续筛选与分析

## 环境安装（官方预编译二进制包优先，需注册获取；官方无镜像/conda → 自建兜底配方）

**已核实（2026-09）**：ANNOVAR 在官方渠道 bioconda / quay.io/biocontainers /
depot.galaxyproject.org **均无**（bioconda 404、quay 无仓库、depot 404），也没有 nf-core
modules / snakemake-wrappers / homebrew 公式；官方（唯一）分发物是**需注册获取的预编译脚本包**
`annovar.latest.tar.gz`，无独立源码编译路线。故既不能走官方镜像直拉，也无法用 conda 安装，
本模块提供**自建 apt 最小化容器配方**兜底。

### 1. 官方预编译二进制包（需注册，唯一官方路线）

1. 打开注册表单：<https://www.openbioinformatics.org/annovar/annovar_download_form.php>
2. 用机构邮箱注册，收到含**个人下载链接**的邮件（文件 `annovar.latest.tar.gz`）
3. 下载并解压到用户目录（免 root；禁 `/opt/biosoft`）：

```bash
mkdir -p ~/software/annovar-latest
tar -xzf ~/Downloads/annovar.latest.tar.gz -C ~/software/annovar-latest --strip-components=1
chmod +x ~/software/annovar-latest/*.pl
echo 'export ANNOVAR_HOME=~/software/annovar-latest' >> ~/.bashrc
echo 'export PATH=$ANNOVAR_HOME:$PATH' >> ~/.bashrc
source ~/.bashrc

# 验证（需宿主 Perl >= 5.8.8）
perl "$ANNOVAR_HOME/table_annovar.pl" --help | head
```

> 💡 一键安装：`bash native/install.sh --tarball ~/Downloads/annovar.latest.tar.gz`
> 或 `bash native/install.sh --url "<邮件中的个人下载链接>"`（部署到 `~/software/annovar-latest`
> 并写 `ANNOVAR_HOME`）。因下载链接为注册专属、版本以 latest 分发，脚本不内嵌 sha256。

### 2. 官方源码编译（已核实：无此路线）

ANNOVAR 官方仅以 **预编译 Perl 脚本包**分发（无需编译，解压即用），不提供独立源码编译路线；
本节仅作说明（如需二次开发，源码即 `annovar.latest.tar.gz` 内的 `*.pl` Perl 脚本）。

### 3. Conda / brew（已核实：均无）

* `conda install -c bioconda annovar`：**已核实 bioconda 无 annovar**（`api.anaconda.org/package/bioconda/annovar` → 404），不可用。
* Homebrew：homebrew-core 与 brewsci/bio 均无 annovar 公式（已核实 404）。
* 请改用上表 §1 注册路线或 §4/§5 自建容器。

### 4. Docker（自建镜像，官方无镜像）

官方渠道无 ANNOVAR 镜像，提供自建兜底配方 `native/Dockerfile`（debian:bookworm-slim +
apt `--no-install-recommends` + 清理四连）：

```bash
# 构建前先把注册下载的 tarball 放到 native/ 目录
cp ~/Downloads/annovar.latest.tar.gz modules/annovar/native/
docker build -t annovar:latest -f modules/annovar/native/Dockerfile modules/annovar/native/

# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data annovar:latest \
    /data/variants.vcf /data/humandb/ -buildver hg38 -out variants.annovar \
    -remove -protocol refGene -operation g -nastring . -vcfinput
```

### 5. Apptainer / Singularity（自建，depot 无现成 sif）

官方无 depot 预构建 sif，用同仓库自建定义 `native/Apptainer.def`（同 apt 最小化路线 + `%test`）：

```bash
cp ~/Downloads/annovar.latest.tar.gz modules/annovar/native/
apptainer build annovar.sif modules/annovar/native/Apptainer.def
apptainer run -B $PWD:/data -H /data annovar.sif \
    /data/variants.vcf /data/humandb/ -buildver hg38 -out variants.annovar -remove -vcfinput
```

## 官方实现登记（不建目录，仅说明 + Schema）

* **nf-core modules**：无 `modules/nf-core/annovar`（2026-09 核实 404）；Nextflow 场景以本模块 `native/` 兜底。
* **snakemake-wrappers**：无 `bio/annovar`（2026-09 核实 404）；Snakemake 场景以本模块 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch _resolve_binary，不依赖已安装 annovar）
```

## 版本

* annovar：`latest`（`annovar.latest.tar.gz`，需注册获取；官方按发布期命名，无公开固定版本号）
* Perl 5（>= 5.8.8）
* 构建路线：官方渠道无镜像/无 conda → **自建兜底配方**（`native/Dockerfile` + `native/Apptainer.def`，
  debian:bookworm-slim + perl）

## 容器与 Conda 链接（均无官方 → 记录替代方案）

* **官网/注册下载**：<https://annovar.openbioinformatics.org/en/latest/user-guide/download/>（注册地址
  <https://www.openbioinformatics.org/annovar/annovar_download_form.php>）
* **Bioconda**：无（404，2026-09 核实）· **quay.io/biocontainers/annovar**：无仓库 · **depot.galaxyproject.org**：404
* **替代方案**：自建容器 `native/Dockerfile` / `native/Apptainer.def`（需注册获取 tarball）；或宿主机
  `bash native/install.sh --tarball <annovar.latest.tar.gz>`
