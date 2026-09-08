#!/bin/bash
set -euo pipefail

###########################################################################
# SRA 数据处理一体化脚本
# 功能：并行下载 + SRA转FASTQ + 状态管理 + 错误处理
# 子命令：download, convert, status, stop, clean
# 合并自：batch_prefetch.sh, batch_prefetch 2.sh, batch_sra_to_fastq.sh, batch_sra_to_fastq_parallel.sh
###########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
LOCK_FILE="${SCRIPT_DIR}/.${SCRIPT_NAME}.lock"
OUTPUT_ROOT="${SCRIPT_DIR}/sra_downloads"
FASTQ_OUTPUT_DIR="${SCRIPT_DIR}/fastq_files"
PID_FILE="${OUTPUT_ROOT}/sra_pipeline.pid"
MASTER_LOG="${OUTPUT_ROOT}/sra_pipeline.log"
FAILED_FILE="${OUTPUT_ROOT}/failed.txt"
SRR_LIST="${SCRIPT_DIR}/SRR_Acc_List.txt"
THREADS=4
RUN_MODE=""
USE_DOCKER=false
DOCKER_IMAGE="quay.io/biocontainers/sra-tools:3.2.1--h4304569_1"
PARALLEL_BIN="${SCRIPT_DIR}/bin/parallel-20251122/src/parallel"
PREFETCH_BIN="${SCRIPT_DIR}/bin/sratoolkit.3.2.0-centos_linux64/bin/prefetch"
FASTQ_DUMP_BIN="${SCRIPT_DIR}/bin/sratoolkit.3.2.0-centos_linux64/bin/fastq-dump"

show_help() {
    cat <<'EOF'
================================================================
  SRA 数据处理一体化脚本 (sra_pipeline.sh)
================================================================
功能：并行下载SRA数据 + SRA转FASTQ + 状态管理 + 错误处理

用法:
  ./sra_pipeline.sh <子命令> [选项]

子命令:
  download    - 并行下载SRA数据（使用prefetch）
  convert     - 并行将SRA转换为FASTQ（使用fastq-dump）
  status      - 查看运行状态
  stop        - 停止任务
  clean       - 清理所有输出目录并重新运行

选项:
  --threads N          - 并行线程数（默认4）
  --srr-list FILE      - 指定SRR列表文件（默认 SRR_Acc_List.txt）
  --docker             - convert命令使用Docker版本的fastq-dump
  --docker-image IMAGE - 自定义Docker镜像
                         （默认 quay.io/biocontainers/sra-tools:3.2.1--h4304569_1）
  -h, --help           - 显示此帮助信息

示例:
  # 下载SRA数据
  ./sra_pipeline.sh download
  ./sra_pipeline.sh download --threads 8

  # 转换SRA为FASTQ（本地二进制）
  ./sra_pipeline.sh convert
  ./sra_pipeline.sh convert --threads 5

  # 使用Docker模式转换
  ./sra_pipeline.sh convert --docker
  ./sra_pipeline.sh convert --docker --threads 8

  # 使用自定义Docker镜像
  ./sra_pipeline.sh convert --docker --docker-image your/sra-tools:latest

  # 状态管理
  ./sra_pipeline.sh status    # 查看运行状态
  ./sra_pipeline.sh stop      # 停止任务
  ./sra_pipeline.sh clean     # 清理所有输出目录

输出目录:
  sra_downloads/   - SRA下载文件
  fastq_files/     - FASTQ转换结果
  sra_downloads/sra_pipeline.log - 运行日志
  sra_downloads/failed.txt      - 失败记录
================================================================
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        download|convert|status|stop|kill|clean)
            RUN_MODE="$1"
            shift
            ;;
        --threads)
            THREADS="$2"
            shift 2
            ;;
        --srr-list)
            SRR_LIST="$2"
            shift 2
            ;;
        --docker)
            USE_DOCKER=true
            shift
            ;;
        --docker-image)
            DOCKER_IMAGE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "错误：未知参数 '$1'"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

acquire_lock() {
    if ! mkdir "${LOCK_FILE}" 2>/dev/null; then
        echo "错误：检测到另一个 $SCRIPT_NAME 正在运行！"
        [ -f "$PID_FILE" ] && echo "旧进程 PID: $(cat "$PID_FILE")"
        echo "解决方法："
        echo "   $0 status     # 查看状态"
        echo "   $0 stop       # 正常停止"
        echo "   $0 clean      # 强制清理并重新运行"
        exit 1
    fi
}

release_lock() {
    rm -rf "${LOCK_FILE}" 2>/dev/null || true
}

trap release_lock EXIT

