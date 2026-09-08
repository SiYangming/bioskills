#!/usr/bin/env python3
"""lftp 测试数据生成（保持仓库轻量：只生成占位路径/目录，不进行真实下载）。

lftp 的真实下载/镜像需要远端 FTP/HTTPS 服务且会产生大文件 —— 测试无法在离线环境真实执行；
因此本脚本只生成供 run_test.sh 作 **argv 构造断言 / 命令串断言** 使用的占位素材：
  - <out>/dl/           占位本地下载目录（get/mirror 的 --local-dir 目标，验证 lcd 注入）
  - <out>/remote_paths.txt  占位远程路径清单（文本 fixture，供断言与文档示例引用；
        SRR797242 来自用户部署文档的 NCBI SRA 示例，其余为按 SRA 路径规则构造的占位示例，
        标注「占位」，不可当真库路径直接下载）
"""

from __future__ import annotations

import sys
from pathlib import Path

# NCBI SRA 布局示例（SRR797242 为用户部署文档中的真实示例；本文件仅作断言 fixture）
REMOTE_PATHS = [
    # (来源, 远程主机, 远程路径)
    ("NCBI-SRA(user doc example)", "ftp-trace.ncbi.nlm.nih.gov",
     "/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra"),
    # 占位构造（同规则推算，未核实）
    ("NCBI-SRA(placeholder)", "ftp-trace.ncbi.nlm.nih.gov",
     "/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797243/SRR797243.sra"),
    # 占位构造（ENA EBI 布局规则：前 6 字符分桶 /vol1/fastq/...，未核实）
    ("ENA-EBI(placeholder)", "ftp.sra.ebi.ac.uk",
     "/vol1/fastq/SRR797/SRR797242/SRR797242_1.fastq.gz"),
]


def main(outdir: str) -> None:
    work = Path(outdir)
    work.mkdir(parents=True, exist_ok=True)
    dl = work / "dl"
    dl.mkdir(parents=True, exist_ok=True)

    lines = [
        "# lftp 测试占位远程路径清单（argv 构造断言 fixture；标注占位，勿当真库路径下载）",
        "# 格式: <说明>\\t<远程主机>\\t<远程路径>",
    ]
    for desc, host, path in REMOTE_PATHS:
        lines.append(f"{desc}\t{host}\t{path}")
    (work / "remote_paths.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # 留空文件占位 dl 目录（避免空目录在 git 中不可见；运行测试时会被 -c 续传语义忽略）
    (dl / ".gitkeep").write_text("", encoding="ascii")

    print(f"[generate_data] wrote placeholder fixtures to {work}")
    for desc, host, path in REMOTE_PATHS:
        print(f"  - [{desc}] {host}{path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: generate_data.py <outdir>", file=sys.stderr)
        raise SystemExit(2)
    main(sys.argv[1])
