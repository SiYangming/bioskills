#!/bin/bash
# ALL the commond lines below should be excuted in root mode.

# 修改/etc/sudoers配置文件，将train用户变成超级管理员用户
perl -i.bak -e 'while (<>) { if (/^root/) { print; print "train   ALL=(ALL)       NOPASSWD:ALL\n"; last; } else { print } }' /etc/sudoers
#perl -p -i -e 's/^(root(.*))/$1\ntrain$2/' /etc/sudoers

# 修改/etc/selinux/config配置文件，永久关闭linux的一个安全机制，开启该安全机制会对很多操作造成阻碍。
perl -p -i -e 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
setenforce 0

# 开放防火墙端口并使之永久生效
firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --add-port=8080/tcp --permanent
firewall-cmd --add-port=3306/tcp --permanent
# 加入--permanent参数，使永久生效。
# 重启防火墙服务
systemctl restart firewalld.service
# 重启后，再查看端口，则生效了。
firewall-cmd --list-ports

# 启动httpd和mariadb(mysqld)服务
systemctl start httpd.service
systemctl start mariadb.service
#设置服务开机启动
systemctl enable httpd.service
systemctl enable mariadb.service


# 修改/etc/ssh/sshd_config配置文件，使openssh远程登录更安全，更快速
perl -p -i -e 's/#RSAAuthentication/RSAAuthentication/' /etc/ssh/sshd_config
perl -p -i -e 's/#PubkeyAuthentication/PubkeyAuthentication/' /etc/ssh/sshd_config
perl -p -i -e 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config
perl -p -i -e 's/.*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
perl -p -i -e 's/.*Protocol\s+2.*/Protocol 2/' /etc/ssh/sshd_config
perl -p -i -e 's/.*ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config
perl -p -i -e 's/.*ClientAliveCountMax.*/ClientAliveCountMax 10/' /etc/ssh/sshd_config
perl -p -i -e 's/.*UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
perl -p -i -e 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd.service
# 无密码openssh登录
#ssh-keygen -t dsa -P '' -f ~/.ssh/id_dsa
#ssh-copy-id -i ~/.ssh/id_dsa.pub train@<SERVER_IP>
#ssh train@<SERVER_IP>

# 修改用户对系统资源的最大权限
cat <<EOF >> /etc/security/limits.conf
*	soft	nproc	10240
*	hard	nproc	102400
*	soft	nofile	10240
*	hard	nofile	102400
*	soft	stack	10240
*	hard	stack	102400
EOF

# 修改train用户的一些配置
cd /home/train/
echo "
PS1='\[\e[1;35;1m\][\u@\h \W]\\$ \[\e[00m\]'
alias lh='ls -lh'
alias les='less -S'
alias del='gvfs-trash'
alias yumlocal='yum --disablerepo=* --enablerepo=c8-media-AppStream'" >> /home/train/.bashrc
echo "
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:\$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64:\$LD_LIBRARY_PATH
export C_INCLUDE_PATH=/usr/local/include/:\$C_INCLUDE_PATH" >> /home/train/.bash_profile
# 清理用户默认文件夹
rm -rf Downloads Templates Public Documents Music Pictures Videos perl5 ~/perl5

# 搭建WWW网页服务器
# 将文件夹权限设置宽松，有利于展示其它生信软件的网页结果
perl -i -e 'while (<>) { $mo = 1 if m#<Directory />#; $mo = 0 if m#<Files \".ht\*\">#; s/Require all denied/#Require all denied/ if $mo == 1; print; }' /etc/httpd/conf/httpd.conf
# 设置展示train用户的家目录
perl -e 'print "
Alias /train \"/home/train\"
<Directory \"/home/train\">
        Options Indexes FollowSymLinks
        indexOptions FancyIndexing NameWidth=128 HTMLTable VersionSort FoldersFirst Charset=UTF-8
        AllowOverride None
        Order allow,deny
        Allow from all
        Require all granted
</Directory>"' >> /etc/httpd/conf/httpd.conf
# 修改用户和文件夹权限
usermod -aG train apache
chmod 750 /home/train/
# 使.pl .sh .py等文件的内容直接在浏览器中展示
perl -p -i -e 's/(AddType text\/html .shtml)/$1\nAddType text\/plain .pl\nAddType text\/plain .py\nAddType text\/plain .sh/' /etc/httpd/conf/httpd.conf
# 使.cgi文件能在浏览器中运行程序生成网页结果
perl -p -i -e 's/#AddHandler cgi-script .cgi/AddHandler cgi-script .cgi/' /etc/httpd/conf/httpd.conf
# 重启网页服务，使配置文件的修改生效
systemctl restart httpd.service

# 搭建Mysql服务器
dnflocal -y install mariadb mariadb-devel mariadb-server
perl -p -i -e 's#^datadir=.*#datadir=/home/.mysql#' /etc/my.cnf.d/mariadb-server.cnf
mkdir /home/.mysql
chown -R mysql:mysql /home/.mysql
systemctl restart mariadb.service
/usr/bin/mysqladmin -u root password '<MYSQL_PASSWORD>'
echo "GRANT ALL ON *.* TO 'train'@'localhost' IDENTIFIED BY '<MYSQL_PASSWORD>'; GRANT SELECT ON *.* TO 'pasa'@'localhost' IDENTIFIED BY '<MYSQL_RO_PASSWORD>'; GRANT ALL ON b2gdb.* TO 'blast2go'@'localhost' IDENTIFIED BY '<BLAST2GO_DB_PASSWORD>'; FLUSH PRIVILEGES;" | mysql -uroot -p'<MYSQL_PASSWORD>'
# the directory /home/mysql was created
#ls /home/mysql/
#/usr/bin/mysql_secure_installation
#mysql -uroot -p<MYSQL_PASSWORD>
#mysql> SHOW DATABASES;
#mysql> CREATE DATABASE b2gdb;
#mysql> DROP DATABASE b2gdb;
#mysql> GRANT ALL ON *.* TO 'train'@'%' IDENTIFIED BY '<MYSQL_PASSWORD>';
#mysql> GRANT SELECT ON *.* TO 'pasa'@'%' IDENTIFIED BY '<MYSQL_RO_PASSWORD>';
#mysql> GRANT ALL ON b2gdb.* TO 'blast2go'@'localhost' IDENTIFIED BY '<BLAST2GO_DB_PASSWORD>';
#mysql> FLUSH PRIVILEGES;
