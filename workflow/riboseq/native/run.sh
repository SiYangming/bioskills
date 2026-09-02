#!/usr/bin/env bash

# run.sh - Master script for Ribo-seq analysis pipeline
#
# Usage: ./run.sh [options]
# Options:
#   --pipeline [RPFs|Totals|Downstream]  Select pipeline to run (required)
#   --env-mode [conda|local]  Select environment mode (default: conda)
#   --step [step_name]        Run a specific step (optional)
#   --output-dir [path]       Specify output directory (default: ./results)
#   --input-csv [path]        Specify input csv file (default: ./info.csv)
#   --threads [num]           Number of threads to use (default: 4)
#   --rpf-adaptor [seq]       RPF adaptor sequence (default: TGGAATTCTCGGGTGCCAAGG)
#   --totals-adaptor [seq]    Totals adaptor sequence (default: AGATCGGAAGAG)
#   --list-steps              List available steps for the selected pipeline
#   --help                    Show this help message
#

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${PROJECT_ROOT}/Shell_scripts"
LOG_DIR="${PROJECT_ROOT}/logs"
RUN_LOG="${LOG_DIR}/run_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local level=$1
    shift
    local msg="$@"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "$RUN_LOG"
}

info() {
    log "INFO" "$@"
}

warn() {
    log "WARN" "${YELLOW}$@${NC}"
}

error() {
    log "ERROR" "${RED}$@${NC}"
}

# Error handler
handle_error() {
    local line=$1
    local command=$2
    error "Failed at line $line: $command"
    exit 1
}

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Check environment
check_env() {
    if [ ! -d "$SCRIPTS_DIR" ]; then
        error "Scripts directory not found at $SCRIPTS_DIR"
        exit 1
    fi
    
    if [ ! -f "$SCRIPTS_DIR/common_variables.sh" ]; then
        error "common_variables.sh not found in $SCRIPTS_DIR"
        exit 1
    fi

    # If in local mode, check if R is available for Downstream pipeline
    if [ "$ENV_MODE" == "local" ] && [ "$PIPELINE" == "Downstream" ]; then
        if ! command -v Rscript >/dev/null 2>&1; then
            error "Local mode selected but Rscript not found in PATH."
            exit 1
        fi
        info "Running in LOCAL mode. Using system R: $(which Rscript)"
        info "Ensure dependencies are installed. You can run: ./Shell_scripts/install_r_pkgs_local.sh"
    fi
}

setup_conda() {
    local pipeline=$1
    local env_name=""

    # Skip conda setup if running in local mode
    if [ "$ENV_MODE" == "local" ]; then
        info "Skipping Conda setup (Local mode enabled)"
        return
    fi

    if [ "$pipeline" == "RPFs" ]; then
        env_name="RiboSeq"
    elif [ "$pipeline" == "Totals" ]; then
        env_name="RNAseq"
    elif [ "$pipeline" == "Downstream" ]; then
        env_name="R_analysis"
    fi

    if [ -n "$env_name" ]; then
        
        # Try to find conda base path
        if [ -z "$CONDA_EXE" ]; then
            # Fallback to common locations or the one found in the system
            local conda_base="/opt/homebrew/Caskroom/miniforge/base"
            if [ -f "$conda_base/etc/profile.d/conda.sh" ]; then
                source "$conda_base/etc/profile.d/conda.sh"
            elif command -v conda >/dev/null 2>&1; then
                 # Try to deduce base from command
                 local conda_bin=$(command -v conda)
                 local conda_base_deduced=$(dirname $(dirname "$conda_bin"))
                 if [ -f "$conda_base_deduced/etc/profile.d/conda.sh" ]; then
                     source "$conda_base_deduced/etc/profile.d/conda.sh"
                 fi
            fi
        else
            # If CONDA_EXE is set, derive base
            local conda_bin="$CONDA_EXE"
            local conda_base_deduced=$(dirname $(dirname "$conda_bin"))
            if [ -f "$conda_base_deduced/etc/profile.d/conda.sh" ]; then
                 source "$conda_base_deduced/etc/profile.d/conda.sh"
            fi
        fi
        
        # Attempt to initialize mamba if available
        # if [ -n "$CONDA_EXE" ] && [ -f "$(dirname "$CONDA_EXE")/../etc/profile.d/mamba.sh" ]; then
        #     source "$(dirname "$CONDA_EXE")/../etc/profile.d/mamba.sh"
        # fi

        # Check if conda/mamba is available
        if command -v conda >/dev/null 2>&1; then
            
            # Check if environment exists
            if conda info --envs | awk '{print $1}' | grep -qw "$env_name"; then
                info "Activating conda environment: $env_name"
                conda activate "$env_name" || {
                    error "Failed to activate conda environment: $env_name"
                    exit 1
                }
            else
                error "Environment '$env_name' not found. Please create it using 'mamba env update -f ${env_name}_env.yml'."
                exit 1
            fi
        else
            warn "Conda not found. Proceeding without environment checks."
        fi
    fi
}

