#!/bin/bash
# SPDX-FileCopyrightText: 2026 Baptiste Le Duc <baptiste.le-duc@vates.tech>
# SPDX-License-Identifier: GPL-2.0
#
# Derived from:
# https://gitlab.com/xen-project/people/olkur/xen/-/blob/latest/automation/scripts/qemu-smoke-riscv64.sh
# Only the dom0 DTB generation part was extracted and adapted.

set -ex

BUILDDIR=$2
FW_PATH=$3
QEMU=$4
XEN=$5
KERNEL=$6
INITRD=$7

TEST_CASE=$1

VERBOSE=${VERBOSE:-0}
log() { [[ $VERBOSE -eq 1 ]] && echo "$*" >&2 || true; }

# Arrays to store parsed data
declare -A PLATFORM_DATA
declare -A DOM0_DATA
declare -A DOMU_DATA

get_dom0_val() {
    local key=$1

    echo "${DOM0_DATA[$key]}"
}

get_domu_val() {
    local key=$1

    echo "${DOMU_DATA[$key]}"
}

get_platform_val() {
    local key=$1

    echo "${PLATFORM_DATA[$key]}"
}

remove_unsupported_nodes() {
    local dts_name="$1.dts"

    # PCI isn't supported now; virtio-mmio is, for dom0's NIC
    awk '/pci[^;]*{/ {f=1} f && /};/ {f=0; next} !f' ${dts_name} > ${dts_name}_ && mv ${dts_name}_ ${dts_name}
}

generate_base_dts() {
    local platform_name=$(get_platform_val NAME)
    local platform_cpu_num=$(get_platform_val CPU_NUM)
    local platform_ram_size=$(get_platform_val RAM_SIZE)
    local platform_interrupt_controller=$(get_platform_val INTERRUPT_CONTROLLER)
    local dts_name="qemu"
    local xen_boot_args=$(get_platform_val XEN_BOOTARGS)

    local ic_flags=""
    case $platform_interrupt_controller in
        aplic-imsic)
            ic_flags=",aclint=off,aia=aplic-imsic,aia-guests=7 -cpu rv64,smstateen=on,sstc=off"
            ;;
    esac

    case $platform_name in
        dom0less-qemu-virt)
            "${QEMU}" -M virt$ic_flags -smp "${platform_cpu_num}" -nographic \
                      -bios ${FW_PATH} \
                      -m "${platform_ram_size}" \
                      -append "${xen_boot_args}" -kernel ${XEN} \
                      -machine dumpdtb=${BUILDDIR}/${dts_name}.dtb
            dtc -I dtb ${BUILDDIR}/${dts_name}.dtb > "${BUILDDIR}/${dts_name}.dts"
            remove_unsupported_nodes ${BUILDDIR}/${dts_name}
            rm ${BUILDDIR}/$dts_name.dtb
            ;;
        dom0-qemu-virt)
            local kernel_path=$(get_dom0_val KERNEL_PATH)
            local kernel_addr=$(get_dom0_val KERNEL_ADDR)
            local ramdisk_path=$(get_dom0_val RAMDISK_PATH)
            local ramdisk_addr=$(get_dom0_val RAMDISK_ADDR)
            local boot_args=$(get_dom0_val BOOTARGS)

            "${QEMU}" -M virt$ic_flags -smp "${platform_cpu_num}" -nographic \
                      -bios ${FW_PATH} \
                      -m "${platform_ram_size}" \
                      -device "guest-loader,kernel=${kernel_path},addr=${kernel_addr},bootargs=${boot_args}" \
                      -device "guest-loader,initrd=${ramdisk_path},addr=${ramdisk_addr}" \
                      -append "${xen_boot_args}" -kernel ${XEN} \
                      -machine dumpdtb=${BUILDDIR}/${dts_name}.dtb
            dtc -I dtb ${BUILDDIR}/${dts_name}.dtb > "${BUILDDIR}/${dts_name}.dts"
            remove_unsupported_nodes ${BUILDDIR}/${dts_name}
            rm ${BUILDDIR}/$dts_name.dtb
            ;;
        *)
            echo "DTB generation for $platform_name not implemented yet"
            exit 1
            ;;
    esac

    echo "${BUILDDIR}/$dts_name.dts"
}

module_size() {
    printf "0x%x" "$(stat -c %s "$1")"
}

