FROM alpine:latest AS builder

COPY ./patches /tmp/patches
COPY ./src/yuzu/ /tmp/yuzu/
# Authoritative dependency versions live in the repo, not the vendored tree.
COPY ./ci/deps.sh /tmp/yuzu/room/.ci/deps.sh

WORKDIR /tmp/yuzu

RUN apk update \
    && apk upgrade --no-cache \
    && apk -U add --no-cache \
        autoconf \
        bash \
        build-base \
        binutils-gold \
        ca-certificates \
        cmake \
        git \
        glslang\
        jq \
        libarchive-tools\
        libstdc++ \
        linux-headers \
        ninja-build \
        openssl-dev \
        wget \
        xz \
        yasm \
    && export PATH=$PATH:/bin:/usr/local/bin:/usr/bin:/sbin:/usr/lib/ninja-build/bin \
    && mkdir -p /server/lib /tmp/yuzu/build /tmp/yuzu/room /tmp/yuzu/mainline \
    && cp /tmp/patches/*.patch /tmp/yuzu/room/patches 2>/dev/null \
    && cd /tmp/yuzu/mainline \
    && git apply /tmp/yuzu/room/patches/*.patch \
    && bash -e /tmp/yuzu/room/.ci/deps.sh \
    && { echo "#!/bin/ash"; \
         echo "SCRIPT_DIR=\$(dirname \"\$(readlink -f \"\$0\")\")"; \
         echo "cd \$SCRIPT_DIR"; \
         echo "LDFLAGS=\"-flto -fuse-linker-plugin -fuse-ld=gold\""; \
         echo "CFLAGS=\"-ftree-vectorize -flto\""; \
         echo "if [[ \"\$(uname -m)\" == \"aarch64\" ]]; then"; \
         echo "  CFLAGS=\"-O2\""; \
         echo "  LDFLAGS=\"\""; \
         echo "elif [[ \"\$(uname -m)\" == \"x86_64\" ]]; then"; \
         echo "  CFLAGS=\"\$CFLAGS -march=znver5 -mtune=znver5\""; \
         echo "fi"; \
         echo "export CFLAGS"; \
         echo "export CXXFLAGS=\"\$CFLAGS\""; \
         echo "export LDFLAGS"; \
         echo "cmake ../mainline -GNinja -DCMAKE_BUILD_TYPE=Release \\"; \
         echo " -DENABLE_SDL2=OFF -DENABLE_QT=OFF -DENABLE_COMPATIBILITY_LIST_DOWNLOAD=OFF \\"; \
         echo " -DUSE_DISCORD_PRESENCE=OFF -DYUZU_USE_BUNDLED_FFMPEG=ON -DYUZU_TESTS=OFF \\"; \
         echo " -DENABLE_LIBUSB=OFF \\"; \
         echo " -DCMAKE_POLICY_VERSION_MINIMUM=3.5"; \
         echo "ninja yuzu-room"; \
       } >/tmp/yuzu/build/build.sh \
    && chmod +x /tmp/yuzu/build/build.sh \
    && /tmp/yuzu/build/build.sh \
    && cp /tmp/yuzu/build/bin/yuzu-room /server/yuzu-room \
    && strip /server/yuzu-room \
    && chmod +x /server/yuzu-room \
    && cp /usr/lib/libgcc_s.so.1 /server/lib/libgcc_s.so.1 \
    && cp /usr/lib/libstdc++.so.6 /server/lib/libstdc++.so.6 \
    && echo -e "YuzuRoom-BanList-1" > /server/bannedlist.ybl \
    && touch /server/yuzu-room.log \
    && rm -R /tmp/yuzu /tmp/patches

FROM alpine:latest

ENV USERNAME=yuzu
ENV USERHOME=/home/$USERNAME
# Required
ENV YUZU_BINDADDR="0.0.0.0"
ENV YUZU_PORT=24872
ENV YUZU_ROOMNAME="yuzu Room"
ENV YUZU_PREFGAME="Any"
ENV YUZU_MAXMEMBERS=4
ENV YUZU_BANLISTFILE="bannedlist.ybl"
ENV YUZU_LOGFILE="yuzu-room.log"
# Optional
ENV YUZU_ROOMDESC=""
ENV YUZU_PREFGAMEID="0"
ENV YUZU_PASSWORD=""
ENV YUZU_ISPUBLIC=0
# Supplied at runtime (compose env_file / -e). Never bake a credential into
# an image layer: it stays readable via `docker history` and survives being
# overridden at runtime.
ENV YUZU_TOKEN=""
ENV YUZU_WEBAPIURL=""

RUN apk update \
    && apk upgrade --no-cache \
    && apk add --no-cache wget vim curl tmux \
    && adduser --disabled-password $USERNAME \
    && rm -rf /tmp/* /var/tmp/*

COPY --from=builder --chown=$USERNAME /server/ $USERHOME/
COPY --chown=$USERNAME ./container_files/ $USERHOME/

USER $USERNAME
WORKDIR $USERHOME

RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]