# Execute a script
run_script() {
    local script_name=$1
    local script_path="${SCRIPTS_DIR}/${script_name}"
    
    if [ ! -f "$script_path" ]; then
        error "Script not found: $script_name"
        return 1
    fi
    
    # Check if script is executable, if not make it executable
    if [ ! -x "$script_path" ]; then
        info "Making $script_name executable..."
        chmod +x "$script_path"
    fi
    
    info "Starting step: $script_name"
    
    # We need to run from SCRIPTS_DIR because the scripts use 'source common_variables.sh'
    (
        cd "$SCRIPTS_DIR" || exit 1
        ./"$script_name"
    )
    
    if [ $? -eq 0 ]; then
        info "Step completed successfully: $script_name"
    else
        error "Step failed: $script_name"
        return 1
    fi
}

# Initialize directories
init_dirs() {
    info "Initializing directories..."
    run_script "makeDirs.sh"
}

# Define pipelines
RPFS_STEPS=(
    "RPFs_0_QC.sh"
    "RPFs_1_adaptor_removal.sh"
    "RPFs_2_extract_UMIs.sh"
    "RPFs_3_align_reads.sh"
    "RPFs_4_deduplication.sh"
    "RPFs_5_Extract_counts_all_lengths.sh"
    "RPFs_6a_summing_region_counts.sh"
    "RPFs_6b_summing_spliced_counts.sh"
    "RPFs_6c_periodicity.sh"
    "RPFs_6d_extract_read_counts.sh"
    "RPFs_7_Extract_final_counts.sh"
    "RPFs_8a_CDS_counts.sh"
    "RPFs_8b_UTR5_counts.sh"
    "RPFs_8c_counts_to_csv.sh"
    "RPFs_8d_count_codon_occupancy.sh"
    "RPFs_all.sh"
)

TOTALS_STEPS=(
    "Totals_0_QC.sh"
    "Totals_1_adaptor_removal.sh"
    "Totals_2_extract_UMIs.sh"
    "Totals_3a_align_reads_transcriptome.sh"
    "Totals_3b_align_reads_genome.sh"
    "Totals_4a_deduplication_transcriptome.sh"
    "Totals_4b_deduplication_genome.sh"
    "Totals_5_isoform_quantification.sh"
    "Totals_6a_write_most_abundant_transcript_fasta.sh"
    "Totals_6b_extract_read_counts.sh"
    "Totals_all.sh"
)

DOWNSTREAM_STEPS=(
    "Downstream_1_QC.sh"
    "Downstream_2_DESeq2.sh"
    "Downstream_3_MetaPlots.sh"
    "Downstream_4_CodonOccupancy.sh"
    "Downstream_5_GSEA.sh"
    "Downstream_all.sh"
)

# Parse arguments
PIPELINE=""
ENV_MODE="conda"
STEP=""
OUTPUT_DIR="${PROJECT_ROOT}/results"
INPUT_CSV="${PROJECT_ROOT}/info.csv"
THREADS=""
RPF_ADAPTOR=""
TOTALS_ADAPTOR=""
FASTA_DIR=""
GENOME_VERSION=""
LIST_STEPS=false

