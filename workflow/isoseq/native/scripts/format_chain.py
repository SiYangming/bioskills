import subprocess
import argparse
import sys


def execute_tool(tool_name, command, allow_warnings=False):
    """执行单个工具，allow_warnings=True时非0返回码仅警告不终止"""
    print(f"=== 开始执行 {tool_name} ===")
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=not allow_warnings
        )
        print(f"✅ {tool_name} 执行成功")
        if result.stdout:
            print(f"输出信息:\n{result.stdout.strip()}\n")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ {tool_name} 发现问题（返回码：{e.returncode}）")
        print(f"详细信息:\n{e.stdout.strip()}\n{e.stderr.strip()}\n")
        if allow_warnings:
            print(f"⚠️ {tool_name} 存在警告，建议修复但不终止流程\n")
            return True
        return False
    except FileNotFoundError:
        print(f"❌ 未找到 {tool_name} 工具，请先安装：pip install {tool_name}\n")
        if allow_warnings:
            print(f"⚠️ 未安装 {tool_name}，已跳过此步骤\n")
            return True
        return False


def main():
    parser = argparse.ArgumentParser(
        description="代码格式化工具链（禁止切片冒号前后空格）",
        epilog="示例：python format_chain.py ./src"
    )
    parser.add_argument("targets", nargs="+", help="Python文件或目录路径")
    args = parser.parse_args()

    # 1. autoflake：清理未使用的导入和变量
    autoflake_cmd = [
        "autoflake",
        "--in-place",
        "--recursive",
        "--remove-unused-variables",
        "--remove-all-unused-imports",
        "--ignore-init-module-imports",
        *args.targets
    ]

    # 2. autopep8：核心处理切片空格（默认移除冒号前后空格，无需额外参数）
    autopep8_cmd = [
        "autopep8",
        "--in-place",
        "--recursive",
        "--aggressive",
        "--aggressive",
        "--max-line-length", "88",
        *args.targets
    ]

    # 3. isort：排序导入
    isort_cmd = [
        "isort",
        "--overwrite-in-place",
        "--profile", "black",
        "--filter-files",
        *args.targets
    ]

    # 4. yapf：仅保留必要配置（避免未知参数错误），依赖autopep8处理切片空格
    yapf_cmd = [
        "yapf",
        "--in-place",
        "--recursive",
        "--style", "{based_on_style: pep8, SPACES_AROUND_SUBSCRIPT_COLON: False}",
        *args.targets
    ]

    # 5. black：强制遵循PEP8，确保切片无空格（无需额外配置）
    black_cmd = [
        "black",
        "--quiet",
        *args.targets
    ]

    # 6. flake8：验证格式
    flake8_cmd = [
        "flake8",
        "--max-line-length", "88",
        *args.targets
    ]

    # 7. mypy：静态类型检查
    mypy_cmd = [
        "mypy",
        "--strict",
        "--show-error-codes",
        "--ignore-missing-imports",
        *args.targets
    ]

    # 工具链执行顺序
    tools = [
    ("black", black_cmd, False),
    ("autoflake", autoflake_cmd, False),
    ("isort", isort_cmd, False),
    ("autopep8", autopep8_cmd, False),
    ("yapf", yapf_cmd, False),
    ("flake8", flake8_cmd, False),
    ("mypy", mypy_cmd, True)
]

    for tool_name, cmd, allow_warnings in tools:
        success = execute_tool(tool_name, cmd, allow_warnings)
        if not success:
            print("❌ 工具链执行中断。")
            sys.exit(1)

    print("🎉 所有工具执行完成！切片冒号前后无空格，格式符合规范。")


if __name__ == "__main__":
    main()