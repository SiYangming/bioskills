# custom/nanoseq 测试数据（testdata/）

数据来源：**[nf-core/test-datasets](https://github.com/nf-core/test-datasets/tree/nanoseq/modification_fast5_fastq)** **[`nanoseq`](https://github.com/nf-core/test-datasets/tree/nanoseq/modification_fast5_fastq)** **[分支](https://github.com/nf-core/test-datasets/tree/nanoseq/modification_fast5_fastq)** **[`modification_fast5_fastq`](https://github.com/nf-core/test-datasets/tree/nanoseq/modification_fast5_fastq)**
（HEK293T-METTL3-KO-rep1 与 HEK293T-WT-rep1 两个样本的原始 fast5 与 basecalled fastq，Nanopore RNA-seq）。

本目录为**精简子集**（便于入库），完整数据见上方链接：

| 样本                     | 本目录内容                       | 官方完整内容                          |
| ---------------------- | --------------------------- | ------------------------------- |
| HEK293T-METTL3-KO-rep1 | 5 个 fast5 + fastq.gz (280K) | 302 个 fast5 (29.4MB) + fastq.gz |
| HEK293T-WT-rep1        | 5 个 fast5 + fastq.gz (152K) | 162 个 fast5 (16.3MB) + fastq.gz |

## 下载完整数据（需要全量时）

```bash
# 方式一：git clone 只取 nanoseq 分支（仓库较大，建议 sparse-checkout）
git clone --branch nanoseq --depth 1 --filter=blob:none --sparse \
    https://github.com/nf-core/test-datasets.git
cd test-datasets
git sparse-checkout set modification_fast5_fastq

# 方式二：单文件 raw 下载
curl -sfL \
  https://raw.githubusercontent.com/nf-core/test-datasets/nanoseq/modification_fast5_fastq/HEK293T-METTL3-KO-rep1/fastq/HEK293T-METTL3-KO-rep1.fastq.gz \
  -o HEK293T-METTL3-KO-rep1.fastq.gz
```

## 用法

* **fastq**：可直接作为 nanoseq 编排器 / minimap2 比对 / FLAIR / StringTie 的输入。

* **fast5**：供 dorado basecall 冒烟测试（`--with-dorado`），需解压 fast5 至目录。

```bash
# 冒烟：用 testdata fastq 跑 dry-run
python skills/custom/nanoseq/nanoseq.py \
    --samplesheet <(printf 'sample,input_file\nHEK293T-METTL3-KO-rep1,%s\n' \
        "$PWD/skills/custom/nanoseq/testdata/HEK293T-METTL3-KO-rep1/fastq/HEK293T-METTL3-KO-rep1.fastq.gz") \
    --reference ref.fa --gtf ref.gtf --outdir /tmp/nano_test
```

> 注：fast5/fastq 为官方原样二进制文件，未做任何修改；上游无版本标签，以分支 `nanoseq` + 路径为准。

