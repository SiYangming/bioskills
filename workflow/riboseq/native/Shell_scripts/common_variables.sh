#!/usr/bin/env bash

# Logging helpers
if ! command -v info &> /dev/null; then
    info() { echo "[INFO] $@"; }
fi

if ! command -v error &> /dev/null; then
    error() { echo "[ERROR] $@"; }
fi

###filenames
# These are the filenames for all RPF and Total RNA-seq samples (without the <.fastq> or any alternative extension)
# Variables are expected to be set by run.sh via prepare_data.py
if [ -z "$RPF_filenames" ]; then
    echo "Warning: RPF_filenames not set. Defaulting to empty or check prepare_data.py"
    RPF_filenames=''
fi

if [ -z "$Totals_filenames" ]; then
    echo "Warning: Totals_filenames not set. Defaulting to empty or check prepare_data.py"
    Totals_filenames=''
fi

###set the sumber of threads available to use
#It is recomended to use one or two less than what is available and also consider whether any else is being run at the same time
#Some of the packages used do not support multi-threading and so the for loops run in parallel, so that all files are run at the same time. For this reason do not run on more files than the number of cores available to use
if [ -n "$RIBO_SEQ_THREADS" ]; then
    threadN="$RIBO_SEQ_THREADS"
else
    threadN=4
fi

###Memory settings
#Memory for bbmap (used in RPFs pipeline)
if [ -n "$RIBO_SEQ_BBMAP_MEMORY" ]; then
    bbmap_memory="$RIBO_SEQ_BBMAP_MEMORY"
else
    bbmap_memory='Xmx=4g' # Default to 4GB which should be enough for transcriptome alignment
fi

###adaptors
#RPF adaptors
#This is the sequence of the 3' adaptor that was used in the library prep. Common sequences are below, unhash the correct one if present, or if not enter it as a variable

if [ -n "$RIBO_SEQ_RPF_ADAPTOR" ]; then
    RPF_adaptor="$RIBO_SEQ_RPF_ADAPTOR"
else
    RPF_adaptor='TGGAATTCTCGGGTGCCAAGG' #this is the adaptor used in the nextflex small RNA library kit
fi
#RPF_adaptor='CTGTAGGCACCATCAAT' #this is the adaptor that seems to have been more commonly used in older ribosome-footprinting studies such as Wolfe 2014
#RPF_adaptor='AGATCGGAAGAGCAC' #this is the one stated in the McGlincy and Ingolia 2017 methods paper
#RPF_adaptor=''

#Totals adaptors
if [ -n "$RIBO_SEQ_TOTALS_ADAPTOR" ]; then
    Totals_adaptor="$RIBO_SEQ_TOTALS_ADAPTOR"
else
    Totals_adaptor='AGATCGGAAGAG' #this is the adaptor used in the LEXOGEN CORALL Total RNA-Seq Library Prep Kit
fi

###paths
# Always define PROJECT_ROOT based on script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PYTHON_SCRIPTS_DIR="${PROJECT_ROOT}/Python_scripts"

# If RIBO_SEQ_PARENT_DIR is set (by run.sh), use it.
# Otherwise, default to the current directory's results folder if not specified, 
# or fallback to a hardcoded path if you prefer.
# Here we default to a 'results' directory in the parent of Shell_scripts if undefined.
if [ -n "$RIBO_SEQ_PARENT_DIR" ]; then
    parent_dir="$RIBO_SEQ_PARENT_DIR"
else
    # Fallback to a default location if not running via run.sh with the variable set
    # Assuming this script is in /path/to/project/Shell_scripts/
    # We want parent_dir to be /path/to/project/results
    parent_dir="${PROJECT_ROOT}/results"
fi

#The following directories are where all the processed data will be saved. These all need to be created prior to starting the analysis

#set the directory where the raw bcl data is. the directory that contains the raw sequencing data in bcl format. This is what you get from a sequencing run and needs to be demulitplexed to write the <.fastq> files.
#If you have more than one bcl directory (you will get one for each sequencing run), then hash one out and write a new one below, each time you re-run the demultiplex.sh script script, so that this acts as a log for all the bcl directories associated with this project
bcl_dir='Path/to/bcl/data'

fastq_dir=${parent_dir}/fastq_files
fastqc_dir=${parent_dir}/fastQC_files
SAM_dir=${parent_dir}/SAM_files
BAM_dir=${parent_dir}/BAM_files
log_dir=${parent_dir}/logs
counts_dir=${parent_dir}/Counts_files
csv_counts_dir=${parent_dir}/Counts_files/csv_files
csv_R_objects=${parent_dir}/Counts_files/R_objects

STAR_dir=${parent_dir}/STAR
rsem_dir=${parent_dir}/rsem

#The following directories are where all the csv files that are used as input into R will be saved
analysis_dir=${parent_dir}/Analysis

region_counts_dir=${analysis_dir}/region_counts
spliced_counts_dir=${analysis_dir}/spliced_counts
periodicity_dir=${analysis_dir}/periodicity
cds_counts_dir=${analysis_dir}/CDS_counts
UTR5_counts_dir=$analysis_dir/UTR5_counts
codon_counts_dir=${analysis_dir}/codon_counts
most_abundant_transcripts_dir=${analysis_dir}/most_abundant_transcripts
DESeq2_dir=${analysis_dir}/DESeq2_output
reads_summary_dir=${analysis_dir}/reads_summary
fgsea_dir=${analysis_dir}/fgsea

