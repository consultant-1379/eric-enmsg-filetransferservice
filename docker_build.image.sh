#!/bin/bash

current_folder_name=$(basename "$PWD")
build_context=.
image_name=${current_folder_name}

export ISO_VERSION=0.0.0
export docker_image_path=armdocker.rnd.ericsson.se/proj_oss/${image_name}
export image_version=$(cat VERSION_PREFIX)-development
docker rmi ${docker_image_path}:${image_version}
docker build --force-rm -f ${build_context}/Dockerfile --tag ${docker_image_path}:${image_version} ${build_context}
docker push ${docker_image_path}:${image_version}
