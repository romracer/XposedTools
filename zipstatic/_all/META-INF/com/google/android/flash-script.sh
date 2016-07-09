##########################################################################################
#
# Xposed framework installer zip.
#
# This script installs the Xposed framework files to the system partition.
# The Xposed Installer app is needed as well to manage the installed modules.
#
##########################################################################################

grep_prop() {
  REGEX="s/^$1=//p"
  shift
  FILES=$@
  if [ -z "$FILES" ]; then
    FILES='/system/build.prop'
  fi
  cat $FILES 2>/dev/null | sed -n $REGEX | head -n 1
}

android_version() {
  case $1 in
    15) echo '4.0 / SDK'$1;;
    16) echo '4.1 / SDK'$1;;
    17) echo '4.2 / SDK'$1;;
    18) echo '4.3 / SDK'$1;;
    19) echo '4.4 / SDK'$1;;
    21) echo '5.0 / SDK'$1;;
    22) echo '5.1 / SDK'$1;;
    23) echo '6.0 / SDK'$1;;
    *)  echo 'SDK'$1;;
  esac
}

find_boot_image() {
  if [ -z "$BOOTIMAGE" ]; then
    for PARTITION in kern-a KERN-A android_boot ANDROID_BOOT kernel KERNEL boot BOOT lnx LNX; do
      BOOTIMAGE=$(readlink /dev/block/by-name/$PARTITION)
      if [ ! -z "$BOOTIMAGE" ]; then break; fi

      for BLOCKDEV in `ls /dev/block/platform/*/by-name/$PARTITION 2>/dev/null`; do
        BOOTIMAGE=$(readlink $BLOCKDEV)
        if [ ! -z "$BOOTIMAGE" ]; then break 2; fi
      done

      for BLOCKDEV in `ls /dev/block/platform/*/*/by-name/$PARTITION 2>/dev/null`; do
        BOOTIMAGE=$(readlink $BLOCKDEV)
        if [ ! -z "$BOOTIMAGE" ]; then break 2; fi
      done
    done
  fi
}

is_mounted() {
  if [ ! -z "$2" ]; then
    grep $1 /proc/mounts | grep $2, >/dev/null
  else
    grep $1 /proc/mounts >/dev/null
  fi
  return $?
}

build_boot_image() {
  if [ -z "$1" ]; then
    return
  fi

  # Build our mkbootimg command line
  CMDLINE="$PACK --kernel boot.img-zImage --ramdisk boot.img-ramdisk.gz"

  if [ -s boot.img-second ]; then
    CMDLINE="$CMDLINE --second boot.img-second"
  fi

  # Weed out any 1 byte command lines (ie. new line character only)
  KERNELCMDLINE=$(read -r line < boot.img-cmdline; printf "%s" $line)
  if [ ! -z $KERNELCMDLINE ]; then
    CMDLINE="$CMDLINE --cmdline \"$(cat boot.img-cmdline)\""
  fi

  # These are all pretty similar
  if [ -s boot.img-base ]; then
    CMDLINE="$CMDLINE --base 0x$(cat boot.img-base)"
  fi
  if [ -s boot.img-pagesize ]; then
    CMDLINE="$CMDLINE --pagesize $(cat boot.img-pagesize)"
  fi
  if [ -s boot.img-dt ]; then
    CMDLINE="$CMDLINE --dt boot.img-dt"
  fi
  if [ -s boot.img-ramdisk_offset ]; then
    CMDLINE="$CMDLINE --ramdisk_offset 0x$(cat boot.img-ramdisk_offset)"
  fi
  if [ -s boot.img-second_offset ]; then
    CMDLINE="$CMDLINE --second_offset 0x$(cat boot.img-second_offset)"
  fi
  if [ -s boot.img-tags_offset ]; then
    CMDLINE="$CMDLINE --tags_offset 0x$(cat boot.img-tags_offset)"
  fi

  # Append output target to final mkbootimg command line
  CMDLINE="$CMDLINE -o $1"
  # echo $CMDLINE
  eval $CMDLINE >/dev/null 2>&1
}

cp_perm() {
  cp -f $1 $2 || exit 1
  set_perm $2 $3 $4 $5 $6
}

set_perm() {
  chown $2:$3 $1 || exit 1
  chmod $4 $1 || exit 1
  if [ "$5" ]; then
    chcon $5 $1 2>/dev/null
  else
    chcon 'u:object_r:system_file:s0' $1 2>/dev/null
  fi
}

