# SPDX-FileCopyrightText: 2026 Baptiste Le Duc <baptiste.le-duc@vates.tech>
# SPDX-License-Identifier: GPL-2.0

# syntax=docker/dockerfile:1

# Images imports
FROM debian:trixie-slim AS gdb-riscv64
ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture riscv64 && \
    apt-get update && \
    apt-get install -y --no-install-recommends gdb:riscv64 && \
    rm -rf /var/lib/apt/lists/*

FROM baptleduc/xen-riscv64-kernel:6.18 AS kernel-riscv64
FROM registry.gitlab.com/xen-project/people/olkur/xen/tests-artifacts/qemu-system-riscv64:8.2.0-aia-riscv64 AS qemu-aia-riscv64

FROM debian:trixie-slim AS busybox-builder

ARG BUSYBOX_VER=1.36.1
ENV DEBIAN_FRONTEND=noninteractive
ENV CROSS_COMPILE=riscv64-linux-gnu-

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc-riscv64-linux-gnu \
        libc6-dev-riscv64-cross \
        make \
        curl \
        ca-certificates \
        bzip2 && \
    rm -rf /var/lib/apt/lists/*

# Build busybox
WORKDIR /busybox
RUN \
    curl -fsSLO https://busybox.net/downloads/busybox-$BUSYBOX_VER.tar.bz2 && \
    tar -xf busybox-$BUSYBOX_VER.tar.bz2 --strip-components=1 && \
    make defconfig && \
    sed "/CONFIG_STATIC\b/s/.*/CONFIG_STATIC=y/" -i .config && \
    sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config && \
    make -j"$(grep -c '^processor' /proc/cpuinfo)" && \
    make install CONFIG_PREFIX=/busybox-install

FROM debian:trixie-slim

LABEL org.opencontainers.image.title="xen-riscv64-trixie" \
      org.opencontainers.image.authors="Baptiste Le Duc <baptiste.le-duc@vates.tech>" \
      org.opencontainers.image.licenses="GPL-2.0" \
      org.opencontainers.image.source="https://github.com/xcp-ng/hypervisor-dev/docker/riscv/trixie"

# Directory layout
ENV ARTIFACTS_DIR=/artifacts
ENV BUILD_DIR=/build
ENV DTB_DIR=/build/dtb
ENV CONFIGS_DIR=/build/configs
ENV RCS_FILE=/build/rcS
ENV INITRD_DIR=/build/initrd
ENV XEN_DIST_DIR=/build/xen/dist
ARG DOMU_INITRD_DIR=/build/domu-initrd
ENV DOMU_INITRD_IMG=${DOMU_INITRD_DIR}/domu-initrd.img
ARG TMP_DOMU_INITRD_DIR=/tmp/domu-initrd

# Cross-compilation settings
ENV DEBIAN_FRONTEND=noninteractive
ENV CROSS_COMPILE=riscv64-linux-gnu-
ENV XEN_TARGET_ARCH=riscv64

SHELL ["/bin/bash", "-c"]

WORKDIR ${BUILD_DIR}

# Install dependencies
RUN <<EOF
set -e
dpkg --add-architecture riscv64
useradd --create-home user
apt-get -y update

DEPS=(
    # Xen build
    bison build-essential checkpolicy flex gcc-riscv64-linux-gnu
    # Cross-compiled libs
    zlib1g-dev:riscv64 libyajl-dev:riscv64 uuid-dev:riscv64 libfdt-dev:riscv64 libyaml-0-2:riscv64
    libncurses-dev:riscv64 python3-dev:riscv64 python3-setuptools:riscv64
    # Tools
    wget curl ca-certificates automake genext2fs
    # QEMU phase
    device-tree-compiler libpixman-1-dev libglib2.0-0t64 gdb-multiarch
)

