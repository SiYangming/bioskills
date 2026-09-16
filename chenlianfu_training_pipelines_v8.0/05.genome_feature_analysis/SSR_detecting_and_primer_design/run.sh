mkdir -p /home/train/05.genome_feature_analysis/SSR_detecting_and_primer_design
cd /home/train/05.genome_feature_analysis/SSR_detecting_and_primer_design

# 使用 MISA 进行 SSR 检测
cp /opt/biosoft/Misa_Primer3/misa.ini .
ln -s ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta genome.fasta
misa.pl genome.fasta
# real	0m4.261s
# user	0m4.253s
# sys	0m0.008s

# 使用 primer3 进行引物批量设计
perl -p -e 's/\s*#.*//; s/^\s*$//; s/P3_FILE_ID/\nP3_FILE_ID/' /opt/biosoft/Misa_Primer3/p3_settings_from_chenlianfu.txt > p3_settings_file
perl -p -i -e 's#^PRIMER_THERMODYNAMIC_PARAMETERS_PATH.*#PRIMER_THERMODYNAMIC_PARAMETERS_PATH=/opt/biosoft/primer3-2.5.0/src/primer3_config/#' p3_settings_file
#head -n 21 genome.fasta.misa > 11; mv 11 genome.fasta.misa
misa_primer3.pl --CPU 8 --gff3_out misa_primer3.gff3 --p3_setting_file p3_settings_file genome.fasta.misa genome.fasta > misa_primer3.out
# real	10m59.590s
# user	86m16.630s
# sys	0m1.332s
