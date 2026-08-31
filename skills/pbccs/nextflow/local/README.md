# pbccs / nextflow / local — 自定义 Nextflow 模块

> 本目录为 nf-core 缺失或需要本地定制时的 **Nextflow 自定义模块**占位。
>
> 使用规范：
> - `source_type: custom`、`type: nextflow_local`
> - 每个 process 一个 `.nf` 文件，文件名即 process 名（Snake_Case → CamelCase）
> - 目录内须包含 `meta.yaml` 与一个示例 `main.nf`
>
> 当前无自定义 Nextflow 模块。登记占位用于 skill-cli / registry 扫描识别。
> 需要时建议把 native 的 ccs 命令逻辑（--chunk/--min-rq/--min-passes/--min-snr/--min-length/--max-length/--top-passes -j）封装为 process。
