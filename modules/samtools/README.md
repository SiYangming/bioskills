# samtools 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# samtools / native

自包含的 samtools 驱动实现（`source_type: custom`）。

## 能力

覆盖 samtools 高频子命令，自动注入线程与临时目录优化：

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `view` | SAM/BAM/CRAM 互转与过滤 | ✅ |
| `sort` | 坐标 / read name 排序 | ✅ |
| `index` | 建立 bai/csi 索引 | — |
| `flagstat` | flag 统计 | — |
| `idxstats` | 按参考序列统计 | — |
| `stats` | 全量统计报告 | — |
| `depth` | 测序深度 | — |
| `mpileup` | pileup 生成 | ✅ |
| `faidx` | FASTA 索引 | — |
| `merge` | 合并 BAM | ✅ |
| `quickcheck` | 完整性校验 | — |

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
conda activate samtools-native
```

### 2. CLI 调用

```bash
python main.py view -bS input.sam -o out.bam --threads 8
python main.py sort input.bam -o sorted.bam --threads 8
python main.py index sorted.bam
python main.py flagstat sorted.bam
python main.py faidx refs.fa
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行

```bash
docker build -t bioskills/samtools:1.21-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/samtools:1.21-v1.0 \
  sort /data/input.bam -o /data/sorted.bam --threads 8
```

### 5. 测试

```bash
bash test/run_test.sh
```

## 性能优化约定

- **线程**：`sort` 默认 8 线程（CPU 密集），其他默认 4；用户显式 `--threads` 永远优先。
- **临时目录**：`sort` 自动使用 `$TMPDIR` 下的临时前缀，避免污染工作目录。
- **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。


---

## snakemake 实现

# samtools / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 缺失或需要本地定制时的 **Snakemake 自维护 rule** 占位。
>
> 使用规范：
> - `source_type: custom`、`type: snakemake_local`
> - 每条 rule 一个 `rule_<name>.py` / `rule_<name>.smk` 文件（按团队习惯二选一）
> - 目录内须包含 `meta.yaml`
>
> 当前无自定义 Snakemake rule。登记占位用于 skill-cli / registry 扫描识别。


---

## Conda 环境（原 native/environment.yml）

```yaml
# samtools native Conda 环境配方
# 创建：mamba env create -f environment.yml
name: samtools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - samtools=1.21
  - htslib=1.21
  - pyyaml>=6.0
  - pip
  - pip:
      - -e .  # 若把 native/ 打包为可安装包（可选）
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/samtools/overview
- **Docker**：`docker pull quay.io/biocontainers/samtools:1.21--h96c455f_1`
- **Singularity**：https://depot.galaxyproject.org/singularity/samtools%3A1.21--h96c455f_1
- 安装方式（本地）：`mamba create -n samtools -c conda-forge -c bioconda samtools=1.21`
