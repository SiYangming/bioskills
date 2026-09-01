# fastqc nextflow local 自定义实现

仅作为占位：当 nf-core 官方 FASTQC 不符合特殊参数需求（例如自定义 -k / -c 污染序列、强制 format 等）时使用。

## 启用步骤

1. 打开本目录下的 `main.nf.template`，按参数需求定制为 `main.nf`；
2. 将本目录复制到用户项目的 `modules/local/fastqc/`；
3. 在 workflow 中：

```nextflow
include { FASTQC_LOCAL } from './modules/local/fastqc/main'
FASTQC_LOCAL( reads_ch )
```

4. 在本目录写好 `meta.yaml` / `module.json`（已预置骨架）。
