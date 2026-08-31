# fastqc / native 自包含实现

基于 bioconda `fastqc=0.12.1` + OpenJDK 17 的 Python 驱动包装：

- 自动注入 `-t` 线程（默认 4，可 CPU 核数协商）
- 通过 `JAVA_OPTS` 注入 JVM 最大堆内存（默认 8 GB）与 `TMPDIR`
- `-o` 不存在时自动创建
- `--nogroup` / `--extract` / `-f` / `-c` / `-a` / `-k` 等常见参数透传
- 运行时仍需本地安装 `fastqc` + `java`：推荐 `mamba env create -f environment.yml`

## CLI 用法示例

```bash
python main.py run sample_R1.fq.gz sample_R2.fq.gz -o qc_out --threads 8 --java-mem-mb 16384
python main.py run sample.fastq -f fastq --nogroup
python main.py --list-commands
python main.py --schema
```

## Docker 调用（推荐）

```bash
docker build -t bioskills/fastqc:0.12.1-v1.0 .
docker run --rm -u $(id -u):$(id -g) \
    -v "$PWD":/work -w /work \
    bioskills/fastqc:0.12.1-v1.0 \
    -c "python /work/main.py run sample_R1.fq.gz -o /work/qc_out --threads 8"
```

## 运行测试

```bash
bash test/run_test.sh
```