install_nobackup() {
  cp_perm ./$1 $1 $2 $3 $4 $5
}

install_and_link() {
  TARGET=$1
  XPOSED="${1}_xposed"
  BACKUP="${1}_original"
  if [ ! -f ./$XPOSED ]; then
    return
  fi
  cp_perm ./$XPOSED $XPOSED $2 $3 $4 $5
  if [ ! -f $BACKUP ]; then
    mv $TARGET $BACKUP || exit 1
    ln -s $XPOSED $TARGET || exit 1
    chcon -h 'u:object_r:system_file:s0' $TARGET 2>/dev/null
  fi
}

install_overwrite() {
  TARGET=$1
  if [ ! -f ./$TARGET ]; then
    return
  fi
  BACKUP="${1}.orig"
  if [ -f $BACKUP ]; then
    rm -f $TARGET
    gzip $BACKUP || exit 1
    set_perm "${BACKUP}.gz" 0 0 600
  elif [ ! -f "${BACKUP}.gz" ]; then
    mv $TARGET $BACKUP || exit 1
    gzip $BACKUP || exit 1
    set_perm "${BACKUP}.gz" 0 0 600
  fi
  cp_perm ./$TARGET $TARGET $2 $3 $4 $5
}

install_file() {
  if [ ! -f ./$BASEPATH/$1 ]; then
    return
  fi
  cp_perm ./$BASEPATH/$1 /$BASEPATH/$1 $2 $3 $4 $5
}

##########################################################################################

echo "******************************"
echo "Xposed framework installer zip"
echo "******************************"

if [ ! -f "system/xposed.prop" -a ! -f "xposed/xposed.prop" ]; then
  echo "! Failed: Extracted file xposed.prop not found!"
  exit 1
fi

BASEPATH='system'
XSYSTEMLESS=$(grep_prop systemless system/xposed.prop xposed/xposed.prop)
if [ "$XSYSTEMLESS" -eq "1" ]; then
  echo "- Systemless install detected"
  BASEPATH='xposed'
  echo "- Mounting /system read-only"
  echo "- Mounting /cache and /data read-write"
  mount -o ro /system >/dev/null 2>&1
  mount /cache >/dev/null 2>&1
  mount /data >/dev/null 2>&1
  mount -o remount,rw /cache
  mount -o remount,rw /data >/dev/null 2>&1
else
  echo "- Mounting /system read-write"
  mount /system >/dev/null 2>&1
  mount -o remount,rw /system
fi

if [ ! -f '/system/build.prop' ]; then
  echo "! Failed: /system could not be mounted!"
  exit 1
fi

echo "- Mounting /vendor read-write"
mount /vendor >/dev/null 2>&1
mount -o remount,rw /vendor >/dev/null 2>&1

echo "- Checking environment"
API=$(grep_prop ro.build.version.sdk)
APINAME=$(android_version $API)
ABI=$(grep_prop ro.product.cpu.abi | cut -c-3)
ABI2=$(grep_prop ro.product.cpu.abi2 | cut -c-3)
ABILONG=$(grep_prop ro.product.cpu.abi)

XVERSION=$(grep_prop version $BASEPATH/xposed.prop)
XARCH=$(grep_prop arch $BASEPATH/xposed.prop)
XMINSDK=$(grep_prop minsdk $BASEPATH/xposed.prop)
XMAXSDK=$(grep_prop maxsdk $BASEPATH/xposed.prop)

XEXPECTEDSDK=$(android_version $XMINSDK)
if [ "$XMINSDK" != "$XMAXSDK" ]; then
  XEXPECTEDSDK=$XEXPECTEDSDK' - '$(android_version $XMAXSDK)
fi

ARCH=arm
IS64BIT=
if [ "$ABI" = "x86" ]; then ARCH=x86; fi;
if [ "$ABI2" = "x86" ]; then ARCH=x86; fi;
if [ "$API" -ge "21" ]; then
  if [ "$ABILONG" = "arm64-v8a" ]; then ARCH=arm64; IS64BIT=1; fi;
  if [ "$ABILONG" = "x86_64" ]; then ARCH=x64; IS64BIT=1; fi;
fi

# echo "DBG [$API] [$ABI] [$ABI2] [$ABILONG] [$ARCH] [$XARCH] [$XMINSDK] [$XMAXSDK] [$XVERSION]"

echo "  Xposed version: $XVERSION"

