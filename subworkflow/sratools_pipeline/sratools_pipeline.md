# subworkflow/sratools_pipeline — SRA 批量获取档案

无上游自写编排（AGENT §0A：留在 bioskills）。一体化脚本：`native/sra_pipeline.sh`。

- 元数据：[sratools_pipeline.yaml](sratools_pipeline.yaml)
- 可执行档案：`native/sra_pipeline.sh`（download | convert | status | stop | clean）
- 安装资源：[modules/sra-tools](../../modules/sra-tools/README.md)
- 官方工具：<https://github.com/ncbi/sra-tools>

## 用法

```bash
cd subworkflow/sratools_pipeline/native

# 准备 SRR 列表（每行一个 accession；可用 test/generate_data.py 生成占位列表）
printf 'SRR000001\n' > SRR_Acc_List.txt

# 依赖：PATH 上有 prefetch、parallel；或 convert 用 --docker
./sra_pipeline.sh download --threads 4
./sra_pipeline.sh convert --threads 4
./sra_pipeline.sh convert --docker          # quay.io/biocontainers/sra-tools
./sra_pipeline.sh status | stop | clean
./sra_pipeline.sh --help
```

## Stage

```
SRR_Acc_List.txt
  → prefetch（并行）→ sra_downloads/<srr>/<srr>.sra
  → fastq-dump / Docker → fastq_files/
```

真跑需网络与已装工具；静态自检：`bash native/test/run_test.sh`（`bash -n` + `--help`，不下载）。
