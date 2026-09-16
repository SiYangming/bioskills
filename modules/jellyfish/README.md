# jellyfish 软件模块

> 汇总说明：本 README 说明 jellyfish（Jellyfish 2.3.0 k-mer 计数）的唯一本地实现（native）
> 与官方 nf-core / snakemake-wrappers 登记；安装方式见下方各节，容器与 conda 信息记录于此。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/jellyfish/count`（唯一子模块，2026-09 核实
  <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/jellyfish>）；pin
  `bioconda::kmer-jellyfish=2.3.1`（`count/environment.yml`）。执行：
  `nf-core modules install nf-core jellyfish/count`。
* **snakemake-wrappers**：`bio/jellyfish/count`（唯一 wrapper，v9.17.1 存在，2026-09 核实）；
  环境 pin `kmer-jellyfish =2.3.1`。**运行靠 Snakemake 解析 `wrapper:` 句柄，勿把示例当 wrapper_path**：

  ```python
  rule jellyfish_count:
      input:
          reads = "reads.fastq",          # 或 expand(...) 多文件
      output:
          counts = "mer_counts.jf",
      params:
          kmer_length = 21,               # 对应 --mer-len
          size = "100M",                  # 对应 --size
          extra = "-C",                   # 官方 wrapper 无 canonical 参数，-C 经 extra 传入
      threads: 4
      log: "logs/jellyfish/count.log"
      wrapper:
          "v9.17.1/bio/jellyfish/count"
  ```

> 官方 wrapper 缺失（如 histo/stats/query/dump/merge）时用 native/main.py 兜底。

***

## native 实现

# jellyfish / native — k-mer 计数驱动（2.3.0）

Jellyfish 2.3.0 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对照官方文档。

## 功能

六个高频子命令覆盖 k-mer 计数到直方图的完整链路：

| 子命令       | 命令                                                                     | 作用                          |
| --------- | ---------------------------------------------------------------------- | --------------------------- |
| `count`   | `jellyfish count -C -m <k> -s <size> -t <N> -o <mer_counts.jf> <reads...>` | k-mer 计数（canonical 正/负链合并） |
| `histo`   | `jellyfish histo -t <N> <mer_counts.jf>`                               | k-mer 频率直方图（供 GenomeScope 等） |
| `stats`   | `jellyfish stats <mer_counts.jf>`                                      | k-mer 统计信息                  |
| `query`   | `jellyfish query <mer_counts.jf> <kmer>`                               | 查询特定 k-mer 出现次数             |
| `dump`    | `jellyfish dump <mer_counts.jf>`                                       | 导出全部 k-mer 及计数              |
| `merge`   | `jellyfish merge -o <out.jf> <hash1.jf> <hash2.jf> ...`                | 合并多个计数文件                    |

## 用法

```bash
# CLI 直跑
python main.py count -m 21 -s 100M -C -o mer_counts.jf reads_1.fastq reads_2.fastq --threads 4
python main.py histo mer_counts.jf -o mer_counts.histo --threads 4
python main.py stats mer_counts.jf
python main.py query mer_counts.jf ATGCATGCATGCATGCATGCA
python main.py dump mer_counts.jf -o mer_counts.dump
python main.py merge -o merged.jf a.jf b.jf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 在 count/histo 注入 `-t`）。

## 实战示例：基因组 survey 的 k-mer 计数

Jellyfish 是 GenomeScope 等基因组评估流程的 k-mer 计数底座。以下为文档给出的典型用法；
等价能力由 `native/main.py` 的 `count` / `histo` / `stats` / `query` 子命令提供（见上「用法」）。

```bash
mkdir -p jellyfish && cd jellyfish
ln -s /path/to/FastUniq/illumina.?.fastq ./

# 第一步：k-mer 计数（-C 计数互补链；-m 21 k-mer 长度；-s 100000000 初始 hash 表大小；-t 4 线程）
jellyfish count -C -m 21 -s 100000000 -t 4 -o mer_counts.jf *.fastq

# 第二步：生成 k-mer 直方图（供 GenomeScope 2.0 使用）
jellyfish histo -t 4 mer_counts.jf > mer_counts.histo

# 第三步：查看统计信息
jellyfish stats mer_counts.jf

# 第四步：查询特定 k-mer 的出现次数
echo "ATGCATGCATGCATGCATGCA" | jellyfish query mer_counts.jf
```

