# installing PASA (https://github.com/PASApipeline/PASApipeline/releases | https://github.com/PASApipeline/PASApipeline/wiki)
# installing GMAP
#wget http://research-pub.gene.com/gmap/src/gmap-gsnap-2017-11-15.tar.gz -P ~/software/
tar zxf ~/software/gmap-gsnap-2017-11-15.tar.gz 
cd gmap-2017-11-15
./configure --prefix=/opt/biosoft/gmap-2017-11-15/ && make -j 4 && make install
cd .. && rm -rf gmap-2017-11-15/
echo 'PATH=$PATH:/opt/biosoft/gmap-2017-11-15/bin/' >> ~/.bashrc
source ~/.bashrc

# installing blat 
#wget http://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/blat/blat -P ~/software/
mkdir /opt/biosoft/blat
cp ~/software/blat /opt/biosoft/blat
echo 'PATH=$PATH:/opt/biosoft/blat/' >> ~/.bashrc
source ~/.bashrc

# installing FASTA
#wget http://faculty.virginia.edu/wrpearson/fasta/fasta36/fasta-36.3.8g.tar.gz -P ~/software/
tar zxf ~/software/fasta-36.3.8g.tar.gz -C /opt/biosoft/
cd /opt/biosoft/fasta-36.3.8g/src/
make -f ../make/Makefile.linux_sse2 all
ln -s /opt/biosoft/fasta-36.3.8g/bin/fasta36 /opt/biosoft/fasta-36.3.8g/bin/fasta
echo 'PATH=$PATH:/opt/biosoft/fasta-36.3.8g/bin/' >> ~/.bashrc
source ~/.bashrc

# installing PASA
#wget https://github.com/PASApipeline/PASApipeline/releases/download/pasa-v2.4.1/PASApipeline.v2.4.1.FULL.tar.gz -P ~/software/
tar zxf ~/software/PASApipeline.v2.4.1.FULL.tar.gz -C /opt/biosoft/
cd /opt/biosoft/PASApipeline.v2.4.1
make -j 4
echo 'PATH=$PATH:/opt/biosoft/PASApipeline.v2.4.1/bin/' >> ~/.bashrc
source ~/.bashrc

# installing UniVec database for seqclean (https://www.ncbi.nlm.nih.gov/tools/vecscreen/univec/)
# install ncbi-blast fistly (ftp://ftp.ncbi.nih.gov/blast/executables/legacy.NOTSUPPORTED/2.2.26/)
#wget ftp://ftp.ncbi.nih.gov/blast/executables/legacy.NOTSUPPORTED/2.2.26/blast-2.2.26-x64-linux.tar.gz -P ~/software/
tar zxf /home/train/software/blast-2.2.26-x64-linux.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/blast-2.2.26/bin/' >> ~/.bashrc
source ~/.bashrc
#wget ftp://ftp.ncbi.nlm.nih.gov/pub/UniVec/UniVec -P ~/software/
mkdir /opt/biosoft/PASApipeline.v2.4.1/UniVec
cd /opt/biosoft/PASApipeline.v2.4.1/UniVec
cp ~/software/UniVec ./
formatdb -t UniVec -i UniVec -p F -o T

# modify pasa configure file
cd /opt/biosoft/PASApipeline.v2.4.1/pasa_conf/
cp pasa.CONFIG.template conf.txt
perl -p -i -e 's/MYSQLSERVER=.*/MYSQLSERVER=localhost/' conf.txt
perl -p -i -e 's/MYSQL_RW_USER=.*/MYSQL_RW_USER=train/' conf.txt
perl -p -i -e 's/MYSQL_RW_PASSWORD=.*/MYSQL_RW_PASSWORD=123456/' conf.txt
perl -p -i -e 's/MYSQL_RO_USER=.*/MYSQL_RO_USER=pasa/' conf.txt
perl -p -i -e 's/MYSQL_RO_PASSWORD=.*/MYSQL_RO_PASSWORD=123456/' conf.txt
perl -p -i -e 's#BASE_PASA_URL=.*#BASE_PASA_URL=http://localhost/pasa/cgi-bin/#' conf.txt
perl -p -i -e 's#VECTOR_DB=.*#VECTOR_DB=/opt/biosoft/PASApipeline.v2.4.1/UniVec/UniVec#' conf.txt