if [ $# -eq 0 ]; then
    echo "Usage: ./run.sh [options]"
    echo "Try './run.sh --help' for more information."
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --pipeline)
            PIPELINE="$2"
            shift 2
            ;;
        --env-mode)
            ENV_MODE="$2"
            shift 2
            ;;
        --step)
            STEP="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --input-csv)
            INPUT_CSV="$2"
            shift 2
            ;;
        --threads)
            THREADS="$2"
            shift 2
            ;;
        --rpf-adaptor)
            RPF_ADAPTOR="$2"
            shift 2
            ;;
        --totals-adaptor)
            TOTALS_ADAPTOR="$2"
            shift 2
            ;;
        --fasta-dir)
            FASTA_DIR="$2"
            shift 2
            ;;
        --genome-version)
            GENOME_VERSION="$2"
            shift 2
            ;;
        --rrna-fasta)
            RRNA_FASTA="$2"
            shift 2
            ;;
        --trna-fasta)
            TRNA_FASTA="$2"
            shift 2
            ;;
        --pc-fasta)
            PC_FASTA="$2"
            shift 2
            ;;
        --genome-fasta)
            GENOME_FASTA="$2"
            shift 2
            ;;
        --bbmap-memory)
            BBMAP_MEMORY="$2"
            shift 2
            ;;
        --rsem-index)
            RSEM_INDEX="$2"
            shift 2
            ;;
        --star-index)
            STAR_INDEX="$2"
            shift 2
            ;;
        --star-gtf)
            STAR_GTF="$2"
            shift 2
            ;;
        --list-steps)
            LIST_STEPS=true
            shift
            ;;
        --help)
            echo "Usage: ./run.sh [options]"
            echo "Options:"
            echo "  --pipeline [RPFs|Totals|Downstream]  Select pipeline to run"
            echo "  --env-mode [conda|local]  Select environment mode (default: conda)"
            echo "  --step [script_name]      Run a specific script (e.g., RPFs_0_QC.sh)"
            echo "  --output-dir [path]       Specify output directory (default: ./results)"
            echo "  --input-csv [path]        Specify input csv file (default: ./info.csv)"
            echo "  --threads [num]           Number of threads to use (default: 16)"
            echo "  --rpf-adaptor [seq]       RPF adaptor sequence (default: TGGAATTCTCGGGTGCCAAGG)"
            echo "  --totals-adaptor [seq]    Totals adaptor sequence (default: AGATCGGAAGAG)"
            echo "  --fasta-dir [path]        Directory containing FASTA files"
            echo "  --genome-version [ver]    Genome version (default: v38)"
            echo "  --rrna-fasta [path]       Path to rRNA FASTA file"
            echo "  --trna-fasta [path]       Path to tRNA FASTA file"
            echo "  --pc-fasta [path]         Path to protein coding FASTA file"
            echo "  --bbmap-memory [mem]      Memory for bbmap (e.g., Xmx=4g)"
            echo "  --rsem-index [path]       Path to RSEM bowtie2 index prefix"
            echo "  --star-index [path]       Path to STAR genome index directory"
            echo "  --star-gtf [path]         Path to STAR GTF file"
            echo "  --list-steps              List available steps for the selected pipeline"
            echo "  --help                    Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper to resolve absolute path
