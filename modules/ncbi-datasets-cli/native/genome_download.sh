#!/bin/bash
set -euo pipefail

###########################################################################
# NCBI 基因组批量下载脚本（genome_download.sh）
# 功能：使用 NCBI datasets 工具批量下载基因组序列（FASTA）与注释（GFF3/GBFF），
#       支持失败重试、解压后 MD5 完整性校验、历史数据断点跳过与按物种分类归置。
# 说明：本脚本为模块 native/ 的经典批量脚本（等价能力主线见 native/main.py 的
#       datasets download 子命令；本脚本补充「批量 + 重试 + MD5 断点 + 分类」能力）。
#       注释默认 --include genome,gff3（GFF3）；如需 GenBank 格式请改用 --include gbff，
#       脚本会自动识别 .gff / .gbff 任一注释文件。
###########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# ===== 颜色输出 =====
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# ===== 默认配置 =====
MAX_RETRIES=3
DOWNLOAD_DIR="."
FASTA_DIR=""
GENES_DIR=""
SPECIES_LIST="species_list.txt"
INCLUDE="genome,gff3"          # 下载数据类型：genome,gff3（注释 GFF3）；改 genome,gbff 则取 GenBank

# ===== 帮助信息 =====
show_help() {
    cat <<EOF
================================================================
  NCBI 基因组批量下载脚本 (genome_download.sh)
================================================================
功能：使用 NCBI datasets 工具批量下载基因组序列和基因注释

用法:
  ./$SCRIPT_NAME [选项]

选项:
  -i, --input FILE      物种列表文件（默认: species_list.txt）
                        文件格式：每行两列，第一列 accession，第二列名称
  -o, --output DIR      输出目录（默认: 当前目录）
  --fasta-dir DIR       FASTA 输出目录（默认: <output>/FASTA）
  --genes-dir DIR       注释输出目录（默认: <output>/GENE）
  --include TYPES       datasets 下载数据类型（默认: genome,gff3；注释文件为 .gff，
                        可改 genome,gbff 取 GenBank .gbff，脚本自动识别两者）
  --retries N           下载失败重试次数（默认: 3）
  -h, --help            显示此帮助信息

物种列表格式:
  GCF_000001405.39    Homo_sapiens
  GCF_000001635.27    Mus_musculus
  # 以 # 开头的行为注释

示例:
  # 使用默认配置
  ./$SCRIPT_NAME

  # 指定物种列表和输出目录
  ./$SCRIPT_NAME -i my_species.txt -o /data/genomes

  # 设置重试次数为5次
  ./$SCRIPT_NAME --retries 5

依赖:
  - NCBI datasets 命令行工具
    下载: https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/LATEST/
================================================================
EOF
}

# ===== 参数解析 =====
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input)
            SPECIES_LIST="${2:?--input 需要文件路径}"
            shift 2
            ;;
        -o|--output)
            DOWNLOAD_DIR="${2:?--output 需要目录路径}"
            shift 2
            ;;
        --fasta-dir)
            FASTA_DIR="${2:?--fasta-dir 需要目录路径}"
            shift 2
            ;;
        --genes-dir)
            GENES_DIR="${2:?--genes-dir 需要目录路径}"
            shift 2
            ;;
        --include)
            INCLUDE="${2:?--include 需要数据类型（如 genome,gff3）}"
            shift 2
            ;;
        --retries)
            MAX_RETRIES="${2:?--retries 需要次数}"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}错误：未知参数 '$1'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

# ===== 目录初始化 =====
if [ -z "$FASTA_DIR" ]; then
    FASTA_DIR="${DOWNLOAD_DIR}/FASTA"
fi
if [ -z "$GENES_DIR" ]; then
    GENES_DIR="${DOWNLOAD_DIR}/GENE"
fi

mkdir -p "$FASTA_DIR" "$GENES_DIR"

# ===== 依赖检查 =====
if ! command -v datasets &> /dev/null; then
    echo -e "${RED}【错误】未找到 datasets 命令，请先安装 NCBI datasets 工具（bash native/install.sh）。${NC}"
    exit 1
fi

if [ ! -f "$SPECIES_LIST" ]; then
    echo -e "${RED}【错误】物种列表文件不存在: $SPECIES_LIST${NC}"
    echo "请创建文件，格式：每行两列，accession 和物种名称，用空格或制表符分隔"
    exit 1
fi

# ===== 下载函数（带重试；失败命令置于 if 条件位，避免 set -e 提前退出） =====
download_with_retry() {
    local acc="$1"
    local name="$2"
    local filename="$3"
    local attempt

    for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
        echo -e "${YELLOW}[尝试 ${attempt}/${MAX_RETRIES}]${NC} 正在下载 ${name}..."
        if datasets download genome accession "$acc" --include "$INCLUDE" --filename "$filename"; then
            return 0
        fi
        echo -e "${RED}[尝试 ${attempt}/${MAX_RETRIES}]${NC} 下载失败，5秒后重试..."
        sleep 5
    done

    return 1
}

