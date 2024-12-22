#!/bin/sh

cp ../domdownload.sh install_dir 

export BUILDKIT_PROGRESS=plain

docker build --no-cache -t nashcom/dominodownload:latest .

rm install_dir/domdownload.sh