# Append a /chosen/domU1 node, dtc merges it into the existing /chosen.
append_domu_node() {
    local dts_name=$1
    local kernel_addr=$(get_domu_val KERNEL_ADDR)
    local kernel_path=$(get_domu_val KERNEL_PATH)
    local ramdisk_addr=$(get_domu_val RAMDISK_ADDR)
    local ramdisk_path=$(get_domu_val RAMDISK_PATH)

    # Without dom0, Xen reads its command line from xen,xen-bootargs
    sed -i 's/\bbootargs\b/xen,xen-bootargs/' "${dts_name}"

    cat >> "${dts_name}" <<EOF
/ {
    chosen {
        domU1 {
            #address-cells = <1>;
            #size-cells = <1>;
            compatible = "xen,domain";
            memory = <0 $(get_domu_val MEMORY_KB)>;
            cpus = <$(get_domu_val CPUS_NUM)>;
            vsbi_uart;

            module@${kernel_addr#0x} {
                compatible = "multiboot,kernel", "multiboot,module";
                reg = <${kernel_addr} $(module_size "${kernel_path}")>;
                bootargs = "$(get_domu_val BOOTARGS)";
            };

            module@${ramdisk_addr#0x} {
                compatible = "multiboot,ramdisk", "multiboot,module";
                reg = <${ramdisk_addr} $(module_size "${ramdisk_path}")>;
            };
        };
    };
};
EOF
}

generate_dtb() {
    dts_name=$(generate_base_dts)

    if [[ $(get_platform_val NAME) == dom0less-qemu-virt ]]; then
        append_domu_node "${dts_name}"
    fi

    # generate dtb
    dtb_name="$(get_platform_val NAME)".dtb

    dtc -O dtb -o ${BUILDDIR}/${dtb_name} $dts_name
}

check_and_set_platform_data_default() {
    local key_to_check="$1"
    local default_value="$2"

    if [[ ! -v "PLATFORM_DATA[$key_to_check]" ]]; then
        PLATFORM_DATA[$key_to_check]="$default_value"
    fi
}

process_platform_data() {
    check_and_set_platform_data_default "NAME" "qemu-virt"
    check_and_set_platform_data_default "RAM_SIZE" "4g"
    check_and_set_platform_data_default "CPU_NUM" "1"
    check_and_set_platform_data_default "XEN_BOOTARGS" ""
    check_and_set_platform_data_default "INTERRUPT_CONTROLLER" "plic"

    if [[ $VERBOSE -eq 1 ]]; then
        log "PLATFORM data:"
        for key in "${!PLATFORM_DATA[@]}"; do
            log "  $key=${PLATFORM_DATA[$key]}"
        done
    fi
}

check_and_set_dom0_data_default() {
    local key_to_check="$1"
    local default_value="$2"

    if [[ ! -v "DOM0_DATA[$key_to_check]" ]]; then
        DOM0_DATA[$key_to_check]="$default_value"
    fi
}

check_and_failure_dom0_data() {
    local key_to_check="$1"

    if [[ ! -v "DOM0_DATA[$key_to_check]" ]]; then
        echo "$key_to_check should be set!"
        exit 1
    fi
}

process_dom0_data() {
    check_and_failure_dom0_data KERNEL_ADDR
    check_and_failure_dom0_data KERNEL_PATH
    check_and_failure_dom0_data RAMDISK_ADDR
    check_and_failure_dom0_data RAMDISK_PATH
    check_and_set_dom0_data_default BOOTARGS ""
}

check_and_set_domu_data_default() {
    local key_to_check="$1"
    local default_value="$2"

    if [[ ! -v "DOMU_DATA[$key_to_check]" ]]; then
        DOMU_DATA[$key_to_check]="$default_value"
    fi
}

check_and_failure_domu_data() {
    local key_to_check="$1"

    if [[ ! -v "DOMU_DATA[$key_to_check]" ]]; then
        echo "DOMU_$key_to_check should be set!"
        exit 1
    fi
}

process_domu_data() {
    check_and_failure_domu_data KERNEL_ADDR
    check_and_failure_domu_data KERNEL_PATH
    check_and_failure_domu_data RAMDISK_ADDR
    check_and_failure_domu_data RAMDISK_PATH
    check_and_set_domu_data_default BOOTARGS ""
    check_and_set_domu_data_default CPUS_NUM 1
    check_and_set_domu_data_default MEMORY_KB 0x40000
}

