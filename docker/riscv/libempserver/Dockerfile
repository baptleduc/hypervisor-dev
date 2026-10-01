# SPDX-FileCopyrightText: 2026 Baptiste Le Duc <baptiste.le-duc@vates.tech>
# SPDX-License-Identifier: GPL-2.0

# syntax=docker/dockerfile:1

# Cross-build libempserver (needed by XCP-ng's xenguest) for riscv64.
#
# The final stage only holds the installed files, laid out for a Debian
# multiarch sysroot:
#   /usr/include/{emp.h,libempserver.h}
#   /usr/lib/riscv64-linux-gnu/libempserver.{a,so,so.1,so.1.1}
#
# Extract them:   docker build --output type=local,dest=out .
# Or reuse them:  COPY --from=baptleduc/libempserver-riscv64 /usr/ /usr/

FROM debian:trixie-slim AS build

ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture riscv64 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc-riscv64-linux-gnu libc6-dev-riscv64-cross \
        libjson-c-dev:riscv64 \
        make pkgconf curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Tarball lives in git-lfs in xcp-ng-rpms/libempserver; sha256 from its LFS pointer.
ARG LIBEMPSERVER_VER=1.1.1
ARG LIBEMPSERVER_SHA256=992d7996051d53769ffb1cd4fe1191376e58622063eff30a870c7c754a305e43
WORKDIR /src
RUN curl -fsSLo src.tar.gz \
        https://media.githubusercontent.com/media/xcp-ng-rpms/libempserver/master/SOURCES/libempserver-${LIBEMPSERVER_VER}.tar.gz && \
    echo "${LIBEMPSERVER_SHA256}  src.tar.gz" | sha256sum -c - && \
    tar xzf src.tar.gz --strip-components=1

# Upstream Makefile hardcodes `ar` and `pkg-config`: point them at the
# riscv64 tools/sysroot.
RUN ln -s /usr/bin/riscv64-linux-gnu-ar /usr/local/bin/ar && \
    PKG_CONFIG_LIBDIR=/usr/lib/riscv64-linux-gnu/pkgconfig \
        make CC=riscv64-linux-gnu-gcc && \
    make install DESTDIR=/out \
        includedir=/usr/include libdir=/usr/lib/riscv64-linux-gnu && \
    riscv64-linux-gnu-nm -D --defined-only /out/usr/lib/riscv64-linux-gnu/libempserver.so.1.1 \
        | grep -q ' emp_send_return$'

FROM scratch
COPY --from=build /out/ /
