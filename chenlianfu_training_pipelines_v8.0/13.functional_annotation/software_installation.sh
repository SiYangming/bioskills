# installing NCBI-blast+ (ftp://ftp.ncbi.nih.gov/blast/executables/blast+/ | https://blast.ncbi.nlm.nih.gov/Blast.cgi)
#wget ftp://ftp.ncbi.nih.gov/blast/executables/blast+/2.9.0/ncbi-blast-2.9.0+-x64-linux.tar.gz -P ~/software/
tar zxf ~/software/ncbi-blast-2.9.0+-x64-linux.tar.gz -C /opt/biosoft/
echo 'PATH=/opt/biosoft/ncbi-blast-2.9.0+/bin/:$PATH' >> ~/.bashrc 
source ~/.bashrc
echo "[BLAST]
BLASTDB=/opt/biosoft/wwwblast/db/" > ~/.ncbirc


# installing DIAMOND (https://github.com/bbuchfink/diamond)
#wget https://github.com/bbuchfink/diamond/releases/download/v2.0.2/diamond-linux64.tar.gz -P ~/software/
mkdir /opt/biosoft/diamond
tar zxf ~/software/diamond-linux64.tar.gz -C /opt/biosoft/diamond
echo 'PATH=$PATH:/opt/biosoft/diamond' >> ~/.bashrc
source ~/.bashrc


# installing wwwblast (NCBI不再提供本软件下载了)
tar zxf ~/software/wwwblast-2.2.26-x64-linux.tar.gz -C /opt/biosoft/
mv /opt/biosoft/blast /opt/biosoft/wwwblast/
# 配置www网页服务
cp /etc/httpd/conf/httpd.conf 11
echo '
Alias /blast "/opt/biosoft/wwwblast"
<Directory "/opt/biosoft/wwwblast">
    Options MultiViews ExecCGI
    AllowOverride AuthConfig
    Order allow,deny
    Allow from all
</Directory>' >> 11
sudo mv 11 /etc/httpd/conf/httpd.conf
sudo perl -p -i -e 's/^#AddHandler cgi-script .cgi/AddHandler cgi-script .cgi/' /etc/httpd/conf/httpd.conf
# 重启httpd，让修改的配置信息生效
sudo systemctl restart httpd.service

