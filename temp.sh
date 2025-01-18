./cross_compile_ffmpeg_native.sh --cflags="-march=native -mtune=native -O3 -DNDEBUG" --compiler-flavors=native --libvmaf-compiler=gcc-12 --libvmaf-cuda=y

./configure --enable-pic --prefix=/media/khaoklong/New-Volume/App/Linux/ffmpeg-windows-build-helpers/sandbox/cross_compilers/native

sed -i 's/\r//' libdavs2-endian-fixes.patch

git apply /home/khaoklong/Downloads/pointerconversion.patch -p1
git apply /media/khaoklong/New-Volume/App/Linux/ffmpeg-windows-build-helpers/patches/xavs2-patch4.patch -p1

sudo apt install libgl1-mesa-dev libxcb-randr0-dev libxcb1 libxcb1-dev build-essential libxmu-dev libxi-dev libgl-dev

export PKG_CONFIG_PATH="/media/khaoklong/New-Volume/App/Linux/ffmpeg-windows-build-helpers/sandbox/cross_compilers/native/lib/pkgconfig/:/media/khaoklong/New-Volume/App/Linux/ffmpeg-windows-build-helpers/sandbox/cross_compilers/native/share/pkgconfig/$PKG_CONFIG_PATH"