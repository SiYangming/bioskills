# minimap2 / native

自包含的 minimap2 驱动实现（`source_type: custom`）。

## 能力

| 子命令 | 说明 |
|--------|------|
| `align` | reads → 参考基因组比对；`--bam` 输出 BAM（`minimap2 -a | samtools sort | samtools view -b -h`），否则输出 PAF |

支持 `--cigar-paf`（PAF 输出 CIGAR，`-c`）与 `--cigar-bam`（长 CIGAR 写 CG 标签，`-L`）；
不提供 `--reference` 时退化为 reads vs reads 自比对。命令逻辑迁移自 `isoseq.py/minimap2_align.py`，
与 nf-core `minimap2/align` 核心行为一致。

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
conda activate minimap2-native
```

### 2. CLI 调用

```bash
# PAF 输出
python main.py align --reads flnc.fa --reference ref.fa --outdir aln --prefix sample --threads 8

# BAM 输出（依赖 samtools）
python main.py align --reads flnc.fa --reference ref.fa --outdir aln --bam --threads 8

# 透传 minimap2 参数（splice 模式示例）
python main.py align --reads flnc.fa --reference ref.fa --outdir aln \
    --args "-x splice -uf -k14" --bam --threads 8
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py align --reads x.fa --reference r.fa --dry-run   # 只打印构建出的命令
```

### 4. 容器运行

```bash
docker build -t bioskills/minimap2:2.24-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/minimap2:2.24-v1.0 \
  align --reads /data/flnc.fa --reference /data/ref.fa --outdir /data/aln --bam --threads 8
```

Apptainer：

```bash
apptainer build minimap2.sif Apptainer.def
apptainer run -B "$PWD":/data minimap2.sif align --reads /data/flnc.fa --reference /data/ref.fa --outdir /data --bam
```

### 5. 测试

```bash
bash test/run_test.sh
```

## 版本说明

- **native 二进制**：`minimap2 2.24`（Debian bookworm 官方 apt `2.24+dfsg-3`）+ `samtools`（apt，BAM 管线）。
- **Conda 兜底**：`environment.yml` 用 bioconda `minimap2=2.24 + samtools=1.21`。
- **与流程原配差异**：isoseq.smk 原配为 bioconda `minimap2=2.28`（`quay.io/biocontainers/minimap2:2.28--h577a1d6_4`）。
  2.24 与 2.28 对本流程（Iso-Seq FLNC 比对）行为一致；若需完全对齐 2.28，
  用 micromamba 装 `bioconda::minimap2=2.28`（Dockerfile 注释已写明替换方式）。
- nf-core / snakemake-wrappers 侧版本见软件级 `meta.yaml` 的 `software_versions`。

## 性能优化约定

- **线程**：`align` 默认 8 线程（CPU 密集），用户显式 `--threads` 永远优先；`-t` 注入 minimap2，
  samtools sort/view 同步使用。
- **临时目录**：`--tmpdir` 覆盖 `$TMPDIR`；中间 SAM 走管道不落盘（`pipefail` 保证失败传导）。
- **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。
