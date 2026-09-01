#!/usr/bin/env python3
"""isoseq — Docker 环境 Snakemake 执行支持（留存自 flrnaseq.smk 模式）。

参考 flrnaseq.smk/workflow/scripts/docker_wrapper.py 的实现方式，
为 Iso-Seq 流程各工具（pbccs/lima/isoseq3/bamtools/gstama/minimap2/ultra）
提供 docker / native / conda 三种执行模式的统一包装。

用法（在 Snakemake 规则中）：
    import scripts.docker_wrapper as dw   # 或用 run: 内联调用
    prefix, bin = dw.docker_wrapper_binary(config, "pbccs", "ccs_bin", "ccs")
    shell(f"{prefix} {bin} <args>")

说明：迁移自原 snakemake.smk/isoseq.smk（common.smk 中 docker_run lambda），
因迁移时规则去掉了 docker 分支，此处按 flrnaseq 的留存方式补回。
"""


def docker_run(exec_mode, platform="linux/amd64"):
    """返回 docker run 基础命令前缀（等价于原 common.smk 的 docker_run lambda）。

    使用 shell 求值的 $(pwd) 与 $(id -u):$(id -g)，保证挂载与用户一致，
    避免输出文件被 root 持有。
    """
    if exec_mode == "docker":
        return f"docker run --rm --platform {platform} -v $(pwd):$(pwd) -u $(id -u):$(id -g) -w $(pwd) "
    return ""


def docker_wrapper_binary(config, tool_name, bin_key, default_bin):
    """根据 exec_mode 决定 (命令前缀, 工具二进制)，逻辑提取自 flrnaseq 实现。

    Args:
        config: snakemake.config 字典（需含 exec_mode 与 tool_name 段）
        tool_name: config 中工具配置的 key（如 'pbccs' / 'lima' / 'minimap2'）
        bin_key: 工具段中二进制路径的 key（如 'ccs_bin' / 'lima_bin'）
        default_bin: 默认二进制名（docker/conda 模式使用）

    Returns:
        tuple[str, str]: (docker_wrapper, binary_path)；native 模式 wrapper 为空串。
    """
    exec_mode = config.get("exec_mode", "native")

    if exec_mode == "docker":
        docker_image = config.get(tool_name, {}).get("docker_image")
        if not docker_image:
            raise ValueError(
                f"Missing docker_image in config under '{tool_name}' section "
                f"when exec_mode is docker!"
            )
        wrapper = f"{docker_run(exec_mode)}{docker_image} "
        return wrapper, default_bin

    if exec_mode == "native":
        tool_bin = config.get(tool_name, {}).get(bin_key)
        if not tool_bin:
            raise ValueError(f"Missing {bin_key} in config when exec_mode is native!")
        return "", tool_bin

    # conda / apptainer / singularity：直接使用 PATH 中的默认二进制
    return "", default_bin


# --------------------------------------------------------------------------- #
# Iso-Seq 工具默认二进制名速查（供规则直接引用）
# --------------------------------------------------------------------------- #
ISOSEQ_TOOLS = {
    "pbccs":    {"bin_key": "ccs_bin",        "default_bin": "ccs"},
    "lima":     {"bin_key": "lima_bin",       "default_bin": "lima"},
    "isoseq3":  {"bin_key": "isoseq3_bin",    "default_bin": "isoseq3"},
    "bamtools": {"bin_key": "bamtools_bin",   "default_bin": "bamtools"},
    "gstama":   {"bin_key": "gstama_bin",     "default_bin": "tama_flnc_polya_cleanup.py"},
    "minimap2": {"bin_key": "minimap2_bin",   "default_bin": "minimap2"},
    "ultra":    {"bin_key": "ultra_bin",      "default_bin": "uLTRA"},
}


def isoseq_wrapper(config, tool_name):
    """便捷封装：按 ISOSEQ_TOOLS 速查表为指定工具返回 (wrapper, binary)。"""
    if tool_name not in ISOSEQ_TOOLS:
        raise KeyError(f"未在 ISOSEQ_TOOLS 中登记的工具: {tool_name}")
    spec = ISOSEQ_TOOLS[tool_name]
    return docker_wrapper_binary(config, tool_name, spec["bin_key"], spec["default_bin"])


if __name__ == "__main__":
    import sys
    import yaml

    cfg = yaml.safe_load(open(sys.argv[1])) if len(sys.argv) > 1 else {}
    print("exec_mode:", cfg.get("exec_mode", "native"))
    for tool in ISOSEQ_TOOLS:
        try:
            w, b = isoseq_wrapper(cfg, tool)
            print(f"  {tool:10s} -> wrapper={w!r:40s} bin={b}")
        except ValueError as exc:
            print(f"  {tool:10s} -> [ERROR] {exc}")
