mkdir /home/train/05.genome_feature_analysis/telomere_analysis
cd /home/train/05.genome_feature_analysis/telomere_analysis

search_telomere_in_genome.pl --repeat-unit CACTTAA ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta > telomere_info.txt

# 1 2 3 4 5 6 双端各含有端粒
# 7 8 9 单端有端粒

# 5 9 含有rRNA序列
# 推测可能的染色体条数为7或8。
