#!/bin/bash -e
# yuzu-room dependency builder -- MODERNIZED COPY, authoritative.
#
# This file is the source of truth for dependency versions. The Dockerfile
# copies it over the one in the vendored tree (src/yuzu/room/.ci/deps.sh),
# so the vendored checkout stays disposable: re-vendor or delete src/ freely
# and these versions survive.
#
# Why these versions (2026-09-12):
#   Alpine 3.24 ships CMake 4.x, which removed support for
#   cmake_minimum_required(VERSION <3.5). zstd 1.5.5 and lz4 1.9.4 declare
#   exactly that and CANNOT configure on a modern base image. The bumps are
#   required, not cosmetic.
#
#   fmt is deliberately held at 10.2.1: fmt 11+ requires custom
#   fmt::formatter::format() to be const, which breaks 4 specializations in
#   yuzu's src/common, and drops transitive <cstring> includes needed by
#   dynamic_library.cpp and host_memory.cpp. Bumping it needs a source patch.
#
#   boost's release assets changed shape after 1.84: there is no plain
#   boost-<ver>.tar.xz any more, only -b2-nodocs and -cmake variants. This
#   uses -b2-nodocs because the build below uses bootstrap.sh/b2.
#
# All sha256sums were computed from the downloaded tarballs, not transcribed.

FMT_VERSION="10.2.1"
JSON_VERSION="3.12.0"
ZLIB_VERSION="1.3.2"
ZSTD_VERSION="1.5.7"
LZ4_VERSION="1.10.0"
BOOST_VERSION="1.92.0"

cmake_install() {
    cmake . -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON "$@"
    ninja install
}

# $1: url $2: dir name $3: sha256sum
download_extract() {
    local filename
    filename="$(basename "$1")"
    wget "$1" -O "$filename"
    echo "$3 $filename" > "$filename".sha256sum
    sha256sum -c "$filename".sha256sum
    bsdtar xf "$filename"
    pushd "$2"
}

info() {
    echo -e "\e[1m--> Downloading and building $1...\e[0m"
}

info "fmt ${FMT_VERSION}"
download_extract "https://github.com/fmtlib/fmt/releases/download/${FMT_VERSION}/fmt-${FMT_VERSION}.zip" "fmt-${FMT_VERSION}" 312151a2d13c8327f5c9c586ac6cf7cddc1658e8f53edae0ec56509c8fa516c9
cmake_install -DFMT_DOC=OFF -DFMT_TEST=OFF
popd

info "nlohmann_json ${JSON_VERSION}"
download_extract "https://github.com/nlohmann/json/releases/download/v${JSON_VERSION}/json.tar.xz" json 42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa
cmake_install -DJSON_BuildTests=OFF
popd

info "zlib ${ZLIB_VERSION}"
download_extract "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.xz" "zlib-${ZLIB_VERSION}" d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3
cmake_install -DCMAKE_POLICY_DEFAULT_CMP0069=NEW
# delete shared libraies as we can't use them in the final image
rm -v /usr/local/lib/libz.so*
popd

info "zstd ${ZSTD_VERSION}"
download_extract "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz" "zstd-${ZSTD_VERSION}"/build/cmake eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
cmake_install -DZSTD_BUILD_PROGRAMS=OFF -DBUILD_TESTING=OFF -GNinja -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=OFF
popd

info "lz4 ${LZ4_VERSION}"
download_extract "https://github.com/lz4/lz4/archive/refs/tags/v${LZ4_VERSION}.tar.gz" "lz4-${LZ4_VERSION}/build/cmake" 537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b
cmake_install -DLZ4_BUILD_CLI=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF -DLZ4_BUILD_LEGACY_LZ4C=OFF
# we need to adjust the exported name of the static library
cat << EOF >> /usr/local/lib/cmake/lz4/lz4Targets.cmake
# Injected commands by yuzu-room builder script
add_library(lz4::lz4 ALIAS LZ4::lz4_static)
EOF
popd

info "boost ${BOOST_VERSION}"
download_extract "https://github.com/boostorg/boost/releases/download/boost-${BOOST_VERSION}/boost-${BOOST_VERSION}-b2-nodocs.tar.xz" "boost-${BOOST_VERSION}" ea7b982002cc9dfbe59b0b217b206f470dc75f3de0bb2973d844118934d82411
# Boost use its own ad-hoc build system
# we only enable what yuzu needs
./bootstrap.sh --with-libraries=context,container,system,headers
./b2 -j "$(nproc)" install --prefix=/usr/local
popd

# fake xbyak for non-amd64 (workaround a CMakeLists bug in yuzu)
echo '!<arch>' > /usr/local/lib/libxbyak.a