# installing lighttpd (https://www.lighttpd.net/) 是启用PASA网页工具所依赖的
#wget https://download.lighttpd.net/lighttpd/releases-1.4.x/lighttpd-1.4.54.tar.gz -P ~/software/
tar zxf ~/software/lighttpd-1.4.54.tar.gz 
cd lighttpd-1.4.54/
./configure --prefix /opt/sysoft/lighttpd-1.4.54
make -j 4
make install
cd ../ && rm -rf lighttpd-1.4.54
echo 'PATH=$PATH:/opt/sysoft/lighttpd-1.4.54/sbin/' >> ~/.bashrc


# installing AUGUSTUS (http://bioinf.uni-greifswald.de/augustus/ | https://github.com/Gaius-Augustus/Augustus)
# 安装bamtools是为了正常编译augustus的程序bam2hints。(https://github.com/pezmaster31/bamtools)
#wget https://github.com/pezmaster31/bamtools/archive/v2.5.1.tar.gz -O ~/software/bamtools-2.5.1.tar.gz
tar zxf ~/software/bamtools-2.5.1.tar.gz
cd bamtools-2.5.1/
mkdir build
cd build/
#cmake ../ -DCMAKE_INSTALL_PREFIX=/opt/biosoft/bamtools-2.5.1
cmake ../
make -j 4
sudo make install
sudo cp /usr/local/include/bamtools/ /usr/include/ -rf
cd ../../
rm bamtools-2.5.1/ -rf

#wget http://bioinf.uni-greifswald.de/augustus/binaries/augustus-3.3.3.tar.gz -P ~/software
tar zxf ~/software/augustus-3.3.3.tar.gz -C /opt/biosoft/
cd /opt/biosoft/augustus-3.3.3/
make clean
perl -p -i -e 's#^SAMTOOLS=.*#SAMTOOLS=/opt/biosoft/samtools-0.1.19/#; s#^HTSLIB=.*#HTSLIB=/opt/biosoft/htslib-1.10/lib/#;' auxprogs/bam2wig/Makefile
export CPLUS_INCLUDE_PATH=/opt/biosoft/boost_1_64_0/include:$CPLUS_INCLUDE_PATH
make -j 4
chmod 777 /opt/biosoft/augustus-3.3.3/config/species
echo 'PATH=$PATH:/opt/biosoft/augustus-3.3.3/bin/' >> ~/.bashrc
echo 'PATH=$PATH:/opt/biosoft/augustus-3.3.3/scripts/' >> ~/.bashrc
echo "export AUGUSTUS_CONFIG_PATH=/opt/biosoft/augustus-3.3.3/config/" >> ~/.bashrc
source ~/.bashrc


