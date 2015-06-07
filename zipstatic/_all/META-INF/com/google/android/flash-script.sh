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
    FILES='/system/build.prop /default.prop'
  fi
  cat $FILES 2>/dev/null | sed -n $REGEX | head -n 1
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
    restorecon $1 2>/dev/null
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
  fi
}

install_overwrite() {
  TARGET=$1
  if [ ! -f ./$TARGET ]; then
    return
  fi
  BACKUP="${1}.orig"
  NO_ORIG="${1}.no_orig"
  if [ ! -f $TARGET ]; then
    touch $NO_ORIG || exit 1
  elif [ ! -f $BACKUP -a ! -f $NO_ORIG ]; then
    mv $TARGET $BACKUP || exit 1
  fi
  cp_perm ./$TARGET $TARGET $2 $3 $4 $5
}

##########################################################################################

echo "******************************"
echo "Xposed framework installer zip"
echo "******************************"

if [ ! -f "system/xposed.prop" ]; then
  echo "! Failed: Extracted file system/xposed.prop not found!"
  exit 1
fi

echo "- Mounting /system read-write"
mount /system >/dev/null 2>&1
mount -o remount,rw /system

echo "- Checking environment"
API=$(grep_prop ro.build.version.sdk)
ABI=$(grep_prop ro.product.cpu.abi | cut -c-3)
ABI2=$(grep_prop ro.product.cpu.abi2 | cut -c-3)
ABILONG=$(grep_prop ro.product.cpu.abi)

XVERSION=$(grep_prop version system/xposed.prop)
XARCH=$(grep_prop arch system/xposed.prop)
XMINSDK=$(grep_prop minsdk system/xposed.prop)
XMAXSDK=$(grep_prop maxsdk system/xposed.prop)

XEXPECTEDSDK=$XMINSDK
if [ "$XMINSDK" != "$XMAXSDK" ]; then
  XEXPECTEDSDK="$XMINSDK-$XMAXSDK"
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
      echo "! Wrong SDK version: $API, expected $XEXPECTEDSDK"
    fi
  else
    echo "! Wrong SDK version: $API, expected $XEXPECTEDSDK"
  fi
else
  echo "! Wrong platform: $ARCH, expected: $XARCH"
fi

if [ -z $XVALID ]; then
  echo "! Please download the correct package"
  echo "! for your platform/ROM!"
  exit 1
fi

echo "- Placing files"
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
install_overwrite /system/lib/libxposed_art.so            0    0 0644
if [ $IS64BIT ]; then
  install_and_link /system/bin/app_process64              0 2000 0755 u:object_r:zygote_exec:s0
  install_overwrite /system/lib64/libart.so               0    0 0644
  install_overwrite /system/lib64/libart-compiler.so      0    0 0644
  install_overwrite /system/lib64/libart-disassembler.so  0    0 0644
  install_overwrite /system/lib64/libsigchain.so          0    0 0644
  install_overwrite /system/lib64/libxposed_art.so        0    0 0644
fi

echo "- Done"
exit 0
