FROM alpine:3.6

RUN echo "#aliyun" > /etc/apk/repositories
RUN echo "https://mirrors.aliyun.com/alpine/v3.6/main/" >> /etc/apk/repositories
RUN echo "https://mirrors.aliyun.com/alpine/v3.6/community/" >> /etc/apk/repositories

ENV TIME_ZONE Asiz/Shanghai

RUN set -ex; \
   apk update && apk add --no-cache --virtual .build-deps \
        coreutils \
                gcc \
                linux-headers \
                make \
                musl-dev \
                tzdata \
                tree \
                curl \
                jq \
                ; \
                \
                cp -r -f /usr/share/zoneinfo/Hongkong /etc/localtime ; \
                mkdir -p /usr/src/redis


COPY redis-unstable.tar.gz /

RUN set -ex; \
    cd /; \
    tar -zxvf redis-unstable.tar.gz -C /usr/src/redis --strip-components=1; \
    rm -rf redis-unstable.tar.gz; \
    make -C /usr/src/redis -j "$(nproc)"; \
    make -C /usr/src/redis install;  \
    rm -rf /usr/src/redis; \
    apk del .build-deps

ENTRYPOINT [ "bash", "-c" ]
