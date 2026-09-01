# dorado / nextflow / local — 自定义 Nextflow 模块

> 本目录为 nf-core 缺失或需要本地定制时的 **Nextflow 自定义模块**占位。
>
> 使用规范：
> - `source_type: custom`、`type: nextflow_local`
> - 每个 process 一个 `.nf` 文件，文件名即 process 名（Snake_Case → CamelCase）
> - 目录内须包含 `meta.yaml` 与一个示例 `main.nf`
>
> 当前无自定义 Nextflow 模块。登记占位用于 skill-cli / registry 扫描识别。
> 需要时建议把 native 的两个子命令（basecall / demux）封装为 `DORADO_BASECALL` /
> `DORADO_DEMUX` 两个 process，container 用 nanoseq config 默认的
> `docker.1ms.run/nanoporetech/dorado:latest`，RNA 模型默认
> `rna004_130bps_sup@v5.1.0`（nanoseq `enable_dorado` 开关为 false 时可跳过整条链路）。
