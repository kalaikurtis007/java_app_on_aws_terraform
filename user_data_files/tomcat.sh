#!/bin/bash
sudo apt update
sudo apt upgrade -y
sudo apt install openjdk-11-jdk -y
sudo apt install tomcat9 tomcat9-admin tomcat9-docs tomcat9-common git -y
sudo apt install nodejs npm -y
sudo git clone https://github.com/kalaikurtis007/node_crud_for_terraform.git
sudo cd node_crud_for_terraform
sudo npm i
sudo npm run start