XVALID=
if [ "$ARCH" = "$XARCH" ]; then
  if [ "$API" -ge "$XMINSDK" ]; then
    if [ "$API" -le "$XMAXSDK" ]; then
      XVALID=1
    else
      echo "! Wrong Android version: $APINAME"
      echo "! This file is for: $XEXPECTEDSDK"
    fi
  else
    echo "! Wrong Android version: $APINAME"
    echo "! This file is for: $XEXPECTEDSDK"
  fi
else
  echo "! Wrong platform: $ARCH"
  echo "! This file is for: $XARCH"
fi

if [ -z $XVALID ]; then
  echo "! Please download the correct package"
  echo "! for your platform/ROM!"
  exit 1
fi

if [ "$XSYSTEMLESS" -eq "1" ]; then
  find_boot_image
  if [ -z $BOOTIMAGE ]; then
    echo "! Unable to detect boot image"
    echo "! required for systemless mode"
    exit 1
  fi

  INITRC=$(readlink -f files/init.xposed.rc)
  MOUNTSH=$(readlink -f files/mount_xposed.sh)
  UNPACK=$(readlink -f files/unpackbootimg)
  PACK=$(readlink -f files/mkbootimg)
  chmod +x $UNPACK
  chmod +x $PACK

  if (is_mounted /data); then
    XIMG=/data/xposed.img
  else
    XIMG=/cache/xposed.img
    echo "- Data unavailable, using /cache"
    echo "******************************"
    echo "* Your device will boot loop *"
    echo "* several times after reboot *"
    echo "******************************"
  fi

  if [ -f $XIMG ]; then
    echo "- $XIMG detected"
    MKFS=0
    fsck -p $XIMG >/dev/null 2>&1
  else
    echo "- Creating $XIMG"
    MKFS=$(which make_ext4fs)
    if [ ! -z $MKFS ]; then
      make_ext4fs -l 32M -a /xposed -S ./files/file_contexts_image $XIMG >/dev/null 2>&1
    else
      touch $XIMG
      mke2fs -F -I 256 -m 0 $XIMG 32768 >/dev/null 2>&1
    fi
  fi

  echo "- Mounting $XIMG to /xposed"
  umount /xposed 2>/dev/null
  chmod 0600 $XIMG
  mkdir -m 0755 -p /xposed
  mount -t ext4 $XIMG /xposed >/dev/null 2>&1
  if (is_mounted /xposed); then
    chmod 0755 /xposed
    chcon 'u:object_r:system_file:s0' /xposed 2>/dev/null
  else
    echo "! Failed: /xposed could not be mounted!"
    exit 1
  fi
fi

echo "- Placing files"
if [ "$XSYSTEMLESS" -eq "1" ]; then
  mkdir -m 0751 -p /$BASEPATH/bin
  mkdir -m 0755 -p /$BASEPATH/framework
  mkdir -m 0755 -p /$BASEPATH/lib
  if [ $IS64BIT ]; then
    mkdir -m 0755 -p /$BASEPATH/lib64
  fi
  if [ -z $MKFS ]; then
    chcon 'u:object_r:system_file:s0' /$BASEPATH/bin 2>/dev/null
    chcon 'u:object_r:system_file:s0' /$BASEPATH/framework 2>/dev/null
    chcon 'u:object_r:system_file:s0' /$BASEPATH/lib 2>/dev/null
    chcon 'u:object_r:system_file:s0' /$BASEPATH/lib64 2>/dev/null
    chcon 'u:object_r:system_file:s0' /$BASEPATH/lost+found 2>/dev/null
    chmod 0700 /$BASEPATH/lost+found 2>/dev/null
  fi

  install_file xposed.prop                                  0    0 0644
  install_file framework/XposedBridge.jar                   0    0 0644

  install_file bin/app_process32                            0 2000 0755 u:object_r:zygote_exec:s0
  install_file bin/dex2oat                                  0 2000 0755 u:object_r:dex2oat_exec:s0
  install_file bin/oatdump                                  0 2000 0755
  install_file bin/patchoat                                 0 2000 0755 u:object_r:dex2oat_exec:s0
  install_file lib/libart.so                                0    0 0644
  install_file lib/libart-compiler.so                       0    0 0644
  install_file lib/libart-disassembler.so                   0    0 0644
  install_file lib/libsigchain.so                           0    0 0644
  install_file lib/libxposed_art.so                         0    0 0644
  if [ $IS64BIT ]; then
    install_file bin/app_process64                          0 2000 0755 u:object_r:zygote_exec:s0
    install_file lib64/libart.so                            0    0 0644
    install_file lib64/libart-compiler.so                   0    0 0644
    install_file lib64/libart-disassembler.so               0    0 0644
    install_file lib64/libsigchain.so                       0    0 0644
    install_file lib64/libxposed_art.so                     0    0 0644
  fi
