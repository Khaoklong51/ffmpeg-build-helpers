#!/usr/bin/env bash
# ffmpeg windows cross compile helper/download script, see github repo README
# Copyright (C) 2012 Roger Pack, the script is under the GPLv3, but output FFmpeg's executables aren't
# set -x

source ./download_link.sh

find_all_build_exes() {
  local found=""
# NB that we're currently in the sandbox dir...
  for file in `find . -name ffmpeg.exe` `find . -name ffmpeg_g.exe` `find . -name ffplay.exe` `find . -name ffmpeg` `find . -name ffplay` `find . -name ffprobe` `find . -name MP4Box.exe` `find . -name mplayer.exe` `find . -name mencoder.exe` `find . -name avconv.exe` `find . -name avprobe.exe` `find . -name x264.exe` `find . -name writeavidmxf.exe` `find . -name writeaviddv50.exe` `find . -name rtmpdump.exe` `find . -name x265.exe` `find . -name ismindex.exe` `find . -name dvbtee.exe` `find . -name boxdumper.exe` `find . -name muxer.exe ` `find . -name remuxer.exe` `find . -name timelineeditor.exe` `find . -name lwcolor.auc` `find . -name lwdumper.auf` `find . -name lwinput.aui` `find . -name lwmuxer.auf` `find . -name vslsmashsource.dll`; do
    found="$found $(readlink -f $file)"
  done

  # bash recursive glob fails here again?
  for file in `find . -name vlc.exe | grep -- -`; do
    found="$found $(readlink -f $file)"
  done
  echo $found # pseudo return value...
}

yes_no_sel () {
  unset user_input
  local question="$1"
  shift
  local default_answer="$1"
  while [[ "$user_input" != [YyNn] ]]; do
    echo -n "$question"
    read user_input
    if [[ -z "$user_input" ]]; then
      echo "using default $default_answer"
      user_input=$default_answer
    fi
    if [[ "$user_input" != [YyNn] ]]; then
      clear; echo 'Your selection was not vaild, please try again.'; echo
    fi
  done
  # downcase it
  user_input=$(echo $user_input | tr '[A-Z]' '[a-z]')
}

set_box_memory_size_bytes() {
  local ram_kilobytes=`grep MemTotal /proc/meminfo | awk '{print $2}'`
  local swap_kilobytes=`grep SwapTotal /proc/meminfo | awk '{print $2}'`
  box_memory_size_bytes=$[ram_kilobytes * 1024 + swap_kilobytes * 1024]
}

function sortable_version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

at_least_required_version() { # params: required actual
  local sortable_required=$(sortable_version $1)
  sortable_required=$(echo $sortable_required | sed 's/^0*//') # remove preceding zeroes, which bash later interprets as octal or screwy
  local sortable_actual=$(sortable_version $2)
  sortable_actual=$(echo $sortable_actual | sed 's/^0*//')
  [[ "$sortable_actual" -ge "$sortable_required" ]]
}

apt_not_installed() {
  for x in "$@"; do
    if ! dpkg -l "$x" | grep -q '^.i'; then
      need_install="$need_install $x"
    fi
  done
  echo "$need_install"
}

determine_distro() {

# Determine OS platform from https://askubuntu.com/a/459425/20972
UNAME=$(uname | tr "[:upper:]" "[:lower:]")
# If Linux, try to determine specific distribution
if [ "$UNAME" == "linux" ]; then
    # If available, use LSB to identify distribution
    if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
        export DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
    # Otherwise, use release info file
    else
        export DISTRO=$(grep '^ID' /etc/os-release | sed 's#.*=\(\)#\1#')
    fi
fi
# For everything else (or if above failed), just use generic identifier
[ "$DISTRO" == "" ] && export DISTRO=$UNAME
unset UNAME
}


intro() {
  cat <<EOL
     ##################### Welcome ######################
  Welcome to the ffmpeg cross-compile builder-helper script.
  Downloads and builds will be installed to directories within $cur_dir
  If this is not ok, then exit now, and cd to the directory where you'd
  like them installed, then run this script again from there.
  NB that once you build your compilers, you can no longer rename/move
  the sandbox directory, since it will have some hard coded paths in there.
  You can, of course, rebuild ffmpeg from within it, etc.
EOL
  echo `date` # for timestamping super long builds LOL
  if [[ $sandbox_ok != 'y' && ! -d sandbox ]]; then
    echo
    echo "Building in $PWD/sandbox, will use ~ 12GB space!"
    echo
  fi
  mkdir -p "$cur_dir"
  cd "$cur_dir"
  non_free="$user_input" # save it away
  echo "sit back, this may take awhile..."
}

pick_compiler_flavors() {
  while [[ "$compiler_flavors" != [1-2] ]]; do
    if [[ -n "${unknown_opts[@]}" ]]; then
      echo -n 'Unknown option(s)'
      for unknown_opt in "${unknown_opts[@]}"; do
        echo -n " '$unknown_opt'"
      done
      echo ', ignored.'; echo
    fi
    cat <<'EOF'
What version of MinGW-w64 would you like to build or update?
  1. Local native
  2. Exit
EOF
    echo -n 'Input your choice [1-2]: '
    read compiler_flavors
  done
  case "$compiler_flavors" in
  1 ) compiler_flavors=native ;;
  2 ) echo "exiting"; exit 0 ;;
  * ) clear;  echo 'Your choice was not valid, please try again.'; echo ;;
  esac
}


# helper methods for downloading and building projects that can take generic input

do_svn_checkout() {
  repo_url="$1"
  to_dir="$2"
  desired_revision="$3"
  if [ ! -d $to_dir ]; then
    echo "svn checking out to $to_dir"
    if [[ -z "$desired_revision" ]]; then
      svn checkout $repo_url $tliblive555_URLo_dir.tmp  --non-interactive --trust-server-cert || exit 1
    else
      svn checkout -r $desired_revision $repo_url $to_dir.tmp || exit 1
    fi
    mv $to_dir.tmp $to_dir
  else
    cd $to_dir
    echo "not svn Updating $to_dir since usually svn repo's aren't updated frequently enough..."
    # XXX accomodate for desired revision here if I ever uncomment the next line...
    # svn up
    cd ..
  fi
}

# params: git url, to_dir
retry_git_or_die() {  # originally from https://stackoverflow.com/a/76012343/32453
  local RETRIES_NO=50
  local RETRY_DELAY=3
  local repo_url=$1
  local to_dir=$2

  for i in $(seq 1 $RETRIES_NO); do
   echo "Downloading (via git clone) $to_dir from $repo_url"
   rm -rf $to_dir.tmp # just in case it was interrupted previously...not sure if necessary...
   git clone $repo_url $to_dir.tmp --recurse-submodules && break
   # get here -> failure
   [[ $i -eq $RETRIES_NO ]] && echo "Failed to execute git cmd $repo_url $to_dir after $RETRIES_NO retries" && exit 1
   echo "sleeping before retry git"
   sleep ${RETRY_DELAY}
  done
  # prevent partial checkout confusion by renaming it only after success
  mv $to_dir.tmp $to_dir
  echo "done git cloning to $to_dir"
}

do_git_checkout() {
  local repo_url="$1"
  local to_dir="$2"
  if [[ -z $to_dir ]]; then
    to_dir=$(basename $repo_url | sed s/\.git/-git/) # http://y/abc.git -> abc_git
  fi
  local desired_branch="$3"
  if [ ! -d $to_dir ]; then
    retry_git_or_die $repo_url $to_dir
    cd $to_dir
  else
    cd $to_dir
    if [[ $git_get_latest = "y" ]]; then
      git fetch # want this for later...
    else
      echo "not doing git get latest pull for latest code $to_dir" # too slow'ish...
    fi
  fi

  # reset will be useless if they didn't git_get_latest but pretty fast so who cares...plus what if they changed branches? :)
  old_git_version=`git rev-parse HEAD`
  if [[ -z $desired_branch ]]; then
	# Check for either "origin/main" or "origin/master".
	if [ $(git show-ref | grep -e origin\/main$ -c) = 1 ]; then
		desired_branch="origin/main"
	elif [ $(git show-ref | grep -e origin\/master$ -c) = 1 ]; then
		desired_branch="origin/master"
	else
		echo "No valid git branch!"
		exit 1
	fi
  fi
  echo "doing git checkout $desired_branch"
  git -c 'advice.detachedHead=false' checkout "$desired_branch" || (git_hard_reset && git -c 'advice.detachedHead=false' checkout "$desired_branch") || (git reset --hard "$desired_branch") || exit 1 # can't just use merge -f because might "think" patch files already applied when their changes have been lost, etc...
  # vmaf on 16.04 needed that weird reset --hard? huh?
  if git show-ref --verify --quiet "refs/remotes/origin/$desired_branch"; then # $desired_branch is actually a branch, not a tag or commit
    git merge "origin/$desired_branch" || exit 1 # get incoming changes to a branch
  fi
  new_git_version=`git rev-parse HEAD`
  if [[ "$old_git_version" != "$new_git_version" ]]; then
    echo "got upstream changes, forcing re-configure. Doing git clean"
    git_hard_reset
  else
    echo "fetched no code changes, not forcing reconfigure for that..."
  fi
  cd ..
}

git_hard_reset() {
  git reset --hard # throw away results of patch files
  git clean -fx # throw away local changes; 'already_*' and bak-files for instance.
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
  local beginning="$1"
  local extra_stuff="$2"
  local touch_name="${beginning}_$(echo -- $extra_stuff $CFLAGS $LDFLAGS | /usr/bin/env md5sum)" # md5sum to make it smaller, cflags to force rebuild if changes
  touch_name=$(echo "$touch_name" | sed "s/ //g") # md5sum introduces spaces, remove them
  echo "$touch_name" # bash cruddy return system LOL
}

do_configure() {
  local configure_options="$1"
  local configure_name="$2"
  if [[ -z $configure_name ]]; then
    local configure_name="./configure"
  fi
  local cur_dir2=$(pwd)
  local english_name=$(basename $cur_dir2)
  local touch_name=$(get_small_touchfile_name already_configured "$configure_options $configure_name")
  if [ ! -f "$touch_name" ]; then
    # make uninstall # does weird things when run under ffmpeg src so disabled for now...
    echo "configuring $english_name ($PWD) as $ PKG_CONFIG_PATH=$PKG_CONFIG_PATH PATH=$mingw_bin_path:\$PATH $configure_name $configure_options" # say it now in case bootstrap fails etc.
    echo "all touch files" already_configured* touchname= "$touch_name"
    echo "config options "$configure_options $configure_name""
    if [ -f bootstrap ]; then
      ./bootstrap # some need this to create ./configure :|
    fi
    if [[ ! -f $configure_name && -f bootstrap.sh ]]; then # fftw wants to only run this if no configure :|
      ./bootstrap.sh
    fi
    if [[ -f autogen.sh ]]; then #  libcdio need this ? 
      ./autogen.sh
    fi
    if [[ ! -f $configure_name ]]; then
      echo "running autoreconf to generate configure file for us..."
      autoreconf -fiv # a handful of them require this to create ./configure :|
    fi
    rm -f already_* # reset
    chmod u+x "$configure_name" # In non-windows environments, with devcontainers, the configuration file doesn't have execution permissions
    nice -n 5 "$configure_name" $configure_options || { echo "failed configure $english_name"; exit 1;} # less nicey than make (since single thread, and what if you're running another ffmpeg nice build elsewhere?)
    touch -- "$touch_name"
    echo "doing preventative make clean"
    nice make clean -j $cpu_count # sometimes useful when files change, etc.
  #else
  #  echo "already configured $(basename $cur_dir2)"
  fi
}

do_make() {
  local extra_make_options="$1"
  extra_make_options="$extra_make_options -j $cpu_count"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "$extra_make_options" )

  if [ ! -f $touch_name ]; then
    echo
    echo "Making $cur_dir2 as $ PATH=$mingw_bin_path:\$PATH make $extra_make_options"
    echo
    if [ ! -f configure ]; then
      nice make clean -j $cpu_count # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
    fi
    nice make $extra_make_options || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "Already made $(dirname "$cur_dir2") $(basename "$cur_dir2") ..."
  fi
}

do_make_and_make_install() {
  local extra_make_options="$1"
  do_make "$extra_make_options"
  do_make_install "$extra_make_options"
}

