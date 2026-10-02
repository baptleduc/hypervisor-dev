# SPDX-FileCopyrightText: 2026 Baptiste Le Duc <baptiste.le-duc@vates.tech>
# SPDX-License-Identifier: GPL-2.0

nproc ?= $(shell nproc)

LINUX_ROOT?=$(BUILD_DIR)/linux
OPENSBI_ROOT?=$(BUILD_DIR)/opensbi

QEMU?=$(ARTIFACTS_DIR)/qemu-system-riscv64
OPENSBI?=$(ARTIFACTS_DIR)/opensbi-riscv64-generic-fw_dynamic.bin
KERNEL?=$(ARTIFACTS_DIR)/Image.gz

INITRD?=$(BUILD_DIR)/initrd.img
DTB_SCRIPT?=$(DTB_DIR)/generate_dtb.sh

XEN_ROOT?=$(BUILD_DIR)/xen
XEN_BIN?=$(XEN_ROOT)/xen/xen
XEN_SYMBOL?=$(XEN_ROOT)/xen/xen-syms
XEN_CONFIG?=$(XEN_ROOT)/xen/.config
XEN_CONFIGURE_OUT := $(XEN_ROOT)/config/Paths.mk

GDB?=/usr/bin/gdb-multiarch

# xenopsd-xc, xenopsd-cli and forkexecd built by docker/riscv/xapi,
# picked up when xen-api is mounted at $(BUILD_DIR)/xen-api
XENOPSD_DIR ?= $(BUILD_DIR)/xen-api/_riscv

INITRD_STAMP := .stamp_initrd_with_tools
XEN_MAKE := $(MAKE) -C $(XEN_ROOT) -j$(nproc)

QEMU_COMMON_FLAGS = \
	-M virt,aclint=off,aia=aplic-imsic,aia-guests=7 \
	-cpu rv64,smstateen=on,sstc=off\
	-bios $(OPENSBI) \
	-smp 2 \
	-nographic \
	-m 3g \
	-kernel $(XEN_BIN) \
	-device loader,file=$(KERNEL),addr=0x808ef000

QEMU_BASE_FLAGS = $(QEMU_COMMON_FLAGS) \
	-netdev user,id=net0,hostfwd=tcp::443-:443 \
	-device virtio-net-device,netdev=net0 \
	-device loader,file=$(INITRD),addr=0xe0000000 \
	-dtb $(DTB_DIR)/dom0-qemu-virt.dtb

QEMU_DOM0LESS_FLAGS = $(QEMU_COMMON_FLAGS) \
	-device loader,file=$(DOMU_INITRD_IMG),addr=0x90400000 \
	-dtb $(DTB_DIR)/dom0less-qemu-virt.dtb

QEMU_DEBUG_FLAGS = -s -S

GDB_FLAGS?=
GDB_ARGS = \
	-ex "set confirm off" \
	-ex "set architecture riscv:rv64"
ifndef VMLINUX
GDB_ARGS += \
	-ex "file $(XEN_SYMBOL)" \
	-ex "directory $(XEN_ROOT)"
else
GDB_ARGS += \
	-ex "file $(VMLINUX)" \
	-ex "directory $(XEN_ROOT)" \
	-ex "directory $(LINUX_ROOT)" \
	-ex "add-symbol-file $(XEN_SYMBOL)"
endif
GDB_ARGS += \
	-ex "target remote localhost:1234" \
	-ex "b start_xen" \
	-ex "c"

.PHONY: all clean help xenopsd-files initrd-tools install-tools install-xen install build-tools build-xen build go go-debug go-dom0less gdb initrd create-common-dirs create-tools-dirs

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  %-16s %s\n", $$1, $$2}'

# --- Internal targets ---

$(XEN_CONFIGURE_OUT): $(XEN_ROOT)/configure
	cd $(XEN_ROOT) && ./configure --prefix=/usr --host=riscv64-linux-gnu --enable-ocamltools \
		--with-system-ipxe=/usr/share/ipxe/ipxe.bin \
		--with-system-ovmf=/usr/share/edk2/OVMF.fd \
		IASL=/usr/bin/iasl