# installing genewise (https://www.ebi.ac.uk/Tools/psa/genewise/ | https://www.ebi.ac.uk/~birney/wise2/)
#wget https://www.ebi.ac.uk/~birney/wise2/wise2.4.1.tar.gz -P ~/software/
tar zxf ~/software/wise2.4.1.tar.gz -C /opt/biosoft/
cd /opt/biosoft/wise2.4.1/src/
find ./ -name makefile | xargs sed -i 's/glib-config/pkg-config --libs glib-2.0/'
perl -p -i -e 's/getline/get_line/g' ./HMMer2/sqio.c
perl -p -i -e 's/isnumber/isdigit/' models/phasemodel.c
make all -j 4
export WISECONFIGDIR=/opt/biosoft/wise2.4.1/wisecfg/
make test
echo 'PATH=$PATH:/opt/biosoft/wise2.4.1/src/bin/' >> ~/.bashrc
echo 'export WISECONFIGDIR=/opt/biosoft/wise2.4.1/wisecfg/' >> ~/.bashrc 
source ~/.bashrc
# 直接使用genewise无法进行全基因组水平的基因预测，需要自行编写程序来调用genewise进行基因预测。
tar zxf ~/software/geta-2.4.5.tar.gz -C /opt/biosoft/
# genewise的预测基因模型结果需要进行过滤处理，此处使用PFAM数据库进行过滤。以下安装Pfam数据库和Hmmer软件
# installing hmmer (http://www.hmmer.org/)
#wget http://eddylab.org/software/hmmer/hmmer-3.3.1.tar.gz -P ~/software/
tar zxf ~/software/hmmer-3.3.1.tar.gz
cd hmmer-3.3.1/
./configure --prefix=/opt/biosoft/hmmer-3.3.1 && make -j 4 && make install
cd .. && rm -rf hmmer-3.3.1
echo 'PATH=/opt/biosoft/hmmer-3.3.1/bin/:$PATH' >> ~/.bashrc
source ~/.bashrc
cd /opt/biosoft/hmmer-3.3.1
# installing Pfam v27 (http://pfam.xfam.org/ | ftp://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam27.0/)
#wegt ftp://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam27.0/Pfam-A.hmm.gz -O ~/software/Pfam-A_V27.hmm.gz
#wget ftp://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam27.0/Pfam-B.hmm.gz -O ~/software/Pfam-B_V27.hmm.gz
gzip -dc ~/software/Pfam-A_V27.hmm.gz > Pfam-AB.hmm
gzip -dc ~/software/Pfam-B_V27.hmm.gz >> Pfam-AB.hmm
hmmpress Pfam-AB.hmm
rm Pfam-AB.hmm


# installing GeneMark-ES / ET (http://topaz.gatech.edu/GeneMark/)
#wget http://topaz.gatech.edu/GeneMark/tmp/GMtool_JJWmO/gmes_linux_64.tar.gz -P ~/software/
tar zxf ~/software/gmes_linux_64.tar.gz -C /opt/biosoft/
gzip -dc ~/software/gm_key_64.gz > ~/.gm_key
echo 'PATH=$PATH:/opt/biosoft/gmes_linux_64' >> ~/.bashrc
source ~/.bashrc
sudo cpan -i YAML Hash::Merge Logger::Simple Parallel::ForkManager


# installing MAKER (http://www.yandell-lab.org/software/maker.html)
# installing exonerate (https://www.ebi.ac.uk/about/vertebrate-genomics/software/exonerate)
#wget http://ftp.ebi.ac.uk/pub/software/vertebrategenomics/exonerate/exonerate-2.2.0-x86_64.tar.gz -P ~/software/
tar zxf ~/software/exonerate-2.2.0-x86_64.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/exonerate-2.2.0-x86_64/bin/' >> ~/.bashrc
source ~/.bashrc
# installing SNAP (https://github.com/KorfLab/SNAP | http://korflab.ucdavis.edu/software.html)
#wget wget http://korflab.ucdavis.edu/Software/snap-2013-11-29.tar.gz -P ~/software/
tar zxf ~/software/snap-2013-11-29.tar.gz -C /opt/biosoft/
cd /opt/biosoft/snap/
make -j 4
echo 'PATH=$PATH:/opt/biosoft/snap' >> ~/.bashrc
source ~/.bashrc

# installing MAKER (http://yandell.topaz.genetics.utah.edu/cgi-bin/maker_license.cgi) 需要填写信息来下载
#wget http://yandell.topaz.genetics.utah.edu/maker_downloads/2D3B/22C6/BE99/41DBB7F9B1D181B2CDCE1E49DFE6/maker-3.01.03.tgz -P ~/software/
tar zxf ~/software/maker-3.01.03.tgz -C /opt/biosoft/
cd /opt/biosoft/maker/src/
perl Build.PL
# 程序会检测依赖的Perl模块是否安装成功。若缺少必须的Perl模块，使用cpan命令安装之。
#Would you like to configure MAKER for MPI                          Y, Enter
# Please specify the path to 'mpicc' on your system: [/usr/lib64/mpich/bin/mpicc ], Enter
# Please specify the path to the directory containing 'mpi.h': [/usr/include/mpich-x86_64 ], Enter
./Build install
echo 'PATH=$PATH:/opt/biosoft/maker/bin/' >> ~/.bashrc
source ~/.bashrc


