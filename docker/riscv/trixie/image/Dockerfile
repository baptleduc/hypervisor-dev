# SPDX-FileCopyrightText: 2026 Baptiste Le Duc <baptiste.le-duc@vates.tech>
# SPDX-License-Identifier: GPL-2.0

# syntax=docker/dockerfile:1

# Images imports
ARG KERNEL_IMAGE_TAG=latest
ARG LIBEMPSERVER_IMAGE_TAG=1.1.1
FROM baptleduc/xen-riscv64-kernel:${KERNEL_IMAGE_TAG} AS kernel-riscv64

# QEMU for the platform + libslirp for user networking (for dom0's NIC)
FROM debian:trixie-slim AS qemu-aia-riscv64
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get -y --no-install-recommends install \
        build-essential ca-certificates curl xz-utils \
        libglib2.0-dev libpixman-1-dev libslirp-dev ninja-build pkg-config \
        python3 python3-venv && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY build-qemu-riscv64.sh .
RUN mkdir binaries && QEMU_VERSION=9.0.0 ./build-qemu-riscv64.sh

# Built from docker/riscv/libempserver, needed by XCP-ng's xenguest
FROM baptleduc/libempserver-riscv64:${LIBEMPSERVER_IMAGE_TAG} AS libempserver-riscv64

FROM debian:trixie-slim AS dtc-riscv64
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc-riscv64-linux-gnu libc6-dev-riscv64-cross \
        make bison flex pkg-config curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*
ARG DTC_VER=1.7.0
RUN curl -fsSL https://github.com/dgibson/dtc/archive/refs/tags/v${DTC_VER}.tar.gz \
        | tar xz && \
    cd dtc-${DTC_VER} && \
    make NO_PYTHON=1 NO_YAML=1 \
         CC=riscv64-linux-gnu-gcc \
         PREFIX=/dtc-install install-bin && \
    riscv64-linux-gnu-strip /dtc-install/bin/dtc

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

# Debug tools (opt-in via --build-arg DEBUG_XL=1)
ARG DEBUG_XL=0

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
    # OCaml toolstack bindings (ocaml:riscv64 itself is extracted below)
    ocaml-interp:riscv64 ocaml-base:riscv64 libzstd-dev:riscv64 ocaml-findlib:riscv64
    libjson-c-dev:riscv64 acpica-tools
    # xapi runtime libs, shipped in the initrd
    libxxhash0:riscv64 libpci3:riscv64 libpam0g:riscv64 libcrypt1:riscv64
    libgmp10:riscv64 libudev1:riscv64 libaudit1:riscv64 libcap2:riscv64
    libcap-ng0:riscv64
    # stunnel, xapi's TLS front end on port 443, and openssl, which gencert
    # runs to make its key
    libssl3t64:riscv64 libsystemd0:riscv64 libwrap0:riscv64
    # pam_unix, for xapi's root password check
    libselinux1:riscv64 libpcre2-8-0:riscv64
    # xcp-networkd dlopen()s these, so they are not in its NEEDED list
    libnl-3-200:riscv64 libnl-route-3-200:riscv64 libffi8:riscv64
    # Tools
    wget curl ca-certificates automake genext2fs
    # QEMU phase
    device-tree-compiler libpixman-1-dev libglib2.0-0t64 libslirp0 gdb-multiarch
)

apt-get -y --no-install-recommends install "${DEPS[@]}"

# ocaml:riscv64 depends on gcc:riscv64 and binutils:riscv64, which conflict
# with the amd64 build-essential. Its ocamlopt only calls the
# riscv64-linux-gnu-{gcc,as} cross tools installed above, so extract the
# package without registering it in dpkg.
cd /tmp
apt-get download ocaml:riscv64
dpkg-deb -x ocaml_*_riscv64.deb /
rm ocaml_*_riscv64.deb
# Same for stunnel4:riscv64 and openssl:riscv64, which would replace their
# amd64 counterparts: only their binaries go in the initrd
apt-get download stunnel4:riscv64 openssl:riscv64
dpkg-deb -x stunnel4_*_riscv64.deb /tmp/riscv64
dpkg-deb -x openssl_*_riscv64.deb /tmp/riscv64
install -D /tmp/riscv64/usr/bin/stunnel4 /opt/riscv64/stunnel
install -D /tmp/riscv64/usr/bin/openssl /opt/riscv64/openssl
# pam_unix checks the password through its unix_chkpwd helper, even as root
apt-get download libpam-modules:riscv64 libpam-modules-bin:riscv64
dpkg-deb -x libpam-modules_*_riscv64.deb /tmp/riscv64
dpkg-deb -x libpam-modules-bin_*_riscv64.deb /tmp/riscv64
install -D /tmp/riscv64/usr/lib/riscv64-linux-gnu/security/pam_unix.so /opt/riscv64/pam_unix.so
install -D /tmp/riscv64/usr/sbin/unix_chkpwd /opt/riscv64/unix_chkpwd
rm -rf stunnel4_*_riscv64.deb openssl_*_riscv64.deb libpam-modules*_riscv64.deb /tmp/riscv64
cd -

