"""bioskills 技能库基础层。

提供：
- 硬件资源探测（CPU 线程、内存上限、临时目录）
- 统一元数据加载（meta.yaml）
- meta.yaml -> JSON Schema 导出（供 AI Agent Function Calling）
- 输入校验与子进程流式执行封装
- SkillBase：所有 native 技能驱动的统一基类
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

import yaml


# --------------------------------------------------------------------------- #
# 硬件资源探测
# --------------------------------------------------------------------------- #
def detect_cpus(default: int = 4, cap: int = 16) -> int:
    """探测当前可用 CPU 线程数（受 cgroup / affinity 约束），并做上限裁剪。"""
    try:
        n = len(os.sched_getaffinity(0))  # type: ignore[attr-defined]
    except AttributeError:
        n = os.cpu_count() or default
    if not n or n < 1:
        return default
    return min(n, cap)


def detect_memory_mb(default: int = 8192) -> int:
    """探测可用内存（MB）。优先读 /proc/meminfo，失败回退默认值。"""
    try:
        with open("/proc/meminfo", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("MemAvailable:"):
                    return int(line.split()[1]) // 1024
    except Exception:
        pass
    return default


def default_tmpdir() -> str:
    """返回推荐的临时目录（优先 $TMPDIR，其次 /tmp）。"""
    return os.environ.get("TMPDIR", "/tmp")


# --------------------------------------------------------------------------- #
# 元数据加载
# --------------------------------------------------------------------------- #
def load_meta(meta_path: str | Path) -> dict[str, Any]:
    """加载 meta.yaml 为字典。"""
    with open(meta_path, encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


# --------------------------------------------------------------------------- #
# JSON Schema 导出
# --------------------------------------------------------------------------- #
class SchemaExporter:
    """把 native/meta.yaml 的 inputs/outputs/optimization 转换为 JSON Schema，
    便于挂载到大模型 Agent 的 tools / function calling 接口。"""

    @staticmethod
    def _yaml_type_to_json(yaml_type: str | None) -> str:
        mapping = {
            "file": "string",
            "string": "string",
            "integer": "integer",
            "int": "integer",
            "float": "number",
            "number": "number",
            "boolean": "boolean",
            "bool": "boolean",
            "map": "object",
        }
        if not yaml_type:
            return "string"
        return mapping.get(yaml_type.lower(), "string")

    @staticmethod
    def _normalize_io_block(block: Any) -> dict[str, dict[str, Any]]:
        """把 meta.yaml 的 inputs/outputs 规范成 {name: spec} 形式。

        本仓库两种写法都允许：
        1) 字典形式（推荐 native / local 使用）
            inputs:
              reads: { type: file, required: true }
        2) 列表形式（nf-core / snakemake-wrappers 为贴近官方 schema 常见写法）
            inputs:
              - name: reads
                type: file
                required: true
        """
        if block is None:
            return {}
        if isinstance(block, dict):
            return {k: (v if isinstance(v, dict) else {}) for k, v in block.items()}
        if isinstance(block, list):
            out: dict[str, dict[str, Any]] = {}
            for item in block:
                if not isinstance(item, dict):
                    continue
                name = item.get("name")
                if not name:
                    continue
                spec = {k: v for k, v in item.items() if k != "name"}
                out[name] = spec
            return out
        return {}

    @staticmethod
    def meta_to_json_schema(meta: dict[str, Any]) -> dict[str, Any]:
        software = meta.get("software", "skill")
        skill_id = meta.get("id", software)
        inputs = SchemaExporter._normalize_io_block(meta.get("inputs"))
        properties: dict[str, Any] = {}
        required: list[str] = []
        for name, spec in inputs.items():
            spec = spec or {}
            jtype = SchemaExporter._yaml_type_to_json(spec.get("type"))
            prop: dict[str, Any] = {"type": jtype}
            if "description" in spec:
                prop["description"] = spec["description"]
            if "default" in spec:
                prop["default"] = spec["default"]
            if spec.get("format") in ("file", "directory"):
                prop["format"] = "path"
            # 列表块写法里 pattern 常放在 IO 层，这里挂到 prop 便于 Agent 参考
            if "pattern" in spec:
                prop["pattern"] = spec["pattern"]
            properties[name] = prop
            if spec.get("required"):
                required.append(name)

        opt = meta.get("optimization", {}) or {}
        for k, v in opt.items():
            if k.startswith("default_") or k == "env_vars":
                properties.setdefault(k, {"type": "string"})

        return {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": skill_id,
            "description": meta.get("summary", f"{software} skill"),
            "type": "object",
            "properties": properties,
            "required": required,
        }

    @staticmethod
    def export_file(meta_path: str | Path, out_path: str | Path | None = None) -> str:
        """导出 JSON Schema 到文件，默认与 meta.yaml 同目录。"""
        meta = load_meta(meta_path)
        schema = SchemaExporter.meta_to_json_schema(meta)
        if out_path is None:
            out_path = Path(meta_path).with_suffix(".schema.json")
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(schema, fh, indent=2, ensure_ascii=False)
        return str(out_path)


# --------------------------------------------------------------------------- #
# 子进程执行
# --------------------------------------------------------------------------- #
@dataclass
class RunResult:
    """子进程执行结果。"""
    command: list[str]
    returncode: int
    stdout: str = ""
    stderr: str = ""

    @property
    def ok(self) -> bool:
        return self.returncode == 0


def run_command(
    args: Iterable[str],
    *,
    env: dict[str, str] | None = None,
    cwd: str | Path | None = None,
    check: bool = True,
    capture: bool = True,
) -> RunResult:
    """流式执行外部命令，统一捕获 stdout/stderr。

    - capture=False 时直接继承父进程 IO（适合交互式或大流量输出）。
    - check=True 时失败抛出 CalledProcessError 风格的 RuntimeError。
    """
    cmd = list(args)
    run_env = os.environ.copy()
    if env:
        run_env.update(env)
    try:
        proc = subprocess.run(
            cmd,
            env=run_env,
            cwd=cwd,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(f"可执行文件未找到: {cmd[0]}") from exc

    result = RunResult(command=cmd, returncode=proc.returncode,
                       stdout=proc.stdout or "", stderr=proc.stderr or "")
    if check and not result.ok:
        raise RuntimeError(
            f"命令执行失败 (code={result.returncode}): {' '.join(cmd)}\n"
            f"stderr:\n{result.stderr}"
        )
    return result


def which(binary: str) -> str | None:
    """安全探测可执行文件路径。"""
    return shutil.which(binary)


# --------------------------------------------------------------------------- #
# SkillBase
# --------------------------------------------------------------------------- #
class SkillBase:
    """所有 native 技能驱动的统一基类。

    子类需设置 ``software`` 与 ``default_subcommands``，并实现 ``build_command``。
    """

    software: str = ""
    binary: str = ""

    def __init__(self, meta_path: str | Path | None = None):
        self.meta_path = Path(meta_path) if meta_path else self._guess_meta_path()
        self.meta: dict[str, Any] = load_meta(self.meta_path) if self.meta_path.exists() else {}
        opt = self.meta.get("optimization", {}) or {}
        self.cpus: int = int(opt.get("default_cpus", detect_cpus()))
        self.mem_mb: int = int(opt.get("default_mem_mb", detect_memory_mb()))
        self.tmpdir: str = opt.get("tmpdir", default_tmpdir())
        self.env_vars: dict[str, str] = self._render_env_vars(opt.get("env_vars", {}))

    # -- 内部工具 ----------------------------------------------------------- #
    def _guess_meta_path(self) -> Path:
        # base.py 位于 modules/ 下，技能目录为其兄弟：modules/<software>/native/meta.yaml
        return Path(__file__).resolve().parent / self.software / "native" / "meta.yaml"

    def _render_env_vars(self, env_vars: dict[str, str]) -> dict[str, str]:
        """渲染环境变量中的 {tmpdir}/{cpus}/{mem_mb} 占位符。"""
        ctx = {"tmpdir": self.tmpdir, "cpus": str(self.cpus), "mem_mb": str(self.mem_mb)}
        rendered: dict[str, str] = {}
        for k, v in env_vars.items():
            try:
                rendered[k] = v.format(**ctx)
            except (KeyError, IndexError):
                rendered[k] = v
        return rendered

    def _resolve_binary(self) -> str:
        bin_name = self.binary or self.software
        path = which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def make_tmpdir(self, prefix: str | None = None) -> str:
        """在配置的 tmpdir 下创建临时目录并返回路径。"""
        prefix = prefix or f"{self.software}_"
        return tempfile.mkdtemp(prefix=prefix, dir=self.tmpdir)

    # -- 子类接口 ----------------------------------------------------------- #
    def build_command(self, subcommand: str, **kwargs: Any) -> list[str]:
        """子类实现：把参数转换为实际命令行。"""
        raise NotImplementedError

    def run(self, subcommand: str, **kwargs: Any) -> RunResult:
        """构建并执行命令，自动注入线程/环境变量。"""
        args = self.build_command(subcommand, **kwargs)
        return run_command(args, env=self.env_vars)

    def schema(self) -> dict[str, Any]:
        """导出本技能的 JSON Schema。"""
        return SchemaExporter.meta_to_json_schema(self.meta)

    def emit_schema(self, out_path: str | Path | None = None) -> str:
        return SchemaExporter.export_file(self.meta_path, out_path)


# --------------------------------------------------------------------------- #
# CLI 自省入口
# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    """``python -m skills.base <meta.yaml> [--schema]`` 导出 JSON Schema。"""
    args = argv or sys.argv[1:]
    if not args:
        print("用法: python -m skills.base <meta.yaml> [--schema]", file=sys.stderr)
        return 2
    meta_path = args[0]
    if "--schema" in args or len(args) == 1:
        out = SchemaExporter.export_file(meta_path)
        print(f"已导出 JSON Schema -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