case "$RUN_MODE" in
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "任务运行中 → PID: $(cat "$PID_FILE")"
            echo "实时日志 → tail -f \"$MASTER_LOG\""
        else
            echo "无运行中的任务"
            [ -f "$PID_FILE" ] && echo "发现残留 PID 文件，可执行 $0 clean 清理"
        fi
        exit 0
        ;;
    stop|kill)
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE")
            if kill -0 "$pid" 2>/dev/null; then
                echo "正在终止进程 $pid ..."
                kill -9 "$pid" && echo "已终止"
            else
                echo "进程 $pid 已不存在"
            fi
            rm -f "$PID_FILE"
        fi
        release_lock
        echo "任务已停止，锁已释放"
        exit 0
        ;;
    clean)
        echo "正在强制停止并清理..."
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE")
            kill -9 "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
        fi
        rm -rf "${OUTPUT_ROOT}" "${LOCK_FILE}" "${FASTQ_OUTPUT_DIR}"
        find "${SCRIPT_DIR}" -maxdepth 2 -type f -name "*.lock" -delete
        echo ".lock 文件清理完成。"
        echo "清理完成！现在可以安全重新运行：./$SCRIPT_NAME"
        exit 0
        ;;
    download)
        acquire_lock
        mkdir -p "$OUTPUT_ROOT"
        echo "===== SRA 数据下载启动（$(date)）=====" | tee "$MASTER_LOG"
        echo "输出目录：$OUTPUT_ROOT" | tee -a "$MASTER_LOG"
        echo "并行线程数：$THREADS" | tee -a "$MASTER_LOG"
        echo "日志实时查看：tail -f \"$MASTER_LOG\""

        nohup "$0" __download_run --threads "$THREADS" --srr-list "$SRR_LIST" > "$MASTER_LOG" 2>&1 &
        echo $! > "$PID_FILE"
        echo "后台下载任务已启动！PID: $(cat "$PID_FILE")"
        echo "常用命令："
        echo "   $0 status    # 查看状态"
        echo "   $0 stop      # 停止任务"
        echo "   $0 clean     # 强制清理并重跑"
        exit 0
        ;;
    convert)
        acquire_lock
        mkdir -p "$FASTQ_OUTPUT_DIR"
        echo "===== SRA 转 FASTQ 启动（$(date)）=====" | tee "$MASTER_LOG"
        echo "SRA输入目录：$OUTPUT_ROOT" | tee -a "$MASTER_LOG"
        echo "FASTQ输出目录：$FASTQ_OUTPUT_DIR" | tee -a "$MASTER_LOG"
        echo "并行线程数：$THREADS" | tee -a "$MASTER_LOG"
        if [ "$USE_DOCKER" = true ]; then
            echo "运行模式：Docker（镜像：$DOCKER_IMAGE）" | tee -a "$MASTER_LOG"
        else
            echo "运行模式：本地二进制" | tee -a "$MASTER_LOG"
        fi
        echo "日志实时查看：tail -f \"$MASTER_LOG\""

        DOCKER_ARGS=""
        [ "$USE_DOCKER" = true ] && DOCKER_ARGS="--docker --docker-image $DOCKER_IMAGE"
        nohup "$0" __convert_run --threads "$THREADS" --srr-list "$SRR_LIST" $DOCKER_ARGS > "$MASTER_LOG" 2>&1 &
        echo $! > "$PID_FILE"
        echo "后台转换任务已启动！PID: $(cat "$PID_FILE")"
        echo "常用命令："
        echo "   $0 status    # 查看状态"
        echo "   $0 stop      # 停止任务"
        echo "   $0 clean     # 强制清理并重跑"
        exit 0
        ;;
    "")
        show_help
        exit 1
        ;;
esac

