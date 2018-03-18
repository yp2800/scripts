#!/bin/bash

set -x
# 运行开关
DRY_RUN=

cd /data/docker/registry2
DATE=`date +%Y%m%d_%H%M%S`
OUTPUT_DIR=cleanup_logs/${DATE}
mkdir -p  ${OUTPUT_DIR}

ROOT_PATH=`pwd`/registry-data
ROOT_SCRIPT=`pwd`

REGISTRY_HOME="docker/registry/v2"
DIR_REPOSITORIES="repositories"
DIR_TAGS="_manifests/tags"
DIR_REVISIONS="_manifests/revisions"
DIR_BLOBS="blobs"
PATH_REGISTRY=${ROOT_PATH}/${REGISTRY_HOME}
PATH_REPOSITORIES=${PATH_REGISTRY}/${DIR_REPOSITORIES}

if [ "${DRY_RUN}" == "true" ]; then
	echo "Running in dry-run mode. Will not make any changes"
fi

image=${1}
# if no image, clean all images
if [ ! -z "${image}" ]; then
    echo ${image} > ${OUTPUT_DIR}/images2clean
else
    #ls -1 ${PATH_REPOSITORIES} > ${OUTPUT_DIR}/images2clean
    cd ${PATH_REPOSITORIES}
    find . -type d -name '_manifests' -printf '%h\n' | sed 's#\./##g'  > ${ROOT_SCRIPT}/${OUTPUT_DIR}/images2clean
    cd -
fi
for IMAGE in $(cat ${OUTPUT_DIR}/images2clean); do

    PATH_TAGS=${PATH_REPOSITORIES}/${IMAGE}/${DIR_TAGS}
    PATH_REVISIONS=${PATH_REPOSITORIES}/${IMAGE}/${DIR_REVISIONS}
    PATH_BLOBS=${PATH_REGISTRY}/${DIR_BLOBS}

    # 去掉目录 / 替换成 -
    IMAGE_REPLACE=${IMAGE//\//-}
    LOG_FILE="${OUTPUT_DIR}/${IMAGE_REPLACE}.log"
    touch ${LOG_FILE}
    echo "Cleaning ${IMAGE}" >> ${LOG_FILE}
    echo "" >> ${LOG_FILE}

    for tag in $(ls -1 ${PATH_TAGS}); do
        echo "Tag ${tag}" >> ${LOG_FILE}
        image_hash=$(cat ${PATH_TAGS}/${tag}/current/link | sed 's|sha256:||')
        echo "Current hash is ${image_hash}" >> ${LOG_FILE}
        index_hashes=$(ls -1 ${PATH_TAGS}/${tag}/index/sha256 | grep -v ${image_hash})

        # If there are more than on file in ${PATH_TAGS}/${tag}/index/sha256
        # that means there are outdated digests and they are the ones we want to delete

        if [ -z "${index_hashes}" ];then
            echo "No hash to clean"  >> ${LOG_FILE}
            echo "==============================" >> ${LOG_FILE}
            continue
        fi

        echo "-----------------------" >> ${LOG_FILE}

        nb_hash_to_delete=$(echo ${index_hashes} | wc -w)
        echo "There are ${nb_hash_to_delete} hashes to delete" >> ${LOG_FILE}

        for hash in ${index_hashes}; do
            echo "Deleting index hash ${PATH_TAGS}/${tag}/index/sha256/${hash}" >> ${LOG_FILE}
            if [ ${DRY_RUN} ]; then
		        echo "Would have run : rm -rf ${PATH_TAGS}/${tag}/index/sha256/${hash}" >> ${LOG_FILE}
            else
                rm -rf ${PATH_TAGS}/${tag}/index/sha256/${hash}
            fi
            echo "Deleting revision hash ${PATH_REVISIONS}/sha256/${hash}" >> ${LOG_FILE}
            if [ ${DRY_RUN} ]; then
                echo "Would have run : rm -rf ${PATH_REVISIONS}/sha256/${hash}" >> ${LOG_FILE}
            else
                rm -rf ${PATH_REVISIONS}/sha256/${hash}
            fi

            # Estimate blobs to delete
            uniq_digest=$(jq -r '.config.digest' "${PATH_BLOBS}/sha256/${hash:0:2}/$hash/data" | sed 's|sha256:||')
            echo ${uniq_digest} >> ${OUTPUT_DIR}/${IMAGE_REPLACE}-blob2delete
            echo "${uniq_digest} unique digest found" >> ${LOG_FILE}

            layers=$(jq -r '.layers[].digest' "${PATH_BLOBS}/sha256/${hash:0:2}/$hash/data" | sed 's|sha256:||')
            for layer in ${layers}; do
                echo ${layer} >> ${OUTPUT_DIR}/${IMAGE_REPLACE}-blob2delete
            done
            echo "${layers} layers found" >> ${LOG_FILE}

        done
        echo "==============================" >> ${LOG_FILE}
    done

    echo "" >> ${LOG_FILE}

    # Estimate freeed storage size
    sort ${OUTPUT_DIR}/${IMAGE_REPLACE}-blob2delete | uniq > ${OUTPUT_DIR}/${IMAGE_REPLACE}-blob2delete.sort

    for hash in $(cat ${OUTPUT_DIR}/${IMAGE_REPLACE}-blob2delete.sort); do
        echo "${PATH_BLOBS}/sha256/${hash:0:2}/$hash" >> ${OUTPUT_DIR}/${IMAGE_REPLACE}-path2delete
    done

    if [ -f ${OUTPUT_DIR}/${IMAGE_REPLACE}-path2delete ];then
        echo "$(cat ${OUTPUT_DIR}/${IMAGE_REPLACE}-path2delete | wc -l) blobs to delete" >> ${LOG_FILE}
        estimated_size=$(du -hc $(cat ${OUTPUT_DIR}/${IMAGE_REPLACE}-path2delete) | tail -n1 | cut -f1)
        echo "${estimated_size} estimated" >> ${LOG_FILE}
        echo "${estimated_size} ${IMAGE}" >> ${OUTPUT_DIR}/total
    else
        echo "No blobs to delete" >> ${LOG_FILE}
        continue
    fi

done

if [ ${DRY_RUN} ]; then
    echo "Would have run : docker exec -it registry-2 registry  garbage-collect /etc/docker/registry/config.yml" >> ${LOG_FILE}
else
    docker exec registry-2 registry garbage-collect /etc/docker/registry/config.yml
    cd /data/docker/registry2 && ./restart.sh
fi