else
  install_nobackup /system/xposed.prop                      0    0 0644
  install_nobackup /system/framework/XposedBridge.jar       0    0 0644

  install_and_link /system/bin/app_process32                0 2000 0755 u:object_r:zygote_exec:s0
  install_overwrite /system/bin/dex2oat                     0 2000 0755 u:object_r:dex2oat_exec:s0
  install_overwrite /system/bin/oatdump                     0 2000 0755
  install_overwrite /system/bin/patchoat                    0 2000 0755 u:object_r:dex2oat_exec:s0
  install_overwrite /system/lib/libart.so                   0    0 0644
  install_overwrite /system/lib/libart-compiler.so          0    0 0644
  install_overwrite /system/lib/libart-disassembler.so      0    0 0644
  install_overwrite /system/lib/libsigchain.so              0    0 0644
  install_nobackup  /system/lib/libxposed_art.so            0    0 0644
  if [ $IS64BIT ]; then
    install_and_link /system/bin/app_process64              0 2000 0755 u:object_r:zygote_exec:s0
    install_overwrite /system/lib64/libart.so               0    0 0644
    install_overwrite /system/lib64/libart-compiler.so      0    0 0644
    install_overwrite /system/lib64/libart-disassembler.so  0    0 0644
    install_overwrite /system/lib64/libsigchain.so          0    0 0644
    install_nobackup  /system/lib64/libxposed_art.so        0    0 0644
  fi
fi

if [ "$API" -ge "22" ]; then
  find /vendor -type f -name '*.odex.gz' 2>/dev/null | while read f; do mv "$f" "$f.xposed"; done
  if [ "$XSYSTEMLESS" -ne "1" ]; then
    find /system -type f -name '*.odex.gz' 2>/dev/null | while read f; do mv "$f" "$f.xposed"; done
  fi
fi

if [ "$XSYSTEMLESS" -eq "1" ]; then
  echo " "
  echo "******************"
  echo "Boot image patcher"
  echo "******************"

  echo "- Found Boot Image: $BOOTIMAGE"
  rm -f /tmp/boot.img
  dd if=$BOOTIMAGE of=/tmp/boot.img >/dev/null 2>&1

  echo "- Patching ramdisk"
  rm -rf /tmp/xposed-boot
  mkdir -p /tmp/xposed-boot
  $UNPACK -i /tmp/boot.img -o /tmp/xposed-boot >/dev/null 2>&1
  cd /tmp/xposed-boot

  if [ ! -s boot.img-ramdisk.gz ]; then
    echo "! Unknown boot image or ramdisk format"
    exit 1
  fi

  gunzip -c < boot.img-ramdisk.gz > ramdisk
  rm -f boot.img-ramdisk.gz
  rm -rf xposed-bootroot
  mkdir xposed-bootroot
  cd xposed-bootroot
  cpio -d -F ../ramdisk -i >/dev/null 2>&1
  rm -f ../ramdisk

  mkdir -m 0755 -p xposed
  chcon 'u:object_r:system_file:s0' xposed 2>/dev/null
  mkdir -m 0750 -p sbin
  cp_perm $INITRC init.xposed.rc 0 0 750 u:object_r:rootfs:s0
  cp_perm $MOUNTSH sbin/mount_xposed.sh 0 0 700 u:object_r:rootfs:s0

  if [ $(grep -c 'import /init.xposed.rc' init.rc) == 0 ]; then
    sed -i '/import \/init\.environ\.rc/iimport /init.xposed.rc' init.rc
  fi

  echo "- Building new boot image"
  find . | cpio -o -H newc | gzip > ../boot.img-ramdisk.gz
  cd ..
  rm -rf xposed-bootroot
  rm -f new-boot.img
  build_boot_image new-boot.img

  if [ ! -s new-boot.img ]; then
    echo "! Failed: Building new boot image"
    exit 1
  fi

  mv new-boot.img /tmp/new_boot.img
  cd /tmp
  rm -rf /tmp/xposed-boot

  echo "- Flashing new boot image"
  dd if=/tmp/new_boot.img of=$BOOTIMAGE >/dev/null 2>&1
  rm -f /tmp/new_boot.img /tmp/boot.img
fi

umount /xposed 2>/dev/null
umount /system 2>/dev/null
umount /vendor 2>/dev/null

echo "- Done"
exit 0