# ===== 文件归置函数（FASTA -> FASTA/<name>/；注释 .gff/.gbff -> GENE/<name>/） =====
move_files() {
    local name="$1"
    local acc="$2"
    local data_dir="${DOWNLOAD_DIR}/${name}_data"
    local fasta_file gff_file

    # 序列文件 *.fna 与注释文件 *.gff / *.gbff（datasets 包内结构固定，按 accession 定位）
    fasta_file=$(find "$data_dir/ncbi_dataset/data/$acc" -type f \( -name "*.fna" \) 2>/dev/null | head -1)
    gff_file=$(find "$data_dir/ncbi_dataset/data/$acc" -type f \( -name "*.gff" -o -name "*.gbff" \) 2>/dev/null | head -1)

    mkdir -p "$FASTA_DIR/$name"
    if [ -n "$fasta_file" ]; then
        cp "$fasta_file" "$FASTA_DIR/$name/${name}.fa"
        echo -e "${GREEN}✅ FASTA 已保存到 ${FASTA_DIR}/${name}/${name}.fa${NC}"
    else
        echo -e "${YELLOW}⚠️  未找到 FASTA 文件${NC}"
    fi

    if [ -n "$gff_file" ]; then
        mkdir -p "$GENES_DIR/$name"
        cp "$gff_file" "$GENES_DIR/$name/$(basename "$gff_file")"
        echo -e "${GREEN}✅ 注释已保存到 ${GENES_DIR}/${name}/$(basename "$gff_file")${NC}"
    else
        echo -e "${YELLOW}⚠️  未找到注释文件（.gff/.gbff），检查 --include 是否包含注释类型${NC}"
    fi
}

# ===== 解压数据包并做 MD5 完整性校验（返回 0=通过） =====
verify_package() {
    local name="$1"
    local zip_file="$2"
    local data_dir="$3"

    if ! unzip -qo "$zip_file" -d "$data_dir/" < /dev/null; then
        echo -e "${RED}【错误】${name} 解压失败！${NC}"
        return 1
    fi

    if (cd "$data_dir" && md5sum --quiet -c md5sum.txt); then
        return 0
    else
        echo -e "${RED}【错误】${name} MD5 校验失败！文件可能损坏或不完整${NC}"
        echo "已保留压缩包与解压目录，请检查网络后重新运行"
        return 1
    fi
}

# ===== 主循环 =====
total=0
success=0
failed=0

while read -r acc name; do
    [[ -z "$acc" || "$acc" =~ ^# ]] && continue

    total=$((total + 1))
    data_dir="${DOWNLOAD_DIR}/${name}_data"
    filename="${DOWNLOAD_DIR}/${name}.zip"

    echo "========================================="
    echo -e "物种: ${GREEN}${name}${NC} (${acc})"
    echo "========================================="

    # 检查历史数据：目录存在且 md5 通过 → 断点跳过（重新归置一次文件）
    if [ -d "$data_dir" ] && [ -f "${data_dir}/md5sum.txt" ]; then
        echo "发现已有数据，正在校验历史数据完整性..."
        if (cd "$data_dir" && md5sum --quiet -c md5sum.txt); then
            echo -e "${GREEN}【跳过】${name} 历史数据完整，无需重复下载${NC}"
            move_files "$name" "$acc"
            success=$((success + 1))
            echo ""
            continue
        else
            echo -e "${YELLOW}【提示】${name} 历史数据损坏，将重新下载${NC}"
            rm -rf "$data_dir"
        fi
    fi

    # 下载 + 解压 + 校验
    if download_with_retry "$acc" "$name" "$filename"; then
        echo "下载完成，正在解压并校验..."
        rm -rf "$data_dir"
        if verify_package "$name" "$filename" "$data_dir"; then
            echo -e "${GREEN}【成功】${name} 校验通过，数据完整${NC}"
            rm -f "$filename"
            move_files "$name" "$acc"
            echo -e "${GREEN}${name} 处理完成！${NC}"
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
    else
        echo -e "${RED}【错误】${name} (${acc}) 下载失败，已尝试 ${MAX_RETRIES} 次${NC}"
        failed=$((failed + 1))
    fi
    echo ""

done < "$SPECIES_LIST"

# ===== 统计总结 =====
echo "========================================="
echo -e "下载完成！总计: ${total} 个物种"
echo -e "成功: ${GREEN}${success}${NC}  失败: ${RED}${failed}${NC}"
echo "========================================="

if [ "$failed" -gt 0 ]; then
    exit 1
fi
exit 0