do_make_install() {
  local extra_make_install_options="$1"
  local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
  if [[ -z $override_make_install_options ]]; then
    local make_install_options="install $extra_make_install_options -j$cpu_count"
  else
    local make_install_options="$override_make_install_options $extra_make_install_options"
  fi
  local touch_name=$(get_small_touchfile_name already_ran_make_install "$make_install_options")
  if [ ! -f $touch_name ]; then
    echo "make installing $(pwd) as $ PATH=$mingw_bin_path:\$PATH make $make_install_options"
    nice make $make_install_options || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake() {
  extra_args="$1"
  local build_from_dir="$2"
  local compiler_choice="$3"
  if [[ -z $build_from_dir ]]; then
    build_from_dir="."
  fi
  local touch_name=$(get_small_touchfile_name already_ran_cmake "$extra_args")
  if [ ! -f $touch_name ]; then
    rm -f already_* # reset so that make will run again if option just changed
    rm -rf build-sandbox # reset some require this
    local cur_dir2=$(pwd)
    echo doing cmake in $cur_dir2 with PATH=$mingw_bin_path:\$PATH with extra_args=$extra_args like this:
    local command="$build_from_dir -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix -G Ninja -B build-sandbox -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release -DENABLE_STATIC_RUNTIME=1 $extra_args"
    echo "doing cmake $command"
    nice -n 5  cmake $command || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake_from_build_dir() { # some sources don't allow it, weird XXX combine with the above :)
  source_dir="$1"
  extra_args="$2"
  do_cmake "$extra_args" "$source_dir"
}

do_cmake_and_install() {
  do_cmake "$1"
  do_ninja_and_ninja_install
}

do_meson() {
    local configure_options="$1 --unity=off"
    local configure_name="$2"
    if [[ -z $configure_name ]]; then
      local configure_name="meson setup build-sandbox"
    fi
    local configure_env="$3"
    local configure_noclean=""
    local cur_dir2=$(pwd)
    local meson_config="--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib --buildtype=release --default-library=static"
    local english_name=$(basename $cur_dir2)
    local touch_name=$(get_small_touchfile_name already_built_meson "$configure_options $configure_name $LDFLAGS $CFLAGS")
    if [ ! -f "$touch_name" ]; then
        if [ "$configure_noclean" != "noclean" ]; then
            ninja -C build-sandbox clean # just in case
        fi
        rm -f already_* # reset
        rm -rf build-sandbox # reset
        echo "Using meson: $english_name ($PWD) as $ PATH=$PATH ${configure_env} $configure_name $configure_options $meson_config"
        #env
        $configure_name $configure_options $meson_config || exit 1
        touch -- "$touch_name"
        ninja -C build-sandbox clean # just in case
    else
        echo "Already used meson $(basename $cur_dir2)"
    fi
}

generic_meson() {
    local extra_configure_options="$1"
    mkdir -pv build
    do_meson "--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib --buildtype=release --default-library=static --cross-file=${top_dir}/meson-cross.mingw.txt $extra_configure_options"
}

generic_meson_ninja_install() {
    generic_meson "$1"
    do_ninja_and_ninja_install
}

do_ninja_and_ninja_install() {
    local extra_ninja_options="$1"
    do_ninja "$extra_ninja_options"
    local touch_name=$(get_small_touchfile_name already_ran_ninja_install "$extra_ninja_options")
    if [ ! -f $touch_name ]; then
        echo "ninja installing $(pwd) as $PATH=$PATH ninja -C build-sandbox install $extra_make_options"
        ninja -C build-sandbox install || exit 1
        touch $touch_name || exit 1
    fi
}

do_ninja() {
  local extra_make_options=" -j $cpu_count"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_ninja "${extra_make_options}")

  if [ ! -f $touch_name ]; then
    echo "ninja-ing $cur_dir2 as $ PATH=$PATH ninja -C build-sandbox "${extra_make_options}""
    ninja -C build-sandbox $extra_make_options || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "already did ninja $(basename "$cur_dir2")"
  fi
}

do_cargo() {
  local build_type=$1
  local extra_cargo_option="$2 --release"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_cargo "${extra_cargo_option}")

  if [[ -z $build_type ]]; then
    build_type="build"
  fi  # Closing the missing 'if' block

  if [ ! -f "$touch_name" ]; then
    cargo clean
    local cargo_command="cargo $build_type $extra_cargo_option"
    echo "cargo compiling $cur_dir2 as PATH=$PATH $cargo_command"
    $cargo_command || exit 1
    touch "$touch_name"
  else
    echo "already done cargo build $(basename "$cur_dir2")"
  fi
}

do_cargo_install() {
  local install_type=$1
  local extra_cargo_option="$2 --release "
  local cur_dir=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_cargo_install "$extra_cargo_option")

  # Set default install type and prefix
  if [[ -z $install_type ]]; then
    install_type="install"
    prefix_type="--root=$mingw_w64_x86_64_prefix"
  elif [[ $install_type == "cinstall" ]]; then
    prefix_type="--prefix=$mingw_w64_x86_64_prefix"
  fi

  # Add prefix to extra options
  extra_cargo_option+="$prefix_type"

  # Check if already installed
  if [ ! -f "$touch_name" ]; then
    cargo clean # reset
    local cargo_command="cargo $install_type $extra_cargo_option"
    echo "Executing: $cargo_command"
    $cargo_command || exit 1
    touch "$touch_name"
  else
    echo "Cargo install already completed for $(basename "$cur_dir")"
  fi
}

do_cargo_and_cargo_install() {
  do_cargo "$1"
  do_cargo_install "$2"
}

apply_patch() {
  local url=$1 # if you want it to use a local file instead of a url one [i.e. local file with local modifications] specify it like file://localhost/full/path/to/filename.patch
  local patch_type=$2
  local not_git=$3
  if [[ -z $patch_type ]]; then
    patch_type="-p0" # some are -p1 unfortunately, git's default
  fi
  local patch_name=$(basename "$url")
  local patch_done_name="$patch_name.done"
  if [[ ! -e $patch_done_name ]]; then
    if [[ -f $patch_name ]]; then
      rm $patch_name || exit 1 # remove old version in case it has been since updated on the server...
    fi

    local curl_command="curl -4 --retry 5 $url -O --fail"
    echo "doing curl: $curl_command"
    
    $curl_command || echo_and_exit "unable to download patch file $url"
    
    echo "applying patch $patch_name"
    if [[ -z $not_git ]]; then
      git apply $patch_type < "$patch_name" || exit 1
    else
      patch $patch_type < "$patch_name" || exit 1
    fi
    touch $patch_done_name || exit 1
  fi
}


echo_and_exit() {
  echo "failure, exiting: $1"
  exit 1
}

# takes a url, output_dir as params, output_dir optional
download_and_unpack_file() {
  url="$1"
  output_name=$(basename $url)
  output_dir="$2"
  if [[ -z $output_dir ]]; then
    output_dir=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx
  fi
  if [ ! -f "$output_dir/unpacked.successfully" ]; then
    echo "downloading $url" # redownload in case failed...
    if [[ -f $output_name ]]; then
      rm $output_name || exit 1
    fi

    #  From man curl
    #  -4, --ipv4
    #  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
    #  this option tells curl to resolve names to IPv4 addresses only.
    #  avoid a "network unreachable" error in certain [broken Ubuntu] configurations a user ran into once
    #  -L means "allow redirection" or some odd :|

    curl -4 "$url" --retry 50 -O -L --fail || echo_and_exit "unable to download $url"
    echo "unzipping $output_name ..."
    tar -xf "$output_name" || unzip "$output_name" || exit 1
    touch "$output_dir/unpacked.successfully" || exit 1
    rm "$output_name" || exit 1
  fi
}

generic_configure() {
  local extra_configure_options="$1"
  do_configure "--prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static $extra_configure_options"
}

# params: url, optional "english name it will unpack to"
generic_download_and_make_and_install() {
  local url="$1"
  local english_name="$2"
  if [[ -z $english_name ]]; then
    english_name=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
  fi
  local extra_configure_options="$3"
  download_and_unpack_file $url $english_name
  cd $english_name || exit "unable to cd, may need to specify dir it will unpack to as parameter"
  generic_configure "$extra_configure_options"
  do_make_and_make_install
  cd ..
}

do_git_checkout_and_make_install() {
  local url=$1
  local git_checkout_name=$(basename $url | sed s/\.git/-git/) # http://y/abc.git -> abc-git
  do_git_checkout $url $git_checkout_name
  cd $git_checkout_name
    generic_configure_make_install
  cd ..
}

