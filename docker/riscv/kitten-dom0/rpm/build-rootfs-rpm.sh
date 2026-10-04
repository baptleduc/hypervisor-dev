#!/bin/bash
# Build an AlmaLinux Kitten dom0 image from the meta-xcpng toolstack RPMs,
# started by their own systemd units. The RISC-V pieces the RPM set does
# not have (our hotplug scripts and SR driver, the QEMU keymap vncterm
# reads, the domU kernel and initrd) come from the dom0 payload, by a
# fixed list; the rest of the payload is not used.
#
# Runs as root in a riscv64 AlmaLinux Kitten container, with this
# directory's parent at /kd, and /in holding dom0-payload.tar.gz, the
# toolstack RPMs in /in/rpms and extra library RPMs (*.riscv64.rpm):
#   docker run --rm --platform linux/riscv64 -v <kitten-dom0>:/kd:ro \
#     -v <in>:/in:ro -v <out>:/out quay.io/almalinuxorg/almalinux:10-kitten \
#     /kd/rpm/build-rootfs-rpm.sh
set -euo pipefail

IN=${IN:-/in}
OUT=${OUT:-/out}
KD=$(cd "$(dirname "$0")/.." && pwd)
RD=$KD/rpm
R=${ROOT:-/rootfs}
IMG=$OUT/${IMG_NAME:-kitten-dom0-rpm.img}
SIZE=${IMG_SIZE:-3G}
PAYLOAD=$IN/dom0-payload.tar.gz
log() { echo "== $*"; }

for f in "$PAYLOAD" "$IN"/rpms/xapi-core-*.rpm; do
  [ -f "$f" ] || {
    echo "Error: $f not found" >&2
    exit 1
  }
done
DNF=(dnf -y -q --installroot="$R" --releasever=10 --setopt=install_weak_deps=False --setopt=tsflags=nodocs)

log "tools for the build"
dnf -y -q install binutils e2fsprogs shadow-utils cpio >/dev/null

log "Kitten base"
rm -rf "$R"
# As in build-rootfs.sh, plus what the toolstack's units and scripts use
# and check for at start-up (zstd for xenopsd, ethtool for xcp-networkd;
# sshd for xapi, which configures the SSH service at start-up and dies
# when systemctl cannot)
# rsyslog: xcp-ng-release-config ships its unit, not a Require on it
"${DNF[@]}" install systemd systemd-udev bash python3 dnf iproute util-linux \
  kmod procps-ng coreutils findutils gawk sed grep tar gzip wget openssl \
  stunnel pam passwd shadow-utils hostname less vim-minimal e2fsprogs libnl3 \
  ncurses iputils json-c zstd ethtool openssh-server rsyslog
shopt -s nullglob
extra=("$IN"/*.riscv64.rpm)
if [ ${#extra[@]} -gt 0 ]; then
  log "local library RPMs: ${extra[*]##*/}"
  "${DNF[@]}" install "${extra[@]}"
fi

