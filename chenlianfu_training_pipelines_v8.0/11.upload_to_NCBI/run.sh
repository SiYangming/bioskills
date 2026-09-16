mkdir -p /home/train/11.upload_to_NCBI/
cd /home/train/11.upload_to_NCBI/

# 制作 ASN 文件
# 将GFF3格式转换成tbl文件
gff3_remove_UTR.pl ~/00.incipient_data/data_for_gene_prediction_and_RNA-seq/Malassezia_sympodialis_V01.BestGeneModels.gff3 > Malassezia_sympodialis.gff3
gff3_to_tbl_for_antismatsh.pl Malassezia_sympodialis.gff3 > Malassezia_sympodialis.tbl
# 准备基因组序列文件
perl -p -e 's/>(\S+).*/>$1 [organism=Malassezia sympodialis] [gcode=1]/' ~/00.incipient_data/data_for_genome_assembling/assemblies_of_Malassezia_sympodialis/Malassezia_sympodialis.genome_V01.fasta > Malassezia_sympodialis.fsa
# 通过网站http://www.ncbi.nlm.nih.gov/WebSub/template.cgi制作sbt文件
cp ~/00.incipient_data/data_for_genome_assembling/template.sbt Malassezia_sympodialis.sbt
# 运行tbl2asn命令生成后缀为.sqn的ASN文件
tbl2asn -t Malassezia_sympodialis.sbt -p ./ -a a -V vb -M n -Z discrep
# real	0m29.280s
# user	0m29.159s
# sys	0m0.093s

# 上传测序数据
md5sum testreads.fastq
lftp -e "put -c testreads.fastq; exit" -u sra,VfOiVJn1 ftp-private.ncbi.nlm.nih.gov

