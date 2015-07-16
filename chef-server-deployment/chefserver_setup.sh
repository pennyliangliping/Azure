#!/bin/bash
# setup chef server and chef workstation

if [ ! -e /home/auto ]; then
    mkdir /home/auto
fi
mkdir /home/auto/test
# change the FQDN for the ubuntu server before installing chef server