log "toolstack RPMs"
# dnf resolves the whole set against Kitten. Scriptlets are off: they
# assume an XCP-ng host; the units are enabled below instead.
toolstack=()
for r in "$IN"/rpms/*.rpm; do
  case "$(rpm -qp --qf '%{NAME}' "$r")" in
  *-devel | *-doc | *-tests | *simulator* | *debuginfo | *debugsource | \
    xapi-storage-ocaml-plugin-runtime | xapi-sdk | busybox-petitboot) ;;
  *) toolstack+=("$r") ;;
  esac
done
dnf -y -q --installroot="$R" --releasever=10 --setopt=install_weak_deps=False \
  --setopt=tsflags=nodocs,noscripts install "${toolstack[@]}"
echo "installed ${#toolstack[@]} toolstack RPMs"

log "RISC-V extras from the payload"
extras=(
  ./usr/lib/xenopsd/vif-riscv ./usr/lib/xenopsd/block-riscv
  ./opt/xensource/sm/rawfileSR ./usr/libexec/xenopsd-stub
  ./usr/libexec/gen-xensource-inventory ./usr/bin/xe-vm-from-cfg
  ./usr/share/qemu/keymaps/en-us ./domu
)
tar -C "$R" -xzf "$PAYLOAD" "${extras[@]}"
# Accounts vncterm needs (its RPM makes them in %pre, and scriptlets are
# off), from the payload, and root's password
tar -xzOf "$PAYLOAD" ./etc/passwd | while IFS=: read -r name _ uid gid _ home shell; do
  [ "$name" = root ] && continue
  grep -q "^$name:" "$R/etc/passwd" && continue
  chroot "$R" groupadd -g "$gid" "$name" 2>/dev/null || true
  chroot "$R" useradd -u "$uid" -g "$gid" -d "$home" -s "$shell" -M "$name"
done
roothash=$(tar -xzOf "$PAYLOAD" ./etc/shadow | awk -F: '$1 == "root" { print $2 }')
[ -n "$roothash" ] && chroot "$R" usermod -p "$roothash" root

log "RISC-V configuration"
install -D -m 644 "$RD/conf/xapi-riscv.conf" "$R/etc/xapi.conf.d/riscv.conf"
install -D -m 644 "$RD/conf/xenopsd-riscv.conf" "$R/etc/xenopsd.conf.d/riscv.conf"
# Linux bridges, not Open vSwitch (not built for riscv64)
install -D -m 644 "$RD/conf/network.conf" "$R/etc/xensource/network.conf"
# networkd's brctl stays a stub (see host-setup); it has no conf.d
echo "brctl=/usr/libexec/xenopsd-stub" >>"$R/etc/xcp-networkd.conf"
install -D -m 755 "$RD/host-setup" "$R/usr/libexec/xcpng-riscv/host-setup"
install -D -m 755 "$RD/firstboot" "$R/usr/libexec/xcpng-riscv/firstboot"
install -D -m 755 "$KD/dom0term.sh" "$R/usr/libexec/xcpng-riscv/dom0term.sh"
echo xcp-ng-riscv64 >"$R/etc/hostname"
printf '/dev/vda / ext4 defaults 0 1\n' >"$R/etc/fstab"

log "units"
cp -r "$RD"/units/* "$R/etc/systemd/system/"
# Xen's own units come with xen-tools; xenconsoled reads its log settings
# from xencommons, and fails on an empty log directory
printf 'XENCONSOLED_TRACE=guest\nXENCONSOLED_LOG_DIR=/var/log/xen/console\n' \
  >>"$R/etc/sysconfig/xencommons"
for u in proc-xen.mount xenstored.service xenconsoled.service xen-init-dom0.service \
  xcpng-riscv-host.service xcpng-riscv-firstboot.service dom0term.service \
  v6d.service gencert.service wsproxy.socket toolstack.target; do
  chroot "$R" systemctl enable "$u"
done
chroot "$R" systemctl set-default multi-user.target
ldconfig -r "$R"

log "shared libraries the dom0 binaries need"
# Every NEEDED soname of every ELF the toolstack RPMs and the extras
# brought: install what Kitten provides, report what it does not
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
done < <({
  for r in "${toolstack[@]}"; do rpm -qlp "$r"; done
  printf '%s\n' "${extras[@]#.}"
} | sort -u | while read -r f; do
  # Not every file is ELF: readelf fails on those, and under pipefail
  # and errexit that would end the scan silently at the first one
  if [ -d "$R$f" ]; then
    find "$R$f" -type f
  elif [ -f "$R$f" ] && [ ! -L "$R$f" ]; then
    echo "$R$f"
  fi
done | while read -r p; do
  { readelf -d "$p" 2>/dev/null || true; } | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'
done | sort -u | tee "$OUT/rpm-dom0-sonames.txt")
ldconfig -r "$R"
[ -s "$OUT/rpm-dom0-sonames.txt" ] || {
  echo "Error: no NEEDED entries found" >&2
  exit 1
}
echo "checked $(wc -l <"$OUT/rpm-dom0-sonames.txt") sonames"
if [ ${#missing[@]} -gt 0 ]; then
  echo "NOT RESOLVED: ${missing[*]}"
  exit 3
fi

log "image"
"${DNF[@]}" clean all >/dev/null 2>&1 || true
du -sh "$R"
rm -f "$IMG.tmp"
truncate -s "$SIZE" "$IMG.tmp"
mkfs.ext4 -q -L kitten-dom0 -d "$R" "$IMG.tmp"
mv -f "$IMG.tmp" "$IMG"
ls -la "$IMG"