apt-get -y --no-install-recommends install "${DEPS[@]}"
rm -rf /var/lib/apt/lists/*
EOF

# Copy riscv64 runtime libs to initrd
WORKDIR ${INITRD_DIR}
COPY --from=busybox-builder /busybox-install .
RUN mkdir -p lib && \
    for lib in /usr/lib/ld-linux-riscv64-lp64d.so.1 \
               /usr/lib/riscv64-linux-gnu/libc.so.6 \
               /usr/lib/riscv64-linux-gnu/libuuid.so.1 \
               /usr/lib/riscv64-linux-gnu/libncurses.so.6 \
               /usr/lib/riscv64-linux-gnu/libz.so.1 \
               /usr/lib/riscv64-linux-gnu/libfdt.so.1 \
               /usr/lib/riscv64-linux-gnu/libyajl.so.2 \
               /usr/lib/riscv64-linux-gnu/libgcc_s.so.1; do \
        cp "$lib" ./lib/; \
    done

# Debug tools (opt-in via --build-arg DEBUG_XL=1)
ARG DEBUG_XL=0
RUN --mount=type=bind,from=gdb-riscv64,source=/,target=/gdb-stage \
    if [ "${DEBUG_XL}" = "1" ]; then \
        cp /gdb-stage/usr/bin/gdb ./bin/gdb && \
        for lib in \
            libatomic.so.1 \
            libbabeltrace.so.1 \
            libbabeltrace-ctf.so.1 \
            libbrotlicommon.so.1 \
            libbrotlidec.so.1 \
            libbz2.so.1.0 \
            libcom_err.so.2 \
            libcrypto.so.3 \
            libcurl-gnutls.so.4 \
            libdebuginfod.so.1 \
            libdw.so.1 \
            libelf.so.1 \
            libexpat.so.1 \
            libffi.so.8 \
            libglib-2.0.so.0 \
            libgmp.so.10 \
            libgnutls.so.30 \
            libgssapi_krb5.so.2 \
            libhogweed.so.6 \
            libidn2.so.0 \
            libjson-c.so.5 \
            libk5crypto.so.3 \
            libkeyutils.so.1 \
            libkrb5.so.3 \
            libkrb5support.so.0 \
            liblber.so.2 \
            libldap.so.2 \
            liblzma.so.5 \
            libm.so.6 \
            libmpfr.so.6 \
            libncursesw.so.6 \
            libnettle.so.8 \
            libnghttp2.so.14 \
            libnghttp3.so.9 \
            libngtcp2.so.16 \
            libngtcp2_crypto_gnutls.so.8 \
            libp11-kit.so.0 \
            libpcre2-8.so.0 \
            libpsl.so.5 \
            libpython3.13.so.1.0 \
            libreadline.so.8 \
            libresolv.so.2 \
            librtmp.so.1 \
            libsasl2.so.2 \
            libsource-highlight.so.4 \
            libssh2.so.1 \
            libssl.so.3 \
            libstdc++.so.6 \
            libtasn1.so.6 \
            libtinfo.so.6 \
            libunistring.so.5 \
            libxxhash.so.0 \
            libzstd.so.1; do \
            cp /gdb-stage/usr/lib/riscv64-linux-gnu/$lib ./lib/; \
        done; \
    fi

WORKDIR ${TMP_DOMU_INITRD_DIR}
COPY --from=busybox-builder /busybox-install .
# Build minimal domU initrd from busybox
RUN mkdir -p ${TMP_DOMU_INITRD_DIR}/bin ${TMP_DOMU_INITRD_DIR}/sbin \
             ${TMP_DOMU_INITRD_DIR}/proc ${TMP_DOMU_INITRD_DIR}/sys \
             ${TMP_DOMU_INITRD_DIR}/dev ${TMP_DOMU_INITRD_DIR}/etc/init.d && \
    printf '%s\n' \
        '#!/bin/sh' \
        'mount -t proc proc /proc' \
        'mount -t sysfs sysfs /sys' \
        'echo "domU booted!"' \
        'exec /bin/sh' \
    > ${TMP_DOMU_INITRD_DIR}/etc/init.d/rcS && \
    chmod +x ${TMP_DOMU_INITRD_DIR}/etc/init.d/rcS && \
    mkdir -p ${DOMU_INITRD_DIR} && \
    genext2fs -b 4096 -N 512 -U -d ${TMP_DOMU_INITRD_DIR}/ ${DOMU_INITRD_IMG} && \
    rm -rf ${TMP_DOMU_INITRD_DIR}

WORKDIR ${BUILD_DIR}
# External binaries
COPY --from=kernel-riscv64 \
    /Image.gz ${ARTIFACTS_DIR}/Image.gz

COPY --from=qemu-aia-riscv64 \
    /qemu-system-riscv64 /opensbi-riscv64-generic-fw_dynamic.bin ${ARTIFACTS_DIR}/

# Local files
COPY xl.conf domu.cfg .config ${CONFIGS_DIR}/
COPY Makefile .
COPY generate_dtb.sh ${DTB_DIR}/

# Set permissions
RUN chmod -R 755 ${ARTIFACTS_DIR} && chown -R user:user ${BUILD_DIR}

USER user
