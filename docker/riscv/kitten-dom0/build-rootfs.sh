#!/bin/bash
# Build an AlmaLinux Kitten root filesystem image for the RISC-V dom0:
# a minimal Kitten (systemd, bash, python3, dnf), the dom0 payload (Xen
# tools, toolstack, our dom0 files: "make dom0-payload" in
# docker/riscv/trixie/image), the shared libraries the payload needs, and
# xcpng-riscv-dom0.service to start it all. Boot it with DOM0_DISK.
#
# Runs as root in a riscv64 AlmaLinux Kitten container, natively or under
# qemu-user, with this directory, the payload and the output mounted:
#   docker run --rm --platform linux/riscv64 -v <this dir>:/kd:ro \
#     -v <dir with dom0-payload.tar.gz and extra RPMs>:/in:ro -v <out dir>:/out \
#     quay.io/almalinuxorg/almalinux:10-kitten /kd/build-rootfs.sh
# Extra RPMs in /in (*.riscv64.rpm) are installed too: Kitten has no EPEL
# for riscv64, so libraries the payload needs from EPEL (xxhash, yajl)
# come from local rebuilds.
set -euo pipefail

IN=${IN:-/in}
OUT=${OUT:-/out}
KD=$(cd "$(dirname "$0")" && pwd)
R=${ROOT:-/rootfs}
IMG=$OUT/${IMG_NAME:-kitten-dom0.img}
SIZE=${IMG_SIZE:-2G}
PAYLOAD=$IN/dom0-payload.tar.gz
log() { echo "== $*"; }

[ -f "$PAYLOAD" ] || {
  echo "Error: $PAYLOAD not found" >&2
  exit 1
}
DNF=(dnf -y -q --installroot="$R" --releasever=10 --setopt=install_weak_deps=False --setopt=tsflags=nodocs)

log "tools for the build"
dnf -y -q install binutils e2fsprogs shadow-utils >/dev/null

log "Kitten base"
rm -rf "$R"
# systemd-udev is a package of its own: without it no device unit ever
# appears, and serial-getty@hvc0 fails on its dependency. libnl3 is
# dlopen()ed by xcp-networkd, so the NEEDED scan below cannot see it.
"${DNF[@]}" install systemd systemd-udev bash python3 dnf iproute util-linux \
  kmod procps-ng coreutils findutils gawk sed grep tar gzip wget openssl \
  stunnel pam passwd shadow-utils hostname less vim-minimal e2fsprogs libnl3 \
  ncurses
shopt -s nullglob
extra=("$IN"/*.riscv64.rpm)
if [ ${#extra[@]} -gt 0 ]; then
  log "local RPMs: ${extra[*]##*/}"
  "${DNF[@]}" install "${extra[@]}"
fi

log "dom0 payload"
# The payload's accounts files are the busybox initrd's: keep Kitten's,
# add the accounts the payload needs, and carry over root's password
tar -C "$R" -xzf "$PAYLOAD" --exclude=./etc/passwd --exclude=./etc/shadow \
  --exclude=./etc/group --exclude=./etc/gshadow
tar -xzOf "$PAYLOAD" ./etc/passwd | while IFS=: read -r name _ uid gid _ home shell; do
  [ "$name" = root ] && continue
  grep -q "^$name:" "$R/etc/passwd" && continue
  chroot "$R" groupadd -g "$gid" "$name" 2>/dev/null || true
  chroot "$R" useradd -u "$uid" -g "$gid" -d "$home" -s "$shell" -M "$name"
done
roothash=$(tar -xzOf "$PAYLOAD" ./etc/shadow | awk -F: '$1 == "root" { print $2 }')
[ -n "$roothash" ] && chroot "$R" usermod -p "$roothash" root

log "start-up"
install -D -m 755 "$KD/dom0-start" "$R/usr/libexec/xcpng-riscv/dom0-start"
install -D -m 755 "$KD/dom0term.sh" "$R/opt/xensource/libexec/dom0term.sh"
install -D -m 644 "$KD/xcpng-riscv-dom0.service" "$R/etc/systemd/system/xcpng-riscv-dom0.service"
chroot "$R" systemctl enable xcpng-riscv-dom0.service
chroot "$R" systemctl set-default multi-user.target
echo xcp-ng-riscv64 >"$R/etc/hostname"
# xapi checks logins through PAM service "xapi". The payload's file names
# /lib/security/pam_unix.so, where the busybox root keeps the trixie
# module; Kitten's are on PAM's own search path (/usr/lib64/security)
printf '%s\n' '#%PAM-1.0' \
  "# xapi's login check (service \"xapi\"), straight to /etc/shadow" \
  'auth     required pam_unix.so' \
  'account  required pam_unix.so' \
  'password required pam_unix.so sha512' >"$R/etc/pam.d/xapi"
printf '/dev/vda / ext4 defaults 0 1\n' >"$R/etc/fstab"
# The payload's libraries are in /usr/lib (Xen's default libdir), which
# is not on Kitten's 64-bit search path
echo /usr/lib >"$R/etc/ld.so.conf.d/xen-riscv.conf"
ldconfig -r "$R"

log "shared libraries the payload needs"
# Every NEEDED soname of every ELF the payload brought: install what
# Kitten provides, report what it does not
missing=()
while read -r so; do
  found=
  for d in /usr/lib64 /usr/lib /lib64 /lib; do
    [ -e "$R$d/$so" ] && found=1 && break
  done
  [ -n "$found" ] && continue
  if "${DNF[@]}" install "$so()(64bit)" >/dev/null 2>&1; then
    echo "installed for $so"
  else
    missing+=("$so")
  fi
done < <(tar -tzf "$PAYLOAD" | sed 's|^\./|/|' | while read -r f; do
  # Not every file is ELF: readelf fails on those, and under pipefail
  # and errexit that would end the scan silently at the first one
  if [ ! -f "$R$f" ] || [ -L "$R$f" ]; then continue; fi
  { readelf -d "$R$f" 2>/dev/null || true; } |
    sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'
done | sort -u | tee "$OUT/payload-sonames.txt")
ldconfig -r "$R"
# The payload always holds ELF files: an empty list means a broken scan,
# not a clean one
[ -s "$OUT/payload-sonames.txt" ] || {
  echo "Error: no NEEDED entries found in the payload" >&2
  exit 1
}
echo "checked $(wc -l <"$OUT/payload-sonames.txt") sonames"
if [ ${#missing[@]} -gt 0 ]; then
  echo "NOT RESOLVED: ${missing[*]}"
fi

log "image"
"${DNF[@]}" clean all >/dev/null 2>&1 || true
du -sh "$R"
# Unresolved libraries make a dom0 that cannot start: keep the previous
# image rather than replace it with that one
[ ${#missing[@]} -eq 0 ] || exit 3
# Built beside the previous image and moved over it only once complete,
# so a failed build never leaves a half-written image in its place
rm -f "$IMG.tmp"
truncate -s "$SIZE" "$IMG.tmp"
mkfs.ext4 -q -L kitten-dom0 -d "$R" "$IMG.tmp"
mv -f "$IMG.tmp" "$IMG"
ls -la "$IMG"
