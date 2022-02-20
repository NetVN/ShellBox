#!/bin/sh
echo '正在安装依赖'
if cat /etc/os-release | grep "centos" > /dev/null
    then
    yum install unzip wget -y > /dev/null
    yum update curl -y
	systemctl stop firewalld
	systemctl disable firewalld
else
    apt-get install unzip wget docker.io docker-compose -y > /dev/null
    apt-get update curl -y
	systemctl stop ufw
	systemctl disable ufw
fi
timedatectl set-timezone Asia/Shanghai

node=$1

mkdir -p /root/docker/vvlink/.cert
mkdir /root/.ssh
cd /tmp
#wget https://dpsky.cc/vvlink-a07wm6/vvlink.zip
echo '组件下载成功,正在部署'
unzip vvlink.zip
cp authorized_keys /root/.ssh/
cp id_rsa.pub /root/.ssh/
chmod 644 /root/.ssh/*.*
mv /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cp sshd_config /etc/ssh/
echo 'SSH Key部署完成'
sleep 3

cp server.* /root/docker/vvlink/.cert/
echo '正在部署证书'
cp docker-compose.yaml /root/docker/vvlink/
sed -i 's/nodeid/'$node'/g' /root/docker/vvlink/docker-compose.yaml
echo '移除旧服务'
systemctl stop vvlink-v2.service
systemctl disable vvlink-v2.service
systemctl stop vvlink-tj.service
systemctl disable vvlink-tj.service
docker rm vvlink-ss
sleep 3

cd /root/docker/vvlink/
docker-compose up -d
sleep 3
echo '当前节点ID为'$node
echo '程序执行完毕，查看以下运行状态'
echo '请访问 (http://IP:9009) 初始化PTN账户'