generic_configure_make_install() {
  if [ $# -gt 0 ]; then
    echo "cant pass parameters to this method today, they'd be a bit ambiguous"
    echo "The following arguments where passed: ${@}"
    exit 1
  fi
  generic_configure # no parameters, force myself to break it up if needed
  do_make_and_make_install
}

gen_ld_script() {
  lib=$mingw_w64_x86_64_prefix/lib/$1
  lib_s="$2"g
  if [[ ! -f $mingw_w64_x86_64_prefix/lib/lib$lib_s.a ]]; then
    echo "Generating linker script $lib: $2 $3"
    mv -f $lib $mingw_w64_x86_64_prefix/lib/lib$lib_s.a
    echo "GROUP ( -l$lib_s $3 )" > $lib
  fi
}

build_dlfcn() {
  do_git_checkout $dlfcn_git dlfcn-win32-git
  cd dlfcn-win32-git
    if [[ ! -f Makefile.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/-O3/-O2/" Makefile
    fi
    do_configure "--prefix=$mingw_w64_x86_64_prefix" # rejects some normal cross compile options so custom here
    do_make_and_make_install
    gen_ld_script libdl.a dl_s -lpsapi # dlfcn-win3g2's 'README.md': "If you are linking to the static 'dl.lib' or 'libdl.a', then you would need to explicitly add 'psapi.lib' or '-lpsapi' to your linking command, depending on if MinGW is used."
  cd ..
}

build_bzip2() {
  do_git_checkout $bzip2_git bzip2-git
  cd bzip2-git
    do_cmake "-DENABLE_SHARED_LIB=OFF -DENABLE_STATIC_LIB=ON -DENABLE_DOCS=OFF"
    do_ninja_and_ninja_install
    ln -s "${mingw_w64_x86_64_prefix}/lib/libbz2_static.a" "${mingw_w64_x86_64_prefix}/lib/libbz2.a" # static library fix
  cd ..
}

build_liblzma() {
  do_git_checkout $liblzma_git xz-git
  cd xz-git
    do_cmake
    do_ninja_and_ninja_install
  cd ..
}

build_zlib() {
  do_git_checkout $zlib_git zlib-git
  cd zlib-git
    local make_options
    export CFLAGS="$CFLAGS -fPIC" # For some reason glib needs this even though we build a static library
    do_configure "--prefix=$mingw_w64_x86_64_prefix --static"
    do_make_and_make_install "$make_prefix_options ARFLAGS=rcs"
    reset_cflags
  cd ..
}

build_iconv() {
  download_and_unpack_file $iconv_tar 
  cd libiconv-1.16
    generic_configure "--disable-nls"
    do_make "install-lib" # No need for 'do_make_install', because 'install-lib' already has install-instructions.
  cd ..
}

build_x11macro() {
  do_git_checkout_and_make_install $x11macro_git
}

build_xorgproto() {
  do_git_checkout_and_make_install $xorgproto_git
}

build_libx11() {
  export CFLAGS="$CFLAGS -fPIC"
  do_git_checkout_and_make_install $libX11_git
  sed -i.bak "s|-lX11.*|-lX11 -lxcb -lXau|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/x11.pc"
  reset_cflags
}

build_libxtrans() {
  do_git_checkout_and_make_install $libxtrans_git
}

build_libxcb() {
  export CFLAGS="$CFLAGS -fPIC"
  do_git_checkout_and_make_install $libxcb_git
  sed -i.bak "s|-lxcb.*|-lxcb -lXau|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/xcb.pc"
  reset_cflags
}

build_xcbproto() {
  do_git_checkout_and_make_install $xcbproto_git
}

build_libxau() {
  do_git_checkout_and_make_install $libxau_git
}

build_libxext() {
  build_x11macro
  export ACLOCAL_PATH="$mingw_w64_x86_64_prefix/share/aclocal:$ACLOCAL_PATH" # need to set otherwise it complain
  build_xorgproto
  cp $mingw_w64_x86_64_prefix/share/pkgconfig/* $mingw_w64_x86_64_prefix/lib/pkgconfig/
  build_xcbproto
  build_libxtrans
  build_libxau
  build_libxcb
  cp $mingw_w64_x86_64_prefix/share/pkgconfig/* $mingw_w64_x86_64_prefix/lib/pkgconfig/
  build_libx11
  export CFLAGS="$CFLAGS -fPIC"
  do_git_checkout_and_make_install $libxext_git
  unset ACLOCAL_PATH
  reset_cflags
}

build_sdl2() {
  build_libxext
  download_and_unpack_file $sdl2_tar SDL-release-2.0.12
  cd SDL-release-2.0.12
    apply_patch file://$patch_dir/SDL2-2.0.12_lib-only.diff "" "patch"
    if [[ ! -f configure.bak ]]; then
      sed -i.bak "s/ -mwindows//" configure # Allow ffmpeg to output anything to console.
    fi
    export CFLAGS="$CFLAGS -DDECLSPEC="  # avoid SDL trac tickets 939 and 282 [broken shared builds]
    unset PKG_CONFIG_LIBDIR # Allow locally installed things for native builds; libpulse-dev is an important one otherwise no audio for most Linux
    generic_configure "--bindir=$mingw_bin_path"
    do_make_and_make_install
    export PKG_CONFIG_LIBDIR=
    if [[ ! -f $mingw_bin_path/$host_target-sdl2-config ]]; then
      mv "$mingw_bin_path/sdl2-config" "$mingw_bin_path/$host_target-sdl2-config" # At the moment FFmpeg's 'configure' doesn't use 'sdl2-config', because it gives priority to 'sdl2.pc', but when it does, it expects 'i686-w64-mingw32-sdl2-config' in 'cross_compilers/mingw-w64-i686/bin'.
    fi
    reset_cflags
  cd ..
}

build_amd_amf_headers() {
  # was https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git too big
  # or https://github.com/DeadSix27/AMF smaller
  # but even smaller!
  do_git_checkout $amd_amf_git amf-headers-git

  cd amf-headers-git
    if [ ! -f "already_installed" ]; then
      #rm -rf "./Thirdparty" # ?? plus too chatty...
      if [ ! -d "$mingw_w64_x86_64_prefix/include/AMF" ]; then
        mkdir -p "$mingw_w64_x86_64_prefix/include/AMF"
      fi
      cp -av "amf/public/include/." "$mingw_w64_x86_64_prefix/include/AMF"
      touch "already_installed"
    fi
  cd ..
}

build_nv_headers() {
  do_git_checkout $nv_headers_git nv-codec-headers-git
  cd nv-codec-headers-git
    #do_make_install "PREFIlepX=$mingw_w64_x86_64_prefix" # just copies in headers
    cp ffnvcodec.pc.in ffnvcodec.pc
    cp ffnvcodec.pc "${mingw_w64_x86_64_prefix}/lib/pkgconfig"
    cp -r include "${mingw_w64_x86_64_prefix}"
    touch already_install
  cd ..
}

build_intel_qsv_mfx() { # disableable via command line switch...
  do_git_checkout $intel_qsv_mfx_git mfx-dispatch-git # lu-zero?? oh well seems somewhat supported...
  cd mfx-dispatch-git
    if [[ ! -f "configure" ]]; then
      autoreconf -fiv || exit 1
      automake --add-missing || exit 1
    fi
    generic_configure_make_install
  cd ..
}

build_libjpeg_turbo() {
  do_git_checkout $libjpeg_turbo_git libjpeg-turbo-git "origin/main"
  cd libjpeg-turbo-git
  export CFLAGS="$CFLAGS -fPIC"
    local cmake_params="-DENABLE_SHARED=0 -DCMAKE_ASM_NASM_COMPILER=nasm -DENABLE_SHARED=FALSE"
    cat > toolchain.cmake << EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ${target_proc})
set(CMAKE_C_COMPILER ${cross_prefix}gcc)
set(CMAKE_RC_COMPILER ${cross_prefix}windres)
EOF
    do_cmake_and_install "$cmake_params"
    reset_cflags
    sed -i.bak "s|-ljpeg.*|-ljpeg -lopenjp2|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/libjpeg.pc"
    cd ..
}

build_libleptonica() {
  build_libopenjpeg
  build_libjpeg_turbo
  do_git_checkout $libleptonica_git leptonica-git
  cd leptonica-git
    do_cmake_and_install
    sed -i.bak "s|-lleptonica.*|-lleptonica -lm -lz -ljpeg -lpng -lwebp -lopenjp2|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/lept.pc"
  cd ..
}

build_libtiff() {
  build_libjpeg_turbo # auto uses it?
  do_git_checkout $libtiff_git libtiff-git
  cd libtiff-git
    generic_configure "--enable-year2038 --enable-shared=no"
    #sed -i.bak 's/-ltiff.*$/-ltiff -llzma -ljpeg -lz/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig/libtiff-4.pc" # static deps
  cd ..
}

build_libtensorflow() {
  do_git_checkout_and_make_install $tensorflow_git tensorflow_git
}

build_gettext() {
  export CPPFLAGS="$CPPFLAGS -DLIBXML_STATIC " # gettext build...
  download_and_unpack_file $gettext_tar gettext-0.23.1
  cd gettext-0.23.1
    
    generic_configure "--enable-shared=no --enable-year2038"
    do_make_and_make_install
  reset_cppflags
  cd ..
}

build_glib() {
  build_gettext
  do_git_checkout $glib_git glib-git
  cd glib-git
    #apply_patch  file://$patch_dir/glib-2.64.3_mingw-static.patch -p1
    #export CPPFLAGS="$CPPFLAGS -DGLIB_STATIC_COMPILATION"
    #export CFLAGS="$CFLAGS -pthread"
    #export CXXFLAGS="$CFLAGS"
    #export LDFLAGS="$LDFLAGS -L${mingw_w64_x86_64_prefix}/lib" # For some reason the frexp configure checks fail without this as math.h isn't found when cross-compiling; no negative impact for native builds
    local meson_options="-Dtests=false -Dforce_posix_threads=true"
    do_meson "$meson_options"
    do_ninja_and_ninja_install
    sed -i.bak 's/-lglib-2.0.*$/-lglib-2.0 -pthread -lm -liconv/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig/glib-2.0.pc"
    reset_cppflags
    unset CXXFLAGS
    reset_ldflags
    reset_cflags
  cd ..
}

build_lensfun() {
  build_glib
  do_git_checkout $lens_fun_git lensfun-git
  cd lensfun-git
    export CMAKE_STATIC_LINKER_FLAGS='-lws2_32 -pthread'
    do_cmake "-DBUILD_STATIC=on -DCMAKE_INSTALL_DATAROOTDIR=$mingw_w64_x86_64_prefix"
    do_ninja_and_ninja_install
    sed -i.bak 's/-llensfun/-llensfun -lstdc++/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig/lensfun.pc"
    unset CMAKE_STATIC_LINKER_FLAGS
  cd ..
}

build_libtesseract() {
  build_libtiff # no disable configure option for this in tesseract? odd...${mingw_w64_x86_64_prefix}/lib/pkgconfig/
  build_libleptonica
  do_git_checkout $tesseract_git tesseract-git
  cd tesseract-git
    export LDFLAGS="$LDFLAGS -lsharpyuv"
    generic_configure "--enable-shared=no --disable-doc --with-curl=no"
    do_make_and_make_install
    sed -i.bak 's/-ltesseract.*$/-ltesseract -lstdc++ -llzma -ljpeg -lz -lgomp/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig//tesseract.pc" # see above, gomp for linux native
    reset_ldflags
    reset_compiler
  cd ..
}

build_libzimg() {
  do_git_checkout $zimg_git zimg-git
  cd zimg-git
    generic_configure_make_install
  cd ..
}

build_libopenjpeg() {
  do_git_checkout $openjpeg_git openjpeg-git
  cd openjpeg-git
    do_cmake_and_install "-DBUILD_CODEC=0 -DBUILD_SHARED_LIBS=OFF"
  cd ..
}

build_rust_bindgen() {
  do_git_checkout $BINDGEN_URL rust-bindgen-git
  cd rust-bindgen-git
    do_cargo_install "install bindgen-cli"
  cd ..
}

build_glew() {
  build_libglslang
  download_and_unpack_file $glew_tgz glew-2.2.0
  cd glew-2.2.0/build/cmake
    local cmake_params="-DBUILD_UTILS=OFF"
    do_cmake "$cmake_params" # "-DWITH_FFMPEG=0 -DOPENCV_GENERATE_PKGCONFIG=1 -DHAVE_DSHOW=0"
    do_ninja_and_ninja_install
  cd ../../..
}

build_libffi() {
  do_git_checkout $libffi_git libffi-git
  cd libffi-git
    do_configure "--prefix=$mingw_w64_x86_64_prefix"
    do_make_and_make_install
  cd ..
}

build_libxml2() {
  do_git_checkout_and_make_install $libxml2_git
}

build_wayland() {
  build_libxml2
  do_git_checkout $wayland_git wayland-git
  local meson_options="--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib \
  -Ddocumentation=false -Dtests=false --buildtype=release --default-library=static"
  cd wayland-git
    do_meson "$meson_options"
    do_ninja_and_ninja_install
  cd ..
}

build_wayland_protocol() {
  do_git_checkout $wayland_protocol_git wayland-protocol-git
  local meson_options="--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib \
  -Dtests=false --buildtype=release --default-library=static"
  cd wayland-protocol-git
    do_meson "$meson_options"
    do_ninja_and_ninja_install
  cp $mingw_w64_x86_64_prefix/share/pkgconfig/wayland-protocols.pc $mingw_w64_x86_64_prefix/lib/pkgconfig/
  cd ..
}

build_libxkbcommon() {
  build_wayland_protocol
  do_git_checkout $libxkbcommon_git libxkbcommon-git
  export LDFLAGS="$LDFLAGS -lXau -lxcb"
  local meson_options="--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib \
  --buildtype=release --default-library=static"
  cd libxkbcommon-git
    do_meson "$meson_options"
    do_ninja_and_ninja_install
  reset_ldflags
  cd ..
}

build_libxrender() {
  do_git_checkout_and_make_install $libxrenser_git
}

build_libxinerama() {
  do_git_checkout_and_make_install $libXinerama_git
}

build_libxrandr() {
  build_libxrender
  do_git_checkout_and_make_install $libxrandr_git
}

build_libxfixes() {
  echo "build_libxfixes..."
  do_git_checkout_and_make_install $libxfixes_git
}

build_libxcursor() {
  do_git_checkout_and_make_install $libxcursor_git
}

build_libxi() {
  do_git_checkout_and_make_install $libxi_git
}

build_glfw() {
  export ACLOCAL_PATH="$mingw_w64_x86_64_prefix/share/aclocal:$ACLOCAL_PATH"
  build_wayland
  build_libxkbcommon
  build_libxrandr
  build_libxinerama
  build_libxfixes
  build_libxcursor
  build_libxi
  do_git_checkout $glfw_git glfw-git
  cd glfw-git
    do_cmake_and_install
  cd ..
  unset ACLOCAL_PATH
}

build_libpng() {
  do_git_checkout $libpng_git libpng-git
  cd libpng-git
    export CFLAGS="$CFLAGS -fpic"
    generic_configure
    do_make_and_make_install
  reset_cflags
  sed -i.bak "s|-lpng16.*|-lpng16 -lm -lz -lm|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/libpng16.pc"
  cd ..
}

build_libwebp() {
  do_git_checkout $libwebp_git libwebp-git
  cd libwebp-git
    export LIBPNG_CONFIG="$mingw_w64_x86_64_prefix/bin/libpng-config --static" # LibPNG somehow doesn't get autodetected.
    generic_configure "--enable-shared=no"
    do_make_and_make_install
    unset LIBPNG_CONFIG
    sed -i.bak "s|-lwebp.*|-lwebp -lsharpyuv|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/libwebp.pc"
  cd ..
}

build_brotli() {
  do_git_checkout $brotli_git brotli-git
  cd brotli-git
    do_cmake_and_install "-DBUILD_SHARED_LIBS=OFF"
    sed -i.bak "s|-lbrotlidec.*|-lbrotlidec -lbrotlicommon|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/libbrotlidec.pc"
    sed -i.bak "s|-lbrotlidec.*|-lbrotlidec -lbrotlicommon|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/libbrotlienc.pc"
  cd ..
}

build_harfbuzz() {
  local new_build=false
  do_git_checkout $hardbuzz_git harfbuzz-git
  if [ ! -f harfbuzz-git/already_done_harf ]; then # Not done or new master, so build
    new_build=true
  fi
  # basically gleaned from https://gist.github.com/roxlu/0108d45308a0434e27d4320396399153
  build_freetype "-Dharfbuzz=disabled" $new_build # Check for initial or new freetype or force rebuild if needed
  local new_freetype=$?
  local meson_options="--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib \
  -Dfreetype=enabled -Ddocs=disabled -Dicu=disabled --buildtype=release --default-library=static -Dtests=disabled"
  if $new_build || [ $new_freetype = 0 ]; then # 0 is true
    rm -f harfbuzz-git/already* # Force rebuilding in case only freetype has changed
    # cmake no .pc file generated so use configure :|
    cd harfbuzz-git
    export LDFLAGS="$LDFLAGS -lbrotlidec -lbrotlienc -lbrotlicommon -lz -lpthread" # :|
    do_meson "$meson_options" # no fontconfig, don't want another circular what? icu is #372
    do_ninja_and_ninja_install
    cd ..

    build_freetype "-Dharfbuzz=enabled" true # with harfbuzz now...
    touch harfbuzz-git/already_done_harf
    echo "Done harfbuzz"
  else
    echo "Already done harfbuzz"
  fi
  sed -i.bak 's/-lfreetype.*/-lfreetype -lharfbuzz -lpng -lbz2 -lpthread/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig/freetype2.pc" # for some reason it lists harfbuzz as Requires.private only??
  sed -i.bak 's/-lharfbuzz.*/-lfreetype -lharfbuzz -lpng -lbz2 -lpthread/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig/harfbuzz.pc" # does anything even use this?
  #sed -i.bak 's/libfreetype.la -lbz2/libfreetype.la -lharfbuzz -lpng -lbz2 -lpthread/' "${mingw_w64_x86_64_prefix}/lib/libfreetype.la" # XXX what the..needed?
  #sed -i.bak 's/libfreetype.la -lbz2/libfreetype.la -lharfbuzz -lpng -lbz2 -lpthread/' "${mingw_w64_x86_64_prefix}/lib/libharfbuzz.la"
  reset_ldflags
}

build_freetype() {
  build_bzip2
  local force_build=$2
  local new_build=1
  if [[ ! -f freetype-git/already_done_freetype || $force_build = true ]]; then
    do_git_checkout $freetype_git freetype-git
    build_brotli
    rm -f freetype-git/already*
    cd freetype-git
      rm -rf build
      #apply_patch file://$patch_dir/freetype2-crosscompiled-apinames.diff # src/tools/apinames.c gets crosscompiled and makes the compilation fail
      # harfbuzz autodetect :|
      
      do_meson "-Dbzip2=enabled $1"
      do_ninja_and_ninja_install
      touch already_done_freetype
      new_build=0
    cd ..
  fi
  return $new_build # Give caller a way to know if a new build was done
}

build_libxml2() {
  do_git_checkout $libxml2_git libxml2-git
  cd libxml2-git
    generic_configure "--with-ftp=no --with-http=no --with-python=no"
    do_make_and_make_install
  cd ..
}

check_vmaf_compiler() {
  if [[ $libvmaf_compiler =~ (gcc|clang)-([0-9]+) ]]; then
    local compiler_type="${BASH_REMATCH[1]}"  # Matches 'gcc' or 'clang'
    local compiler_version="${BASH_REMATCH[2]}"  # Matches the version number
    
    echo "Compiler detected: $compiler_type, version: $compiler_version"
    
    if [[ $compiler_type == "gcc" ]]; then
      export CC="gcc-$compiler_version"
      export CXX="g++-$compiler_version"
    elif [[ $compiler_type == "clang" ]]; then
      export CC="clang-$compiler_version"
      export CXX="clang++-$compiler_version"
    fi

    echo "CC set to $CC"
    echo "CXX set to $CXX"
  else
    echo "Valid compiler not detected in libvmaf_compiler. Please set libvmaf_compiler to a valid format (e.g., gcc-12 or clang-15)."
  fi
}

build_libvmaf() {
  do_git_checkout https://github.com/Netflix/vmaf.git vmaf-git
  cd vmaf-git
    cd libvmaf
      export CFLAGS="$CFLAGS -pthread"
      export CXXFLAGS="$CXXFLAGS -pthread"
      export LDFLAGS="$LDFLAGS -pthread" # Needed here too for some reason
      mkdir build
      local meson_options="-Denable_docs=false -Denable_tests=false -Denable_float=true"
      if [[ $libvmaf_cuda == "y" ]]; then
       check_vmaf_compiler
        export CFLAGS="$CFLAGS -I/usr/local/cuda/lib64"
        local meson_options+=" -Denable_cuda=true"
      fi
      do_meson "$meson_options"
      do_ninja_and_ninja_install
      reset_cflags
      unset CXXFLAGS
      reset_ldflags
      rm -f ${mingw_w64_x86_64_prefix}/lib/libvmaf.so
      # TODO: better patch pc file
      sed -i.bak "s/Libs: .*/& -lstdc++/" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/libvmaf.pc" # .pc is still broken
      if [[ $libvmaf_cuda == "y" ]]; then
        reset_compiler
      fi
    cd ../..
}

build_fontconfig() {
  build_brotli
  do_git_checkout $fontconfig_git fontconfig-git
  cd fontconfig-git
    #export CFLAGS= # compile fails with -march=sandybridge ... with mingw 4.0.6 at least ...
    generic_configure "--enable-iconv --enable-libxml2 --disable-docs --with-libiconv \
    --enable-static=yes --enable-shared=no --enable-year2038" # Use Libxml2 instead of Expat.
    do_make_and_make_install
    reset_ldflags
  cd ..
}

build_gmp() {
  download_and_unpack_file $gmp_tar
  cd gmp-6.2.1
    generic_configure "ABI=$bits_target"
    do_make_and_make_install
  cd ..
}

build_librtmfp() {
  # needs some version of openssl...
  # build_openssl-1.0.2 # fails OS X
  build_openssl-1.1.1
  do_git_checkout $librtmfp_git
  cd librtmfp_git/include/Base
    do_git_checkout $mingw_std_threads_git mingw-std-threads-git # our g++ apparently doesn't have std::mutex baked in...weird...this replaces it...
  cd ../../..
  cd librtmfp_git
    apply_patch file://$patch_dir/rtfmp.static.make.patch -p1
    do_make "$make_prefix_options GPP=${cross_prefix}g++"
    do_make_install "prefix=$mingw_w64_x86_64_prefix PKGCONFIGPATH=$PKG_CONFIG_PATH"
    sed -i.bak 's/-lrtmfp.*/-lrtmfp -lstdc++/' "$PKG_CONFIG_PATH/librtmfp.pc"    fi
  cd ..
}

build_libnettle() {
  do_git_checkout $libnettle_git nettle-git
  cd nettle-git
    local config_options="--disable-openssl --disable-documentation" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh?
    config_options+=" --libdir=${mingw_w64_x86_64_prefix}/lib" # Otherwise native builds install to /lib32 or /lib64 which gnutls doesn't find
    generic_configure "$config_options" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh? https://github.com/rdp/ffmpeg-windows-build-helpers/issues/25#issuecomment-28158515
    do_make_and_make_install # What's up with "Configured with: ... --with-gmp=/cygdrive/d/ffmpeg-windows-build-helpers-master/native_build/windows/ffmpeg_local_builds/sandbox/cross_compilers/pkgs/gmp/gmp-6.1.2-i686" in 'config.log'? Isn't the 'gmp-6.1.2' above being used?
  cd ..
}

build_libunistring() {
  generic_download_and_make_and_install $libunistring_tar
}

build_libidn2() {
  generic_download_and_make_and_install $libidn2_tar
}

build_gnutls() {
  download_and_unpack_file $gnutls_tar
  cd gnutls-3.8.9
    # --disable-cxx don't need the c++ version, in an effort to cut down on size... XXXX test size difference...
    # --enable-local-libopts to allow building with local autogen installed,
    # --disable-guile is so that if it finds guile installed (cygwin did/does) it won't try and link/build to it and fail...
    # libtasn1 is some dependency, appears provided is an option [see also build_libnettle]
    # pks #11 hopefully we don't need kit
    generic_configure "--enable-shared=no --enable-static=yes --disable-maintainer-mode --enable-year2038 --disable-doc --disable-tools --disable-cxx --disable-tests --disable-gtk-doc-html --disable-libdane --disable-nls --enable-local-libopts --disable-guile --with-included-libtasn1 --without-p11-kit"
    do_make_and_make_install
    # libsrt doesn't know how to use its pkg deps, so put them in as non-static deps :| https://github.com/Haivision/srt/issues/565
    sed -i.bak 's/-lgnutls.*/-lgnutls -lnettle -lhogweed -lgmp -lidn2 -liconv -lunistring/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig/gnutls.pc"
  cd ..
}

build_libogg() {
  do_git_checkout $libogg_git ogg-git
  cd ogg-git
    generic_configure_make_install
  cd ..
}

build_libvorbis() {
  do_git_checkout $libvorbis_git vorbis-git
  cd vorbis-git
    export CPPFLAGS="$CPPFLAGS -fpic"
    generic_configure "--disable-docs --disable-examples --disable-oggtest"
    do_make_and_make_install
    reset_cppflags
  cd ..
}

build_libopus() {
  do_git_checkout $libopus_git opus-git
  cd opus-git
    do_cmake_and_install
  cd ..
}

build_libspeexdsp() {
  do_git_checkout $libspeexdsp_git speexdsp-git
  cd speexdsp-git
    generic_configure "--disable-examples"
    do_make_and_make_install
  cd ..
}

build_libspeex() {
  do_git_checkout $libspeex_git speex-git
  cd speex-git
    export SPEEXDSP_CFLAGS="-I$mingw_w64_x86_64_prefix/include"
    export SPEEXDSP_LIBS="-L$mingw_w64_x86_64_prefix/lib -lspeexdsp" # 'configure' somehow can't find SpeexDSP with 'pkg-config'.
    generic_configure "--disable-binaries" # If you do want the libraries, then 'speexdec.exe' needs 'LDFLAGS=-lwinmm'.
    do_make_and_make_install
    unset SPEEXDSP_CFLAGS
    unset SPEEXDSP_LIBS
  cd ..
}

build_libtheora() {
  do_git_checkout $libtheora_git theora-git
  cd theora-git
    generic_configure "--disable-doc --disable-spec --disable-oggtest --disable-vorbistest --disable-examples --disable-asm" # disable asm: avoid [theora @ 0x1043144a0]error in unpack_block_qpis in 64 bit... [OK OS X 64 bit tho...]
    do_make_and_make_install
  cd ..
}

build_libsndfile() {
  do_git_checkout $libsndfile_git libsndfile-git
  cd libsndfile-git
    export LDFLAGS="$LDFLAGS -lm"
    generic_configure "--disable-sqlite --disable-external-libs --disable-full-suite"
    do_make_and_make_install
    if [ "$1" = "install-libgsm" ]; then
      if [[ ! -f $mingw_w64_x86_64_prefix/lib/libgsm.a ]]; then
        install -m644 src/GSM610/gsm.h $mingw_w64_x86_64_prefix/include/gsm.h || exit 1
        install -m644 src/GSM610/.libs/libgsm.a $mingw_w64_x86_64_prefix/lib/libgsm.a || exit 1
      else
        echo "already installed GSM 6.10 ..."
      fi
    fi
    reset_ldflags
  cd ..
}

build_mpg123() {
  do_svn_checkout $mpg123_svn mpg123-svn # avoid Think again failure
  cd mpg123-svn
    export CPPFLAGS="$CPPFLAGS -fpic"
    generic_configure
    do_make_and_make_install
    reset_cppflags
  cd ..
}

build_mp3lame() {
  do_svn_checkout $lame_svn lame-svn
  cd lame-svn
    apply_patch file://$patch_dir/mp3lame.patch "" "patch"
    generic_configure "--enable-nasm --enable-shared=no --disable-frontend"
    do_make_and_make_install
  cd ..
}

build_twolame() {
  do_git_checkout $twolame_git twolame-git "origin/main"
  cd twolame-git
    if [[ ! -f Makefile.am.bak ]]; then # Library only, front end refuses to build for some reason with git master
      sed -i.bak "/^SUBDIRS/s/ frontend.*//" Makefile.am || exit 1
    fi
    cpu_count=1 # maybe can't handle it http://betterlogic.com/roger/2017/07/mp3lame-woe/ comments
    generic_configure_make_install
    cpu_count=$original_cpu_count
  cd ..
}

build_fdk-aac() {
local checkout_dir=fdk-aac-git
    do_git_checkout $fdk_aac_git fdk-aac-git
  cd $checkout_dir
    if [[ ! -f "configure" ]]; then
      autoreconf -fiv || exit 1
    fi
    generic_configure_make_install
  cd ..
}

build_libopencore() {
  generic_download_and_make_and_install $opencore_amr_0_1_5
  generic_download_and_make_and_install $vo_amrwbenc_0_1_3
}

build_libilbc() {
  do_git_checkout $libilbc_git libilbc-git
  cd libilbc-git
    do_cmake "-DBUILD_SHARED_LIBS=OFF"
    do_ninja_and_ninja_install
  cd ..
}

build_libmodplug() {
  do_git_checkout $libmodplug_git libmodplug-git
  cd libmodplug-git
    sed -i.bak 's/__declspec(dllexport)//' "$mingw_w64_x86_64_prefix/include/libmodplug/modplug.h" #strip DLL import/export directives
    sed -i.bak 's/__declspec(dllimport)//' "$mingw_w64_x86_64_prefix/include/libmodplug/modplug.h"
    if [[ ! -f "configure" ]]; then
      autoreconf -fiv || exit 1
      automake --add-missing || exit 1
    fi
    generic_configure_make_install # or could use cmake I guess
  cd ..
}

build_libgme() {
  do_git_checkout $libgme_git
  cd game-music-emu-git
    do_cmake_and_install "-DENABLE_UBSAN=0"
  cd ..
}

build_mingw_std_threads() {
  do_git_checkout $mingw_std_threads_git mingw-std-threads-git # it needs std::mutex too :|
  cd mingw-std-threads-git
    cp *.h "$mingw_w64_x86_64_prefix/include"
  cd ..
}

build_opencv() {
  build_mingw_std_threads
  #do_git_checkout https://github.com/opencv/opencv.git # too big :|
  download_and_unpack_file $opencv_tar -4.10.0
  mkdir -p opencv-4.10.0/build
  cd opencv-4.10.0
     apply_patch file://$patch_dir/opencv.detection_based.patch -p1 "patch"
  cd ..
  cd opencv-4.10.0/build
    # could do more here, it seems to think it needs its own internal libwebp etc...
    cpu_count=1
    do_cmake_from_build_dir .. "-DWITH_FFMPEG=0 -DOPENCV_GENERATE_PKGCONFIG=1 -DHAVE_DSHOW=0" # https://stackoverflow.com/q/40262928/32453, no pkg config by default on "windows", who cares ffmpeg
    do_make_and_make_install
    cp unix-install/opencv.pc $PKG_CONFIG_PATH
    cpu_count=$original_cpu_count
  cd ../..
}

build_facebooktransform360() {
  build_opencv
  do_git_checkout $facebooktransform360_git transform360-git
  cd transform360-git
    apply_patch file://$patch_dir/transform360.pi.diff -p1
  cd ..
  cd transform360_git/Transform360
    do_cmake ""
    sed -i.bak "s/isystem/I/g" CMakeFiles/Transform360.dir/includes_CXX.rsp # weird stdlib.h error
    do_make_and_make_install
  cd ../..
}

build_libbluray() {
  unset JDK_HOME # #268 was causing failure
  do_git_checkout $libbluray_git libbluray-git
  cd libbluray-git
    if [[ ! -d .git/modules ]]; then
      git submodule update --init --remote # For UDF support [default=enabled], which strangely enough is in another repository.
    else
      local local_git_version=`git --git-dir=.git/modules/contrib/libudfread rev-parse HEAD`
      local remote_git_version=`git ls-remote -h https://code.videolan.org/videolan/libudfread.git | sed "s/[[:space:]].*//"`
      if [[ "$local_git_version" != "$remote_git_version" ]]; then
        echo "detected upstream udfread changed, attempted to update submodules" # XXX use do_git_checkout here instead somehow?
        git submodule foreach -q 'git clean -fx' # Throw away local changes; 'already_configured_*' and 'udfread.c.bak' in this case.
        rm -f contrib/libudfread/src/udfread-version.h
        git submodule update --remote -f # Checkout even if the working tree differs from HEAD.
      fi
    fi
    if [[ ! -f jni/win32/jni_md.h.bak ]]; then
      sed -i.bak "/JNIEXPORT/s/ __declspec.*//" jni/win32/jni_md.h # Needed for building shared FFmpeg libraries.
    fi
    # avoid collision with newer ffmpegs, couldn't figure out better glob LOL
    sed -i.bak "s/dec_init/dec__init/g" src/libbluray/disc/*.{c,h}
    cd contrib/libudfread
      if [[ ! -f src/udfread.c.bak ]]; then
        sed -i.bak "/WIN32$/,+4d" src/udfread.c # Fix WinXP incompatibility.
      fi
      if [[ ! -f src/udfread-version.h ]]; then
        generic_configure # Generate 'udfread-version.h', or building Libbluray fails otherwise.
      fi
    cd ../..
    generic_configure "--disable-examples --disable-bdjava-jar"
    do_make_and_make_install "CPPFLAGS=\"-Ddec_init=libbr_dec_init\""
  cd ..
}

build_libbs2b() {
  download_and_unpack_file $libbs2b_tar
  cd libbs2b-3.1.0
    apply_patch file://$patch_dir/libbs2b.patch "" "patch"
    sed -i.bak "s/AC_FUNC_MALLOC//" configure.ac # #270
    export LIBS=-lm # avoid pow failure linux native
    generic_configure_make_install
    unset LIBS
  cd ..
}

build_libsoxr() {
  do_git_checkout $libsoxr_git soxr-git
  cd soxr-git
    do_cmake_and_install "-DBUILD_SHARED_LIBS=OFF -DHAVE_WORDS_BIGENDIAN_EXITCODE=0 -DWITH_OPENMP=0 -DBUILD_TESTS=0 -DBUILD_EXAMPLES=0"
  cd ..
}

build_libflite() {
  # download_and_unpack_file http://www.festvox.org/flite/packed/flite-2.1/flite-2.1-release.tar.bz2
  # original link is not working so using a substitute
  # from a trusted source
  do_git_checkout $libflite_git flite-git
  cd flite-git
    if [[ ! -f main/Makefile.bak ]]; then
      sed -i.bak "s/cp -pd/cp -p/" main/Makefile # friendlier cp for OS X
    fi
    generic_configure "--disable-shared"
    do_make_and_make_install
  cd ..
}

build_libsnappy() {
  do_git_checkout $libsnappy_git snappy-git
  cd snappy-git
    do_cmake_and_install "-DBUILD_BINARY=OFF -DCMAKE_BUILD_TYPE=Release -DSNAPPY_BUILD_TESTS=OFF" # extra params from deadsix27 and from new cMakeLists.txt content
    rm -f $mingw_w64_x86_64_prefix/lib/libsnappy.dll.a # unintall shared :|
  cd ..
}

build_vamp_plugin() {
  download_and_unpack_file $vamp_plugin_tar vamp-plugin-sdk-2.10.0
  cd vamp-plugin-sdk-2.10.0
    apply_patch file://$patch_dir/vamp-plugin-sdk-2.10_static-lib.diff "" "patch"
    if [[ $compiler_flavors != "native" && ! -f src/vamp-sdk/PluginAdapter.cpp.bak ]]; then
      sed -i.bak "s/#include <mutex>/#include <mingw.mutex.h>/" src/vamp-sdk/PluginAdapter.cpp
    fi
    if [[ ! -f configure.bak ]]; then # Fix for "'M_PI' was not declared in this scope" (see https://stackoverflow.com/a/29264536).
      sed -i.bak "s/c++11/gnu++11/" configure
      sed -i.bak "s/c++11/gnu++11/" Makefile.in
    fi
    do_configure "--prefix=$mingw_w64_x86_64_prefix --disable-programs"
    do_make "install-static" # No need for 'do_make_install', because 'install-static' already has install-instructions.
  cd ..
}

build_fftw() {
  download_and_unpack_file $fftw_tar fftw-3.3.8
  cd fftw-3.3.8
    generic_configure "--disable-doc"
    do_make_and_make_install
  cd ..
}

build_libsamplerate() {
  # I think this didn't work with ubuntu 14.04 [too old automake or some odd] :|
  do_git_checkout $libsamplerate_git libsamplerate-git
  cd libsamplerate-git
    generic_configure
    do_make_and_make_install
  cd ..
  # but OS X can't use 0.1.9 :|
  # rubberband can use this, but uses speex bundled by default [any difference? who knows!]
}

build_librubberband() {
  do_git_checkout $rubberband_git rubberband-git default
  cd rubberband-git
    do_meson "-Dtests=disabled -Dcmdline=disabled"
    do_ninja_and_ninja_install
    #apply_patch file://$patch_dir/rubberband_git_static-lib.diff "-p1" # create install-static target
    #do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-ladspa"
    #do_make "install-static AR=${cross_prefix}ar" # No need for 'do_make_install', because 'install-static' already has install-instructions.
    sed -i.bak 's/-lrubberband.*$/-lrubberband -lfftw3 -lsamplerate -lstdc++/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig/rubberband.pc"
  cd ..
}

build_frei0r() {
  do_git_checkout $frei0r_git frei0r-git
  cd frei0r-git
    sed -i.bak 's/-arch i386//' CMakeLists.txt # OS X https://github.com/dyne/frei0r/issues/64
    do_cmake_and_install "-DWITHOUT_OPENCV=1" # XXX could look at this more...

    mkdir -p $cur_dir/redist # Strip and pack shared libraries.
    local arch=x86_64
    archive="$cur_dir/redist/frei0r-plugins-${arch}-$(git describe --tags).7z"
    if [[ ! -f "$archive.done" ]]; then
      for sharedlib in $mingw_w64_x86_64_prefix/lib/frei0r-1/*.dll; do
        ${cross_prefix}strip $sharedlib
      done
      for doc in AUTHORS ChangeLog COPYING README.md; do
        sed "s/$/\r/" $doc > $mingw_w64_x86_64_prefix/lib/frei0r-1/$doc.txt
      done
      7z a -mx=9 $archive $mingw_w64_x86_64_prefix/lib/frei0r-1 && rm -f $mingw_w64_x86_64_prefix/lib/frei0r-1/*.txt
      touch "$archive.done" # for those with no 7z so it won't restrip every time
    fi
  cd ..
}

build_svt-hevc() {
  do_git_checkout $svt_hevc_git SVT-HEVC-git
  mkdir -p SVT-HEVC-git/release
  cd SVT-HEVC-git/release
    do_cmake_from_build_dir ..
    do_ninja_and_ninja_install
  cd ../..
}

build_svt-vp9() {
  do_git_checkout $svt_vp9_git SVT-VP9-git
  cd SVT-VP9-git
  cd Build
    do_cmake_from_build_dir ..
    do_ninja_and_ninja_install
  cd ../..
}

build_svt-av1() {
  do_git_checkout $svt_av1_git SVT-AV1-git
  cd SVT-AV1-git
    do_cmake "-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DSVT_AV1_LTO=OFF" # error adding symbol in ffmpeg if lto is on
    do_ninja_and_ninja_install
  cd ..
}

build_vidstab() {
  do_git_checkout $vidstab_git vid.stab-git
  cd vid.stab-git
    do_cmake_and_install "-DUSE_OMP=0 -DBUILD_SHARED_LIBS=OFF" # '-DUSE_OMP' is on by default, but somehow libgomp ('cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/omp.h') can't be found, so '-DUSE_OMP=0' to prevent a compilation error.
  cd ..
}

build_libmysofa() {
  do_git_checkout $libmysofa_git libmysofa-git "origin/main"
  cd libmysofa-git
    local cmake_params="-DBUILD_TESTS==OFF -DBUILD_SHARED_LIBS=OFF"
    do_cmake "$cmake_params"
    do_ninja_and_ninja_install
  cd ..
}

build_libcaca() {
  do_git_checkout $libcaca_git libcaca-git
  cd libcaca-git
    apply_patch file://$patch_dir/libcaca-patch.patch -p1
    cd caca
      sed -i.bak "s/__declspec(dllexport)//g" *.h # get rid of the declspec lines otherwise the build will fail for undefined symbols
      sed -i.bak "s/__declspec(dllimport)//g" *.h
    cd ..
    generic_configure "--libdir=$mingw_w64_x86_64_prefix/lib --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-doc --disable-cocoa --disable-ncurses"
    do_make_and_make_install
    sed -i.bak "s/-lcaca.*/-lcaca -lX11/" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/caca.pc"
  cd ..
}

build_libdecklink() {
  local url=$libdecklink_git_1
  git ls-remote $url
  if [ $? -ne 0 ]; then
    # If NotABug.org server is down , Change to use GitLab.com .
    # https://gitlab.com/m-ab-s/decklink-headers
    url=$libdecklink_git_2
  fi
  do_git_checkout $url
  cd decklink-headers_git
    do_make_install PREFIX=$mingw_w64_x86_64_prefix
  cd ..
}

build_zvbi() {
  download_and_unpack_file $zvbi_tar zvbi-0.2.35
  cd zvbi-0.2.35
    #apply_patch file://$patch_dir/zvbi-no-contrib.diff # weird issues with some stuff in contrib...
    #apply_patch file://$patch_dir/zvbi-aarch64.patch
    generic_configure " --disable-dvb --disable-bktr --disable-proxy --disable-nls --without-doxygen --without-libiconv-prefix"
    # Without '--without-libiconv-prefix' 'configure' would otherwise search for and only accept a shared Libiconv library.
    do_make_and_make_install
  cd ..
}

build_libv4l2() {
  build_libopenjpeg
  build_libjpeg_turbo
  do_git_checkout $libv4l_git libv4l-git
  cd libv4l-git
    do_meson "-Dudevdir=$mingw_w64_x86_64_prefix/lib/udev"
    do_ninja_and_ninja_install
  cd ..
}

build_fribidi() {
  do_git_checkout $fribidi_git # Get c2man errors building from repo
  cd fribidi-git
  local meson_options="--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib --buildtype=release -Ddeprecated=false -Ddocs=false"
  mkdir build
    do_meson "$meson_options"
    do_ninja_and_ninja_install
  cd ..
}

build_libsrt() {
  do_git_checkout $srt_git srt-git # might be able to use these days...?
  cd srt-git
    do_cmake "-DUSE_GNUTLS=ON -DENABLE_SHARED=OFF -DUSE_STATIC_LIBSTDCXX=ON -DOPENSSL_USE_STATIC_LIBS=ON -DENABLE_APPS=OFF"
    do_ninja_and_ninja_install
    sed -i.bak "s|"
  cd ..
}

build_libass() {
  do_git_checkout_and_make_install $libass_git
}

build_libaribb24() {
  do_git_checkout $libaribb24_git aribb24-git
  cd aribb24-git
    generic_configure_make_install
  cd ..
}

build_libaribcaption() {
  do_git_checkout $libaribcaption_git libaribcaption-git
  cd libaribcaption-git
  do_cmake 
  do_ninja_and_ninja_install
  cd ..
}

build_libxavs2() {
  do_git_checkout $libxavs2_git xavs2-git
  cd xavs2-git
    export CFLAGS="$CFLAGS -Wno-error=incompatible-pointer-types" # gcc-14 thing don't know how to fix
    apply_patch file://$patch_dir/xavs2-patch.patch -p1
    cd build/linux
      do_configure "--prefix=$mingw_w64_x86_64_prefix --enable-pic"
      do_make_and_make_install
    reset_cflags
  cd ../../..
}

build_libdavs2() {
  do_git_checkout $libdavs2_git davs2-git
  cd davs2-git
    apply_patch file://$patch_dir/libdavs2-endian-fixes.patch -p1
    #apply_patch https://github.com/pkuvcl/xavs2/compare/master...1480c1:xavs2:gcc14/pointerconversion.patch
    cd build/linux
      do_configure "--prefix=$mingw_w64_x86_64_prefix --enable-pic"
      do_make_and_make_install
  cd ../../..
}

build_libxvid() {
  download_and_unpack_file $libxvid_tar xvidcore
  cd xvidcore/build/generic
    apply_patch file://$patch_dir/xvidcore-1.3.7_static-lib.patch "" "patch"
    do_configure "--prefix=$mingw_w64_x86_64_prefix" # no static option...
    do_make_and_make_install
  cd ../../..
}

build_libvpx() {
  do_git_checkout $libvpx_git libvpx-git "origin/main"
  cd libvpx-git
    local config_options=""
    export CROSS="$cross_prefix"  
    # VP8 encoder *requires* sse3 support
    do_configure "$config_options --prefix=$mingw_w64_x86_64_prefix --enable-ssse3 --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth --extra-cflags=-fno-asynchronous-unwind-tables --extra-cflags=-mstackrealign" # fno for Error: invalid register for .seh_savexmm
    do_make_and_make_install
    unset CROSS
  cd ..
}

build_libaom() {
  do_git_checkout $libaom_git aom-git
  cd aom-git
  mkdir aom-build
  cd aom-build
    do_cmake_from_build_dir .. "-DENABLE_EXAMPLES=OFF -DENABLE_TESTS=OFF" # google test fail
    do_ninja_and_ninja_install
  cd ../..
}

build_dav1d() {
  do_git_checkout $dav1d_git libdav1d
  cd libdav1d
    #if [[ $bits_target == 32 || $bits_target == 64 ]]; then # XXX why 64???
      #apply_patch file://$patch_dir/david_no_asm.patch -p1 # XXX report
    #fi
    #cpu_count=1 # XXX report :|
    local meson_options="--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib --buildtype=release --default-library=static"
    do_meson "$meson_options"
    do_ninja_and_ninja_install
    #cp build/src/libdav1d.a $mingw_w64_x86_64_prefix/lib || exit 1 # avoid 'run ranlib' weird failure, possibly older meson's https://github.com/mesonbuild/meson/issues/4138 :|
    #cpu_count=$original_cpu_count
  cd ..
}

build_avisynth() {
  do_git_checkout $avisynth_git avisynth-git
  cd avisynth-git
    do_cmake "-DBUILD_SHARED_LIBS=OFF"
    do_ninja_and_ninja_install
  cd ..
}

build_libx265() {
  do_git_checkout $x265_git x265-git 
  cd x265-git

  local cmake_params="-DENABLE_SHARED=OFF" # build x265.exe

  # Apply x86 noasm detection fix on newer versions
  apply_patch "file://$patch_dir/x265_x86_noasm_fix.patch" -p1

  mkdir -p 8bit/build-sandbox 10bit 12bit
  
  # Build 12bit (main12)
  cd 12bit
  local cmake_12bit_params="$cmake_params -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=ON -DMAIN12=ON -DEXPORT_C_API=OFF"
  do_cmake_from_build_dir ../source "$cmake_12bit_params"
  do_ninja
  cd ..

  # Build 10bit (main10)
  cd 10bit
  local cmake_10bit_params="$cmake_params -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=ON -DENABLE_HDR10_PLUS=ON -DEXPORT_C_API=OFF"
  do_cmake_from_build_dir ../source "$cmake_10bit_params"
  do_ninja
  cd ..

  # Build 8 bit (main) with linked 10 and 12 bit then install
  cd 8bit
  cmake_params="$cmake_params -DEXTRA_LINK_FLAGS=-L. -DENABLE_CLI=ON -DLINKED_10BIT=ON -DLINKED_12BIT=ON -DEXPORT_C_API=ON"
  cmake_params+=" -DEXTRA_LIB=libx265_main10.a;libx265_main12.a"
  do_cmake_from_build_dir ../source "$cmake_params"
  cp ../10bit/build-sandbox/libx265.a build-sandbox/libx265_main10.a
  cp ../12bit/build-sandbox/libx265.a build-sandbox/libx265_main12.a
  do_ninja_and_ninja_install
  cp build-sandbox/libx265_main10.a "${mingw_w64_x86_64_prefix}/lib"
  cp build-sandbox/libx265_main12.a "${mingw_w64_x86_64_prefix}/lib"
  sed -i.bak "s|-lx265.*|-lx265 -lx265_main10 -lx265_main12 -static-libgcc|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/x265.pc"
  cd ../..
}

build_libopenh264() {
  do_git_checkout "$libopenh264_git" openh264_git 75b9fcd2669c75a99791 # wels/codec_api.h weirdness
  cd openh264_git
    sed -i.bak "s/_M_X64/_M_DISABLED_X64/" codec/encoder/core/inc/param_svc.h # for 64 bit, avoid missing _set_FMA3_enable, it needed to link against msvcrt120 to get this or something weird?
    local arch=x86_64
    # No need for 'do_make_install', because 'install-static' already has install-instructions. we want install static so no shared built...
    do_make "$make_prefix_options ASM=nasm install-static"
    
  cd ..
}

build_libx264() {
  do_git_checkout $x264_git x264-git
  cd x264-git
    if [[ ! -f configure.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/O3 -/O2 -/" configure
    fi

    local configure_flags="--enable-static --prefix=$mingw_w64_x86_64_prefix --enable-strip" # --enable-win32thread --enable-debug is another useful option here?
    configure_flags+=" --disable-lavf"
    configure_flags+=" --bit-depth=all"
    for i in $CFLAGS; do
      configure_flags+=" --extra-cflags=$i" # needs it this way seemingly :|
    done

    # normal path non profile guided
    do_configure "$configure_flags"
    do_make
    make install # force reinstall in case changed stable -> unstable

    unset LAVF_LIBS
    unset LAVF_CFLAGS
    unset SWSCALE_LIBS
  cd ..
}

build_libvvenc() {
  do_git_checkout $vvenc_git vvenc-git
  cd vvenc-git
    do_cmake_and_install "-DVVENC_ENABLE_LINK_TIME_OPT=OFF"
  cd ..
}

build_libdvdread() {
  build_libdvdcss
  do_git_checkout $libdvdread_git libdvdread-git
  cd libdvdread-git
    # XXXX better CFLAGS here...
    generic_configure "CFLAGS=-DHAVE_DVDCSS_DVDCSS_H LDFLAGS="$LDFLAGS -ldvdcss" --enable-dlfcn" # vlc patch: "--enable-libdvdcss" # XXX ask how I'm *supposed* to do this to the dvdread peeps [svn?]
    do_make_and_make_install
    sed -i.bak 's/-ldvdread.*/-ldvdread -ldvdcss/' "${mingw_w64_x86_64_prefix}/lib/pkgconfig/dvdread.pc"
  cd ..
}

build_libdvdcss() {
  generic_download_and_make_and_install $libdvdcss_tar
}

build_libhdhomerun() {
  exit 1 # still broken unfortunately, for cross compile :|
  download_and_unpack_file https://download.silicondust.com/hdhomerun/libhdhomerun_20150826.tgz libhdhomerun
  cd libhdhomerun
    do_make CROSS_COMPILE=$cross_prefix  OS=Windows_NT
  cd ..
}

build_flac() {
  do_git_checkout $FLAC_URL flac-git
  cd flac-git
    do_cmake_and_install "-DBUILD_DOCS=OFF -DINSTALL_MANPAGES=OFF"
  cd ..
}

build_libglslang() {
  do_git_checkout $LIBGLSLANG_URL libglslang-git
  cd libglslang-git
   ./update_glslang_sources.py
   do_cmake_and_install
  cd ..
}

build_omx() {
  do_git_checkout $OMX_URL omx-git
  cd omx-git
    # TODO: better implementation of this
    apply_patch file://$patch_dir/omx-patch.patch -p1 "patch" # fix -Werror default
    do_configure "--disable-doc"
    make clean
    make -j $cpu_count
    make -j $cpu_count
    do_make_install
  cd ..
}

build_openal() {
  do_git_checkout $OPENAL_URL openal-soft-git
  cd openal-soft-git
    do_cmake_and_install "-DALSOFT_STATIC_LIBGCC=ON -DALSOFT_STATIC_STDCXX=OFF -DLIBTYPE=STATIC"
  cd ..
}

build_libcap() {
  do_git_checkout $LIBCAP_URL libcap-git
  cd libcap-git
    do_make_and_make_install "prefix=$mingw_w64_x86_64_prefix"
    ln -s "${mingw_w64_x86_64_prefix}/lib64/pkgconfig/libcap.pc" "${mingw_w64_x86_64_prefix}/lib/pkgconfig"
    ln -s "${mingw_w64_x86_64_prefix}/lib64/pkgconfig/libpsx.pc" "${mingw_w64_x86_64_prefix}/lib/pkgconfig"
    rm -f "${mingw_w64_x86_64_prefix}/lib64/*.so.*"
  cd ..
}

buid_util_linux() {
  do_git_checkout $UTIL_LINUX_URL util-linux-git
  cd util-linux-git
    do_meson "-Dbuild-libmount=enabled"
    do_ninja_and_ninja_install
  cd ..
}

build_glu() {
  do_git_checkout $GLU_URL "glu-git" "debian-unstable"
  cd glu-git
    export CC=gcc
    export CXX=g++
    generic_configure_make_install
    reset_compiler
  cd ..
}

build_libatomic_ops() {
  do_git_checkout $LIPATOMIC_OPS_URL libatomic-ops-git
  cd libatomic-ops-git
    do_cmake_and_install
  cd ..
}

build_libpciaccess() {
  do_git_checkout $LIBPCIACCESS_URL libpciaccess-git
  cd libpciaccess-git
    do_meson
    do_ninja_and_ninja_install
  cd ..
}

build_libdrm() {
  build_libatomic_ops
  build_libpciaccess
  do_git_checkout $LIBDRM_URL libdrm-git
  cd libdrm-git
    do_meson "-Dintel=enabled -Dradeon=enabled -Damdgpu=enabled -Dnouveau=enabled -Dvmwgfx=enabled -Dtests=false"
    do_ninja_and_ninja_install
  cd ..
}


build_libva() {
  build_libdrm
  do_git_checkout_and_make_install $LIBVA_URL libav-git
}

build_opencl() {
  build_glu
  #build_systemd # build for udev but broken install libudev-dev instead
  do_git_checkout $OPENCL_HEADER_URL opencl-git
  cd opencl-git
    do_cmake "-DBUILD_TESTING=OFF -DBUILD_DOCS=OFF -DBUILD_EXAMPLES=OFF -DOPENCL_SDK_BUILD_SAMPLES=OFF -DOPENCL_SDK_BUILD_SAMPLES=OFF"
    do_ninja_and_ninja_install
  cd ..
}

build_libvpl() {
  do_git_checkout $LIBVPL_URL libvpl-git
  cd libvpl-git
    do_cmake "-DBUILD_SHARED_LIBS=OFF"
    do_ninja_and_ninja_install
  cd ..
}

build_libcdio() {
  do_git_checkout $LIBCDIO_URL libcdio-git
  cd libcdio-git
    generic_configure "--enable-year2038 --enable-vcd-info  --disable-rpath --enable-shared=no"
    make install -j $cpu_count # broken make build
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$(pwd)" # add this folder path to pkgconfig instead
  cd ..
}

# this is the actual library ffmpeg need 
build_libcdio_paranoia() {
  build_libcdio
  do_git_checkout $LIBCDIO_CDPARANOIA_URL libcdio-paranoia-git
  cd libcdio-paranoia-git
    generic_configure "--enable-shared=no"
    do_make_and_make_install
  cd ..
}

build_libcodec2() {
  do_git_checkout $CODEC2_URL codec2-git
  cd codec2-git
    grep -ERl "\b(lsp|lpc)_to_(lpc|lsp)" --include="*.[ch]" | \
    xargs -r sed -ri "s;((lsp|lpc)_to_(lpc|lsp));c2_\1;g"
    
    do_cmake_and_install
  cd ..
}

build_rav1e() {
  do_git_checkout $RAV1E_URL rav1e-git
  cd rav1e-git
    do_cargo_install "cinstall"
    #rm -rf "${mingw_w64_x86_64_prefix}/lib/x86_64-linux-gnu/librav1e.*"
  cd ..
}

build_libopenmpt() {
  do_svn_checkout $LIBOPENMPT_URL openmpt-git
  cd openmpt-git
    local make_option="PREFIX=$mingw_w64_x86_64_prefix SHARED_LIB=0 STATIC_LIB=1 TEST=0"
    make_option+=" EXAMPLES=0 DYNLINK=0 NO_FLAC=1 NO_OGG=1 NO_VORBIS=1 NO_VORBISFILE=1"
    make_option+=" NO_SDL2=1 NO_FLAC=1 NO_SNDFILE=1"
    do_make_and_make_install "$make_option"
  cd ..
}

reset_cflags() {
  export CFLAGS=$original_cflags
  export CXXFLAGS=$original_cflags
}

reset_cppflags() {
  export CPPFLAGS=$original_cppflags
}

reset_ldflags() {
  export LDFLAGS=$original_ldflags
}

reset_compiler() {
  unset CC
  unset CXX
}

build_mp4box() { # like build_gpac
  # This script only builds the gpac_static lib plus MP4Box. Other tools inside
  # specify revision until this works: https://sourceforge.net/p/gpac/discussion/287546/thread/72cf332a/
  do_git_checkout $gpac_git mp4box_gpac_git
  cd mp4box_gpac_git
    # are these tweaks needed? If so then complain to the mp4box people about it?
    sed -i.bak "s/has_dvb4linux=\"yes\"/has_dvb4linux=\"no\"/g" configure
    # XXX do I want to disable more things here?
    # ./sandbox/cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-sdl-config
    generic_configure " --target-os=MINGW32 --extra-cflags=-Wno-format --static-build --static-bin --disable-oss-audio --extra-ldflags=-municode --disable-x11 --sdl-cfg=${cross_prefix}sdl-config"
    ./check_revision.sh
    # I seem unable to pass 3 libs into the same config line so do it with sed...
    sed -i.bak "s/EXTRALIBS=.*/EXTRALIBS=-lws2_32 -lwinmm -lz/g" config.mak
    cd src
      do_make "$make_prefix_options"
    cd ..
    rm -f ./bin/gcc/MP4Box* # try and force a relink/rebuild of the .exe
    cd applications/mp4box
      rm -f already_ran_make* # ??
      do_make "$make_prefix_options"
    cd ../..
    # copy it every time just in case it was rebuilt...
    cp ./bin/gcc/MP4Box ./bin/gcc/MP4Box.exe # it doesn't name it .exe? That feels broken somehow...
    echo "built $(readlink -f ./bin/gcc/MP4Box.exe)"
  cd ..
}

build_ffmpeg() {
  local extra_postpend_configure_options=$2
  local build_type=$1
  if [[ -z $3 ]]; then
    local output_dir="ffmpeg-git"
  fi
  
  local postpend_configure_opts=""
  local install_prefix=""
  # can't mix and match --enable-static --enable-shared unfortunately, or the final executable seems to just use shared if the're both present
  install_prefix="${mingw_w64_x86_64_prefix}" # don't really care since we just pluck ffmpeg.exe out of the src dir for static, but x264 pre wants it installed...

  # allow using local source directory version of ffmpeg
  if [[ -z $ffmpeg_source_dir ]]; then
    do_git_checkout $ffmpeg_git_checkout $output_dir $ffmpeg_git_checkout_version || exit 1
  else
    output_dir="${ffmpeg_source_dir}"
    install_prefix="${output_dir}"
  fi
    postpend_configure_opts="--enable-static --disable-shared --prefix=${install_prefix}"
  cd $output_dir
    #apply_patch file://$patch_dir/frei0r_load-shared-libraries-dynamically.diff
    local arch=x86_64
    #sed -i.bak "s|-lstdc++ -lm -lgcc_s -lgcc -lc -lgcc_s -lgcc|-static-libgcc -lstdc++ -lm -static-libgcc -lc -static-libgcc|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/srt.pc"
    #sed -i.bak "s|-lstdc++ -lm -lgcc_s -lgcc -lgcc_s -lgcc -lrt -ldl|-static-libgcc -lstdc++ -lm -static-libgcc -lrt -ldl|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/x265.pc"
    sed -i.bak "s|-static-libgcc -pthread -ldl -latomic -lm|-static-libgcc -lstdc++ -pthread -ldl -latomic -lm|" "${mingw_w64_x86_64_prefix}/lib64/pkgconfig/openal.pc"
    sed -i.bak "s|-lvpl -ldl.*|-lvpl -ldl -lmfx -lstdc++ -ldl|" "${mingw_w64_x86_64_prefix}/lib64/pkgconfig/vpl.pc"
    #sed -i.bak "s|-lcdio_cdda -lcdio -lm|-lcdio_cdda -lcdio -lm -liconv|" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/libcdio_cdda.pc"
    ln -s "${mingw_w64_x86_64_prefix}/share/pkgconfig/OpenCL-Headers.pc" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/"
    ln -s "${mingw_w64_x86_64_prefix}/lib/pkgconfig/OpenCL-Headers.pc" "${mingw_w64_x86_64_prefix}/lib/pkgconfig/OpenCL.pc"
    
    python "../../../python/symlink_all_file.py" \
    --input-folder "${mingw_w64_x86_64_prefix}/lib/x86_64-linux-gnu/pkgconfig/" \
    --output-folder "${mingw_w64_x86_64_prefix}/lib/pkgconfig/" || (echo "symlink failed" && exit 1)

    python "../../../python/symlink_all_file.py" \
    --input-folder "${mingw_w64_x86_64_prefix}/lib64/pkgconfig/" \
    --output-folder "${mingw_w64_x86_64_prefix}/lib/pkgconfig/" || (echo "symlink failed" && exit 1)
    
    config_options="--pkg-config=pkg-config --pkg-config-flags=--static --extra-version=ffmpeg-build-helpers --enable-version3 --disable-debug --disable-w32threads"
    # just use locally packages for all the xcb stuff for now, you need to install them locally first...
    
    config_options+=" --extra-cflags=-Wno-error=incompatible-pointer-types" # broke lib4lv2 in ffmpeg gcc-14 thing don't know how to fix
    config_options+=" --enable-libvvenc"
    config_options+=" --enable-version3"
    config_options+=" --enable-libxcb-shm" 
    config_options+=" --enable-libxcb-xfixes" 
    config_options+=" --enable-libxcb-shape"
    config_options+=" --enable-libxcb"
    config_options+=" --enable-libv4l2"
    config_options+=" --enable-libcaca"
    config_options+=" --enable-gray"
    #config_options+=" --enable-libtesseract"
    config_options+=" --enable-fontconfig"
    config_options+=" --enable-gmp"
    config_options+=" --enable-libass"
    config_options+=" --enable-libbluray"
    config_options+=" --enable-libbs2b"
    #config_options+=" --enable-libflite"
    config_options+=" --enable-libfreetype"
    config_options+=" --enable-libfribidi"
    config_options+=" --enable-libgme"
    config_options+=" --enable-libgsm"
    config_options+=" --enable-libilbc"
    config_options+=" --enable-libmodplug"
    config_options+=" --enable-libmp3lame"
    config_options+=" --enable-libopencore-amrnb"
    config_options+=" --enable-libopencore-amrwb"
    config_options+=" --enable-libopus"
    config_options+=" --enable-libsnappy"
    config_options+=" --enable-libsoxr"
    config_options+=" --enable-libspeex"
    config_options+=" --enable-libtheora"
    config_options+=" --enable-libtwolame"
    config_options+=" --enable-libvo-amrwbenc"
    config_options+=" --enable-libvorbis"
    config_options+=" --enable-libwebp"
    config_options+=" --enable-libzimg"
    config_options+=" --enable-libzvbi"
    config_options+=" --enable-libmysofa"
    config_options+=" --enable-libopenjpeg"
    config_options+=" --enable-libopenh264"
    config_options+=" --enable-libvmaf"
    config_options+=" --enable-libsrt"
    config_options+=" --enable-libxml2"
    config_options+=" --enable-opengl" # cannot static ? 
    config_options+=" --enable-libdav1d"
    config_options+=" --enable-gnutls"
    config_options+=" --enable-ffnvcodec"
    config_options+=" --enable-cuda"
    config_options+=" --enable-cuvid"
    config_options+=" --enable-nvdec"
    config_options+=" --enable-cuda-llvm"
    config_options+=" --enable-libharfbuzz"
    config_options+=" --enable-filter=drawtext"
    config_options+=" --enable-omx"
    config_options+=" --enable-libglslang"
    config_options+=" --enable-openal"
    config_options+=" --enable-opencl"
    config_options+=" --enable-libdvdread"
    config_options+=" --enable-sdl2"
    config_options+=" --enable-vulkan-static" # window only ? 
    config_options+=" --enable-vulkan" # cannot static ?
    config_options+=" --enable-vaapi"
    config_options+=" --enable-v4l2-m2m"
    config_options+=" --enable-vdpau" # cannot static ? 
    config_options+=" --enable-libvpl"
    config_options+=" --enable-vapoursynth"
    config_options+=" --enable-libcdio" # this need libcdio-paranoia not libcdio or libcdparanoia
    config_options+=" --enable-libcodec2"
    config_options+=" --enable-librav1e"
    config_options+=" --enable-libfontconfig"
    config_options+=" --enable-libopenmpt"

    
    if [[ $libvmaf_cuda == "y" ]]; then
    # should be fine even if paths are hard code
      config_options+=" --extra-cflags=-I/usr/local/cuda/include"
      config_options+=" --extra-ldflags=-L/usr/local/cuda/lib64"
      config_options+=" --extra-ldflags=-L/usr/local/cuda/lib64/stubs"
      #config_options+=" --enable-cuda-nvcc"
    fi

      if [[ $build_svt_hevc = y ]]; then
        # SVT-HEVC
        # Apply the correct patches based on version. Logic (n4.4 patch for n4.2, n4.3 and n4.4)  based on patch notes here:
        # https://github.com/OpenVisualCloud/SVT-HEVC/commit/b5587b09f44bcae70676f14d3bc482e27f07b773#diff-2b35e92117ba43f8397c2036658784ba2059df128c9b8a2625d42bc527dffea1
        # newer:
        git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/master-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
        config_op_mingw_patches_lametions+=" --enable-libsvthevc"
      fi
      if [[ $build_svt_vp9 = y ]]; then
        # SVT-VP9
        # Apply the correct patches based on version. Logic (n4.4 patch for n4.2, n4.3 and n4.4)  based on patch notes here:
        # https://github.com/OpenVisualCloud/SVT-VP9/tree/master/ffmpeg_plugin
        # newer:
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/master-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
        config_options+=" --enable-libsvtvp9"
      fi
    config_options+=" --enable-libsvtav1"
    config_options+=" --enable-libvpx"
    config_options+=" --enable-libaom"
    config_options+=" --enable-amf"

    # the order of extra-libs switches is important (appended in reverse)
    config_options+=" --extra-libs=-lz"
    config_options+=" --extra-libs=-lpng"
    config_options+=" --extra-libs=-lm" # libflite seemed to need this linux native...and have no .pc file huh?
    config_options+=" --extra-libs=-lfreetype" # libbluray need
    config_options+=" --extra-libs=-lpthread" # for some reason various and sundry needed this linux native
    config_options+=" --extra-libs=-lmpg123" # ditto libm3lame need
    config_options+=" --extra-libs=-liconv" # libcdio need this ?

    config_options+=" --extra-cflags=-DLIBTWOLAME_STATIC --extra-cflags=-DMODPLUG_STATIC --extra-cflags=-DCACA_STATIC" # if we ever do a git pull then it nukes changes, which overrides manual changes to configure, so just use these for now :|

      
    
    if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5.1"* ]] && [[ $ffmpeg_git_checkout_version != *"n5.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n4.4"* ]] && [[ $ffmpeg_git_checkout_version != *"n4.3"* ]] && [[ $ffmpeg_git_checkout_version != *"n4.2"* ]] && [[ $ffmpeg_git_checkout_version != *"n4.1"* ]] && [[ $ffmpeg_git_checkout_version != *"n3.4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3.2"* ]] && [[ $ffmpeg_git_checkout_version != *"n2.8"* ]]; then
      # Disable libaribcatption on old versions
      config_options+=" --enable-libaribcaption" # libaribcatption (MIT licensed)
    fi
    config_options+=" --enable-gpl --enable-frei0r --enable-librubberband --enable-libvidstab --enable-libx264 --enable-libx265 --enable-avisynth --enable-libaribb24"
    config_options+=" --enable-libxvid --enable-libdavs2"
      if [[ $host_target != 'i686-w64-mingw32' ]]; then
        config_options+=" --enable-libxavs2"
      fi
      if [[ $compiler_flavors != "native" ]]; then
        config_options+=" --enable-libxavs" # don't compile OS X
      fi
    local licensed_gpl=n # lgpl build with libx264 included for those with "commercial" license :)
    if [[ $licensed_gpl == 'y' ]]; then
      apply_patch file://$patch_dir/x264_non_gpl.diff -p1
      config_options+=" --enable-libx264"
    fi
    # other possibilities:
    #   --enable-w32threads # [worse UDP than pthreads, so not using that]

    for i in $CFLAGS; do
      config_options+=" --extra-cflags=$i" # --extra-cflags may not be needed here, but adds it to the final console output which I like for debugging purposes
    done

    for i in $LDFLAGS; do
      config_options+=" --extra-ldflags=$i" # --extra-ldflags may not be needed here, but adds it to the final console output which I like for debugging purposes
    done

    if [[ $enable_lto == "y" ]]; then
      config_options+=" --enable-lto"
      config_options+=" --extra-cflags=-flto=$cpu_count" # gcc use 1 cpu by default if only -flto is set
    fi  
    
    if [[ $use_clang == "y" ]]; then
      config_options+=" --cc=clang --cxx=clang++"
    fi

    config_options+=" $postpend_configure_opts"

    config_options+=" --enable-nonfree --enable-libfdk-aac"
      # other possible options: --enable-openssl [unneeded since we already use gnutls]

    do_debug_build=n # if you need one for backtraces/examining segfaults using gdb.exe ... change this to y :) XXXX make it affect x264 too...and make it real param :)
    config_options+=" $extra_postpend_configure_options"

    do_configure "$config_options"
    rm -f */*.a */*.dll *.exe # just in case some dependency library has changed, force it to re-link even if the ffmpeg source hasn't changed...
    rm -f already_ran_make*
    echo "doing ffmpeg make $(pwd)"

    do_make_and_make_install # install ffmpeg as well (for shared, to separate out the .dll's, for things that depend on it like VLC, to create static libs)

    # build ismindex.exe, too, just for fun
    if [[ $build_ismindex == "y" ]]; then
      make tools/ismindex.exe || exit 1
    fi

    # XXX really ffmpeg should have set this up right but doesn't, patch FFmpeg itself instead...
    if [[ $1 == "static" ]]; then
     # nb we can just modify this every time, it getes recreated, above..
      if [[ $build_intel_qsv = y  && $compiler_flavors != "native" ]]; then # Broken for native builds right now: https://github.com/lu-zero/mfx_dispatch/issues/71
        sed -i.bak 's/-lavutil -pthread -lm /-lavutil -pthread -lm -lmfx -lstdc++ -lmpg123 -lshlwapi /' "$PKG_CONFIG_PATH/libavutil.pc"
      else
        sed -i.bak 's/-lavutil -pthread -lm /-lavutil -pthread -lm -lmpg123 -lshlwapi /' "$PKG_CONFIG_PATH/libavutil.pc"
      fi
    fi

    sed -i.bak 's/-lswresample -lm.*/-lswresample -lm -lsoxr/' "$PKG_CONFIG_PATH/libswresample.pc" # XXX patch ffmpeg

    if [[ $non_free == "y" ]]; then
      if [[ $build_type == "shared" ]]; then
        echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)/bin"
      else
        echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)"
      fi
    else
      mkdir -p $cur_dir/redist
      archive="$cur_dir/redist/ffmpeg-$(git describe --tags --match N)-win$bits_target-$1"
      if [[ $original_cflags =~ "pentium3" ]]; then
        archive+="_legacy"
      fi
      if [[ $build_type == "shared" ]]; then
        echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)/bin"
        # Some manual package stuff because the install_root may be cluttered with static as well...
        # XXX this misses the docs and share?
        if [[ ! -f $archive.7z ]]; then
          sed "s/$/\r/" COPYING.GPLv3 > bin/COPYING.GPLv3.txt # XXX we include this even if it's not a GPL build?
          cp -r include bin
          cd bin
            7z a -mx=9 $archive.7z include *.exe *.dll *.lib COPYING.GPLv3.txt && rm -f COPYING.GPLv3.txt
          cd ..
        fi
      else
        echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)" `date`
        if [[ ! -f $archive.7z ]]; then
          sed "s/$/\r/" COPYING.GPLv3 > COPYING.GPLv3.txt
          echo "creating distro zip..." # XXX opt in?
          7z a -mx=9 $archive.7z ffmpeg.exe ffplay.exe ffprobe.exe COPYING.GPLv3.txt && rm -f COPYING.GPLv3.txt
        else
          echo "not creating distro zip as one already exists..."
        fi
      fi
      echo "You will find redistributable archive .7z file in $archive.7z"
    fi

  if [[ -z $ffmpeg_source_dir ]]; then
    cd ..
  fi
  while IFS= read -r file; do
    found+=("$(readlink -f "$file")")
  done < <(
    find . \( \
      -name "ffmpeg.exe" -o -name "ffmpeg_g.exe" -o -name "ffplay.exe" -o -name "ffmpeg" \
      -o -name "ffplay" -o -name "ffprobe" -o -name "MP4Box.exe" -o -name "mplayer.exe" \
      -o -name "mencoder.exe" -o -name "avconv.exe" -o -name "avprobe.exe" -o -name "x264.exe" \
      -o -name "writeavidmxf.exe" -o -name "writeaviddv50.exe" -o -name "rtmpdump.exe" \
      -o -name "x265.exe" -o -name "ismindex.exe" -o -name "dvbtee.exe" -o -name "boxdumper.exe" \
      -o -name "muxer.exe" -o -name "remuxer.exe" -o -name "timelineeditor.exe" \
      -o -name "lwcolor.auc" -o -name "lwdumper.auf" -o -name "lwinput.aui" \
      -o -name "lwmuxer.auf" -o -name "vslsmashsource.dll" -o -name "vlc.exe" \
    \)
  )

  # Print all found executables (pseudo return value)
  printf "%s\n" "${found[@]}"
}


build_ffmpeg_dependencies() {
  if [[ $build_dependencies = "n" ]]; then
    echo "Skip build ffmpeg dependency libraries..."
    return
  fi

  echo "Building ffmpeg dependency libraries..."
  if [[ $compiler_flavors != "native" ]]; then # build some stuff that don't build native...
    build_dlfcn
    build_libxavs
  fi
  build_libv4l2 # put in the top, read comment in function
  build_libaom
  build_libx265
  build_libdavs2
  build_rav1e
  build_libxavs2

  build_mingw_std_threads
  build_libffi
  build_zlib # Zlib in FFmpeg is autodetected.
  build_libcaca # Uses zlib and dlfcn (on windows).
  build_bzip2 # Bzlib (bzip2) in FFmpeg is autodetected.
  build_liblzma # Lzma in FFmpeg is autodetected. Uses dlfcn.
  build_iconv # Iconv in FFmpeg is autodetected. Uses dlfcn.
  build_sdl2 # Sdl2 in FFmpeg is autodetected. Needed to build FFPlay. Uses iconv and dlfcn.
  build_amd_amf_headers
  build_intel_qsv_mfx
  build_nv_headers
  build_libzimg # Uses dlfcn.
  build_libopenjpeg
  build_glew
  build_glfw
  #build_libjpeg_turbo # mplayer can use this, VLC qt might need it? [replaces libjpeg] (ffmpeg seems to not need it so commented out here)
  build_libpng # Needs zlib >= 1.0.4. Uses dlfcn.
  build_libwebp # Uses dlfcn.
  build_harfbuzz
  # harf does now include build_freetype # Uses zlib, bzip2, and libpng.
  build_libxml2 # Uses zlib, liblzma, iconv and dlfcn.
  build_libvmaf
  build_fontconfig # Needs freetype and libxml >= 2.6. Uses iconv and dlfcn.
  build_gmp # For rtmp support configure FFmpeg with '--enable-gmp'. Uses dlfcn.
  #build_librtmfp # mainline ffmpeg doesn't use it yet
  build_libnettle # Needs gmp >= 3.0. Uses dlfcn.
  build_libunistring
  build_libidn2 # needs iconv and unistring
  #build_gnutls # Needs nettle >= 3.1, hogweed (nettle) >= 3.1. Uses libidn2, unistring, zlib, and dlfcn.
  #if [[ "$non_free" = "y" ]]; then
  #  build_openssl-1.0.2 # Nonfree alternative to GnuTLS. 'build_openssl-1.0.2 "dllonly"' to build shared libraries only.
  #  build_openssl-1.1.1 # Nonfree alternative to GnuTLS. Can't be used with LibRTMP. 'build_openssl-1.1.1 "dllonly"' to build shared libraries only.
  #fi
  build_libogg # Uses dlfcn.
  build_libvorbis # Needs libogg >= 1.0. Uses dlfcn.
  build_libopus # Uses dlfcn.
  build_libspeexdsp # Needs libogg for examples. Uses dlfcn.
  build_libspeex # Uses libspeexdsp and dlfcn.
  build_libtheora # Needs libogg >= 1.1. Needs libvorbis >= 1.0.1, sdl and libpng for test, programs and examples [disabled]. Uses dlfcn.
  build_libsndfile "install-libgsm" # Needs libogg >= 1.1.3 and libvorbis >= 1.2.3 for external support [disabled]. Uses dlfcn. 'build_libsndfile "install-libgsm"' to install the included LibGSM 6.10.
  build_mpg123
  build_mp3lame # Uses dlfcn, mpg123
  build_twolame # Uses libsndfile >= 1.0.0 and dlfcn.
  build_libopencore # Uses dlfcn.
  build_libilbc # Uses dlfcn.
  build_libmodplug # Uses dlfcn.
  build_libgme
  build_libbluray # Needs libxml >= 2.6, freetype, fontconfig. Uses dlfcn.
  build_libbs2b # Needs libsndfile. Uses dlfcn.
  build_libsoxr
  #build_libflite
  build_libsnappy # Uses zlib (only for unittests [disabled]) and dlfcn.
  build_vamp_plugin # Needs libsndfile for 'vamp-simple-host.exe' [disabled].
  build_fftw # Uses dlfcn.
  build_libsamplerate # Needs libsndfile >= 1.0.6 and fftw >= 0.15.0 for tests. Uses dlfcn.
  build_librubberband # Needs libsamplerate, libsndfile, fftw and vamp_plugin. 'configure' will fail otherwise. Eventhough librubberband doesn't necessarily need them (libsndfile only for 'rubberband.exe' and vamp_plugin only for "Vamp audio analysis plugin"). How to use the bundled libraries '-DUSE_SPEEX' and '-DUSE_KISSFFT'?
  build_frei0r # Needs dlfcn. could use opencv...
  if [[ $build_svt_hevc = y ]]; then
      build_svt-hevc
  fi
  if [[ $build_svt_vp9 = y ]]; then
    build_svt-vp9
  fi
  build_svt-av1
  build_libvvenc
  build_vidstab
  #build_facebooktransform360 # needs modified ffmpeg to use it so not typically useful
  build_libmysofa # Needed for FFmpeg's SOFAlizer filter (https://ffmpeg.org/ffmpeg-filters.html#sofalizer). Uses dlfcn.
  build_fdk-aac # Uses dlfcn.
  build_zvbi # Uses iconv, libpng and dlfcn.
  build_fribidi # Uses dlfcn.
  build_libass # Needs freetype >= 9.10.3 (see https://bugs.launchpad.net/ubuntu/+source/freetype1/+bug/78573 o_O) and fribidi >= 0.19.0. Uses fontconfig >= 2.10.92, iconv and dlfcn.

  build_libxvid # FFmpeg now has native support, but libxvid still provides a better image.
  #build_libsrt # requires gnutls, mingw-std-threads
  if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5.1"* ]] && [[ $ffmpeg_git_checkout_version != *"n5.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n4.4"* ]] && [[ $ffmpeg_git_checkout_version != *"n4.3"* ]] && [[ $ffmpeg_git_checkout_version != *"n4.2"* ]] && [[ $ffmpeg_git_checkout_version != *"n4.1"* ]] && [[ $ffmpeg_git_checkout_version != *"n3.4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3.2"* ]] && [[ $ffmpeg_git_checkout_version != *"n2.8"* ]]; then
    build_libaribcaption
  fi
  build_libaribb24
  #build_libtesseract
  build_lensfun  # requires png, zlib, iconv  if [[ $build_lsw = "y" ]]; then
  #build_libtensorflow # broken
  build_libvpx
  build_libopenh264
  build_dav1d
  build_avisynth
  build_libx264 # at bottom as it might internally build a copy of ffmpeg (which needs all the above deps...
  build_libglslang
  build_flac
  build_omx
  build_libdvdread
  build_openal
  build_opencl
  build_libvpl
  build_libva
  build_libcdio_paranoia 
  build_libcodec2
  build_libopenmpt
 }

build_apps() {
  # now the things that use the dependencies...
  if [[ $build_mp4box = "y" ]]; then
    build_mp4box
  fi
  if [[ $build_ffmpeg_static = "y" ]]; then
    build_ffmpeg static
  fi
}

# set some parameters initial values
top_dir="$(pwd)"
cur_dir="$(pwd)/sandbox"
patch_dir="$(pwd)/patches"
cpu_count="$(nproc)" # linux cpu count
if [ -z "$cpu_count" ]; then
  cpu_count=`sysctl -n hw.ncpu | tr -d '\n'` # OS X cpu count
  if [ -z "$cpu_count" ]; then
    echo "warning, unable to determine cpu count, defaulting to 1"
    cpu_count=1 # else default to just 1, instead of blank, which means infinite
  fi
fi

set_box_memory_size_bytes
if [[ $box_memory_size_bytes -lt 600000000 ]]; then
  echo "your box only has $box_memory_size_bytes, 512MB (only) boxes crash when building cross compiler gcc, please add some swap" # 1G worked OK however...
  exit 1
fi

if [[ $box_memory_size_bytes -gt 2000000000 ]]; then
  gcc_cpu_count=$cpu_count # they can handle it seemingly...
else
  echo "low RAM detected so using only one cpu for gcc compilation"
  gcc_cpu_count=1 # compatible low RAM...
fi

# variables with their defaults
build_ffmpeg_static=y
build_dependencies=y
git_get_latest=y
prefer_stable=n # Only for x264 and x265.
build_intel_qsv=y # note: not windows xp friendly!
build_amd_amf=y
original_cflags='-march=native -mtune=native -O3' # high compatible by default, see #219, some other good options are listed below, or you could use -march=native to target your local box:
# Needed for mingw-w64 7 as FORTIFY_SOURCE is now partially implemented, but not actually working
# if you specify a march it needs to first so x264's configure will use it :| [ is that still the case ?]

#flags=$(cat /proc/cpuinfo | grep flags)
#if [[ $flags =~ "ssse3" ]]; then # See https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html, https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html and https://stackoverflow.com/questions/19689014/gcc-difference-between-o3-and-os.
#  original_cflags='-march=core2 -O2'
#elif [[ $flags =~ "sse3" ]]; then
#  original_cflags='-march=prescott -O2'
#elif [[ $flags =~ "sse2" ]]; then
#  original_cflags='-march=pentium4 -O2'
#elif [[ $flags =~ "sse" ]]; then
#  original_cflags='-march=pentium3 -O2 -mfpmath=sse -msse'
#else
#  original_cflags='-mtune=generic -O2'
#fi
ffmpeg_git_checkout_version=
ffmpeg_git_checkout="https://github.com/FFmpeg/FFmpeg.git"
ffmpeg_source_dir=
build_svt_hevc=n
build_svt_vp9=n
libvmaf_cuda=n
libvmaf_compiler=
original_ldflags=
enable_lto=n
skip_git_check=n

# parse command line parameters, if any
while true; do
  case $1 in
    -h | --help ) echo "available option=default_value:
      --ffmpeg-git-checkout=[https://github.com/FFmpeg/FFmpeg.git] if you want to clone FFmpeg from other repositories
      --ffmpeg-source-dir=[default empty] specifiy the directory of ffmpeg source code. When specified, git will not be used.
      --build-cpu-count=$cpu_count set to lower than your cpu cores if the background processes eating all your cpu bugs your desktop usage this will set to half if --enable-lto=y and not override by --build-cpu-count
      --sandbox-ok=n [skip sandbox prompt if y]
      --build-mp4box=n [builds MP4Box.exe from the gpac project]
      -a 'build all' builds ffmpeg, mplayer, vlc, etc. with all fixings turned on [many disabled from disuse these days]
      --build-svt-hevc=n [builds libsvt-hevc modules within ffmpeg etc.]
      --build-svt-vp9=n [builds libsvt-hevc modules within ffmpeg etc.]
      --compiler-flavors=[native] [default prompt, or skip if you already have one built]
      --cflags=[default is $original_cflags, which works on any cpu, see README for options]
      --git-get-latest=y [do a git pull for latest code from repositories like FFmpeg--can force a rebuild if changes are detected]
      --prefer-stable=n build a few libraries from releases instead of git master
      --debug Make this script  print out each line as it executes
      --build-dependencies=y [builds the ffmpeg dependencies. Disable it when the dependencies was built once and can greatly reduce build time. ]
      --libvmaf-cuda=n build ffmpeg with libvmaf_cuda filter support, require nvidia-cuda-toolkit(from your distro repo) and cuda-toolkit(from nvidia website) 
      --libvmaf-compiler= build libvmaf with specified compiler, this avoid error when compiler libvmaf with cuda support
      --ldflags= [default "not set"]
      --enable-lto=n enable lto when build
       "; exit 0 ;;
    --sandbox-ok=* ) sandbox_ok="${1#*=}"; shift ;;
    --build-cpu-count=* ) user_cpu_count="${1#*=}"; shift ;;
    --ffmpeg-git-checkout-version=* ) ffmpeg_git_checkout_version="${1#*=}"; shift ;;
    --ffmpeg-git-checkout=* ) ffmpeg_git_checkout="${1#*=}"; shift ;;
    --ffmpeg-source-dir=* ) ffmpeg_source_dir="${1#*=}"; shift ;;
    --build-mp4box=* ) build_mp4box="${1#*=}"; shift ;;
    --cflags=* )
       user_cflags="${1#*=}"; shift ;;
    --build-svt-hevc=* ) build_svt_hevc="${1#*=}"; shift ;;
    --build-svt-vp9=* ) build_svt_vp9="${1#*=}"; shift ;;
    --compiler-flavors=* )
         compiler_flavors="${1#*=}";
         shift ;;
    --prefer-stable=* ) prefer_stable="${1#*=}"; shift ;;
    --build-dependencies=* ) build_dependencies="${1#*=}"; shift ;;
    --debug ) set -x; shift ;;
    --libvmaf-cuda=* ) libvmaf_cuda="${1#*=}"; shift ;;
    --libvmaf-compiler=* ) libvmaf_compiler="${1#*=}"; shift ;;
    --ldflags=* ) original_ldflags="${1#*=}"; shift ;;
    --enable-lto=* ) enable_lto="${1#*=}"; shift ;;
    --git-get-latest=* ) git_get_latest="${1#*=}"; shift ;;
    -- ) shift; break ;;
    -* ) echo "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

