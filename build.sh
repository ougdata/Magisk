#!/bin/bash

usage() {
  echo "$0 all <version name>"
  echo -e "\tBuild binaries, zip, and sign Magisk"
  echo -e "\tThis is equlivant to first --build, then --zip"
  echo "$0 clean"
  echo -e "\tCleanup compiled / generated files"
  echo "$0 build"
  echo -e "\tBuild the binaries with ndk"
  echo "$0 zip <version name>"
  echo -e "\tZip and sign Magisk"
  echo "$0 uninstaller"
  echo -e "\tZip and sign the uninstaller"
  exit 1
}

cleanup() {
  echo "************************"
  echo "* Cleaning up"
  echo "************************"
  ndk-build clean 2>/dev/null
  ls zip_static/arm/* | grep -v "busybox" | xargs rm -rfv
  ls zip_static/arm64/* | grep -v "busybox" | xargs rm -rfv
  ls zip_static/x86/* | grep -v "busybox" | xargs rm -rfv
  ls zip_static/x64/* | grep -v "busybox" | xargs rm -rfv
  rm -rfv zip_static/META-INF/com/google/android/update-binary 
  rm -rfv zip_static/common/magic_mask.sh
  rm -rfv uninstaller/arm
  rm -rfv uninstaller/arm64
  rm -rfv uninstaller/x86
  rm -rfv uninstaller/x64
}

mkcp() {
  [ ! -d "$2" ] && mkdir -p "$2"
  cp -afv $1 $2
}

build_bin() {
  echo "************************"
  echo "* Building binaries"
  echo "************************"
  if [ -z `which ndk-build` ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "! Please add ndk-build to PATH!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
  fi
  ndk-build -j4
  if [ $? -ne 0 ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "! Magisk binary tools build failed...."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
  fi
  echo "************************"
  echo "* Copying binaries"
  echo "************************"
  mkcp "libs/armeabi/*" zip_static/arm
  mkcp libs/armeabi/bootimgtools uninstaller/arm
  mkcp "libs/arm64-v8a/*" zip_static/arm64
  mkcp libs/arm64-v8a/bootimgtools uninstaller/arm64
  mkcp "libs/x86/*" zip_static/x86
  mkcp libs/x86/bootimgtools uninstaller/x86
  mkcp "libs/x86_64/*" zip_static/x64
  mkcp libs/x86_64/bootimgtools uninstaller/x64
}

zip_package() {
  if [ ! -f "zip_static/arm/bootimgtools" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "! Missing binaries!!"
    echo "! Please run \"$0 build\" before zipping"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
  fi
  echo "************************"
  echo "* Adding version info"
  echo "************************"
  sed "s/MAGISK_VERSION_STUB/Magisk v$1 Boot Image Patcher/g" scripts/flash_script.sh > zip_static/META-INF/com/google/android/update-binary
  sed "s/MAGISK_VERSION_STUB/setprop magisk.version \"$1\"/g" scripts/magic_mask.sh > zip_static/common/magic_mask.sh
  echo "************************"
  echo "* Zipping Magisk v$1"
  echo "************************"
  cd zip_static
  find . -type f -exec chmod 644 {} \;
  find . -type d -exec chmod 755 {} \;
  rm -rf "../Magisk-v$1.zip"
  zip "../Magisk-v$1.zip" -r .
  cd ../
  sign_zip "Magisk-v$1.zip"
}

zip_uninstaller() {
  if [ ! -f "uninstaller/arm/bootimgtools" ]; then
    echo "! Missing binaries!!"
    echo "! Please run \"$0 build\" before zipping"
    exit 1
  fi
  echo "************************"
  echo "* Zipping uninstaller"
  echo "************************"
  cd uninstaller
  find . -type f -exec chmod 644 {} \;
  find . -type d -exec chmod 755 {} \;
  TIMESTAMP=$(date "+%Y%m%d")
  rm -rf "../Magisk-uninstaller-$TIMESTAMP.zip"
  zip "../Magisk-uninstaller-$TIMESTAMP.zip" -r .
  cd ../
  sign_zip "Magisk-uninstaller-$TIMESTAMP.zip"
}

sign_zip() {
  if [ ! -f "zipsigntools/zipadjust" ]; then
    echo "************************"
    echo "* Compiling ZipAdjust"
    echo "************************"
    gcc -o zipsigntools/zipadjust zipsigntools/src/*.c -lz
    if [ $? -ne 0 ]; then
      echo "!!!!!!!!!!!!!!!!!!!!!!!!"
      echo "! ZipAdjust Build failed...."
      echo "!!!!!!!!!!!!!!!!!!!!!!!!"
      exit 1
    fi
    chmod 755 zipsigntools/zipadjust
  fi
  echo "************************"
  echo "* First sign $1"
  echo "************************"
  java -jar "zipsigntools/signapk.jar" "zipsigntools/test.certificate.x509.pem" "zipsigntools/test.key.pk8" "$1" "${1%.*}-firstsign.zip"
  echo "************************"
  echo "* Adjusting $1"
  echo "************************"
  zipsigntools/zipadjust "${1%.*}-firstsign.zip" "${1%.*}-adjusted.zip"
  echo "************************"
  echo "* Final sign $1"
  echo "************************"
  java -jar "zipsigntools/signapk.jar" "zipsigntools/test.certificate.x509.pem" "zipsigntools/test.key.pk8" "${1%.*}-adjusted.zip" "${1%.*}-signed.zip"

  mv "${1%.*}-signed.zip" "$1"
  rm "${1%.*}-adjusted.zip" "${1%.*}-firstsign.zip"
}

DIR="$(cd "$(dirname "$0")"; pwd)"
cd "$DIR"

case $1 in
  "all" )
    [ -z "$2" ] && echo -e "! Missing version number\n" && usage
    build_bin
    zip_package $2
    ;;
  "clean" )
    cleanup
    ;;
  "build" )
    build_bin
    ;;
  "zip" )
    [ -z "$2" ] && echo -e "! Missing version number\n" && usage
    zip_package $2
    ;;
  "uninstaller" )
    zip_uninstaller
    ;;
  * )
    usage
    ;;
esac
