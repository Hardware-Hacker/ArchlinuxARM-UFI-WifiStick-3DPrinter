#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright(c) 2023 John Sanpe <sanpeqf@gmail.com>
#

kerndtb="build/kernel-dtb"
bootimg="build/boot.img"
lk2ndimg="build/aboot.img"

livecd="build/livecd"
rootfs="$livecd/mnt"
rootimg="build/rootfs.img"

function make_boot()
{
    kernel="linux/arch/arm64/boot/Image.gz"
    dtbfile="linux/arch/arm64/boot/dts/qcom/msm8916-thwc-ufi001c.dtb"
    cat ${kernel} ${dtbfile} > ${kerndtb}
}

function make_image()
{
    unset options
    options+=" --base 0x80000000"
    options+=" --pagesize 2048"
    options+=" --second_offset 0x00f00000"
    options+=" --tags_offset 0x01e00000"
    options+=" --kernel_offset 0x00080000"
    options+=" --kernel ${kerndtb}"
    options+=" -o ${bootimg}"

    cmdline="earlycon console=ttyMSM0,115200 rootwait root=PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e rw"
    mkbootimg --cmdline "${cmdline}" ${options}
}

function build_lk2nd()
{
    cd lk2nd
    make TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916 -j$[$(nproc) * 2]
    cp -p build-lk1st-msm8916/emmc_appsboot.mbn ../$lk2ndimg
    cd -
}

function build_linux()
{
    for file in patch/linux/*.patch; do
        patch -N -p 1 -d linux <$file
    done

    cd linux
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- msm8916_defconfig
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$[$(nproc) * 2]
    make INSTALL_MOD_PATH=../$rootfs modules_install
    cd -
}

function prepare_livecd()
{
    url="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
    livepack="build/ArchLinuxARM-aarch64-latest.tar.gz"

    if [ ! -e $livepack ]; then
        curl -L -o $livepack $url
    fi

    mkdir -p $livecd
    mount --bind $livecd $livecd
    bsdtar -xpf $livepack -C $livecd
}

function prepare_rootfs()
{
    dd if=/dev/zero of=$rootimg bs=1MiB count=2048
    mkfs.ext4 $rootimg
    mount $rootimg $rootfs
}

function chlivealarmdo()
{
    path=$1
    chalarm="cd /home/alarm/$path && su alarm -c"
    command="$chalarm '$2'"

    $chlivedo "$command"
}

function chlive_path_do() {
    path=$1
    command="cd $path; $2"
    $chlivedo "$command"
}

function chlive_alarm_path_do() {
    chlive_path_do '/home/alarm/' "$1"
}


function build_aur_package_live()
{
    local name=$1

    local project_url="https://aur.archlinux.org/$name.git"

    result=`chlive_alarm_path_do "file $name"`

    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "" "git clone $project_url $name"
    fi

    local runtimedeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${depends[@]}')
    local compiledeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${makedepends[@]}')
    local checkdepends=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${checkdepends[@]}')

    local pkgver=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${pkgver}-${pkgrel}')
    # local pkgarch=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${arch[@]}')

    for dep in $compiledeps; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done


    for dep in $runtimedeps; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done


    for dep in $checkdepends; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done

    result=`chlive_alarm_path_do "file $name/$name-*-*.pkg.tar.xz"`
    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "$name" "makepkg -s --noconfirm"
    fi

    chlive_alarm_path_do "pacman --noconfirm -U $name/$name-*-*.pkg.tar.xz"

    echo "build aur packaege $name to live finished"
}

function build_aur_package_rootfs()
{
    local name=$1
    local project_url="https://aur.archlinux.org/$name.git"

    echo "build aur packaege $name to rootfs start"

    result=`chlive_alarm_path_do "file $name"`
    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "" "git clone $project_url $name"
    fi

    local runtimedeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${depends[@]}')
    local compiledeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${makedepends[@]}')
    local checkdepends=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${checkdepends[@]}')

    local pkgver=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${pkgver}-${pkgrel}')
    # local pkgarch=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${arch[@]}')

    for dep in $compiledeps; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done


    for dep in $runtimedeps; do
        if $chrootdo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_rootfs $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
            $chlivedo "pacstrap -cGM /mnt $dep"
        fi
    done

    for dep in $checkdepends; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done

    result=`chlive_alarm_path_do "file $name/$name-*-*.pkg.tar.xz"`
    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "$name" "makepkg -s --noconfirm"
    fi

    chlive_alarm_path_do "pacman --noconfirm -U $name/$name-*-*.pkg.tar.xz"
    chlive_alarm_path_do "pacstrap -cGMU /mnt $name/$name-*-*.pkg.tar.xz"

    echo "build aur packaege $name to rootfs finished"
}

function config_rootfs()
{
    chlivedo="arch-chroot $livecd qemu-aarch64-static /bin/bash -c"
    chrootdo="arch-chroot $rootfs qemu-aarch64-static /bin/bash -c"

    cp -p /usr/bin/qemu-aarch64-static $livecd/bin/qemu-aarch64-static

    # Initialize environment
    $chlivedo "pacman-key --init"
    $chlivedo "pacman-key --populate archlinuxarm"
    $chlivedo "pacman --noconfirm -Syyu"
    $chlivedo "pacman --noconfirm -S arch-install-scripts cloud-guest-utils"
    $chlivedo "pacman --noconfirm -S base-devel git"

    # Install basic rootfs
    for package in $(cat config/*.pkg.conf); do
        $chlivedo "pacstrap -cGM /mnt $package"
    done

    for package in $(cat config/*.aur.conf); do
        build_aur_package_rootfs $package
    done

    $chlivedo "echo '3dprinter' > /mnt/etc/hostname"
    $chlivedo "echo 'LANG=C'> /mnt/etc/locale.conf"
    $chlivedo "echo -n > /mnt/etc/machine-id"

    cp -p /usr/bin/qemu-aarch64-static $rootfs/bin/qemu-aarch64-static
    cp -p config/resize2fs.service $rootfs/usr/lib/systemd/system

    cp -p config/moonraker.conf $rootfs/etc/klipper/
    cp -p config/nginx.conf $rootfs/etc/nginx/

    cp -p  config/klipper.conf $rootfs/etc/klipper/klipper.conf

    cp -p config/usb_host.service $rootfs/usr/lib/systemd/system

    # Configure rootfs
    $chrootdo "useradd -d /home/alarm -m -U alarm"
    $chrootdo "echo -e 'root:root\nalarm:alarm' | chpasswd"
    $chrootdo "usermod -a -G wheel alarm"
    $chrootdo "systemctl enable $(cat config/services.conf)"
    $chrootdo "pacman-key --init"
    $chrootdo "pacman-key --populate archlinuxarm"

    rm -rf $livecd/bin/qemu-aarch64-static
    rm -rf $rootfs/bin/qemu-aarch64-static
}

function pack_rootfs()
{
    cp -rp firmware $rootfs/usr/lib/firmware
    umount $rootfs

    tune2fs -M / $rootimg
    e2fsck -yf -E discard $rootimg
    resize2fs -M $rootimg
    e2fsck -yf $rootimg
    zstd $rootimg -o $rootimg.zst
}

function generate_checksum()
{
    sha256sum $lk2ndimg > $lk2ndimg.sha256sum
    sha256sum $bootimg > $bootimg.sha256sum
    sha256sum $rootimg.zst > $rootimg.zst.sha256sum
}

set -ev
mkdir -p build
prepare_livecd
prepare_rootfs
config_rootfs

build_lk2nd
build_linux
make_boot
make_image

pack_rootfs
generate_checksum