# intalling BRAKER (https://github.com/Gaius-Augustus/BRAKER)
#wget https://github.com/Gaius-Augustus/BRAKER/archive/v2.1.5.tar.gz -O ~/software/BRAKER-2.1.5.tar.gz
tar zxf ~/software/BRAKER-2.1.5.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/BRAKER-2.1.5/scripts/' >> ~/.bashrc
source ~/.bashrc
sudo cpan -i Scalar::Util::Numeric MCE::Mutex Math::Utils
# 修改augustus-3.3.3的一支perl程序（augustus-3.3.3/scripts/filterGenesIn_mRNAname.pl）内容，否则braker调用该程序后，生成空文件导致程序运行失败
perl -p -i -e 's#\(\.\*\)#\(\.\*\?\)# if m/transcript_id/;' /opt/biosoft/augustus-3.3.3/scripts/filterGenesIn_mRNAname.pl

# installing GenomeThreader (http://genomethreader.org/)
#wget http://genomethreader.org/distributions/gth-1.7.3-Linux_x86_64-64bit.tar.gz -P ~/software/
tar zxf ~/software/gth-1.7.3-Linux_x86_64-64bit.tar.gz -C /opt/biosoft/
# install ProtHint (https://github.com/gatech-genemark/ProtHint)
#wget https://github.com/gatech-genemark/ProtHint/releases/download/v2.4.0/ProtHint-2.4.0.tar.gz -P ~/software/
tar zxf ~/software/ProtHint-2.4.0.tar.gz -C /opt/biosoft/
ln -s /opt/biosoft/ProtHint-2.4.0/bin/* /opt/biosoft/gth-1.7.3-Linux_x86_64-64bit/bin/


# 5. installing EVM (https://github.com/EVidenceModeler/EVidenceModeler/ | http://evidencemodeler.github.io/)
#wget https://github.com/EVidenceModeler/EVidenceModeler/archive/v1.1.1.tar.gz -O ~/software/EVidenceModeler-1.1.1.tar.gz
tar zxf ~/software/EVidenceModeler-1.1.1.tar.gz -C /opt/biosoft/
tar zxf ~/software/EVM_r2012-06-25.tgz -C /opt/biosoft/


# 6. installing GETA (https://github.com/chenlianfu/geta)
#wget https://github.com/chenlianfu/geta/archive/2.4.5.tar.gz -O ~/software/geta-2.4.5.tar.gz
tar zxf ~/software/geta-2.4.5.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/geta-2.4.5/bin/' >> ~/.bashrc
source ~/.bashrc


# 7. installing BUSCO (https://busco.ezlab.org/)
#wget https://github.com/soedinglab/metaeuk/releases/download/2-ddf2742/metaeuk-linux-sse41.tar.gz -P ~/software
tar zxf ~/software/metaeuk-linux-sse41.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/metaeuk/bin' >> ~/.bashrc
source ~/.basrhc
#wget https://github.com/smirarab/sepp/archive/4.3.10.tar.gz -O ~/software/sepp-4.3.10.tar.gz
pip install dendropy -i https://mirrors.aliyun.com/pypi/simple/
tar zxf ~/software/sepp-4.3.10.tar.gz -C /opt/biosoft/
python setup.py config
python setup.py install
#wget https://github.com/hyattpd/Prodigal/releases/download/v2.6.3/prodigal.linux -P ~/software
mkdir /opt/biosoft/prodigal-v2.6.3
cp ~/software/prodigal.linux /opt/biosoft/prodigal-v2.6.3/prodigal
chmod 755 /opt/biosoft/prodigal-v2.6.3/prodigal
echo 'PATH=$PATH:/opt/biosoft/prodigal-v2.6.3' >> ~/.bashrc
source ~/.bashrc

#wget https://gitlab.com/ezlab/busco/-/archive/4.1.2/busco-4.1.2.tar.gz -P ~/software
tar zxf ~/software/busco-4.1.2.tar.gz -C /opt/biosoft/
cd /opt/biosoft/busco-4.1.2/
python3 setup.py install
./scripts/busco_configurator.py config/config.ini config/myconfig.ini
cp config/myconfig.ini config/config.ini
echo 'export BUSCO_CONFIG_FILE=/opt/biosoft/busco-4.1.2/config/config.ini' >> ~/.bashrc
echo 'PATH=$PATH:/opt/biosoft/busco-4.1.2/bin/'  >> ~/.bashrc
source ~/.bashrc

pip3 install intervaltree==3.0.0 -i https://mirrors.aliyun.com/pypi/simple/
pip3 install bio -i https://mirrors.aliyun.com/pypi/simple/

busco --list-datasets &> Lineage_datasets.txt
# downloading databases
#wget https://busco-data.ezlab.org/v4/data/lineages/fungi_odb10.2019-12-13.tar.gz -P ~/software/BUSCO_databases
#wget https://busco-data.ezlab.org/v4/data/lineages/basidiomycota_odb10.2019-11-20.tar.gz -P ~/software/BUSCO_databases
#wget https://busco-data.ezlab.org/v4/data/lineages/ascomycota_odb10.2019-11-20.tar.gz -P ~/software/BUSCO_databases
mkdir databases
cd databases
tar zxf ~/software/BUSCO_databases/fungi_odb10.2019-12-13.tar.gz
tar zxf ~/software/BUSCO_databases/basidiomycota_odb10.2019-11-20.tar.gz
tar zxf ~/software/BUSCO_databases/ascomycota_odb10.2019-11-20.tar.gz


# 8. installing SpliceGrapher (http://splicegrapher.sourceforge.net/)
#wget https://sourceforge.net/projects/splicegrapher/files/SpliceGrapher-0.2.7.tgz -P ~/software/
tar zxf ~/software/SpliceGrapher-0.2.7.tgz -C /opt/biosoft/
cd /opt/biosoft/SpliceGrapher-0.2.7/
python setup.py build
python setup.py install
echo 'PATH=$PATH:/opt/biosoft/SpliceGrapher-0.2.7/scripts/' >> ~/.bashrc
source ~/.bashrc

pip install numpy pysam matplotlib -i https://mirrors.aliyun.com/pypi/simple/
#wget https://sourceforge.net/projects/pyml/files/PyML-0.7.14.tar.gz -P ~/software/
tar zxf ~/software/PyML-0.7.14.tar.gz
cd PyML-0.7.14
python setup.py install
cd .. && rm PyML-0.7.14/ -rf

# installing isolasso (http://alumni.cs.ucr.edu/~liw/isolasso.html)
#wget http://alumni.cs.ucr.edu/~liw/isolasso-2.6.1.tar.gz -P ~/software/
tar zxf ~/software/isolasso-2.6.1.tar.gz -C /opt/biosoft/
cd /opt/biosoft/isolasso/src/
export CXXFLAGS="$CXXFLAGS -I/opt/biosoft/isolasso/src/isolassocpp/CGAL/include -L/opt/biosoft/isolasso/src/isolassocpp/CGAL/lib"
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/biosoft/isolasso/src/isolassocpp/CGAL/lib/
make -j 4
sudo cp isolassocpp/CGAL/lib/libCGAL.so* /usr/local/lib/
sudo cp isolassocpp/CGAL/include/* /usr/local/include/ -r
echo 'PATH=$PATH:/opt/biosoft/isolasso/bin/' >> ~/.bashrc
source ~/.bashrc


## 9. installing genemarkS (http://exon.gatech.edu/GeneMark/)
#wget http://topaz.gatech.edu/GeneMark/tmp/GMtool_Gtc4c/gms2_linux_64.tar.gz -P ~/software/
tar zxf ~/software/gms2_linux_64.tar.gz -C /opt/biosoft/
gzip -dc /home/train/software/gm_key_64.gms2.gz > ~/.gmhmmp2_key
echo 'PATH=$PATH:/opt/biosoft/gms2_linux_64//' >> ~/.bashrc
source ~/.bashrc