#The following directories are where all the plots generated in R will be saved
plots_dir=${parent_dir}/plots

summed_counts_plots_dir=${plots_dir}/summed_counts
periodicity_plots_dir=${plots_dir}/periodicity
offset_plots_dir=${plots_dir}/offset
heatmaps_plots_dir=${plots_dir}/heatmaps
DE_analysis_dir=${plots_dir}/DE_analysis
PCA_dir=${plots_dir}/PCAs
Interactive_scatters_dir=${plots_dir}/Interactive_scatters
fgsea_plots_dir=${plots_dir}/fgsea
fgsea_scatters_dir=${plots_dir}/fgsea/scatters
fgsea_interactive_scatters_dir=${plots_dir}/fgsea/Interactive_scatters
read_counts_summary_dir=${plots_dir}/read_counts_summary
binned_plots_dir=${plots_dir}/binned_plots
single_transcript_binned_plots_dir=${plots_dir}/binned_plots/single_transcripts
normalisation_binned_plots_dir=${plots_dir}/binned_plots/normalisation


#Fastas
if [ -n "$RIBO_SEQ_FASTA_DIR" ]; then
    fasta_dir="$RIBO_SEQ_FASTA_DIR"
else
    fasta_dir='reference'
fi

#Genome Version
if [ -n "$GENOME_VERSION" ]; then
    genome_version="$GENOME_VERSION"
else
    genome_version='v49'
fi

if [ -n "$RIBO_SEQ_RRNA_FASTA" ]; then
    rRNA_fasta="$RIBO_SEQ_RRNA_FASTA"
else
    rRNA_fasta=${fasta_dir}/rRNA/sortmerna_rrna.fasta #this needs to point to a fasta file containing rRNA sequences for the correct species
fi

if [ -n "$RIBO_SEQ_TRNA_FASTA" ]; then
    tRNA_fasta="$RIBO_SEQ_TRNA_FASTA"
else
    tRNA_fasta=${fasta_dir}/tRNA/hg38-mature-tRNAs-dna.fasta #this needs to point to a fasta file containing tRNA sequences for the correct species
fi

if [ -n "$RIBO_SEQ_PC_FASTA" ]; then
    pc_fasta="$RIBO_SEQ_PC_FASTA"
else
    pc_fasta=${fasta_dir}/GENCODE/${genome_version}/gencode.${genome_version}.pc_transcripts_chr20_filtered.fa #this needs to point to a protein coding fasta. See GitHub README file for more information on what is most recommended
fi

if [ -n "$RIBO_SEQ_GENOME_FASTA" ]; then
    genome_fasta="$RIBO_SEQ_GENOME_FASTA"
else
    # Default to a guessed path, though for full genome it's usually gencode.vX.transcripts.fa or dna.primary_assembly.fa
    # Here we assume a standard name, but user should likely provide it if it differs
    genome_fasta=${fasta_dir}/GENCODE/${genome_version}/gencode.${genome_version}.dna_chr20.fa.gz
fi

if [ -n "$RIBO_SEQ_RSEM_INDEX" ]; then
    rsem_index="$RIBO_SEQ_RSEM_INDEX"
else
    rsem_index=${fasta_dir}/GENCODE/${genome_version}/rsem_bowtie2_index/gencode.${genome_version}.pc_transcripts_filtered #this needs to point to a index that has been generated for alignment, that is also compatible for RSEM usage. Bowtie2 is recommended for this
fi

if [ -n "$RIBO_SEQ_STAR_INDEX" ]; then
    STAR_index="$RIBO_SEQ_STAR_INDEX"
else
    STAR_index=${fasta_dir}/GENCODE/${genome_version}/STAR_index #This needs to point to a STAR genome index that needs to have been previously created
fi

if [ -n "$RIBO_SEQ_STAR_GTF" ]; then
    STAR_GTF="$RIBO_SEQ_STAR_GTF"
else
    STAR_GTF=${fasta_dir}/GENCODE/${genome_version}/gencode.${genome_version}.annotation_chr20.gtf #This needs to point to the GTF file used to create the STAR index
fi
most_abundant_fasta=$most_abundant_transcripts_dir/most_abundant_transcripts.fa #this needs to be created for each specific project (see GitHub README file for more information)

###fasta info
#The below needs to point to a <.csv> file that contains the following information for all transcripts within the protein coding FASTA
#transcript_ID,5'UTR length,CDS length,3'UTR length
#Running the Filter_GENCODE_FASTA.py script will generate this file as one of its outputs

if [ -n "$RIBO_SEQ_REGION_LENGTHS" ]; then
    region_lengths="$RIBO_SEQ_REGION_LENGTHS"
else
    region_lengths=${fasta_dir}/GENCODE/${genome_version}/transcript_info/gencode.${genome_version}.pc_transcripts_chr20_region_lengths.csv
fi

