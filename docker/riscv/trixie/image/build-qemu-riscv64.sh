#!/usr/bin/env bash
# From xen-project/hardware/test-artifacts scripts/build-qemu-riscv64.sh,
# without the extra-serials patch. Builds with user networking when
# libslirp-dev is installed.

if test -z "${QEMU_VERSION}"
then
    >&2 echo "QEMU_VERSION must be set"; exit 1
fi

set -ex -o pipefail

WORKDIR="${PWD}"
COPYDIR="${WORKDIR}/binaries"

curl -fsSLO https://download.qemu.org/qemu-"${QEMU_VERSION}".tar.xz
tar xf qemu-"${QEMU_VERSION}".tar.xz
cd qemu-"${QEMU_VERSION}"

./configure                        \
    --target-list=riscv64-softmmu  \
    --enable-system                \
    --disable-bochs                \
    --disable-bsd-user             \
    --disable-cloop                \
    --disable-containers           \
    --disable-debug-info           \
    --disable-dmg                  \
    --disable-glusterfs            \
    --disable-gtk                  \
    --disable-guest-agent          \
    --disable-libssh               \
    --disable-linux-user           \
    --disable-live-block-migration \
    --disable-opengl               \
    --disable-parallels            \
    --disable-qcow1                \
    --disable-qed                  \
    --disable-qom-cast-debug       \
    --disable-replication          \
    --disable-safe-stack           \
    --disable-sdl                  \
    --disable-spice                \
    --disable-stack-protector      \
    --disable-tools                \
    --disable-tpm                  \
    --disable-vdi                  \
    --disable-vhost-kernel         \
    --disable-vhost-net            \
    --disable-vhost-user           \
    --disable-vhost-vdpa           \
    --disable-virglrenderer        \
    --disable-virtfs               \
    --disable-vnc                  \
    --disable-vvfat                \
    --disable-werror               \
    --disable-xen

make -j"$(nproc)"

cp build/qemu-system-riscv64 "${COPYDIR}"
cp pc-bios/opensbi-riscv64-generic-fw_dynamic.bin "${COPYDIR}"
