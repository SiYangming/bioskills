mkdir -p /home/train/05.genome_feature_analysis/Rfam
cd /home/train/05.genome_feature_analysis/Rfam

cmsearch --cut_ga --nohmmonly --rfam --noali --cpu 8 --tblout rfam_out.tab /opt/biosoft/infernal-1.1.3/Rfam.cm ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta  > rfam_out.txt
# real	7m8.997s
# user	42m29.662s
# sys	0m13.048s

Rfam_rRNA_stats.pl rfam_out.tab
Rfam_miRNA_stats.pl rfam_out.tab /opt/biosoft/infernal-1.1.3/Rfam.cm
Rfam_snRNA_stats.pl rfam_out.tab ~/software/snoRNA_type.txt