###########################################################################
# 下载工作逻辑
###########################################################################
if [ "$RUN_MODE" = "__download_run" ]; then
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 开始依赖检查..." | tee -a "$MASTER_LOG"
    if [ ! -x "$PREFETCH_BIN" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: prefetch 工具不可执行！路径：$PREFETCH_BIN" | tee -a "$MASTER_LOG"
        exit 1
    fi
    if [ ! -x "$PARALLEL_BIN" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: parallel 未找到或不可执行！路径：$PARALLEL_BIN" | tee -a "$MASTER_LOG"
        exit 1
    fi
    if [ ! -f "$SRR_LIST" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: SRR列表文件不存在！路径：$SRR_LIST" | tee -a "$MASTER_LOG"
        exit 1
    fi
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 依赖检查通过！SRR列表：$SRR_LIST" | tee -a "$MASTER_LOG"

    download_srr() {
        local srr_id="$1"
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] 正在下载: $srr_id"
        "$PREFETCH_BIN" "$srr_id" 2>&1
        if [ $? -eq 0 ]; then
            echo "[$(date +%Y-%m-%d_%H:%M:%S)] $srr_id 下载成功。"
        else
            echo "[$(date +%Y-%m-%d_%H:%M:%S)] $srr_id 下载失败！"
            echo "$srr_id" >> "$FAILED_FILE"
        fi
    }
    export -f download_srr
    export PREFETCH_BIN FAILED_FILE

    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 开始并行下载所有 SRR（线程数：$THREADS）..." | tee -a "$MASTER_LOG"
    rm -f "$FAILED_FILE"
    grep -v '^$' "$SRR_LIST" | "$PARALLEL_BIN" -j "$THREADS" --progress --bar download_srr {}

    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 所有下载任务完成！" | tee -a "$MASTER_LOG"
    if [ -f "$FAILED_FILE" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] 下载失败的 SRR 已记录在 $FAILED_FILE" | tee -a "$MASTER_LOG"
    fi
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] ===== SRA 下载流程全部完成！=====" | tee -a "$MASTER_LOG"
    release_lock
    exit 0
fi

###########################################################################
# 转换工作逻辑
###########################################################################
if [ "$RUN_MODE" = "__convert_run" ]; then
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 开始依赖检查..." | tee -a "$MASTER_LOG"
    if [ "$USE_DOCKER" = true ]; then
        if ! command -v docker &>/dev/null; then
            echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: Docker 未安装或不可用！" | tee -a "$MASTER_LOG"
            exit 1
        fi
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] Docker 模式，镜像：$DOCKER_IMAGE" | tee -a "$MASTER_LOG"
    else
        if [ ! -x "$FASTQ_DUMP_BIN" ]; then
            echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: fastq-dump 工具不可执行！路径：$FASTQ_DUMP_BIN" | tee -a "$MASTER_LOG"
            exit 1
        fi
    fi
    if [ ! -x "$PARALLEL_BIN" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: parallel 未找到或不可执行！路径：$PARALLEL_BIN" | tee -a "$MASTER_LOG"
        exit 1
    fi
    if [ ! -f "$SRR_LIST" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] ERROR: SRR列表文件不存在！路径：$SRR_LIST" | tee -a "$MASTER_LOG"
        exit 1
    fi
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 依赖检查通过！" | tee -a "$MASTER_LOG"

    convert_srr() {
        local srr_id="$1"
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] 开始转换: $srr_id"
        local sra_file_path="${OUTPUT_ROOT}/${srr_id}/${srr_id}.sra"
        if [ ! -f "$sra_file_path" ]; then
            echo "[$(date +%Y-%m-%d_%H:%M:%S)] 错误: SRA文件 $sra_file_path 不存在。"
            echo "$srr_id" >> "$FAILED_FILE"
            return 1
        fi
        if [ "$USE_DOCKER" = true ]; then
            docker run --rm \
                -v "${OUTPUT_ROOT}:/sra_input:ro" \
                -v "${FASTQ_OUTPUT_DIR}:/fastq_output" \
                "$DOCKER_IMAGE" fastq-dump \
                --split-3 --gzip \
                -O /fastq_output \
                "/sra_input/${srr_id}/${srr_id}.sra"
        else
            "$FASTQ_DUMP_BIN" --split-3 --gzip -O "$FASTQ_OUTPUT_DIR" "$sra_file_path"
        fi
        if [ $? -eq 0 ]; then
            echo "[$(date +%Y-%m-%d_%H:%M:%S)] 成功: $srr_id"
        else
            echo "[$(date +%Y-%m-%d_%H:%M:%S)] 失败: $srr_id"
            echo "$srr_id" >> "$FAILED_FILE"
        fi
    }
    export -f convert_srr
    export FASTQ_DUMP_BIN FASTQ_OUTPUT_DIR OUTPUT_ROOT FAILED_FILE USE_DOCKER DOCKER_IMAGE

    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 开始并行转换所有 SRR（线程数：$THREADS）..." | tee -a "$MASTER_LOG"
    rm -f "$FAILED_FILE"
    grep -v '^$' "$SRR_LIST" | "$PARALLEL_BIN" -j "$THREADS" --progress --bar convert_srr {}

    echo "[$(date +%Y-%m-%d_%H:%M:%S)] 所有转换任务完成！" | tee -a "$MASTER_LOG"
    if [ -f "$FAILED_FILE" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] 转换失败的 SRR 已记录在 $FAILED_FILE" | tee -a "$MASTER_LOG"
    else
        echo "[$(date +%Y-%m-%d_%H:%M:%S)] 所有文件均转换成功！" | tee -a "$MASTER_LOG"
    fi
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] ===== SRA 转 FASTQ 流程全部完成！=====" | tee -a "$MASTER_LOG"
    release_lock
    exit 0
fi