#!/usr/bin/env python3

def docker_run(exec_mode, platform="linux/amd64"):
    """
    Returns the base docker run command string (equivalent to common.smk logic).
    Use this for shell injection where $(pwd) and $(id) are evaluated by the shell.
    """
    if exec_mode == "docker":
        return f"docker run --rm --platform {platform} -v $(pwd):$(pwd) -u $(id -u):$(id -g) -w $(pwd) "
    return ""

def docker_wrapper_binary(config, tool_name, bin_key, default_bin):
    """
    Determines execution mode and returns (cmd_prefix, tool_bin).
    Logic extracted from transdecoder_longorfs.py.
    
    Args:
        config: snakemake.config dictionary
        params: snakemake.params object (or dict)
        tool_name: Key in config for tool settings (e.g. 'transdecoder')
        bin_key: Key in tool settings for binary path (e.g. 'transdecoder_longorfs_bin')
        default_bin: Default binary name (e.g. 'TransDecoder.LongOrfs')
        
    Returns:
        tuple: (docker_wrapper, binary_path)
    """
    exec_mode = config["exec_mode"]
    
    if exec_mode == "docker":
        docker_image = config[tool_name]["docker_image"]
        if not docker_image:
            raise ValueError(f"Missing docker_image in config/config.yaml under {tool_name} section when exec_mode is docker!")
        
        # Call docker_run function directly instead of relying on params
        docker_cmd = docker_run(exec_mode)
             
        docker_wrapper = f"{docker_cmd}{docker_image} "
        tool_bin = default_bin
        return docker_wrapper, tool_bin

    elif exec_mode == "native":
        tool_bin = config[tool_name][bin_key]
        if not tool_bin:
             raise ValueError(f"Missing {bin_key} in config when exec_mode is native!")
        return "", tool_bin

    else: # conda or apptainer/singularity
        return "", default_bin
