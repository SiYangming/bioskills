#!/usr/bin/env bash

# This script checks if the required indices for RSEM/Bowtie2 and STAR exist.
# If they do not exist, it attempts to build them from the reference FASTA/GTF files.

# Get the directory of the current script to correctly source common_variables.sh
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/common_variables.sh"

# Function to check and build filtered FASTA
check_build_filtered_fasta() {
    if [ ! -f "$pc_fasta" ]; then
        echo "[INFO] Filtered FASTA not found at $pc_fasta"
        echo "[INFO] Attempting to generate it using Filtering_GENCODE_FASTA.py..."
        
        # Determine input reformatted FASTA path
        # Assuming pc_fasta ends with _filtered.fa and we need _reformatted.fa
        local reformatted_fasta="${pc_fasta/_filtered.fa/_reformatted.fa}"
        
        if [ ! -f "$reformatted_fasta" ]; then
            echo "[ERROR] Reformatted FASTA not found at $reformatted_fasta."
            echo "[ERROR] Cannot generate filtered FASTA."
            exit 1
        fi
        
        if [ ! -f "$STAR_GTF" ]; then
             echo "[ERROR] GTF file not found at $STAR_GTF."
             exit 1
        fi
        
        if [ ! -f "$region_lengths" ]; then
             echo "[ERROR] Region lengths file not found at $region_lengths."
             exit 1
        fi

        echo "[INFO] Running Filtering_GENCODE_FASTA.py..."
        python $PYTHON_SCRIPTS_DIR/Filtering_GENCODE_FASTA.py "$reformatted_fasta" "$STAR_GTF" "$region_lengths"
        
        if [ $? -eq 0 ]; then
            echo "[INFO] Filtered FASTA generated successfully."
        else
            echo "[ERROR] Failed to generate filtered FASTA."
            exit 1
        fi
    else
        echo "[INFO] Filtered FASTA found at $pc_fasta"
    fi
}

# Function to check and build RSEM/Bowtie2 index
check_build_rsem_index() {
    local index_prefix="$rsem_index"
    local index_dir=$(dirname "$index_prefix")
    local check_file="${index_prefix}.1.bt2"

    if [ ! -f "$check_file" ]; then
        echo "[INFO] RSEM/Bowtie2 index not found at $index_prefix"
        echo "[INFO] Attempting to build index..."
        
        if [ ! -f "$pc_fasta" ]; then
            echo "[ERROR] Protein coding FASTA not found at $pc_fasta. Cannot build index."
            exit 1
        fi

        mkdir -p "$index_dir"
        
        # Build index
        # Note: Using --bowtie2 flag as recommended in common_variables.sh
        # Ensure paths are clean (no newlines)
        local clean_pc_fasta=$(echo "$pc_fasta" | tr -d '\n')
        local clean_index_prefix=$(echo "$index_prefix" | tr -d '\n')
        
        cmd="rsem-prepare-reference --bowtie2 --num-threads $threadN \"$clean_pc_fasta\" \"$clean_index_prefix\""
        echo "[INFO] Running: $cmd"
        
        # Check if rsem-prepare-reference is available
        if ! command -v rsem-prepare-reference &> /dev/null; then
             echo "[ERROR] rsem-prepare-reference could not be found."
             echo "[ERROR] Please ensure you are in the 'RNAseq' conda environment which contains this tool."
             echo "[INFO] Current PATH: $PATH"
             exit 1
        fi
        
        eval "$cmd"
        
        if [ $? -eq 0 ]; then
            echo "[INFO] RSEM/Bowtie2 index built successfully."
        else
            echo "[ERROR] Failed to build RSEM/Bowtie2 index."
            exit 1
        fi
    else
        echo "[INFO] RSEM/Bowtie2 index found at $index_prefix"
    fi
}

# Function to check and build STAR index
check_build_star_index() {
    local index_dir="$STAR_index"
    local check_file="${index_dir}/Genome"

    if [ ! -f "$check_file" ]; then
        echo "[INFO] STAR index not found at $index_dir"
        echo "[INFO] Attempting to build index..."
        
        if [ ! -f "$genome_fasta" ]; then
            echo "[ERROR] Genome FASTA not found at $genome_fasta. Cannot build index."
            echo "[INFO] Please provide path to genome FASTA via --genome-fasta argument."
            exit 1
        fi

        if [ ! -f "$STAR_GTF" ]; then
            echo "[ERROR] GTF file not found at $STAR_GTF. Cannot build index."
            exit 1
        fi

        mkdir -p "$index_dir"
        
        # Unzip genome fasta if it is gzipped
        local genome_fasta_to_use="$genome_fasta"
        if [[ "$genome_fasta" == *.gz ]]; then
            echo "[INFO] Genome FASTA is gzipped. Unzipping to temporary file..."
            # Create a temporary unzipped file in the same directory (or temp dir)
            local unzipped_fasta="${genome_fasta%.gz}"
            
            # Check if unzipped version already exists to avoid re-unzipping
            if [ ! -f "$unzipped_fasta" ]; then
                gunzip -c "$genome_fasta" > "$unzipped_fasta"
                if [ $? -ne 0 ]; then
                    echo "[ERROR] Failed to unzip genome FASTA."
                    exit 1
                fi
            else
                 echo "[INFO] Unzipped genome FASTA already exists at $unzipped_fasta"
            fi
            genome_fasta_to_use="$unzipped_fasta"
        fi
        
        # Use readlink to resolve absolute path of the fasta to use (whether original or unzipped)
        # This handles cases where paths might be relative or contain symlinks
        # However, since we are using absolute paths from run.sh, this is just a safety measure.
        
        # Build index
        # Ensure paths are clean (no newlines)
        local clean_index_dir=$(echo "$index_dir" | tr -d '\n')
        local clean_genome_fasta=$(echo "$genome_fasta_to_use" | tr -d '\n')
        local clean_gtf=$(echo "$STAR_GTF" | tr -d '\n')

        cmd="STAR --runMode genomeGenerate --runThreadN $threadN --genomeDir \"$clean_index_dir\" --genomeFastaFiles \"$clean_genome_fasta\" --sjdbGTFfile \"$clean_gtf\" --sjdbOverhang 100 --genomeSAindexNbases 11"

        echo "[INFO] Running: $cmd"
        eval "$cmd"
        
        if [ $? -eq 0 ]; then
            echo "[INFO] STAR index built successfully."
        else
            echo "[ERROR] Failed to build STAR index."
            exit 1
        fi
    else
        echo "[INFO] STAR index found at $index_dir"
    fi
}

# Main execution
echo "[INFO] Checking indices..."

# Check which pipeline is running or just check both?
# The script can be run generally.

# Check Filtered FASTA
check_build_filtered_fasta

# Check RSEM
check_build_rsem_index

# Check STAR
check_build_star_index

echo "[INFO] Index check complete."
