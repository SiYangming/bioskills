# fgenesh 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器信息记录于此。
> 来源：从头基因预测环节——FGENESH。
>
> ⚠️ **许可受限（务必先读）**：FGENESH 是 **Softberry 公司的商业软件**。学术用户须向 Softberry
> 申请**免费学术许可**，商业用户须**购买许可**后方可获得发行包。**禁止未授权获取、使用与再分发。**
> 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**均无** FGENESH（2026-09 核实），
> 且官网 `softberry.com` 2026-09 探测不可达（curl 000），版本号未能在线核实。

***

## native 实现

# fgenesh / native — 自包含从头基因预测驱动（许可受限）

FGENESH 的本地自包含实现（`source_type: custom`、`type: native`）。

FGENESH 是基于隐马尔可夫模型（HMM）的真核生物从头（ab initio）基因预测程序，支持多种物种预训练参数，准确性在从头预测工具中较高（Solovyev et al., *Genome Biol* 2006）。

## 功能

| 子命令       | 命令                                                                                     | 作用             |
| --------- | -------------------------------------------------------------------------------------- | -------------- |
| `predict` | `fgenesh <genome.fa> -L <params.par> -o <output_prefix> [-gff] [-exon] [-gene] -cpu <N>` | 从头基因预测（输出 GFF） |

> `-cpu N` 由本驱动自动注入：线程优先级 `--threads > per_subcommand_threads > default_cpus`。

## 用法

```bash
# CLI 直跑：指定物种参数文件
python main.py predict genome.fasta -L /opt/fgenesh/params/fungi.par -o fgenesh.gff -gff --threads 8

# 用物种预设（自动解析为 <params-dir>/<species>.par）
python main.py predict genome.fasta --species fungi --params-dir /opt/fgenesh/params -o out -gff

# 仅输出外显子 / 仅输出基因
python main.py predict genome.fasta --species rice --params-dir /opt/fgenesh/params -o out -exon

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

参数（节选）：

| 参数                      | 说明                                                       |
| ----------------------- | -------------------------------------------------------- |
| 位置参数                    | 待预测基因组序列 FASTA                                            |
| `-L`                    | 物种参数文件（`*.par`）；或用 `--species` + `--params-dir` 自动解析     |
| `-o`                    | 输出文件前缀                                                   |
| `-gff`                  | 以 GFF 格式输出                                                |
| `-exon` / `-gene`       | 仅输出外显子 / 仅输出基因                                          |
| `-cpu`                  | 并行线程数（本驱动从 `--threads` 注入）                                |

### 常用物种参数文件

FGENESH 提供了多种物种的预训练参数：

| 参数文件               | 适用物种     |
| ------------------ | -------- |
| `fungi.par`        | 真菌       |
| `arabidopsis.par`  | 拟南芥（植物）  |
| `rice.par`         | 水稻（植物）   |
| `human.par`        | 人类（哺乳动物） |
| `mouse.par`        | 小鼠（哺乳动物） |
| `drosophila.par`   | 果蝇（昆虫）   |
| `worm.par`         | 线虫       |

## 实战示例：真菌基因组从头预测

```bash
mkdir -p fgenesh_out && cd fgenesh_out

# 准备基因组序列
ln -s ../Malassezia_sympodialis.genome_V01.fasta genome.fasta

# 使用真菌参数文件进行基因预测（GFF 输出，8 线程）
fgenesh genome.fasta -L /opt/biosoft/fgenesh/params/fungi.par -o fgenesh.gff -gff -cpu 8
```

> 上述命令与 `native/main.py` 的 `predict` 子命令等价：
> `python main.py predict genome.fasta --species fungi --params-dir <params_dir> -o fgenesh.gff -gff --threads 8`。

## 环境安装（许可受限；需向 Softberry 申请许可；官方渠道全无 → 自建容器兜底）

### 0. 许可申请（首要，不可跳过）

* FGENESH 为商业软件，须向 Softberry 公司申请**学术免费许可**或**购买商业许可**后取得发行包。
* 官方入口：<http://www.softberry.com/berry.phtml?topic=fgenesh&group=programs&subgroup=gfind>
  （2026-09 探测不可达 curl 000，请以搜索引擎获取当前有效地址）。
* **禁止未授权获取、使用与再分发**；本模块不自带、不下载任何 Softberry 资产。

### 1. 授权发行包部署（推荐）

收到 Softberry 授权发行包后，解压并加入 PATH：

```bash
# 一键部署（解压授权发行包 -> ~/software/fgenesh，定位 fgenesh 可执行文件并写 PATH）
bash native/install.sh --tarball ~/downloads/fgenesh.tar.gz

# 或手工部署（官方写法，改为用户前缀）
tar zxf ~/software/fgenesh.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/fgenesh/bin/' >> ~/.bashrc
source ~/.bashrc
fgenesh   # 断言（需授权环境）
```

> 参数文件位于发行包的 `params/` 目录（`fungi.par` / `human.par` / ...）；`--species` + `--params-dir` 指向之。

### 2. Docker（自建镜像；消费用户自备授权发行包）

无官方镜像 → 用本模块自建配方构建；配方**不下载** Softberry 资产，需先将授权发行包放到构建目录为 `fgenesh.tar.gz`：

```bash
cp ~/downloads/fgenesh.tar.gz modules/fgenesh/native/fgenesh.tar.gz
docker build -t fgenesh:local modules/fgenesh/native

# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    fgenesh:local /data/genome.fasta -L /opt/fgenesh/params/fungi.par -o /data/fgenesh.gff -gff -cpu 8
```

### 3. Apptainer / Singularity（自建 def）

```bash
cp ~/downloads/fgenesh.tar.gz modules/fgenesh/native/fgenesh.tar.gz
apptainer build fgenesh.sif modules/fgenesh/native/Apptainer.def
apptainer run -B $PWD:/data fgenesh.sif /data/genome.fasta \
    -L /opt/fgenesh/params/fungi.par -o /data/fgenesh.gff -gff -cpu 8
```

### 4. Conda / brew

* **Conda**：bioconda 无 `fgenesh` 包（2026-09 核实 api.anaconda.org 未找到）→ 不可用。
* **brew**：homebrew-core 与 brewsci/bio 均无 `fgenesh`（2026-09 核实 404）→ 不提供 brew 块。

## 测试

```bash
bash test/run_test.sh   # predict 为 argv 构造验证；fgenesh 未安装（许可受限）时跳过真实冒烟
```

## 版本

* FGENESH：Softberry 授权版（未公开版本号；官网 2026-09 探测不可达 000，未能在线核实）

* 构建路线：官方渠道全无 + 许可受限 → 自建容器配方 `native/Dockerfile` / `native/Apptainer.def`（消费用户自备授权发行包）

* nf-core / snakemake-wrappers 均无 fgenesh 官方模块（2026-09 核实 404）

## 容器与 Conda 链接

* **官方镜像**：无（bioconda / quay.io/biocontainers / depot.galaxyproject.org 均无 FGENESH）

* **替代方案（自建）**：`modules/fgenesh/native/Dockerfile` + `modules/fgenesh/native/Apptainer.def`（消费用户自备 Softberry 授权发行包）

* **官网（许可申请）**：<http://www.softberry.com/berry.phtml?topic=fgenesh&group=programs&subgroup=gfind>（2026-09 不可达）

* 安装方式（本地）：`bash modules/fgenesh/native/install.sh --tarball <授权发行包>`
