# gunzip / native

自包含的 gunzip 驱动实现（`source_type: custom`），命令逻辑迁移自
`snakemake.smk/isoseq.smk/workflow/modules/gunzip/snakemake/gunzip.smk`（`gzip -cd <in.gz> > <out>`）。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `gunzip` | 解压 .gz 文件（`gzip -cd <in.gz> > <out>`） | —（单线程） |

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
conda activate gunzip-native
```

### 2. CLI 调用

```bash
python main.py gunzip genome.fa.gz -o genome.fa
python main.py gunzip reads.fq.gz          # 默认输出 reads.fq
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行

```bash
docker build -t bioskills/gunzip:1.12-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/gunzip:1.12-v1.0 \
  gunzip /data/genome.fa.gz -o /data/genome.fa
```

### 5. 测试

```bash
bash test/run_test.sh
```

## 说明

- 二进制为 `gzip`（`gunzip` 是其硬链接前端）；`gzip -cd` 同时兼容 GNU gzip 与 macOS 系统 gzip。
- 成功后会在输出文件同目录写 `versions.yml`（与 nf-core/gunzip 对齐）。
- 临时目录/线程参数（`--tmpdir` / `--threads`）按 skill 统一契约保留；`gzip -cd` 本身单线程。
