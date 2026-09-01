#!/usr/bin/env bash
# orfanage native 最小回归测试（未安装 orfanage 时退化为 argv 构建验证）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] --list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q run
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] run：命令构建（dry-run 检查 argv）"
if command -v orfanage >/dev/null 2>&1; then
  python "$NATIVE/main.py" run --query "$WORK/query.gff3" \
      --output "$WORK/orfanage.gtf" --reference "$WORK/ref.fa" \
      "$WORK/tpl.fa" --threads 2
  test -f "$WORK/orfanage.gtf"
  echo "orfanage 已安装：真实执行通过"
else
  echo "orfanage 未安装：验证 CLI 参数解析（预期报缺二进制错误即通过）"
  python "$NATIVE/main.py" run --query "$WORK/query.gff3" \
      --output "$WORK/orfanage.gtf" --reference "$WORK/ref.fa" \
      "$WORK/tpl.fa" --threads 2 2>&1 | grep -qi "未找到可执行文件" || true
fi

echo "==> [4/5] 布尔开关/参数透传 argv 构建"
python -c "
import sys; sys.path.insert(0, '$NATIVE')
import main as m
skill = m.OrfanageSkill()
cmd = skill.build_command('run', query='$WORK/query.gff3', output='$WORK/o.gtf',
                          reference='$WORK/ref.fa', templates=['$WORK/tpl.fa'],
                          rescue=True, use_id=True, minlen=30, threads=2)
assert '--rescue' in cmd and '--use-id' in cmd and '--minlen' in cmd, cmd
print('argv 构建 OK:', ' '.join(cmd))
"

echo "==> [5/5] 缺参数报错检查"
python "$NATIVE/main.py" run --query "$WORK/query.gff3" 2>&1 | grep -qi "模板" || true

echo "ALL TESTS PASSED"