### 参数说明

| 参数   | 说明                        |
| ---- | ------------------------- |
| `-m` | k-mer 长度                  |
| `-s` | 初始 hash 表大小（估计的不同 k-mer 数） |
| `-t` | 线程数                       |
| `-C` | 计数互补链的 k-mer（canonical）   |
| `-o` | 输出文件名                     |
| `-c` | 计数位宽（默认 2）                |
| `-Q` | 碱基质量阈值（低于此质量的碱基被视为 N） |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方 release **同时提供**源码包与预编译静态二进制，且 bioconda → quay.io/biocontainers →
depot.galaxyproject.org 均维护（`kmer-jellyfish`）；两条官方安装路线与官方镜像均保留。

### 1. 官方预编译二进制（首选）

```bash
# 官方 release v2.3.0 资产 jellyfish-linux（Linux x86_64 静态二进制，2026-09 核实 200）
# 一键：下载并部署到用户前缀（免 root，写 PATH）
bash native/install.sh --method binary --prefix ~/software/jellyfish-2.3.0
export PATH="$HOME/software/jellyfish-2.3.0/bin:$PATH"
jellyfish --version    # 断言
```

### 2. 官方源码编译（并列保留）

```bash
# 官方源码归档 jellyfish-2.3.0.tar.gz
curl -fSL -o jellyfish-2.3.0.tar.gz \
    https://github.com/gmarcais/Jellyfish/releases/download/v2.3.0/jellyfish-2.3.0.tar.gz
tar zxf jellyfish-2.3.0.tar.gz
cd jellyfish-2.3.0
./configure --prefix=$HOME/software/jellyfish-2.3.0
make -j 8 && make install
export PATH="$HOME/software/jellyfish-2.3.0/bin:$PATH"
jellyfish --version
```

### 3. Conda / brew（包管理器安装）

```bash
# bioconda 现行包名为 kmer-jellyfish（旧的 jellyfish 包仅到 2.2.10）
mamba create -n jellyfish -c conda-forge -c bioconda kmer-jellyfish=2.3.0
conda activate jellyfish
jellyfish --version
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install jellyfish
jellyfish --version   # 断言；brew 当前 2.3.1，与 meta 登记 2.3.0 略有差异（以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 `kmer-jellyfish=2.3.0` 环境，
> 无 conda 时下载官方静态二进制到 `~/software/jellyfish-2.3.0` 并写 PATH）。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/kmer-jellyfish:2.3.1--py312pl5321hf731ba3_6
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/kmer-jellyfish:2.3.1--py312pl5321hf731ba3_6 \
    count -C -m 21 -s 100M -t 4 -o /data/mer_counts.jf /data/reads_1.fastq
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull jellyfish.sif docker://depot.galaxyproject.org/singularity/kmer-jellyfish:2.3.1--py312pl5321hf731ba3_6
apptainer run -B $PWD:/data -H /data jellyfish.sif histo /data/mer_counts.jf
```

## 测试

```bash
bash test/run_test.sh   # 合成数据 + argv 构造验证；jellyfish 未安装时跳过真实冒烟
```

## 版本

* jellyfish 2.3.0（官方 release v2.3.0；bioconda 包名 kmer-jellyfish）
* 构建路线：官方预编译静态二进制（jellyfish-linux）/ 官方源码编译 / 官方 biocontainer
* nf-core `jellyfish/count`、snakemake-wrappers `bio/jellyfish/count` 均 pin kmer-jellyfish=2.3.1（较本模块 2.3.0 高一个 patch）

***

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/kmer-jellyfish/overview>
* **官方 release（源码 + 静态二进制）**：<https://github.com/gmarcais/Jellyfish/releases/tag/v2.3.0>
* **Docker**：`docker pull quay.io/biocontainers/kmer-jellyfish:2.3.1--py312pl5321hf731ba3_6`
* **Singularity**：<https://depot.galaxyproject.org/singularity/kmer-jellyfish%3A2.3.1--py312pl5321hf731ba3_6>
* 安装方式（本地）：`bash native/install.sh`（conda 或官方静态二进制）
