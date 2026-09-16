mkdir -p /home/train/05.genome_feature_analysis/RNAmmer
cd /home/train/05.genome_feature_analysis/RNAmmer

/opt/biosoft/rnammer-1.2/rnammer -S euk -multi -f rRNA.fasta -h rRNA.hmmreport -xml rRNA.xml -gff rRNA.gff2 ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta
# real	0m16.902s
# user	0m37.592s
# sys	0m0.175s
rRNAmmer_gff2gff3.pl rRNA.gff2 > rRNA.gff3
cd ..