original_cflags=$user_cflags
echo

original_cpu_count=$cpu_count # save it away for some that revert it temporarily
reset_cflags # also overrides any "native" CFLAGS, which we may need if there are some 'linux only' settings in there
reset_cppflags # Ensure CPPFLAGS are cleared and set to what is configured
reset_ldflags
reset_compiler # reset c compiler to clang
check_missing_packages # do this first since it's annoying to go through prompts then be rejected

echo "setting cflags as $original_cflags"
echo "setting ldflags as $original_ldflags"
intro # remember to always run the intro, since it adjust pwd

export PKG_CONFIG_LIBDIR= # disable pkg-config from finding [and using] normal linux system installed libs [yikes]

original_path="$PATH"


echo "starting native build..."
host_target=x86_64-linux-gnu
# realpath so if you run it from a different symlink path it doesn't rebuild the world...
# mkdir required for realpath first time
mkdir -p "$cur_dir/prefix/"
mkdir -p "$cur_dir/prefix/bin"
mingw_w64_x86_64_prefix="$(realpath "$cur_dir/prefix")"
mingw_bin_path="$(realpath "$cur_dir/prefix/bin")" # sdl needs somewhere to drop "binaries"??
export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig:$mingw_w64_x86_64_prefix/share/pkgconfig"
export PATH="$mingw_bin_path:$original_path"
echo "PATH include: $PATH" 
make_prefix_options="PREFIX=$mingw_w64_x86_64_prefix"
bits_target=64
#  bs2b doesn't use pkg-config, sndfile needed Carbon :|
export CPATH=""$cur_dir/prefix/include":/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Headers" # C_INCLUDE_PATH
export LIBRARY_PATH=""$cur_dir/prefix/lib""
work_dir="$(realpath "$cur_dir/source")"
mkdir -p "$work_dir"
cd "$work_dir"
  build_ffmpeg_dependencies
  build_ffmpeg
cd ..

echo "Searching for all local exe's (some may not have been built this round, NB)..."
find_all_build_exes | while IFS= read -r file; do
  echo "Built $file"
done
