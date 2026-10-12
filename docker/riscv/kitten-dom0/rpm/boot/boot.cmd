# U-Boot boot script for the Kitten dom0 disk (DISK_LAYOUT=gpt), written
# to /boot/boot.scr by build-rootfs-rpm.sh. U-Boot's distro boot runs it
# and sets devtype, devnum, distro_bootpart and prefix ("/boot/").
# It loads only the stable names the packages keep current: /boot/xen.uimg
# (xen-hypervisor) and /boot/vmlinuz-xcpng (kernel-xcpng-riscv64), so a
# package update needs no change here.
# Command lines: the defaults below, overridden by /boot/xen-cmdline.txt
# when it exists ("name=value" lines, read with env import -t). Edit that
# file, not this script; without it the defaults boot.
# Same layout as the lab's QEMU guest-loader setup: dom0 kernel as a
# /chosen multiboot module, Xen command line in /chosen/bootargs, PCI
# node removed (a QEMU virt node: another board needs its own).
# Load addresses come from the board's U-Boot environment. xen.uimg is a
# kernel_noload image, run in place: loading it 0x40 below kernel_addr_r
# puts Xen itself on kernel_addr_r, which must be 4 KiB aligned.
setexpr xen_uimg_r ${kernel_addr_r} - 0x40
setenv dom0_addr ${ramdisk_addr_r}
setenv xen_args "com1=poll sched=null dom0_max_vcpus=1 dom0_mem=1536M noreboot"
setenv dom0_args "rw root=/dev/vda1 console=hvc0 keep_bootcon bootmem_debug debug dom0_mem=512M"

if load ${devtype} ${devnum}:${distro_bootpart} ${pxefile_addr_r} ${prefix}xen-cmdline.txt; then
  env import -t ${pxefile_addr_r} ${filesize}
fi

load ${devtype} ${devnum}:${distro_bootpart} ${xen_uimg_r} ${prefix}xen.uimg || exit
load ${devtype} ${devnum}:${distro_bootpart} ${dom0_addr} ${prefix}vmlinuz-xcpng || exit
setenv dom0_size 0x${filesize}

fdt move ${fdtcontroladdr} ${fdt_addr_r} 0x20000
fdt resize 4096
fdt rm /soc/pci@30000000
fdt set /chosen "#address-cells" <2>
fdt set /chosen "#size-cells" <2>
fdt mknode /chosen module
fdt set /chosen/module compatible "multiboot,kernel" "multiboot,module"
fdt set /chosen/module reg <0x0 ${dom0_addr} 0x0 ${dom0_size}>
fdt set /chosen/module bootargs "${dom0_args}"

# bootm writes the bootargs variable into /chosen/bootargs: Xen's command line
setenv bootargs "${xen_args}"
bootm ${xen_uimg_r} - ${fdt_addr_r}
