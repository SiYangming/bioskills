## Installing Circos (http://circos.ca/)
#wget http://circos.ca/distribution/circos-0.69-6.tgz -P ~/software/
tar zxf ~/software/circos-0.69-6.tgz -C /opt/biosoft/
cd /opt/biosoft/circos-0.69-6/bin
./circos -modules | perl -e 'while (<>) { print "$1 " if m/missing\s+(\S+)/ }' | perl -p -e 's/^/sudo cpan -i /; s/$/\n/' | sh
./circos -modules
./gddiag
./circos --help
cd ../example/
../bin/circos -conf etc/circos.conf
echo 'PATH=$PATH:/opt/biosoft/circos-0.69-6/bin/' >> ~/.bashrc
source ~/.bashrc


## installing IGV (http://software.broadinstitute.org/software/igv/)
#wget http://data.broadinstitute.org/igv/projects/downloads/2.5/IGV_Linux_2.5.3.zip -P ~/software/
unzip ~/software/IGV_Linux_2.5.3.zip -d /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/IGV_Linux_2.5.3/' >> ~/.bashrc
source ~/.bashrc
mkdir -p ~/igv/genomes/
cp ~/software/hg18.genome ~/igv/genomes/


# installing GBrowse (http://gmod.org/wiki/GBrowse | https://github.com/GMOD/GBrowse) 使用root用户运行下面的命令进行安装：
#wget https://github.com/GMOD/GBrowse/archive/release-2.56.tar.gz -O ~/software/GBrowse-release-2.56.tar.gz
tar zxf /home/train/software/GBrowse-release-2.56.tar.gz -C /opt/biosoft/
cd /opt/biosoft/GBrowse-release-2.56/
perl Makefile.PL
# 程序会检测GBrowse2所依赖的Perl模块是否就绪，若必须依赖的Perl模块全部就绪，才能成功安装GBrowse2
./Build test
./Build install
systemctl restart httpd.service

# 若缺少部分Perl模块，则使用如下命令自动安装
./Build installdeps
# 自动安装一般会由于各种原因而失败。推荐进行如下操作：
# （1）注意安装perl模块，推荐优先设置网速快的CPAN源，使用root用户执行下面的命令，使用国内速度较快的aliyun和163的CPAN源。
#perl -p -i -e "s#urllist.*#urllist' => [q[http://mirrors.aliyun.com/CPAN/], q[http://mirrors.163.com/CPAN/]],#" /usr/share/perl5/CPAN/Config.pm
# （2）难点在于安装BioPerl会失败。需要LibGD支持才能安装BioPerl成功，安装LibGD流程请参考01.CentOS_System_Configuration/system_software_installation.sh部分。
# 单独安装一些perl模块
# cpan -i BioPerl
# cpan -fi Bio::DB::GFF
# cpan -i Bio::DB::SeqFeature
# cpan -i Bio::Graphics
# cpan -i GD::SVG
# cpan -fi Bio::Das
# （3）最后剩下 Bio::DB::BigFile 和 Bio::DB::Sam 模块较难安装。他们的安装分别需要依赖 kent 和 samtools 。
# Installing kent
#wget http://hgdownload.cse.ucsc.edu/admin/jksrc.archive/jksrc.v330.zip -O ~/software/jksrc.zip
#不要用最新版本kent，最新版kent编译不出所需要的jkweb.a文件
unzip /home/train/software/jksrc.zip -d /opt/biosoft/
cd /opt/biosoft/kent/src/
export MACHTYPE=x86_64
mkdir -p ~/bin/x86_64
make CXXFLAGS=-fPIC CFLAGS=-fPIC CPPFLAGS=-fPIC -j 4
cp ./lib/x86_64/jkweb.a ./lib/
mv ~/bin/x86_64/ bin/
mv ~/bin/scripts/ ./
# Installing samtools
#wget https://sourceforge.net/projects/samtools/files/samtools/0.1.19/samtools-0.1.19.tar.bz2 -P ~/software/
tar jxf /home/train/software/samtools-0.1.19.tar.bz2 -C /opt/biosoft/
cd /opt/biosoft/samtools-0.1.19/
make clean
make CXXFLAGS=-fPIC CFLAGS=-fPIC CPPFLAGS=-fPIC
# 再次进行安装perl模块
cd /opt/biosoft/GBrowse-2.6/
./Build installdeps
# 输入 /opt/biosoft/kent/src 路径来安装 Bio::DB::BigFile
# 输入 /opt/biosoft/samtools-0.1.19/ 路径来安装 Bio::DB::Sam
# 安装Bio::BigFile和Bio::DB::Sam模块时可能会由于编译警告而失败，则需要手动安装该模块，修改其Build.PL内容，使-Wformat=1，则能编译成功。
# 最后安装 GBrowse
./Build test
# test步骤继续失败的原因可能是BioPerl安装有问题。
./Build install
systemctl restart httpd.service

