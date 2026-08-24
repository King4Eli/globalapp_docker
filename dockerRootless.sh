#!/bin/bash
##run all these in the user wanting to use rootless

# install for user
dockerd-rootless-setuptool.sh install

# Enable the user service
systemctl --user enable docker
systemctl --user start docker

echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' >> ~/.bashrc
source ~/.bashrc

# Allow it to keep running after logout:
#run as root
sudo loginctl enable-linger [username]