parse_config_file() {
    while IFS= read -r line; do
        if [[ $line =~ ^\s*# || -z $line ]]; then
            continue
        fi

        key=$(echo "$line" | cut -d '=' -f 1)
        value=$(echo "$line" | cut -d '=' -f 2-)

        # Remove trailing spaces and quotes with xargs
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        rest="${key#*_}"

        log "parsing key: $rest"

        case "$key" in
            PLATFORM*)
                PLATFORM_DATA["$rest"]=$value
                ;;
            DOM0*)
                DOM0_DATA["$rest"]=$value
                ;;
            DOMU*)
                DOMU_DATA["$rest"]=$value
                ;;
        esac
    done < "$CONFIG_FILE"

    process_platform_data
    if [[ $(get_platform_val NAME) == dom0less-qemu-virt ]]; then
        process_domu_data
    else
        process_dom0_data
    fi
}

case "${TEST_CASE}" in
    "dom0-test" | "dom0-smp-test" | "dom0-domU-test")
        if [ "$TEST_CASE" = "dom0-smp-test" ]; then
            PLATFORM_PCPU_NUM=4
        elif [ "$TEST_CASE" = "dom0-test" ]; then
            PLATFORM_PCPU_NUM=1
        elif [ "$TEST_CASE" = "dom0-domU-test" ]; then
            PLATFORM_PCPU_NUM=2
        fi

        CONFIG_FILE="dom0.conf"
        PLATFORM_NAME=dom0-qemu-virt
        PLATFORM_RAM_SIZE=3g
        PLATFORM_XEN_BOOTARGS="com1=poll sched=null dom0_max_vcpus=1 dom0_mem=1536M"
        DOM0_KERNEL_ADDR=0x808ef000
        DOM0_KERNEL_PATH=${KERNEL}
        # High in RAM, so Xen's 1:1 allocation of dom0 gets a large first
        # bank right after the kernel, where the initrd is copied
        DOM0_RAMDISK_ADDR=0xe0000000
        DOM0_RAMDISK_PATH=${INITRD}
        DOM0_BOOTARGS="rw ${DOM0_ROOT_ARGS:-root=/dev/ram ramdisk_size=600000} console=hvc0 keep_bootcon bootmem_debug debug dom0_mem=512M"

        echo "PLATFORM_NAME=\"${PLATFORM_NAME}\"
        PLATFORM_CPU_NUM=\"${PLATFORM_PCPU_NUM}\"
        PLATFORM_RAM_SIZE=\"${PLATFORM_RAM_SIZE}\"
        PLATFORM_XEN_BOOTARGS=\"${PLATFORM_XEN_BOOTARGS}\"
        PLATFORM_INTERRUPT_CONTROLLER=\"aplic-imsic\"

        DOM0_KERNEL_ADDR=\"${DOM0_KERNEL_ADDR}\"
        DOM0_KERNEL_PATH=\"${DOM0_KERNEL_PATH}\"
        DOM0_RAMDISK_ADDR=\"${DOM0_RAMDISK_ADDR}\"
        DOM0_RAMDISK_PATH=\"${DOM0_RAMDISK_PATH}\"
        DOM0_BOOTARGS=\"${DOM0_BOOTARGS}\"" > "${CONFIG_FILE}"
        ;;
    "dom0less-test")
        CONFIG_FILE="dom0less.conf"

        echo "PLATFORM_NAME=\"dom0less-qemu-virt\"
        PLATFORM_CPU_NUM=\"2\"
        PLATFORM_RAM_SIZE=\"2g\"
        PLATFORM_XEN_BOOTARGS=\"com1=poll sched=null\"
        PLATFORM_INTERRUPT_CONTROLLER=\"aplic-imsic\"

        DOMU_KERNEL_ADDR=\"0x808ef000\"
        DOMU_KERNEL_PATH=\"${KERNEL}\"
        DOMU_RAMDISK_ADDR=\"0x90400000\"
        DOMU_RAMDISK_PATH=\"${INITRD}\"
        DOMU_CPUS_NUM=\"1\"
        DOMU_BOOTARGS=\"rw root=/dev/ram console=hvc0\"" > "${CONFIG_FILE}"
        ;;
    *)
        echo "Invalid option: ${TEST_CASE}"
        exit 1
        ;;
esac

log "Generated config:"
[[ $VERBOSE -eq 1 ]] && cat "${CONFIG_FILE}" >&2

parse_config_file
generate_dtb