rm -rf /var/lib/apt/lists/*
EOF

# riscv64 libempserver headers and libs, for building xenguest
COPY --from=libempserver-riscv64 /usr/ /usr/

# Copy riscv64 runtime libs to initrd
WORKDIR ${INITRD_DIR}
COPY --from=busybox-builder /busybox-install .
RUN mkdir -p lib && \
    for lib in /usr/lib/ld-linux-riscv64-lp64d.so.1 \
               /usr/lib/riscv64-linux-gnu/libc.so.6 \
               /usr/lib/riscv64-linux-gnu/libm.so.6 \
               /usr/lib/riscv64-linux-gnu/libzstd.so.1 \
               /usr/lib/riscv64-linux-gnu/libuuid.so.1 \
               /usr/lib/riscv64-linux-gnu/libncurses.so.6 \
               /usr/lib/riscv64-linux-gnu/libz.so.1 \
               /usr/lib/riscv64-linux-gnu/libfdt.so.1 \
               /usr/lib/riscv64-linux-gnu/libyajl.so.2 \
               /usr/lib/riscv64-linux-gnu/libjson-c.so.5 \
               /usr/lib/riscv64-linux-gnu/libempserver.so.1 \
               /usr/lib/riscv64-linux-gnu/libgcc_s.so.1 \
               /usr/lib/riscv64-linux-gnu/libxxhash.so.0 \
               /usr/lib/riscv64-linux-gnu/libpci.so.3 \
               /usr/lib/riscv64-linux-gnu/libpam.so.0 \
               /usr/lib/riscv64-linux-gnu/libcrypt.so.1 \
               /usr/lib/riscv64-linux-gnu/libgmp.so.10 \
               /usr/lib/riscv64-linux-gnu/libudev.so.1 \
               /usr/lib/riscv64-linux-gnu/libaudit.so.1 \
               /usr/lib/riscv64-linux-gnu/libcap.so.2 \
               /usr/lib/riscv64-linux-gnu/libcap-ng.so.0 \
               /usr/lib/riscv64-linux-gnu/libnl-3.so.200 \
               /usr/lib/riscv64-linux-gnu/libnl-route-3.so.200 \
               /usr/lib/riscv64-linux-gnu/libffi.so.8 \
               /usr/lib/riscv64-linux-gnu/libssl.so.3 \
               /usr/lib/riscv64-linux-gnu/libcrypto.so.3 \
               /usr/lib/riscv64-linux-gnu/libsystemd.so.0 \
               /usr/lib/riscv64-linux-gnu/libwrap.so.0 \
               /usr/lib/riscv64-linux-gnu/libselinux.so.1 \
               /usr/lib/riscv64-linux-gnu/libpcre2-8.so.0; do \
        cp "$lib" ./lib/; \
    done && \
    install -D /opt/riscv64/stunnel ./usr/bin/stunnel && \
    install -D /opt/riscv64/openssl ./usr/bin/openssl && \
    install -D /opt/riscv64/pam_unix.so ./lib/security/pam_unix.so && \
    install -D /opt/riscv64/unix_chkpwd ./usr/sbin/unix_chkpwd

RUN --mount=type=bind,from=dtc-riscv64,source=/dtc-install,target=/dtc-stage \
    if [ "${DEBUG_XL}" = "1" ]; then \
        cp /dtc-stage/bin/dtc ./bin/dtc; \
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
    /build/binaries/qemu-system-riscv64 \
    /build/binaries/opensbi-riscv64-generic-fw_dynamic.bin ${ARTIFACTS_DIR}/

# Local files
COPY xl.conf domu.cfg .config \
     xenopsd-xc.conf xenopsd-stub riscv.cfg xapi.conf squeezed.conf v6d.conf \
     xcp-networkd.conf gen-xensource-inventory xe-vm-from-cfg systemctl \
     pam.d-xapi passwd \
     ${CONFIGS_DIR}/
# dom0 root password, checked by xapi (xe -pw, Xen Orchestra) through PAM
ARG ROOT_PASSWORD=vates123
RUN printf 'root:%s:19000:0:99999:7:::\n' "$(openssl passwd -6 "$ROOT_PASSWORD")" \
        > ${CONFIGS_DIR}/shadow
COPY Makefile .
COPY generate_dtb.sh ${DTB_DIR}/

# Set permissions
RUN chmod -R 755 ${ARTIFACTS_DIR} && chown -R user:user ${BUILD_DIR}

USER user
