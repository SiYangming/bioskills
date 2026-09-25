#!/bin/bash
# ============================================================
# 系统配置文件修改脚本 - CentOS 6 版本
# 使用 /etc/init.d/ 和 iptables
# ============================================================
# ALL the commond lines below should be excuted in root mode.

# 修改/etc/sudoers配置文件，将train用户变成超级管理员用户
perl -p -i -e 's/^(root(.*))/$1\ntrain$2/' /etc/sudoers

# 修改/etc/selinux/config配置文件，永久关闭linux的一个安全机制，开启该安全机制会对很多操作造成阻碍。
perl -p -i -e 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
setenforce 0

# 开放防火墙端口并使之永久生效 (CentOS 6 使用 iptables)
perl -p -i -e 's/((.*) 22 (.*))/$1\n$2 80 $3\n$2 3306 $3/' /etc/sysconfig/iptables
/etc/init.d/iptables restart

# 启动httpd和mysqld服务 (CentOS 6 使用 /etc/init.d/)
/etc/init.d/httpd start
/etc/init.d/mysqld start
#设置服务开机启动
chkconfig httpd on
chkconfig mysqld on
chkconfig --list httpd
chkconfig --list mysqld

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
/etc/init.d/sshd restart

# 无密码openssh登录
#ssh-keygen -t dsa -P '' -f ~/.ssh/id_dsa
#ssh-copy-id -i ~/.ssh/id_dsa.pub train@<SERVER_IP>
#ssh train@<SERVER_IP>

# 修改用户对系统资源的最大权限
cat <<EOF >> /etc/security/limits.conf
*       soft    nproc   10240
*       hard    nproc   102400
*       soft    nofile  10240
*       hard    nofile  102400
*       soft    stack   10240
*       hard    stack   102400
EOF

# 修改train用户的一些配置
cd /home/train/
echo "
PS1='\[\e[1;35;1m\][\u@\h \W]\\$ \[\e[00m\]'
alias lh='ls -lh'
alias les='less -S'
alias del='gvfs-trash'" >> /home/train/.bashrc
echo "
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:\$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64:\$LD_LIBRARY_PATH
export C_INCLUDE_PATH=/usr/local/include/:\$C_INCLUDE_PATH" >> /home/train/.bash_profile
# 清理用户默认文件夹
rm Desktop Downloads Templates Public Documents Music Pictures Videos
perl -p -i -e 's/^[^#].*//s' ~/.config/user-dirs.dirs
echo '
XDG_DESKTOP_DIR="$HOME/desktop"
XDG_DOWNLOAD_DIR="$HOME/downloads"
XDG_TEMPLATES_DIR="$HOME/ "
XDG_PUBLICSHARE_DIR="$HOME/c"
XDG_DOCUMENTS_DIR="$HOME/ "
XDG_MUSIC_DIR="$HOME/ "
XDG_PICTURES_DIR="$HOME/ "
XDG_VIDEOS_DIR="$HOME/ "' >> ~/.config/user-dirs.dirs

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
/etc/init.d/httpd restart

# 搭建Mysql服务器 (CentOS 6 使用 mysqld)
yum -y install mysql mysql-devel mysql-server
cp -rf /usr/share/mysql/my-large.cnf /etc/my.cnf
perl -p -i -e 's/(\[mysqld\])/$1\ndatadir         = \/home\/mysql/' /etc/my.cnf
/etc/init.d/mysqld start
