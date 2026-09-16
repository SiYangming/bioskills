mkdir -p /home/train/05.genome_feature_analysis/tRNAscan-SE
cd /home/train/05.genome_feature_analysis/tRNAscan-SE

tRNAscan-SE -o tRNA.out -f tRNA.ss -m tRNA.stats ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta
# real	0m2.087s
# user	0m2.034s
# sys	0m0.041s

tRNAscanSE2GFF3.pl tRNA.out tRNA.ss > tRNA.gff3
