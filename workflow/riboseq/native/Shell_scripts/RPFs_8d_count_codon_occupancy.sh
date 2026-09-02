#!/usr/bin/env bash

#read in variables
source common_variables.sh

#run count_codon_occupancy.py to calculate codon occupancy counts in each position of the ribosome
for filename in $RPF_filenames
do
python3 $PYTHON_SCRIPTS_DIR/count_codon_occupancy.py ${filename}_pc_final.counts $most_abundant_fasta $region_lengths 20 -10 -in_dir $counts_dir -out_dir $codon_counts_dir &
done
wait
