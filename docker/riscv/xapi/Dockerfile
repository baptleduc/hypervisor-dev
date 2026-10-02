# SPDX-License-Identifier: GPL-2.0
#
# Native riscv64 (qemu-user) environment to build xapi, xe and xenopsd
# from xen-api.
#
# Uses Debian's OCaml as opam's system compiler: it is the same 5.3.0 that
# builds the Xen tree's OCaml bindings in xen-riscv64-trixie, so xenctrl and
# friends from that tree are link-compatible.
#
#   docker buildx build --platform linux/riscv64 -t baptleduc/xapi-riscv64 .
#   docker run --rm --platform linux/riscv64 \
#     -v $XEN_SRC:/build/xen -v $XEN_API_SRC:/build/xen-api \
#     baptleduc/xapi-riscv64 build-xapi

FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get -y --no-install-recommends install \
        ocaml ocaml-findlib libfindlib-ocaml-dev opam build-essential git ca-certificates curl \
        pkg-config m4 unzip bubblewrap \
        libgmp-dev libffi-dev libpam0g-dev libsystemd-dev libzstd-dev \
        libjson-c-dev libfdt-dev libyajl-dev uuid-dev zlib1g-dev \
        libssl-dev libev-dev libpci-dev hwdata libxxhash-dev && \
    rm -rf /var/lib/apt/lists/*

ENV OPAMROOT=/opam OPAMYES=1 OPAMJOBS=4
RUN opam init --disable-sandboxing --bare -n && \
    opam switch create default ocaml-system && \
    opam repo add xs-opam https://github.com/xapi-project/xs-opam.git --rank 2 --all-switches

# External (non xen-api, non Xen) dependencies of xapi, xe, xenopsd-xc,
# xenopsd-cli and forkexecd plus the in-tree libraries they pull in.
# ambient-context and cohttp are pinned to xs-opam's versions: newer ones
# dropped ambient-context.thread_local and changed Cohttp's IO signature.
# Same for tar, mirage-crypto and x509, whose APIs xapi tracks.
RUN opam install ocamlfind \
        dune astring base64 cmdliner fmt logs mtime re result rresult \
        rpclib ppx_deriving_rpc ppx_deriving ppx_deriving_yojson \
        ppx_sexp_conv sexplib sexplib0 uri uuidm xmlm yojson ptime \
        integers ipaddr unix-errno lwt cohttp ambient-context \
        fd-send-recv inotify polly qmp xenstore xenstore_transport \
        crc digestif ezjsonm menhir xapi-backtrace dune-build-info \
        bigarray-compat fpath magic-mime psq sha pci \
        ambient-context.0.1.0 cohttp.5.3.1 \
        tar.2.6.0 tar-unix.2.6.0 x509.1.0.6 \
        mirage-crypto.2.0.1 mirage-crypto-pk.2.0.1 mirage-crypto-rng.2.0.1

# xcp-networkd's netlink binding (libnl-3 through ctypes-foreign), pinned to
# xs-opam's version. Separate layer so the ones above stay cached.
RUN apt-get update && apt-get -y --no-install-recommends install \
        libnl-3-dev libnl-route-3-dev && \
    rm -rf /var/lib/apt/lists/* && \
    opam install netlink.0.3.4

ENV PATH=/opam/default/bin:$PATH \
    OCAMLPATH=/opam/default/lib \
    CAML_LD_LIBRARY_PATH=/opam/default/lib/stublibs

COPY build-xapi /usr/local/bin/
COPY xcp-featured-switchless.patch /usr/local/share/build-xapi/
WORKDIR /build/xen-api