$(XEN_CONFIG):
	cp $(CONFIGS_DIR)/.config $(XEN_CONFIG)

$(INITRD_STAMP):
	touch $(INITRD_STAMP)

create-common-dirs:
	mkdir -p $(INITRD_DIR)/dev
	mkdir -p $(INITRD_DIR)/dist
	mkdir -p $(INITRD_DIR)/proc
	mkdir -p $(INITRD_DIR)/sys
	mkdir -p $(INITRD_DIR)/etc/init.d
	mkdir -p $(INITRD_DIR)/etc/xen

create-tools-dirs: create-common-dirs
	mkdir -p $(INITRD_DIR)/var/run/xenstored
	mkdir -p $(INITRD_DIR)/var/run/xen
	mkdir -p $(INITRD_DIR)/var/lib/xen
	mkdir -p $(INITRD_DIR)/var/lock
	mkdir -p $(INITRD_DIR)/var/log/xen
	mkdir -p $(INITRD_DIR)/domu
	cp $(CONFIGS_DIR)/xl.conf $(INITRD_DIR)/etc/xen/
	cp $(CONFIGS_DIR)/domu.cfg $(INITRD_DIR)/domu/
	cp $(KERNEL) $(INITRD_DIR)/domu/
	cp $(DOMU_INITRD_IMG) $(INITRD_DIR)/domu/initrd.img

# --- Build targets ---

build-tools: $(XEN_CONFIGURE_OUT) ## Build Xen tools
	$(XEN_MAKE) build-tools

build-xen: $(XEN_CONFIG) $(XEN_CONFIGURE_OUT) ## Build Xen hypervisor
	$(XEN_MAKE) build-xen

build: $(XEN_CONFIG) $(XEN_CONFIGURE_OUT) ## Build Xen hypervisor and tools
	$(XEN_MAKE) build SUBSYSTEMS="xen tools"

# --- Install targets ---

install-tools: $(XEN_CONFIGURE_OUT) ## Build and install Xen tools to INITRD_DIR
	$(XEN_MAKE) install-tools DESTDIR=$(INITRD_DIR)

install-xen: $(XEN_CONFIG) $(XEN_CONFIGURE_OUT) ## Build and install Xen hypervisor to INITRD_DIR
	$(XEN_MAKE) install-xen DESTDIR=$(INITRD_DIR)

install: $(XEN_CONFIG) $(XEN_CONFIGURE_OUT) ## Build and install Xen hypervisor and tools to INITRD_DIR
	$(XEN_MAKE) install DESTDIR=$(INITRD_DIR) SUBSYSTEMS="xen tools"

# --- Initrd targets ---

initrd: $(INITRD_STAMP) install-xen create-common-dirs ## Create basic initrd image
	echo "Building initrd image"
	printf '%s\n' \
	'#!/bin/sh' \
	'echo "Hello RISC-V World!"' \
	'mount -t proc proc /proc' \
	'mount -t xenfs xenfs /proc/xen' \
	'mkdir -p /dev/pts/' \
	'mount -t devpts devpts /dev/pts' \
	'mount -t sysfs sysfs /sys' \
	'exec /bin/sh' \
	> $(RCS_FILE) && \
	chmod +x $(RCS_FILE)
	cp $(RCS_FILE) $(INITRD_DIR)/etc/init.d/
	genext2fs -b 10000 -N 1024 -U -d $(INITRD_DIR)/ $(INITRD)

