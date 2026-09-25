#!/bin/bash

# 使用 yum 安装软件
yum install screen lftp

# 安装本地源
mkdir -p /media/CentOS/Packages
mount -o loop /home/train/software/CentOS-6.8-x86_64-bin-DVD1.iso /mnt/
cp /mnt/Packages/*.rpm /media/CentOS/Packages/
cp /mnt/repodata/ /media/CentOS/ -r
umount /mnt/
mount -o loop /home/train/software/CentOS-6.8-x86_64-bin-DVD2.iso /mnt/
cp /mnt/Packages/*.rpm /media/CentOS/Packages/
umount /mnt/
# 使用本地源安装软件
yum --disablerepo=\* --enablerepo=c6-media install gd*
echo "alias yumlocal='yum --disablerepo=* --enablerepo=c6-media'" >> ~/.bashrc
source ~/.bashrc
yumlocal -y install gcc* ftp openmpi* mpi* cmake gsl*

# 备份原来的yum源，变更为163的yum源
mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
wget http://mirrors.163.com/.help/CentOS6-Base-163.repo -O /etc/yum.repos.d/CentOS-Base.repo
yum clean all
yum makecache

# 增加 RPMforge 源
rpm -ivh /home/train/software/rpmforge-release-0.5.3-1.el6.rf.x86_64.rpm
yum clean all
yum makecache
yum -y install mplayer
yum -y install sshfs autossh screen 

# 安装软件ntfs-3g，用于挂载NTFS格式磁盘
cd 
tar zxf /home/train/software/ntfs-3g_ntfsprogs-2015.3.14.tgz
cd ntfs-3g_ntfsprogs-2015.3.14
./configure && make -j 4 && make install
cd
rm ntfs-3g_ntfsprogs-2015.3.14 -rf

# 安装Adobe Flasy Player
rpm -ivh http://linuxdownload.adobe.com/adobe-release/adobe-release-x86_64-1.0-1.noarch.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-adobe-linux
yum install firefox.x86_64 flash-plugin nspluginwrapper alsa-plugins-pulseaudio libcurl

# 准备/opt/biosoft目录，用于生物信息学软件的安装
# 准备/opt/sysoft目录，用于系统软件的安装
mkdir /opt/biosoft/
mkdir /opt/sysoft/
chmod 1777 /opt/biosoft/ /opt/sysoft/