# installing public databases
rm /opt/biosoft/wwwblast/db/* -rf

# Nr (version:20190401)
cd /opt/biosoft/wwwblast/db/
ASCP="ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv";
for ((i=0;i<=9;i=i+1))
do
    for ((x=0;x<=9;x=x+1))
    do
        echo "$ASCP /blast/db/nr.$i$x.tar.gz ./"
        echo "$ASCP /blast/db/nr.$i$x.tar.gz.md5 ./"
    done
done > command.ascp_nr.list
for ((i=0;i<=1;i=i+1))
do
    for ((x=0;x<=9;x=x+1))
    do
        echo "$ASCP /blast/db/nr.1$i$x.tar.gz ./"
        echo "$ASCP /blast/db/nr.1$i$x.tar.gz.md5 ./"
    done
done | head -n 28 >> command.ascp_nr.list
ParaFly -c command.ascp_nr.list -CPU 2
# 检测下载的文件是否正常
md5sum nr.??.tar.gz > nr.md5sum.txt1
cat nr.??.tar.gz.md5 > nr.md5sum.txt2
diff nr.md5sum.txt1 nr.md5sum.txt2
for i in `ls nr.??.tar.gz`
do
    tar zxf $i
done
rm command.ascp_nr.list* nr.md5sum.txt1 nr.md5sum.txt2 *.md5 *.gz

# Nr数据库子集数据库的创建方法
cd /opt/biosoft/Nr_database
# 下载Nr数据库（FASTA文件）
ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp.ncbi.nih.gov --user=anonftp --mode=recv /blast/db/FASTA/nr.gz ./
# 下载NCBI的分类数据库文件
ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp.ncbi.nih.gov --user=anonftp --mode=recv /pub/taxonomy/taxdump.tar.gz ./
ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh --host=ftp.ncbi.nih.gov --user=anonftp --mode=recv /pub/taxonomy/accession2taxid/prot.accession2taxid.gz ./
# 下载并安装NCBI分类数据库解析软件TaxonKit
wget https://github.com/shenwei356/taxonkit/releases/download/v0.2.4/taxonkit_linux_amd64.tar.gz
tar zxvf taxonkit_linux_amd64.tar.gz
#提取想要的指定大类物种序列
mkdir ~/.taxonkit
tar zxf taxdump.tar.gz -C ~/.taxonkit
# 其主要有效文件有两个：
# names.dmp 记录物种名及其分类编号
# nodes.dmp 记录分类编号的节点信息
# 提取古菌(2157)、细菌(2)和病毒(10239)这几个大类对应的所有分类编号。
# 查看~/.taxonkit/names.dmp文件，使用关键词检索得到目标类的分类编号，例如：
# fungi	4751             # grep -P "\|\s+[fF]ungi\w*\s*\|" ~/.taxonkit/names.dmp
# plants 3193            # grep -P "\|\s+[pP]lant\w*\s*\|" ~/.taxonkit/names.dmp
# animals 33208          # grep -P "\|\s+[aA]nimal\w*\s*\|" ~/.taxonkit/names.dmp
# 提取包含古菌(2157)、细菌(2)和病毒(10239)的子集
# 使用taxonkit命令解析nodes.dmp文件的物种节点信息，得到指定类的所有物种列表信息；再编写程序extract_sub_data_from_Nr.pl获得列表中物种在Nr数据库中的序列信息。
./taxonkit list -j 8 --ids 2,2157,10239 > sub.meta.list
gzip -dc prot.accession2taxid.gz > prot.accession2taxid
gzip -dc nr.gz | perl extract_sub_data_from_Nr.pl --sub_taxon sub.meta.list --acc2taxid prot.accession2taxid - > nr_meta.fasta
# 提取fungi/plants/animals子集
./taxonkit list -j 8 --ids 4751 > sub.fungi.list
./taxonkit list -j 8 --ids 3193 > sub.plants.list
./taxonkit list -j 8 --ids 33208 > sub.animals.list
gzip -dc nr.gz | perl extract_sub_data_from_Nr.pl --sub_taxon sub.fungi.list --acc2taxid prot.accession2taxid - > nr_fungi.fasta
gzip -dc nr.gz | perl extract_sub_data_from_Nr.pl --sub_taxon sub.plants.list --acc2taxid prot.accession2taxid - > nr_plants.fasta
gzip -dc nr.gz | perl extract_sub_data_from_Nr.pl --sub_taxon sub.animals.list --acc2taxid prot.accession2taxid - > nr_animals.fasta
cat nr_animals.fasta nr_plants.fasta nr_fungi.fasta > nr_eukaryon.fasta
# 使用makeblastdb创建blast本地数据库
makeblastdb -in nr_fungi.fasta -dbtype prot -title nr_fungi -parse_seqids -out nr_fungi_`date +%Y%m%d` -logfile nr_fungi_`date +%Y%m%d`.log
makeblastdb -in nr_fungi.fasta -dbtype prot -title nr_plants -parse_seqids -out nr_plants_`date +%Y%m%d` -logfile nr_plants_`date +%Y%m%d`.log
makeblastdb -in nr_fungi.fasta -dbtype prot -title nr_animals -parse_seqids -out nr_animals_`date +%Y%m%d` -logfile nr_animals_`date +%Y%m%d`.log
makeblastdb -in nr_eukaryon.fasta -dbtype prot -title nr_eukaryon -parse_seqids -out nr_eukaryon_`date +%Y%m%d` -logfile nr_eukaryon_`date +%Y%m%d`.log

# COG/KOG (https://www.ncbi.nlm.nih.gov/COG/)
#wget ftp://ftp.ncbi.nih.gov/pub/COG/COG/myva -P ~/software/
#wget ftp://ftp.ncbi.nih.gov/pub/COG/KOG/kyva -P ~/software/
cd /opt/biosoft/wwwblast/db/
cp ~/software/myva cog.fasta
cp ~/software/kyva kog.fasta
makeblastdb -in cog.fasta -dbtype prot -title cog -parse_seqids -out cog -logfile cog.log
makeblastdb -in kog.fasta -dbtype prot -title kog -parse_seqids -out kog -logfile kog.log

# Uniprot Swiss-Prot (https://www.uniprot.org/downloads)
#wget ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz -P ~/software/
cd /opt/biosoft/wwwblast/db/
gzip -dc ~/software/uniprot_sprot.fasta.gz > uniprot_sprot.fasta
makeblastdb -in uniprot_sprot.fasta -dbtype prot -title uniprot_sprot -parse_seqids -out uniprot_sprot -logfile uniprot_sprot.log

# 更新wwwblast数据库设置
cd /opt/biosoft/wwwblast/
update_wwwblast_config.pl

# 设置使用用户和密码访问wwwblast
echo 'AuthName     "Protected!"
Authtype     Basic
AuthUserFile /var/www/apache.passwd
require user train' > /opt/biosoft/wwwblast/.htaccess
sudo htpasswd -c -b /var/www/apache.passwd train 123456


# installing eggnog-mapper (https://github.com/eggnogdb/eggnog-mapper | http://eggnogdb.embl.de)
#wget https://github.com/eggnogdb/eggnog-mapper/archive/1.0.3.tar.gz -O ~/software/eggnog-mapper-1.0.3.tar.gz
tar zxf ~/software/eggnog-mapper-1.0.3.tar.gz -C /opt/biosoft
cd /opt/biosoft/eggnog-mapper-1.0.3
# http://eggnogdb.embl.de/download/emapperdb-4.5.1/og2level.tsv.gz
# http://eggnogdb.embl.de/download/emapperdb-4.5.1/eggnog.db.gz
# http://eggnogdb.embl.de/download/emapperdb-4.5.1/OG_fasta.tar.gz
# http://eggnogdb.embl.de/download/emapperdb-4.5.1/eggnog_proteins.dmnd.gz
# http://eggnogdb.embl.de/download/emapperdb-4.5.1/hmmdb_levels/euk_500/
# installing eggnog-mapper database (http://eggnogdb.embl.de/#/app/downloads)


# installing Blast2go Databases
mkdir /opt/biosoft/blast2go
cd /opt/biosoft/blast2go
wget http://archive.geneontology.org/latest-full/go_monthly-assocdb-data.gz
wget ftp://ftp.ncbi.nlm.nih.gov/gene/DATA/gene_info.gz
wget ftp://ftp.ncbi.nlm.nih.gov/gene/DATA/gene2accession.gz   
wget ftp://ftp.pir.georgetown.edu/databases/idmapping/idmapping.tb.gz
gzip -dv go_monthly-assocdb-data.gz
gzip -dv gene_info.gz
gzip -dv gene2accession.gz
gzip -dv idmapping.tb.gz

tar zxf ~/software/local_b2g_db.tar.gz 
mv local_b2g_db/* ./  && rm -rf local_b2g_db/
perl -p -i -e 's/go_201512-assocdb-data/go_monthly-assocdb-data/' install_blast2goDB.sh
DATE=$(date +%Y%m%d)
perl -p -i -e "s/dbname=b2gdb/dbname=b2gdb$DATE/" install_blast2goDB.sh
perl -p -i -e "s/b2gdb/b2gdb$DATE/" b2gdb.sql
perl -p -i -e 's/\$dbname < b2gdb.sql/< b2gdb.sql/' install_blast2goDB.sh
./install_blast2goDB.sh

# 使用Ontologizer进行GO富集分析需要使用1.7版本JAVA
tar zxf ~/software/jre1.7.0_05.tar.gz -C /opt/sysoft/

# GO class分析软件安装
tar zxf ~/software/go_class.tar.gz -C /opt/biosoft/
cd /opt/biosoft/go_class/bin/
./make_go_class_config.pl go.obo
echo 'PATH=$PATH:/opt/biosoft/go_class/bin/' >> ~/.bashrc
source ~/.bashrc

#wget https://www.blast2go.com/downloads/software/blast2go/latest/3_3/Blast2GO_unix_3_3_x64.zip -P ~/software/
unzip ~/software/Blast2GO_unix_3_3_x64.zip
./Blast2GO_unix_3_3_x64.sh 
# 指定安装目录为/opt/biosoft/Blast2GO。
rm Blast2GO_unix_3_3_x64.sh 
echo 'PATH=$PATH:/opt/biosoft/Blast2GO/' >> ~/.bashrc
source ~/.bashrc


# 安装 dbCAN (http://bcb.unl.edu/dbCAN2/index.php)
#mkdir /opt/biosoft/dbCAN_v9.0
#cd /opt/biosoft/dbCAN_v9.0
#wget http://bcb.unl.edu/dbCAN2/download/dbCAN-HMMdb-V9.txt
#wget http://bcb.unl.edu/dbCAN2/download/CAZyDB.07312020.fa
#perl -p -i -e 's/\|\s*$/\n/ if m/^>/' CAZyDB.07312020.fa
#wget http://bcb.unl.edu/dbCAN2/download/Databases/V9/hmmscan-parser.sh
#wget http://bcb.unl.edu/dbCAN2/download/Databases/V9/readme.txt
tar zxf ~/software/dbCAN_v9.0.tar.gz -C /opt/biosoft/
cd /opt/biosoft/dbCAN_v9.0
ln -s dbCAN-HMMdb-V9.txt dbCAN-fam-HMMs.txt
hmmpress dbCAN-fam-HMMs.txt
diamond makedb --in /opt/biosoft/dbCAN_v9.0/CAZyDB.07312020.fa --db /opt/biosoft/dbCAN_v9.0/CAZyDB.07312020


# Installing SignalP (http://www.cbs.dtu.dk/services/SignalP/ | http://www.cbs.dtu.dk/services/software.php)
# 需要填写edu邮箱和相关信息来获取下载地址
#wget http://www.cbs.dtu.dk/download/6B91F6BC-5A05-11E9-8172-2ED6B9CD16B5/signalp-5.0.Linux.tar.gz -P ~/software/
tar zxf /home/train/software/signalp-5.0.Linux.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/signalp-5.0/bin' >> ~/.bashrc
source ~/.bashrc


# Installing TMHMM (http://www.cbs.dtu.dk/services/TMHMM/)
# 需要填写edu邮箱和相关信息来获取下载地址
#wget http://www.cbs.dtu.dk/download/2435F062-5A0E-11E9-8117-6AA2B9CD16B5/tmhmm-2.0c.Linux.tar.gz -P ~/software/
tar zxf /home/train/software/tmhmm-2.0c.Linux.tar.gz -C /opt/biosoft/
perl -p -i -e 's#/usr/local/bin/perl#/usr/bin/perl#' /opt/biosoft/tmhmm-2.0c/bin/tmhmm*
echo 'PATH=$PATH:/opt/biosoft/tmhmm-2.0c/bin/' >> ~/.bashrc
source ~/.bashrc


# Installing HPI-Base
mkdir /opt/biosoft/PHI-base4.8
cd /opt/biosoft/PHI-base4.8
cp ~/software/phi-base_v4-8_2019-09-16* ./
makeblastdb -in phi-base_v4-8_2019-09-16.fas -dbtype prot -title protein -parse_seqids -out phi -logfile phi.protein.log
cp phi* /opt/biosoft/wwwblast/db/
