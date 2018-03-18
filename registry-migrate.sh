#!/bin/bash
#镜像迁移从v1到v2

for repo in `curl -s docker.xxxxxx.com/v1/search?q= | jq -r '.results | .[] | .name'`
        do
        V1_REGISTRY=docker.xxxxxx.com
        V2_REGISTRY=dockertest.xxxxxx.com
        for tag in `curl -s $V1_REGISTRY/v1/repositories/$repo/tags | jq -r 'keys | .[]'`
        do
            source_image=$V1_REGISTRY/$repo:$tag
            destination_image=$V2_REGISTRY/$repo:$tag
            docker pull $source_image && docker tag $source_image $destination_image && docker push $destination_image && docker rmi $destination_image
            #echo $source_image, $destination_image
        done
    done
