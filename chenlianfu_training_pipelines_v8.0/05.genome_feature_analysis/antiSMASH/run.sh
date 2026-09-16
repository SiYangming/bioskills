mkdir -p /home/train/05.genome_feature_analysis/antiSMASH
cd /home/train/05.genome_feature_analysis/antiSMASH

ln -s ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.GeneModels.gbf genome.gbk
export PATH=/opt/biosoft/miniconda3_for_antiSMASH/bin:$PATH
source activate antismash
antismash -c 8 --taxon fungi genome.gbk
# real	59m31.857s
# user	277m22.548s
# sys	10m43.819s

tar zxf ~/00.incipient_data/data_for_functional_annotation/antiSMASH_out.tar.gz