# 若安装失败，需要重新安装，则需要删除GBrowse相关的全部文件，然后重新安装
# /bin/rm -rf /etc/gbrowse2 /var/www/html/gbrowse2 /var/tmp/gbrowse2 /var/lib/gbrowse2 /var/www/cgi-bin/gb2 /etc/httpd/conf.d/z_gbrowse2.conf /opt/biosoft/GBrowse-2.56/ /etc/httpd/conf.d/gbrowse2.conf


## installing JBrowse (http://jbrowse.org/)
#wget https://github.com/GMOD/jbrowse/releases/download/1.16.4-release/JBrowse-1.16.4.zip -P ~/software/
unzip ~/software/JBrowse-1.16.4.zip -d /opt/biosoft/
cd /opt/biosoft/JBrowse-1.16.4/

sudo ./setup.sh
echo 'PATH=$PATH:/opt/biosoft/JBrowse-1.16.4/bin/' >> ~/.bashrc
source ~/.bashrc

cp /etc/httpd/conf/httpd.conf ./
echo '
Alias /JBrowse "/opt/biosoft/JBrowse-1.16.4/"
<Directory "/opt/biosoft/JBrowse-1.16.4/">
    Options MultiViews ExecCGI Indexes FollowSymlinks
    AllowOverride None
    Order allow,deny
    Allow from all
</Directory>' >> httpd.conf
sudo mv httpd.conf /etc/httpd/conf/httpd.conf
sudo systemctl restart httpd.service


## installing webApollo (http://gmod.org/wiki/WebApollo | https://github.com/GMOD/Apollo)
#wget https://github.com/GMOD/Apollo/archive/2.3.1.tar.gz -O ~/software/Apollo-2.3.1.tar.gz
# 安装 postgresql 数据库
sudo dnf --disablerepo=* --enablerepo=c8-media-AppStream install postgresql postgresql-devel
# 初始化 postgresql 数据库
sudo postgresql-setup initdb
# 启动 postgresql 数据库并设置开机启动 posgresql 服务
sudo systemctl start postgresql.service
sudo systemctl enable postgresql.service
# 修改 postgresql 配置文件，使用用户train具有通过密码连接数据库的权限
sudo cp /var/lib/pgsql/data/pg_hba.conf ./
sudo chown -R train:train pg_hba.conf
perl -p -i -e 'unless (m/^#/) { s/ident/trust/; s/peer/trust/; }' pg_hba.conf
sudo mv pg_hba.conf /var/lib/pgsql/data/pg_hba.conf
sudo chown -R postgres:postgres /var/lib/pgsql/data/pg_hba.conf
sudo chmod 600 /var/lib/pgsql/data/pg_hba.conf
sudo systemctl restart postgresql.service

# 安装 perl 模块
sudo cpan -i BioPerl JSON JSON::XS PerlIO::gzip Heap::Simple Heap::Simple::XS Devel::Size Hash::Merge Bio::GFF3::LowLevel::Parser  Digest::Crc32  Cache::Ref::FIFO File::Next
# 安装 Web Apollo
tar zxf ~/software/WebApollo-2014-04-03.tgz -C /opt/biosoft/
cd /opt/biosoft/WebApollo-2014-04-03/
tar zxf ~/software/apache-tomcat-7.0.57.tar.gz 
cd apache-tomcat-7.0.57/
# 修改 Tomcat 7 的报错设置
perl -p -i -e 's/(autoDeploy=.*)>/$1\n            errorReportValveClass="org.bbop.apollo.web.ErrorReportValve">/' conf/server.xml
# 修改 Tomcat 7 的内存设置，推荐设置 heap size 至少 1G， permgen size 至少 256M，基因组越大，设置越大。
perl -p -i -e 's/cygwin=false/CATALINA_OPTS="-Xms512m -Xmx1g -XX:+CMSClassUnloadingEnabled -XX:+CMSPermGenSweepingEnabled -XX:+UseConcMarkSweepGC -XX:MaxPermSize=256m"\ncygwin=false/' bin/catalina.sh
