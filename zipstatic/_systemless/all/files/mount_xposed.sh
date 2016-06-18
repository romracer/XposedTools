#!/system/bin/sh

log_xposed() {
  echo $1
  log -p i -t Xposed "mount_xposed: $1"
}

loopsetup() {
  LOOPDEVICE=
  for DEV in $(ls /dev/block/loop*); do
    LS=$(losetup $DEV $1 2>/dev/null)
    if [ $? -eq 0 ]; then
      LOOPDEVICE=$DEV
      break
    fi
  done
}

bind_mount() {
  if [ -f "/xposed/$1" ]; then
    mount -o bind /xposed/$1 /system/$1
    if [ "$?" -eq "0" ]; then log_xposed "/xposed/$1 -> /system/$1"; fi
  fi
}

if [ "$1" == "-cache" ]; then
  if [ -f "/cache/xposed.img" ]; then
    log_xposed "/cache/xposed.img found!"
    if [ -f "/data/xposed.img" ]; then
      log_xposed "/data/xposed.img found! Start merging"
      umount /xposed
      mkdir /cache/xposed_cache
      mkdir /cache/xposed_data
      loopsetup /cache/xposed.img
      if [ ! -z "$LOOPDEVICE" ]; then
        mount -t ext4 -o rw,noatime $LOOPDEVICE /cache/xposed_cache
      fi
      loopsetup /data/xposed.img
      if [ ! -z "$LOOPDEVICE" ]; then
        mount -t ext4 -o rw,noatime $LOOPDEVICE /cache/xposed_data
      fi
      cp -af /cache/xposed_cache/. /cache/xposed_data
      chcon u:object_r:system_file:s0 /cache/xposed_data
      chcon u:object_r:system_file:s0 /cache/xposed_data/bin
      chcon u:object_r:system_file:s0 /cache/xposed_data/framework
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib64
      chcon u:object_r:system_file:s0 /cache/xposed_data/xposed.prop
      chcon u:object_r:zygote_exec:s0 /cache/xposed_data/bin/app_process32
      chcon u:object_r:zygote_exec:s0 /cache/xposed_data/bin/app_process64
      chcon u:object_r:dex2oat_exec:s0 /cache/xposed_data/bin/dex2oat
      chcon u:object_r:system_file:s0 /cache/xposed_data/bin/oatdump
      chcon u:object_r:dex2oat_exec:s0 /cache/xposed_data/bin/patchoat
      chcon u:object_r:system_file:s0 /cache/xposed_data/framework/XposedBridge.jar
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib/libart.so
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib/libart-compiler.so
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib/libsigchain.so
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib/libxposed_art.so
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib64/libart.so
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib64/libart-disassembler.so
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib64/libsigchain.so
      chcon u:object_r:system_file:s0 /cache/xposed_data/lib64/libxposed_art.so
      umount /cache/xposed_cache
      umount /cache/xposed_data
      rm -rf /cache/xposed.img /cache/xposed_cache /cache/xposed_data
    else
      log_xposed "/data/xposed.img not found! Move from /cache to /data"
      mv /cache/xposed.img /data/xposed.img
    fi
    reboot
  fi
  exit 0
fi

if [ "$(getprop xposed.mount)" -eq "0" ]; then
  grep /xposed /proc/mounts >/dev/null
  if [ "$?" -ne "0" ]; then
    if [ -f "/data/xposed.img" ]; then
      log_xposed "init image mount failed! Use manual loop mount"
      e2fsck -p /data/xposed.img
      chcon u:object_r:system_data_file:s0 /data/xposed.img
      chmod 0600 /data/xposed.img
      loopsetup /data/xposed.img
      if [ ! -z "$LOOPDEVICE" ]; then
        mount -t ext4 -o rw,noatime $LOOPDEVICE /xposed
        grep /xposed /proc/mounts >/dev/null
        if [ "$?" -eq "0" ]; then log_xposed "Manual loop mount success!"; fi
      fi
    else
      log_xposed "/data/xposed.img not found! Nothing to do"
      exit 1
    fi
  else
    log_xposed "init image mount success!"
  fi

  grep /xposed /proc/mounts >/dev/null
  if [ "$?" -eq "0" ]; then
    log_xposed "Bind mount start"
    if [ ! -f /data/data/de.robv.android.xposed.installer/conf/disabled ]; then
      bind_mount bin/app_process32
      bind_mount bin/app_process64
    fi
    bind_mount bin/dex2oat
    bind_mount bin/oatdump
    bind_mount bin/patchoat
    bind_mount lib/libart.so
    bind_mount lib/libart-compiler.so
    bind_mount lib/libsigchain.so
    bind_mount lib64/libart.so
    bind_mount lib64/libart-disassembler.so
    bind_mount lib64/libsigchain.so
    # Prevent double bind mount
    setprop xposed.mount 1
  else
    log_xposed "init image mount still fails!"
  fi
fi
