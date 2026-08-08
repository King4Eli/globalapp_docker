#!/bin/bash

# install for user
dockerd-rootless-setuptool.sh install
# Enable the user service
systemctl --user enable docker
systemctl --user start docker
# Allow it to keep running after logout:
#run as root
sudo loginctl enable-linger [username]