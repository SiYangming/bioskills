# fastqc / nextflow / nf-core — 官方模块标注目录

本目录只做 **说明 + Schema + 引用信息**，不携带 nf-core 官方源码。
使用时必须在你的工作项目中通过官方途径安装：

```bash
nf modules install nf-core fastqc
```

推荐的标准用法（Nextflow DSL2）：

```nextflow
include { FASTQC } from './modules/nf-core/fastqc/main'

workflow QC {
    take: reads_ch   // [ meta, [R1,R2] ] 或 [ meta, R1 ]
    main:
        FASTQC(reads_ch)
    emit:
        FASTQC.out.html
        FASTQC.out.zip
}
```

输入/输出与 `module.json`、`meta.yaml` 中的声明保持一致。
版本：`fastqc=0.12.1`（官方 modules 侧 v2.1.0 测试）。