xenopsd-files: create-tools-dirs ## Install xenopsd, xenopsd-cli and forkexecd into INITRD_DIR if built
ifneq ($(wildcard $(XENOPSD_DIR)/xenopsd-xc),)
	install -D -m 755 $(XENOPSD_DIR)/xenopsd-xc $(INITRD_DIR)/usr/sbin/xenopsd-xc
	install -D -m 755 $(XENOPSD_DIR)/forkexecd $(INITRD_DIR)/usr/sbin/forkexecd
	install -D -m 755 $(XENOPSD_DIR)/vfork_helper $(INITRD_DIR)/usr/libexec/xapi/vfork_helper
	install -D -m 755 $(XENOPSD_DIR)/xenopsd-cli $(INITRD_DIR)/usr/bin/xenopsd-cli
	install -D -m 644 $(CONFIGS_DIR)/xenopsd-xc.conf $(INITRD_DIR)/etc/xenopsd-xc.conf
	install -D -m 755 $(CONFIGS_DIR)/xenopsd-stub $(INITRD_DIR)/usr/libexec/xenopsd-stub
	install -D -m 644 $(CONFIGS_DIR)/riscv.cfg $(INITRD_DIR)/domu/riscv.cfg
	mkdir -p $(INITRD_DIR)/etc/xcp $(INITRD_DIR)/var/lib/xcp $(INITRD_DIR)/var/xapi/forker \
		$(INITRD_DIR)/var/run/nonpersistent/forkexecd $(INITRD_DIR)/var/log
	echo bridge > $(INITRD_DIR)/etc/xcp/network.conf
ifneq ($(wildcard $(XENOPSD_DIR)/xapi),)
	install -D -m 755 $(XENOPSD_DIR)/xapi $(INITRD_DIR)/usr/sbin/xapi
	install -D -m 755 $(XENOPSD_DIR)/xe $(INITRD_DIR)/usr/bin/xe
	install -D -m 755 $(XENOPSD_DIR)/gencert $(INITRD_DIR)/opt/xensource/libexec/gencert
	install -D -m 755 $(CONFIGS_DIR)/systemctl $(INITRD_DIR)/usr/libexec/systemctl
	install -D -m 644 $(CONFIGS_DIR)/pam.d-xapi $(INITRD_DIR)/etc/pam.d/xapi
	install -D -m 644 $(CONFIGS_DIR)/passwd $(INITRD_DIR)/etc/passwd
	install -D -m 600 $(CONFIGS_DIR)/shadow $(INITRD_DIR)/etc/shadow
	mkdir -p $(INITRD_DIR)/etc/stunnel
	install -D -m 755 $(CONFIGS_DIR)/xe-vm-from-cfg $(INITRD_DIR)/usr/bin/xe-vm-from-cfg
	install -D -m 644 $(CONFIGS_DIR)/xapi.conf $(INITRD_DIR)/etc/xapi.conf
	install -D -m 755 $(XENOPSD_DIR)/squeezed $(INITRD_DIR)/usr/sbin/squeezed
	install -D -m 644 $(CONFIGS_DIR)/squeezed.conf $(INITRD_DIR)/etc/squeezed.conf
	install -D -m 755 $(XENOPSD_DIR)/v6d $(INITRD_DIR)/usr/sbin/v6d
	install -D -m 644 $(CONFIGS_DIR)/v6d.conf $(INITRD_DIR)/etc/v6d.conf
	install -D -m 755 $(XENOPSD_DIR)/xcp-networkd $(INITRD_DIR)/usr/sbin/xcp-networkd
	install -D -m 644 $(CONFIGS_DIR)/xcp-networkd.conf $(INITRD_DIR)/etc/xcp-networkd.conf
	install -D -m 755 $(CONFIGS_DIR)/gen-xensource-inventory $(INITRD_DIR)/usr/libexec/gen-xensource-inventory
	install -D -m 644 $(XENOPSD_DIR)/pool.conf $(INITRD_DIR)/etc/xensource/pool.conf
	install -D -m 644 $(XENOPSD_DIR)/db.conf $(INITRD_DIR)/etc/xensource/db.conf
	install -D -m 644 $(XENOPSD_DIR)/udhcpd.skel $(INITRD_DIR)/etc/xensource/udhcpd.skel
	# dom0 console for XO: wsproxy (from xen-api) and vncterm + sockexec
	# (docker/riscv/console), installed when built
	if [ -x $(XENOPSD_DIR)/wsproxy ] && [ -x $(XENOPSD_DIR)/vncterm ] && [ -x $(XENOPSD_DIR)/sockexec ]; then \
		install -D -m 755 $(XENOPSD_DIR)/wsproxy $(INITRD_DIR)/usr/libexec/xapi/wsproxy && \
		install -D -m 755 $(XENOPSD_DIR)/sockexec $(INITRD_DIR)/usr/libexec/xapi/sockexec && \
		install -D -m 755 $(XENOPSD_DIR)/vncterm $(INITRD_DIR)/usr/lib/xen/bin/vncterm && \
		install -D -m 644 $(XENOPSD_DIR)/keymaps/en-us $(INITRD_DIR)/usr/share/qemu/keymaps/en-us && \
		printf '%s\n' '#!/bin/sh' 'clear' 'if [ -x /bin/login ]; then exec /bin/login root; fi' 'exec /bin/sh' \
			> $(INITRD_DIR)/opt/xensource/libexec/dom0term.sh && \
		chmod 755 $(INITRD_DIR)/opt/xensource/libexec/dom0term.sh && \
		install -d -m 700 $(INITRD_DIR)/root && \
		{ grep -q '^vncterm=' $(INITRD_DIR)/etc/xenopsd-xc.conf || \
		  echo 'vncterm=/usr/lib/xen/bin/vncterm' >> $(INITRD_DIR)/etc/xenopsd-xc.conf; }; \
	fi
	# ponytail: directories xapi requires at start-up, left empty (xen-cmdline
	# is only access()-checked)
	mkdir -p $(INITRD_DIR)/opt/xensource/sm $(INITRD_DIR)/opt/xensource/www \
		$(INITRD_DIR)/usr/libexec/xapi/cluster-stack \
		$(INITRD_DIR)/opt/xensource/libexec/xen-cmdline $(INITRD_DIR)/opt/xensource/gpg \
		$(INITRD_DIR)/opt/xensource/packages/post-install-scripts