get_abs_path() {
    local path="$1"
    # Check if path is empty
    if [ -z "$path" ]; then
        echo ""
        return
    fi
    
    # If path starts with /, it's absolute
    if [[ "$path" == /* ]]; then
        echo "$path"
    else
        # Otherwise, prepend current working directory
        echo "$(pwd)/$path"
    fi
}

# Convert paths to absolute
if [ -n "$PC_FASTA" ]; then PC_FASTA=$(get_abs_path "$PC_FASTA"); fi
if [ -n "$GENOME_FASTA" ]; then GENOME_FASTA=$(get_abs_path "$GENOME_FASTA"); fi
if [ -n "$RRNA_FASTA" ]; then RRNA_FASTA=$(get_abs_path "$RRNA_FASTA"); fi
if [ -n "$TRNA_FASTA" ]; then TRNA_FASTA=$(get_abs_path "$TRNA_FASTA"); fi

# Set default FASTA_DIR if not provided
if [ -z "$FASTA_DIR" ]; then
    FASTA_DIR="${PROJECT_ROOT}/reference"
fi
FASTA_DIR=$(get_abs_path "$FASTA_DIR")

if [ -n "$RSEM_INDEX" ]; then RSEM_INDEX=$(get_abs_path "$RSEM_INDEX"); fi
if [ -n "$STAR_INDEX" ]; then STAR_INDEX=$(get_abs_path "$STAR_INDEX"); fi
if [ -n "$STAR_GTF" ]; then STAR_GTF=$(get_abs_path "$STAR_GTF"); fi

# Validation
check_env

if [ "$LIST_STEPS" = true ]; then
    if [ "$PIPELINE" == "RPFs" ]; then
        echo "Available steps for RPFs:"
        printf '%s\n' "${RPFS_STEPS[@]}"
    elif [ "$PIPELINE" == "Totals" ]; then
        echo "Available steps for Totals:"
        printf '%s\n' "${TOTALS_STEPS[@]}"
    elif [ "$PIPELINE" == "Downstream" ]; then
        echo "Available steps for Downstream:"
        printf '%s\n' "${DOWNSTREAM_STEPS[@]}"
    else
        echo "Please specify --pipeline [RPFs|Totals|Downstream] to list steps."
    fi
    exit 0
fi

if [ -z "$PIPELINE" ]; then
    error "Pipeline not specified. Use --pipeline [RPFs|Totals]"
    exit 1
fi

if [ "$PIPELINE" != "RPFs" ] && [ "$PIPELINE" != "Totals" ] && [ "$PIPELINE" != "Downstream" ]; then
    error "Invalid pipeline: $PIPELINE. Must be 'RPFs', 'Totals' or 'Downstream'."
    exit 1
fi

info "Starting $PIPELINE pipeline..."
info "Output directory: $OUTPUT_DIR"

# Export parent dir for common_variables.sh
export RIBO_SEQ_PARENT_DIR="$OUTPUT_DIR"

if [ -n "$THREADS" ]; then
    export RIBO_SEQ_THREADS="$THREADS"
    info "Using threads: $THREADS"
fi

if [ -n "$RPF_ADAPTOR" ]; then
    export RIBO_SEQ_RPF_ADAPTOR="$RPF_ADAPTOR"
    info "Using RPF adaptor: $RPF_ADAPTOR"
fi

if [ -n "$TOTALS_ADAPTOR" ]; then
    export RIBO_SEQ_TOTALS_ADAPTOR="$TOTALS_ADAPTOR"
    info "Using Totals adaptor: $TOTALS_ADAPTOR"
fi

if [ -n "$FASTA_DIR" ]; then
        export RIBO_SEQ_FASTA_DIR="$FASTA_DIR"
        info "Using FASTA directory: $FASTA_DIR"
    fi

    if [ -n "$GENOME_VERSION" ]; then
    export GENOME_VERSION="$GENOME_VERSION"
    info "Using Genome Version: $GENOME_VERSION"
else
    # Default to v49 if not specified
    GENOME_VERSION="v49"
    export GENOME_VERSION="$GENOME_VERSION"
    info "Using default Genome Version: $GENOME_VERSION"
fi

if [ -n "$RRNA_FASTA" ]; then
    export RIBO_SEQ_RRNA_FASTA="$RRNA_FASTA"
    info "Using rRNA FASTA: $RRNA_FASTA"
fi

if [ -n "$TRNA_FASTA" ]; then
    export RIBO_SEQ_TRNA_FASTA="$TRNA_FASTA"
    info "Using tRNA FASTA: $TRNA_FASTA"
fi

if [ -z "$PC_FASTA" ]; then
    # Set default PC_FASTA path if not provided
    # Matches common_variables.sh logic: ${fasta_dir}/GENCODE/${genome_version}/gencode.${genome_version}.pc_transcripts_filtered.fa
    PC_FASTA="${FASTA_DIR}/GENCODE/${GENOME_VERSION}/gencode.${GENOME_VERSION}.pc_transcripts_filtered.fa"
fi

if [ -n "$PC_FASTA" ]; then
    export RIBO_SEQ_PC_FASTA="$PC_FASTA"
    info "Using protein coding FASTA: $PC_FASTA"
fi

if [ -n "$GENOME_FASTA" ]; then
        export RIBO_SEQ_GENOME_FASTA="$GENOME_FASTA"
        info "Using genome FASTA: $GENOME_FASTA"
    fi

    # Setup environment: Activate RNAseq for Python scripts (Generation + Prepare Data)
    # The user specified that python scripts should run in the RNAseq environment.
    # We use "Totals" here to map to "RNAseq" environment as per setup_conda logic.
    setup_conda "Totals"

    # Auto-generate filtered FASTA if missing but input files are available
    if [ -n "$PC_FASTA" ] && [ ! -f "$PC_FASTA" ]; then
        info "PC_FASTA specified but not found: $PC_FASTA"
        info "Attempting to generate it using Python scripts..."
        
        # 1. Locate Source Files in the same directory as PC_FASTA parent
        source_dir=$(dirname "$PC_FASTA")
        
        # Try to find original transcripts (exclude filtered and reformatted)
        # We look for files containing "pc_transcripts" and ending in ".fa"
        original_transcripts=$(find "$source_dir" -maxdepth 1 -name "*pc_transcripts*.fa" | grep -v "filtered" | grep -v "reformatted" | head -n 1)
        
        # Try to find original translations (prioritize real file over dummy)
        original_translations=$(find "$source_dir" -maxdepth 1 -name "*pc_translations*.fa" | grep -v "reformatted" | head -n 1)
        
        if [ -z "$original_translations" ]; then
            # Fallback to dummy if real translations not found
            original_translations=$(find "$source_dir" -maxdepth 1 -name "dummy_translations.fa" | head -n 1)
        fi

        if [ -z "$original_transcripts" ]; then
            error "Could not find original PC transcripts FASTA in $source_dir to generate filtered FASTA."
            exit 1
        fi
        info "Found original transcripts: $original_transcripts"
        
        if [ -z "$original_translations" ]; then
            error "Could not find original PC translations FASTA (or dummy) in $source_dir."
            exit 1
        fi
        info "Found translations: $original_translations"
        
        if [ -z "$STAR_GTF" ]; then
             # Try to find GTF
             candidate_gtf=$(find "$source_dir" -maxdepth 1 -name "*.gtf" | head -n 1)
             if [ -n "$candidate_gtf" ]; then
                 STAR_GTF="$candidate_gtf"
                 export RIBO_SEQ_STAR_GTF="$STAR_GTF"
                 info "Found GTF: $STAR_GTF"
             else
                 error "STAR_GTF not set and could not be found in $source_dir."
                 exit 1
             fi
        fi

        # 2. Run Reformatting
        info "Running Reformatting_GENCODE_FASTA.py..."
        mkdir -p "${source_dir}/transcript_info"
        python3 "${PROJECT_ROOT}/Python_scripts/Reformatting_GENCODE_FASTA.py" \
            "$original_transcripts" \
            "$original_translations" \
            --output_dir "${source_dir}/transcript_info"
            
        if [ $? -ne 0 ]; then error "Reformatting failed"; exit 1; fi

        # Cleanup dummy output if it exists
        if [ -f "${source_dir}/dummy_translations_reformatted.fa" ]; then
             rm "${source_dir}/dummy_translations_reformatted.fa"
        fi

        # CSV files are generated directly in transcript_info directory

        # 3. Determine Intermediate Filenames
        # The python script replaces '.fa' with '_reformatted.fa'
        reformatted_fasta="${original_transcripts/.fa/_reformatted.fa}"
        
        # Region lengths file was moved to transcript_info
        # Use basename to construct the new path
        transcripts_basename=$(basename "$original_transcripts")
        region_lengths_filename="${transcripts_basename/.fa/_region_lengths.csv}"
        region_lengths="${source_dir}/transcript_info/${region_lengths_filename}"
        
        if [ ! -f "$reformatted_fasta" ]; then
             error "Expected reformatted FASTA not found: $reformatted_fasta"
             exit 1
        fi
        
        # Export the generated region lengths file so downstream scripts use it
        export RIBO_SEQ_REGION_LENGTHS="$region_lengths"
        info "Exported region lengths: $region_lengths"

        # 4. Run Filtering
        info "Running Filtering_GENCODE_FASTA.py..."
        # Filtering script expects: FASTA GTF region_lengths
        python3 "${PROJECT_ROOT}/Python_scripts/Filtering_GENCODE_FASTA.py" \
            "$reformatted_fasta" \
            "$STAR_GTF" \
            "$region_lengths"
            
        if [ $? -ne 0 ]; then error "Filtering failed"; exit 1; fi

        # 5. Determine Final Output
        # The python script replaces '_reformatted' with '_filtered' (implicit logic)
        # Note: arg is reformatted_fasta which has '_reformatted.fa'
        # So it replaces '_reformatted' with '_filtered'. Result: '_filtered.fa'
        filtered_output="${reformatted_fasta/_reformatted/_filtered}"
        
        if [ -f "$filtered_output" ]; then
            if [ "$filtered_output" != "$PC_FASTA" ]; then
                info "Moving $filtered_output to $PC_FASTA"
                mv "$filtered_output" "$PC_FASTA"
            fi
            info "Successfully generated $PC_FASTA"
        else
            error "Expected output $filtered_output not found."
            exit 1
        fi
    fi

    if [ -n "$BBMAP_MEMORY" ]; then
    export RIBO_SEQ_BBMAP_MEMORY="$BBMAP_MEMORY"
    info "Using bbmap memory: $BBMAP_MEMORY"
fi

if [ -n "$RSEM_INDEX" ]; then
    export RIBO_SEQ_RSEM_INDEX="$RSEM_INDEX"
    info "Using RSEM index: $RSEM_INDEX"
fi

if [ -n "$STAR_INDEX" ]; then
    export RIBO_SEQ_STAR_INDEX="$STAR_INDEX"
    info "Using STAR index: $STAR_INDEX"
fi

if [ -n "$STAR_GTF" ]; then
    export RIBO_SEQ_STAR_GTF="$STAR_GTF"
    info "Using STAR GTF: $STAR_GTF"
fi


# Prepare data and load configuration
info "Preparing data and loading configuration..."
PREPARE_SCRIPT="${PROJECT_ROOT}/Python_scripts/prepare_data.py"
SAMPLES_ENV="${OUTPUT_DIR}/samples.env"

if [ -f "$PREPARE_SCRIPT" ]; then
    python3 "$PREPARE_SCRIPT" --input-csv "$INPUT_CSV" --output-dir "$OUTPUT_DIR"
    if [ $? -ne 0 ]; then
        error "Data preparation failed."
        exit 1
    fi
else
    error "prepare_data.py not found at $PREPARE_SCRIPT"
    exit 1
fi

if [ -f "$SAMPLES_ENV" ]; then
    source "$SAMPLES_ENV"
    info "Loaded sample configuration."
    # Optional: Clean up env file if not needed
    # rm "$SAMPLES_ENV"
else
    error "Sample configuration file not found: $SAMPLES_ENV"
    exit 1
fi

# Run makeDirs.sh to ensure directories exist (uses mkdir -p, so it's safe)
init_dirs

# Define steps based on pipeline
if [ "$PIPELINE" == "RPFs" ]; then
    steps=("${RPFS_STEPS[@]}")
elif [ "$PIPELINE" == "Totals" ]; then
    steps=("${TOTALS_STEPS[@]}")
    
    # Check and build indices if necessary for Totals pipeline
    info "Checking and building indices for Totals pipeline..."
    chmod +x Shell_scripts/check_and_build_indices.sh
    ./Shell_scripts/check_and_build_indices.sh
    if [ $? -ne 0 ]; then
        error "Failed to check/build indices."
    fi

elif [ "$PIPELINE" == "Downstream" ]; then
    steps=("${DOWNSTREAM_STEPS[@]}")
    
    # Switch conda environment to R_analysis for Downstream pipeline
    setup_conda "Downstream"
    
else
    error "Invalid pipeline: $PIPELINE"
fi

# Run steps
if [ -n "$STEP" ]; then
    # Run single step
    found=false
    for s in "${steps[@]}"; do
        if [ "$s" == "$STEP" ]; then
            found=true
            break
        fi
    done
    
    if [ "$found" = true ]; then
        run_script "$STEP"
    else
        error "Step '$STEP' not found in $PIPELINE pipeline."
        exit 1
    fi
else
    # Run all steps
    for step in "${steps[@]}"; do
        run_script "$step"
    done
fi

info "Pipeline $PIPELINE completed successfully."
