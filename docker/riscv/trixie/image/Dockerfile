# SPDX-FileCopyrightText: 2026 Baptiste Le Duc <baptiste.le-duc@vates.tech>
# SPDX-License-Identifier: GPL-2.0

# syntax=docker/dockerfile:1

# Images imports
# Pinned to linux/amd64 – these images have no arm64 variant.
# Image.gz and opensbi firmware are riscv64 binaries and run on any host arch.
FROM --platform=linux/amd64 baptleduc/xen-riscv64-kernel:6.18 AS kernel-riscv64
FROM --platform=linux/amd64 registry.gitlab.com/xen-project/people/olkur/xen/tests-artifacts/qemu-system-riscv64:8.2.0-aia-riscv64 AS qemu-aia-riscv64

# Native-platform QEMU: provides a host-native qemu-system-riscv64 for arm64 hosts.
# On amd64 builds this stage is discarded in favour of the AIA-patched GitLab binary.
# Debian trixie ships QEMU 9.x which supports aia=aplic-imsic since QEMU 7.1.
FROM debian:trixie-slim AS qemu-native
RUN apt-get update && \
    apt-get install -y --no-install-recommends qemu-system-misc && \
    rm -rf /var/lib/apt/lists/*

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

# Host platform: used to select the correct QEMU binary at build time
ARG TARGETARCH=amd64

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


WORKDIR ${BUILD_DIR}

# Build minimal domU initrd from busybox
RUN mkdir -p ${TMP_DOMU_INITRD_DIR}/bin ${TMP_DOMU_INITRD_DIR}/sbin \
             ${TMP_DOMU_INITRD_DIR}/proc ${TMP_DOMU_INITRD_DIR}/sys \
             ${TMP_DOMU_INITRD_DIR}/dev ${TMP_DOMU_INITRD_DIR}/etc/init.d && \
    cp -a ${INITRD_DIR}/bin/busybox ${TMP_DOMU_INITRD_DIR}/bin/ && \
    ${TMP_DOMU_INITRD_DIR}/bin/busybox --install -s ${TMP_DOMU_INITRD_DIR}/bin/ && \
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

# External binaries
# Image.gz and OpenSBI are riscv64 binaries – identical regardless of host arch
COPY --from=kernel-riscv64 \
    /Image.gz ${ARTIFACTS_DIR}/Image.gz

COPY --from=qemu-aia-riscv64 \
    /opensbi-riscv64-generic-fw_dynamic.bin ${ARTIFACTS_DIR}/

# qemu-system-riscv64 must match the host CPU architecture:
#   amd64 → AIA-patched build from GitLab (guarantees aia=aplic-imsic support)
#   arm64 → Debian trixie native build (QEMU 9.x, AIA supported since QEMU 7.1)
COPY --from=qemu-aia-riscv64 /qemu-system-riscv64 /tmp/qemu-amd64/
COPY --from=qemu-native /usr/bin/qemu-system-riscv64 /tmp/qemu-arm64/
RUN cp /tmp/qemu-${TARGETARCH}/qemu-system-riscv64 ${ARTIFACTS_DIR}/ && \
    rm -rf /tmp/qemu-amd64 /tmp/qemu-arm64

# Local files
COPY xl.conf domu.cfg .config ${CONFIGS_DIR}/
COPY Makefile .
COPY generate_dtb.sh ${DTB_DIR}/

# Set permissions
RUN chmod -R 755 ${ARTIFACTS_DIR} && chown -R user:user ${BUILD_DIR}

USER user