endif
else
	@echo "No xenopsd in $(XENOPSD_DIR), skipping (mount xen-api, see docker/riscv/xapi)"
endif

initrd-tools: install create-tools-dirs xenopsd-files ## Create initrd with Xen tools included
	echo "Building initrd with tools image"
	printf '%s\n' \
	'#!/bin/sh' \
	'echo "Hello RISC-V World!"' \
	'mount -t proc proc /proc' \
	'mount -t xenfs xenfs /proc/xen' \
	'mkdir -p /dev/pts/' \
	'mount -t devpts devpts /dev/pts' \
	'mount -t sysfs sysfs /sys' \
	'# xapi listens on 127.0.0.1:80 behind stunnel' \
	'ip link set lo up' \
	'# ponytail: QEMU user networking always hands out 10.0.2.15, so no' \
	'# DHCP client; use udhcpc once dom0 runs on other networks' \
	'if [ -e /sys/class/net/eth0 ]; then' \
	'    ip link set eth0 up' \
	'    ip addr add 10.0.2.15/24 dev eth0' \
	'    ip route add default via 10.0.2.2' \
	'fi' \
	'export LIBXL_DEBUG_DUMP_DTB="/var/log/xen/debug_dump_dt.dtb"' \
	'xenstored' \
	'xenconsoled -vvvv' \
	'sleep 0.5' \
	'if [ -x /usr/sbin/xapi ]; then' \
	'    /usr/libexec/gen-xensource-inventory' \
	'    . /etc/xensource-inventory' \
	'fi' \
	'/usr/lib/xen/bin/xen-init-dom0 $$CONTROL_DOMAIN_UUID' \
	'if [ -x /usr/sbin/xenopsd-xc ]; then' \
	'    syslogd -O /var/log/messages' \
	'    mount -t cgroup2 none /sys/fs/cgroup' \
	'    forkexecd > /var/log/forkexecd.log 2>&1 &' \
	'    xenopsd-xc > /var/log/xenopsd.log 2>&1 &' \
	'fi' \
	'if [ -x /usr/sbin/xapi ]; then' \
	'    squeezed > /var/log/squeezed.log 2>&1 &' \
	'    v6d > /var/log/v6d.log 2>&1 &' \
	'    xcp-networkd > /var/log/xcp-networkd.log 2>&1 &' \
	'    /opt/xensource/libexec/gencert /etc/xensource/xapi-pool-tls.pem -1 xapi:pool' \
	'    # The default cert asks xcp-networkd for the management IP: wait for' \
	'    # it, and bound the call so a stuck networkd cannot block the boot' \
	'    i=0; while [ ! -S /var/lib/xcp/networkd ] && [ $$i -lt 120 ]; do sleep 1; i=$$((i+1)); done' \
	'    # ponytail: without a dom0 NIC there is no management IP for the' \
	'    # default cert: serve the pool one on 443 instead' \
	'    timeout 120 /opt/xensource/libexec/gencert /etc/xensource/xapi-ssl.pem -1 default ||' \
	'        cp /etc/xensource/xapi-pool-tls.pem /etc/xensource/xapi-ssl.pem' \
	'    xapi > /var/log/xapi.log 2>&1 &' \
	'    # dom0 console: xapi hands websocket consoles to wsproxy, which' \
	'    # connects to vncterm on 127.0.0.1:5900 (host_console_vncport)' \
	'    if [ -x /usr/libexec/xapi/wsproxy ]; then' \
	'        /usr/libexec/xapi/sockexec /var/lib/xcp/websockproxy /usr/libexec/xapi/wsproxy > /var/log/wsproxy.log 2>&1 &' \
	'        TERM=linux /usr/lib/xen/bin/vncterm -v 127.0.0.1:0 -r -x /local/domain/0/console -T -c /opt/xensource/libexec/dom0term.sh > /var/log/vncterm.log 2>&1 &' \
	'    fi' \
	'fi' \
	'exec /bin/sh' \
	> $(RCS_FILE) && \
	chmod +x $(RCS_FILE)
	cp $(RCS_FILE) $(INITRD_DIR)/etc/init.d/
	# Size the image to its content (+25%, +8MiB): dom0 holds it in RAM twice,
	# as the loaded module and as the /dev/ram copy
	genext2fs -b $$(( $$(du -sk $(INITRD_DIR) | cut -f1) * 5 / 4 + 8192 )) -N 1444 -U \
		-d $(INITRD_DIR)/ $(INITRD)

