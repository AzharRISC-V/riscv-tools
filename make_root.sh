#!/bin/bash
#
# help:
# BUSYBOX=path/to/busybox LINUX=path/to/linux LOWRISC=path/to/lowrisc make_root.sh

if [ -z "$BUSYBOX" ]; then BUSYBOX=$TOP/riscv-tools/busybox-1.21.1; fi
BUSYBOX_CFG=$TOP/riscv-tools/busybox_config

ROOT_INITTAB=$TOP/riscv-tools/inittab

if [ -z "$LINUX" ]; then LINUX=$TOP/riscv-tools/linux-4.6.2; fi
LINUX_CFG=$TOP/riscv-tools/vmlinux_config

# use nexys4 dev_map.h by default
if [ -z "$FPGA_BOARD" ]; then LOWRISC=$TOP/fpga/board/nexys4_ddr
else LOWRISC=$TOP/fpga/board/$FPGA_BOARD; fi

cat > /tmp/init1 <<EOF
#!/bin/busybox ash
/bin/busybox --install -s
mount -t proc proc /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
sleep 2
echo Mounting SD root
mkdir /dos
mount -t msdos /dev/mmcblk0p1 /dos || (echo Mount failed, dropping to ash; /bin/ash)
cd /dos
flash_eraseall -j /dev/mtd0
dd if=cfgmem.bin of=/dev/mtd0 bs=1M
dd if=/dev/mtd0 of=readback.bin bs=1M
cmp cfgmem.bin readback.bin || (echo Compare failed, dropping to ash; /bin/ash)

exec /sbin/init
EOF

CDIR=$PWD

if [ -d "$BUSYBOX" ] && [ -d "$LINUX" ]; then
    echo "build busybox..."
    cp  $BUSYBOX_CFG "$BUSYBOX"/.config &&
    make -j$(nproc) -C "$BUSYBOX" 2>&1 1>/dev/null &&
    if [ -d ramfs ]; then rm -fr ramfs; fi &&
    mkdir ramfs && cd ramfs &&
    mkdir -p bin etc dev lib proc sbin sys tmp usr usr/bin usr/lib usr/sbin &&
    cp "$BUSYBOX"/busybox bin/ &&
    cp /tmp/init1 ./init && chmod +x ./init &&
    cp $ROOT_INITTAB etc/inittab &&
    echo "\
        mknod dev/null c 1 3 && \
        mknod dev/tty c 5 0 && \
        mknod dev/zero c 1 5 && \
        mknod dev/console c 5 1 && \
        find . | cpio -H newc -o > "$LINUX"/initramfs.cpio\
        " | fakeroot &&
    if [ $? -ne 0 ]; then echo "build busybox failed!"; fi &&
    \
    echo "build linux..." &&
    cp $LINUX_CFG "$LINUX"/.config &&
    make -j$(nproc) -C "$LINUX" ARCH=riscv vmlinux 2>&1 1>/dev/null &&
    if [ $? -ne 0 ]; then echo "build linux failed!"; fi &&
    \
    echo "build bbl..." &&
    if [ ! -d $TOP/fpga/bootloader/build ]; then
        mkdir -p $TOP/fpga/bootloader/build
    fi   &&
    cd $TOP/fpga/bootloader/build &&
    ../configure \
        --host=riscv64-unknown-elf \
        --with-lowrisc="$LOWRISC" \
        --with-payload="$LINUX"/vmlinux \
        2>&1 1>/dev/null &&
    make -j$(nproc) bbl 2>&1 1>/dev/null &&
    if [ $? -ne 0 ]; then echo "build linux failed!"; fi &&
    \
    cd "$CDIR"
    cp $TOP/fpga/bootloader/build/bbl ./boot.bin
else
    echo "make sure you have both linux and busybox downloaded."
    echo "usage:  [BUSYBOX=path/to/busybox] [LINUX=path/to/linux] [LOWRISC=path/to/lowrisc] make_root.sh"
fi