# --- Run targets ---

go: $(INITRD) $(KERNEL) $(QEMU) $(OPENSBI) $(XEN_BIN) $(DTB_SCRIPT) ## Launch Xen with dom0 in QEMU
	@echo "Using Linux kernel: $(KERNEL)"
	cd $(DTB_DIR) && \
	bash $(DTB_SCRIPT) dom0-domU-test $(DTB_DIR) $(OPENSBI) $(QEMU) $(XEN_BIN) $(KERNEL) $(INITRD)
	$(QEMU) $(QEMU_BASE_FLAGS)

go-debug: $(INITRD) $(KERNEL) $(QEMU) $(OPENSBI) $(XEN_BIN) $(DTB_SCRIPT) ## Launch Xen in QEMU with GDB server waiting on port 1234
	@echo "Using Linux kernel: $(KERNEL)"
	cd $(DTB_DIR) && \
	bash $(DTB_SCRIPT) dom0-domU-test $(DTB_DIR) $(OPENSBI) $(QEMU) $(XEN_BIN) $(KERNEL) $(INITRD)
	$(QEMU) $(QEMU_BASE_FLAGS) $(QEMU_DEBUG_FLAGS)

go-dom0less: build-xen $(KERNEL) $(QEMU) $(OPENSBI) $(DTB_SCRIPT) ## Build Xen, then launch it dom0less with one domU in QEMU
	@echo "Using Linux kernel: $(KERNEL)"
	cd $(DTB_DIR) && \
	bash $(DTB_SCRIPT) dom0less-test $(DTB_DIR) $(OPENSBI) $(QEMU) $(XEN_BIN) $(KERNEL) $(DOMU_INITRD_IMG)
	$(QEMU) $(QEMU_DOM0LESS_FLAGS)

gdb: $(GDB) ## Attach GDB to a running Xen instance
	$(GDB) $(GDB_FLAGS) $(GDB_ARGS)

# --- Clean ---

clean: ## Clean build artifacts (distclean)
	@if [ -f "$(XEN_CONFIGURE_OUT)" ]; then \
		rm -f "$(XEN_CONFIGURE_OUT)"; \
		echo "WARNING: removed $(XEN_CONFIGURE_OUT)"; \
		echo "WARNING: next builds will use the Docker image defaults (.config and ./configure output)"; \
	fi
	$(XEN_MAKE) distclean
