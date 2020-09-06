#!/usr/bin/env bash
# ffmpeg windows cross compile helper/download script, see github repo README
# Copyright (C) 2012 Roger Pack, the script is under the GPLv3, but output FFmpeg's executables aren't

yes_no_sel() {
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
  if [[ $OSTYPE == darwin* ]]; then
    box_memory_size_bytes=20000000000 # 20G fake it out for now :|
  else
    local ram_kilobytes=`grep MemTotal /proc/meminfo | awk '{print $2}'`
    local swap_kilobytes=`grep SwapTotal /proc/meminfo | awk '{print $2}'`
    box_memory_size_bytes=$[ram_kilobytes * 1024 + swap_kilobytes * 1024]
  fi
}

check_missing_packages() {
  # zeranoe's build scripts use wget, though we don't here...
  local check_packages=('7z' 'autoconf' 'autogen' 'automake' 'bison' 'bzip2' 'cmake' 'curl' 'cvs' 'ed' 'flex' 'g++' 'gcc' 'git' 'gperf' 'hg' 'libtool' 'libtoolize' 'make' 'makeinfo' 'patch' 'pax' 'pkg-config' 'svn' 'unzip' 'wget' 'xz' 'yasm')
  for package in "${check_packages[@]}"; do
    type -P "$package" >/dev/null || missing_packages=("$package" "${missing_packages[@]}")
  done
  if [[ -n "${missing_packages[@]}" ]]; then
    clear
    echo "Could not find the following execs (svn is actually package subversion, makeinfo is actually package texinfo, hg is actually package mercurial if you're missing them): ${missing_packages[@]}"
    echo 'Install the missing packages before running this script.'
    echo "for ubuntu: $ sudo apt-get install subversion curl texinfo g++ bison flex cvs yasm automake libtool autoconf gcc cmake git make pkg-config zlib1g-dev mercurial unzip pax nasm gperf autogen -y"
    echo "for gentoo (a non ubuntu distro): same as above, but no g++, no gcc, git is dev-vcs/git, zlib1g-dev is zlib, pkg-config is dev-util/pkgconfig, add ed..."
    echo "for OS X (homebrew): brew install wget cvs hg yasm autogen automake autoconf cmake hg libtool xz pkg-config nasm"
    echo "for debian: same as ubuntu, but also add libtool-bin and ed"
    exit 1
  fi

  local out=`cmake --version` # like cmake version 2.8.7
  local version_have=`echo "$out" | cut -d " " -f 3`
  function version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }
  if [[ $(version $version_have)  < $(version '2.8.12') ]]; then
    echo "your cmake version is too old $version_have wanted 2.8.12"
    exit 1
  fi

  if [[ ! -f /usr/include/zlib.h ]]; then
    echo "warning: you may need to install zlib development headers first if you want to build mp4-box [on ubuntu: $ apt-get install zlib1g-dev]" # XXX do like configure does and attempt to compile and include zlib.h instead?
    sleep 1
  fi

  out=`yasm --version`
  yasm_version=`echo "$out" | cut -d " " -f 2` # like 1.1.0.112
  if [[ $(version $yasm_version)  < $(version '1.2.0') ]]; then
    echo "your yasm version is too old $yasm_version wanted 1.2.0"
    exit 1
  fi

  if [ ! -f $HOME/.hgrc ]; then # 'hg purge' (the Mercurial equivalent of 'git clean') isn't enabled by default.
    mkdir -p "$HOME"
    cat > $HOME/.hgrc <<EOF
[extensions]
purge =
EOF
  fi
}


intro() {
  echo `date`
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
  if [[ $sandbox_ok != 'y' && ! -d sandbox ]]; then
    echo -e "\nBuilding in $PWD/sandbox, will use ~ 4GB space!\n"
  fi
  mkdir -p "$cur_dir"
  cd "$cur_dir"
}

# made into a method so I don't/don't have to download this script every time if only doing just 32 or just6 64 bit builds...
download_gcc_build_script() {
  rm -f $1 || exit 1
  curl -4 file://$patch_dir/$1 -O --fail || exit 1
  chmod u+x $1
}

install_cross_compiler() {
  local win32_gcc="cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-gcc"
  if [[ -f $win32_gcc ]]; then
    echo -e "MinGW-w64 compilers for Win32 already installed, not re-installing.\n"
  else
    mkdir -p cross_compilers
    cd cross_compilers
      unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
      # pthreads version to avoid having to use cvs for it
      echo -e "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count.\n"

      # --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
      local zeranoe_script_name=mingw-w64-build-r28 # https://files.1f0.de/mingw/scripts/
      local zeranoe_script_options="--default-configure --cpu-count=$gcc_cpu_count --pthreads-w32-ver=2-9-1 --disable-shared --clean-build --verbose"
      echo "Building win32 cross compiler."
      download_gcc_build_script $zeranoe_script_name
      if [[ `uname` =~ "5.1" ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
        sed -i "s/ --enable-secure-api//" $zeranoe_script_name
      fi
      ./$zeranoe_script_name $zeranoe_script_options --build-type=win32 || exit 1
      if [[ ! -f ../$win32_gcc ]]; then
        echo "Failure building 32 bit gcc? Recommend nuke sandbox (rm -fr sandbox) and start over."
        exit 1
      fi

      rm -f build.log # left over stuff...
      reset_cflags
    cd ..
    echo "Done building (or already built) MinGW-w64 cross-compiler(s) successfully."
    echo -e "$(date)\n" # so they can see how long it took :)
  fi
}

do_svn_checkout() {
  local dir="$2"
  if [ ! -d $dir ]; then
    echo -e "\e[1;33mDownloading (svn checkout) ${1##*/} to $dir.\e[0m"
    if [[ $3 ]]; then
      svn checkout -r $3 $1 $dir.tmp || exit 1
    else
      svn checkout $1 $dir.tmp --non-interactive --trust-server-cert-failures=unknown-ca || exit 1
    fi
    mv $dir.tmp $dir
  else
    cd $dir
      if [[ $(svn info --show-item revision) != $(svn info --show-item revision $1) ]]; then
        echo -e "\e[1;33mUpdating $dir to latest svn revision.\e[0m"
        svn revert . -R # Return files to their original state.
        svn cleanup --remove-ignored # Clean the working tree; build- ...
        svn cleanup --remove-unversioned # ...as well as untracked files.
        svn update || exit 1
      else
        echo -e "\e[1;33mLocal $dir is up-to-date.\e[0m"
      fi
    cd ..
  fi
}

do_git_checkout() {
  if [[ $2 ]]; then
    local dir="$2"
  else
    local dir=$(basename ${1/.git/_git}) # http://y/abc.git -> abc_git
  fi
  if [[ $3 ]]; then
    local branch="$3"
  else
    local branch="master" # http://y/abc.git -> abc_git
  fi
  if [ ! -d $dir ]; then
    rm -fr $dir.tmp # just in case it was interrupted previously...
    echo -e "\e[1;33mDownloading (git clone) $1 to $dir.\e[0m"
    git clone --branch $branch --single-branch $1 $dir.tmp || exit 1
    # prevent partial checkouts by renaming it only after success
    mv $dir.tmp $dir
    if [[ $4 ]]; then
      cd $dir
        echo -e "\e[1;33mChanging head of $dir to ${4:0:7}.\e[0m"
        git checkout $4 || exit 1
      cd ..
    fi
  else
    cd $dir
      if [[ $4 ]]; then
        if [[ $(git rev-parse HEAD) != $4 ]]; then
          echo -e "\e[1;33mChanging head of $dir to ${4:0:7}.\e[0m"
          git checkout $4 || exit 1
        else
          echo -e "\e[1;33mHead of $dir is already at ${4:0:7}.\e[0m"
        fi
      elif [[ $(git rev-parse HEAD) != $(git ls-remote -h $1 $branch | sed "s/\s.*//") ]]; then
        echo -e "\e[1;33mUpdating $dir to latest git head on 'origin/$branch'.\e[0m"
        git reset --hard # Return files to their original state.
        git clean -fdx # Clean the working tree; build- as well as untracked files.
        git fetch # Fetch list of changes.
        git checkout $branch || exit 1 # Show amount of commits behind 'origin/$branch'.
        git merge origin/$branch || exit 1 # Apply changes to local repo.
      else
        echo -e "\e[1;33mLocal $dir is up-to-date.\e[0m"
      fi
    cd ..
  fi
}

do_hg_checkout() {
  if [[ $2 ]]; then
    local dir="$2"
  else
    local dir="${1##*/}_hg" # http://y/abc -> abc_hg
  fi
  if [ ! -d $dir ]; then
    rm -fr $dir.tmp # just in case it was interrupted previously...
    echo -e "\e[1;33mDownloading (hg clone) $1 to $dir.\e[0m"
    hg clone $1 $dir.tmp || exit 1
    # prevent partial checkouts by renaming it only after success
    mv $dir.tmp $dir
  else
    cd $dir
      if [[ $(hg id -i) != $(hg id -r default $1) ]]; then # 'hg id http://hg.videolan.org/x265' defaults to the "stable" branch!
        echo -e "\e[1;33mUpdating $dir to latest hg head.\e[0m"
        hg revert -a --no-backup # Return files to their original state.
        hg purge # Clean the working tree; build- as well as untracked files.
        hg pull -u || exit 1
        hg update || exit 1
      else
        echo -e "\e[1;33mLocal $dir repo is up-to-date.\e[0m"
      fi
    cd ..
  fi
}

download_and_unpack_file() {
  local name="${1##*/}"
  if [[ $2 ]]; then
    local dir="$2"
  else
    local dir="${name/.tar*/}" # remove .tar.xx
  fi
  if [ ! -f "$dir/unpacked.successfully" ]; then
    echo -e "\e[1;33mDownloading (curl) $1.\e[0m"
    if [[ -f $name ]]; then
      rm $name || exit 1
    fi
    #  From man curl
    #  -4, --ipv4
    #  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
    #  this option tells curl to resolve names to IPv4 addresses only.
    #  avoid a "network unreachable" error in certain [broken Ubuntu] configurations a user ran into once
    curl -4 "$1" --retry 50 -O -L --fail || exit 1 # -L means "allow redirection" or some odd :|
    tar -xf "$name" || unzip "$name" || exit 1
    touch "$dir/unpacked.successfully" || exit 1
    rm "$name" || exit 1
  fi
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
  echo "$1_$(echo -- "$@" $CFLAGS $LDFLAGS | /usr/bin/env md5sum | sed "s/ //g")" # md5sum to make it smaller, cflags to force rebuild if changes and sed to remove spaces that md5sum introduced.
}

do_configure() {
  if [ "${1:0:2}" == "./" ]; then
    local configure_name=$1
    local configure_options=("${@:2}")
  else
    local configure_name=./configure
    local configure_options=("${@}")
  fi
  local name=$(get_small_touchfile_name already_configured "${configure_options[@]}")
  if [ ! -f "$name" ]; then # This is to generate 'configure', 'Makefile.in' and some other files.
    if [ ! -f $configure_name ]; then
      echo -e "\e[1;33mGenerating 'configure' script.\e[0m"
      if [ -f autogen.sh ]; then
        NOCONFIGURE=1 ./autogen.sh # Without NOCONFIGURE=1 TwoLame's 'autogen.sh' will run 'configure' with no arguments.
      elif [ -f autobuild ]; then
        ./autobuild
      elif [ -f buildconf ]; then
        ./buildconf
      elif [ -f bootstrap ]; then
        ./bootstrap
      elif [ -f bootstrap.sh ]; then
        ./bootstrap.sh
      else
        autoreconf -fiv
      fi
    fi
    echo -e "\e[1;33mConfiguring ${PWD##*/} as \"${configure_options[@]}\".\e[0m"
    $configure_name "${configure_options[@]}" || exit 1
    touch $name || exit 1
  #  echo -e "\e[1;33mDoing preventative make clean.\e[0m"
  #  make -j $cpu_count clean # sometimes useful when files change, etc.
  #else
  #  echo -e "\e[1;33mAlready configured ${PWD##*/}.\e[0m"
  fi
}

generic_configure() {
  do_configure --host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static "$@"
}

do_cmake() {
  local cmake_options=(-DENABLE_STATIC_RUNTIME=1 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_FIND_ROOT_PATH=$mingw_w64_x86_64_prefix -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_RANLIB=${cross_prefix}ranlib.exe -DCMAKE_C_COMPILER=${cross_prefix}gcc.exe -DCMAKE_CXX_COMPILER=${cross_prefix}g++.exe -DCMAKE_RC_COMPILER=${cross_prefix}windres.exe -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix "${@:2}" $1)
  local name=$(get_small_touchfile_name already_ran_cmake "${cmake_options[@]}")
  if [ ! -f $name ]; then
    echo -e "\e[1;33mConfiguring ${1##*/} as \"cmake -G \"Unix Makefiles\" ${cmake_options[@]}\".\e[0m"
    cmake -G "Unix Makefiles" "${cmake_options[@]}" || exit 1
    touch $name || exit 1
  #else
  #  echo -e "\e[1;33mAlready configured ${1##*/}.\e[0m"
  fi
}

do_make() {
  local dir="${PWD/$cur_dir\/win32\/}"
  local make_options=(-j $cpu_count "$@")
  local name=$(get_small_touchfile_name already_ran_make "${make_options[@]}")
  if [ ! -f $name ]; then
    if [[ $1 == install* ]]; then
      echo -e "\e[1;33mCompiling and installing ${dir%%/*} as \"make ${make_options[@]}\".\e[0m"
    else
      echo -e "\e[1;33mCompiling ${dir%%/*} as \"make ${make_options[@]}\".\e[0m"
    fi
  #  if [ ! -f configure ]; then
  #    make -j $cpu_count clean # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
  #  fi
    make "${make_options[@]}" || exit 1
    touch $name || exit 1 # only touch if the build was OK
  else
    if [[ $1 == install* ]]; then
      echo -e "\e[1;33mAlready made and installed ${dir%%/*}.\e[0m"
    else
      echo -e "\e[1;33mAlready made ${dir%%/*}.\e[0m"
    fi
  fi
}

do_make_install() {
  local dir="${PWD/$cur_dir\/win32\/}"
  local make_install_options=(install "$@")
  local name=$(get_small_touchfile_name already_ran_make_install "${make_install_options[@]}")
  if [ ! -f $name ]; then
    echo -e "\e[1;33mInstalling ${dir%%/*} as \"make ${make_install_options[@]}\".\e[0m"
    make "${make_install_options[@]}" || exit 1
    touch $name || exit 1
  else
    echo -e "\e[1;33mAlready installed ${dir%%/*}.\e[0m"
  fi
}

apply_patch() {
  if [[ $2 ]]; then
    local type=$2 # Git patches need '-p1' (also see https://unix.stackexchange.com/a/26502).
  else
    local type="-p0"
  fi
  local name="${1##*/}"
  if [[ ! -e $name.done ]]; then
    if [[ -f $name ]]; then
      rm $name || exit 1 # remove old version in case it has been since updated on the server...
    fi
    curl -4 --retry 5 $1 -O --fail || exit 1
    echo -e "\e[1;33mApplying patch '$name'.\e[0m"
    patch $type -i "$name" || exit 1
    touch $name.done || exit 1
    rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
  else
    echo -e "\e[1;33mPatch '$name' already applied.\e[0m"
  fi
}

gen_ld_script() {
  lib=$mingw_w64_x86_64_prefix/lib/$1
  lib_s="${1:3:-2}_s"
  if [ "$1" -nt "$mingw_w64_x86_64_prefix/lib/lib$lib_s.a" ]; then
    rm $mingw_w64_x86_64_prefix/lib/lib$lib_s.a
  fi
  if [ ! -f "$mingw_w64_x86_64_prefix/lib/lib$lib_s.a" ]; then
    echo -e "\e[1;33mGenerating linker script for $1, adding $2.\e[0m"
    mv $lib $mingw_w64_x86_64_prefix/lib/lib$lib_s.a
    echo "echo \"GROUP ( -l$lib_s $2 )\" > $lib"
    echo "GROUP ( -l$lib_s $2 )" > $lib
  else
    echo -e "\e[1;33mAlready generated linker script for '$1'.\e[0m"
  fi
} # gen_ld_script libxxx.a -lxxx

build_mingw_std_threads() {
  do_git_checkout https://github.com/meganz/mingw-std-threads.git
  cd mingw-std-threads_git
    for file in *.h; do
      if [ ! -f "$mingw_w64_x86_64_prefix/include/$file" ] || [ "$file" -nt "$mingw_w64_x86_64_prefix/include/$file" ]; then
        rm -v $mingw_w64_x86_64_prefix/include/$file
        cp -v $file $mingw_w64_x86_64_prefix/include
      else
        echo -e "\e[1;33m$file is up-to-date.\e[0m"
      fi
    done
  cd ..
}

build_cmake() {
  download_and_unpack_file https://cmake.org/files/v3.18/cmake-3.18.2.tar.gz
  cd cmake-3.18.2
    do_configure --prefix=/usr -- -DBUILD_CursesDialog=0 -DBUILD_TESTING=0 # Don't build 'ccmake' (ncurses), or './configure' will fail otherwise.
    # Options after "--" are passed to CMake (Usage: ./bootstrap [<options>...] [-- <cmake-options>...])
    do_make install/strip # This overwrites Cygwin's 'cmake.exe', 'cpack.exe' and 'ctest.exe'.
  cd ..
}

build_nasm() {
  download_and_unpack_file https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.xz
  cd nasm-2.15.05
    if [[ ! -f Makefile.in.bak ]]; then # Library only and install nasm stripped.
      sed -i.bak '/man1/d;/install:/a\\t$(STRIP) --strip-unneeded nasm$(X) ndisasm$(X)' Makefile.in
    fi
    do_configure --prefix=/usr
    # No '--prefix=$mingw_w64_x86_64_prefix', because NASM has to be built with Cygwin's GCC. Otherwise it can't read Cygwin paths and you'd get errors like "nasm: fatal: unable to open output file `/cygdrive/c/DOCUME~1/Admin/LOCALS~1/Temp/ffconf.Ld8518el/test.o'" while configuring FFmpeg for instance.
    do_make install # 'nasm.exe' and 'ndisasm.exe' will be installed in '/usr/bin' (Cygwin's bin map).
  cd ..
}

build_dlfcn() {
  do_git_checkout https://github.com/dlfcn-win32/dlfcn-win32.git
  cd dlfcn-win32_git
    if [[ ! -f Makefile.bak ]]; then # Change GCC optimization level.
      sed -i.bak "s/CFLAGS =/CFLAGS +=/;s/-O3/-O2/" Makefile
    fi
    do_configure --prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix # rejects some normal cross compile options so custom here
    do_make
    do_make_install
    gen_ld_script libdl.a -lpsapi # dlfcn-win32's 'README.md': "If you are linking to the static 'dl.lib' or 'libdl.a', then you would need to explicitly add 'psapi.lib' or '-lpsapi' to your linking command, depending on if MinGW is used."
  cd ..
}

build_bzip2() {
  download_and_unpack_file https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
  cd bzip2-1.0.8
    apply_patch file://$patch_dir/bzip2-1.0.8_mingw-cross.diff
    if [[ ! -f $mingw_w64_x86_64_prefix/lib/libbz2.a ]]; then # Library only.
      do_make $make_prefix_options libbz2.a
      install -m644 libbz2.a $mingw_w64_x86_64_prefix/lib/libbz2.a
      install -m644 bzlib.h $mingw_w64_x86_64_prefix/include/bzlib.h
    else
      echo -e "\e[1;33mAlready made and installed bzip2-1.0.8.\e[0m"
    fi
  cd ..
}

build_liblzma() {
  #download_and_unpack_file https://sourceforge.net/projects/lzmautils/files/xz-5.2.4.tar.xz
  download_and_unpack_file https://github.com/xz-mirror/xz/archive/v5.2.5.tar.gz xz-5.2.5
  cd xz-5.2.5
    generic_configure --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --disable-nls
    do_make install
  cd ..
} # [dlfcn]

build_zlib() {
  download_and_unpack_file https://github.com/madler/zlib/archive/v1.2.11.tar.gz zlib-1.2.11
  cd zlib-1.2.11
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/man3dir/d" Makefile.in
    fi
    do_configure --prefix=$mingw_w64_x86_64_prefix --static
    do_make install $make_prefix_options
  cd ..
}

build_iconv() {
  download_and_unpack_file https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.16.tar.gz
  cd libiconv-1.16
    generic_configure --disable-nls
    do_make install-lib # No need for 'do_make_install', because 'install-lib' already has install-instructions.
  cd ..
} # [dlfcn]

build_sdl2() {
  download_and_unpack_file https://libsdl.org/release/SDL2-2.0.12.tar.gz
  cd SDL2-2.0.12
    if [[ ! -f Makefile.in.bak ]]; then
      sed -i.bak "/aclocal/d" Makefile.in # Library only.
      sed -i.bak "s/ -mwindows//;s/iconv_open ()/libiconv_open ()/;s/\"iconv\"/\"libiconv\"/" configure # Allow ffmpeg to output anything to console and use libiconv instead of iconv.
      sed -i.bak "/#ifndef DECLSPEC/i\#define DECLSPEC" include/begin_code.h # Needed for building shared FFmpeg libraries.
    fi
    generic_configure --bindir=$mingw_bin_path
    do_make install
    if [[ ! -f $mingw_bin_path/${host_target}-sdl2-config ]]; then
      mv -v "$mingw_bin_path/sdl2-config" "$mingw_bin_path/${host_target}-sdl2-config" # At the moment FFmpeg's 'configure' doesn't use 'sdl2-config', because it gives priority to 'sdl2.pc', but when it does, it expects 'i686-w64-mingw32-sdl2-config' in 'cross_compilers/mingw-w64-i686/bin'.
    fi
  cd ..
} # [iconv, dlfcn]

build_libwebp() {
  do_git_checkout https://chromium.googlesource.com/webm/libwebp.git
  cd libwebp_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "s/src.*/src/;4,\$d" Makefile.am
    fi
    generic_configure --disable-gl --disable-sdl --disable-png --disable-jpeg --disable-tiff --disable-gif --disable-wic # These are only necessary for building the bundled tools/binaries.
    do_make install
  cd ..
} # [dlfcn]

build_freetype() {
  download_and_unpack_file https://download.savannah.gnu.org/releases/freetype/freetype-2.10.2.tar.xz
  cd freetype-2.10.2
    if [[ ! -f builds/unix/install.mk.bak ]]; then
      sed -i.bak "/config \\\/s/\s*\\\//;/bindir) /s/\s*\\\//;/aclocal/d;/man1/d;/BUILD_DIR/d;/docs/d" builds/unix/install.mk # Library only.
      sed -i.bak "490s/if/if 0 \/\//" builds/unix/ftconfig.in # Static library.
    fi
    generic_configure --build=i686-pc-cygwin # Without '--build=i686-pc-cygwin' you'd get: "could not open '/cygdrive/[...]/include/freetype/ttnameid.h' for writing".
    do_make install
  cd ..
} # [zlib, bzip2, libpng]

build_libxml2() {
  download_and_unpack_file http://xmlsoft.org/sources/libxml2-2.9.10.tar.gz
  cd libxml2-2.9.10
    if [[ ! -f Makefile.in.bak ]]; then
      sed -i.bak "/^PROGRAMS/s/=.*/=/;/^SUBDIRS/s/ doc.*//;/^install-data-am/s/:.*/: install-pkgconfigDATA/;/\tinstall-m4dataDATA/d;/^install-exec-am/s/:.*/: install-libLTLIBRARIES/;/install-confexecDATA install-libLTLIBRARIES/d" Makefile.in # Library only.
      sed -i.bak "/DOC_DISABLE/a\\\n#ifndef LIBXML_STATIC\\n#define LIBXML_STATIC\\n#endif" include/libxml/xmlexports.h # Static library.
    fi
    generic_configure --with-ftp=no --with-http=no --with-python=no
    do_make install
  cd ..
} # [zlib, liblzma, iconv, dlfcn]

build_fontconfig() {
  download_and_unpack_file https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.13.92.tar.xz
  cd fontconfig-2.13.92
    if [[ ! -f Makefile.in.bak ]]; then
      sed -i.bak "/^SUBDIRS/s/fc.*/src/;456,457d;/^install-data-am/s/:.*/: install-pkgconfigDATA/;/\tinstall-xmlDATA$/d" Makefile.in # Library only.
      sed -i.bak "s/llu/\" PRIu64 \"/;/limits/a\#include <inttypes.h>" src/fccache.c # Fix printf-format warning.
    fi
    generic_configure --enable-libxml2 --disable-docs # Use Libxml2 instead of Expat.
    do_make install
  cd ..
} # freetype, libxml >= 2.6, [iconv, dlfcn]

build_gmp() {
  download_and_unpack_file https://gmplib.org/download/gmp/gmp-6.2.0.tar.xz
  cd gmp-6.2.0
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/c\SUBDIRS = mpn mpz mpq mpf printf scanf rand cxx tune" Makefile.in
    fi
    generic_configure
    do_make install
  cd ..
} # [dlfcn]

build_mbedtls() {
  download_and_unpack_file https://github.com/ARMmbed/mbedtls/archive/v2.16.7.tar.gz mbedtls-2.16.7
  # mbedtls-2.23.0 causes "The procedure entry point _vsnprintf_s could not be located in the dynamic link library msvcrt.dll" upon running ffmpeg.exe, ffplay.exe, or ffprobe.exe, because '_vsnprintf_s()' is only available on Windows Vista and later. See 'programs/psa/psa_constant_names.c'.
  cd mbedtls-2.16.7
    mkdir -p build_dir
    cd build_dir # Out-of-source build.
      do_cmake ${PWD%/*} -DENABLE_PROGRAMS=0 -DENABLE_TESTING=0 -DENABLE_ZLIB_SUPPORT=1
      do_make install
    cd ..
  cd ..
}

build_libogg() {
  do_git_checkout https://github.com/xiph/ogg.git
  cd ogg_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "s/ doc//;/m4data/,+2d" Makefile.am
    fi
    generic_configure
    do_make install
  cd ..
} # [dlfcn]

build_libvorbis() {
  do_git_checkout https://github.com/xiph/vorbis.git
  cd vorbis_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "s/ test.*//;/m4data/,+2d" Makefile.am
    fi
    generic_configure --disable-docs --disable-examples --disable-oggtest
    do_make install
  cd ..
} # libogg >= 1.0, [dlfcn]

build_libopus() {
  do_git_checkout https://github.com/xiph/opus.git
  cd opus_git
    if [[ ! -f Makefile.am.bak ]]; then
      sed -i.bak "/m4data/,+2d;/install-data-local/,+2d" Makefile.am # Library only.
      sed -i.bak "s/@LIBM@/& -lssp/" opus.pc.in # Otherwise you'd get "undefined reference to `__memcpy_chk'" while configuring FFmpeg.
    fi
    generic_configure --disable-doc --disable-extra-programs
    do_make install
  cd ..
} # [dlfcn]

build_lame() {
  do_svn_checkout https://svn.code.sf.net/p/lame/svn/trunk/lame lame_svn
  cd lame_svn
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/ frontend//;/^SUBDIRS/s/ doc//" Makefile.in
    fi
    generic_configure --enable-nasm --disable-decoder --disable-frontend
    do_make install
  cd ..
} # [dlfcn]

build_twolame() {
  do_git_checkout https://github.com/njh/twolame.git
  cd twolame_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/ frontend.*//;/pkgdocdir/,+6d;/pkgdoc_DATA/d" Makefile.am
      sed -i.bak "/#ifdef TL_API/i\#ifndef LIBTWOLAME_STATIC\\n#define LIBTWOLAME_STATIC\\n#endif\\n" libtwolame/twolame.h # Static library.
    fi
    generic_configure
    do_make install
  cd ..
} # [dlfcn]

build_fdk-aac() {
  do_git_checkout https://github.com/mstorsjo/fdk-aac.git
  cd fdk-aac_git
    do_configure --host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-static # Build shared library ('libfdk-aac-2.dll').
    do_make install-strip

    mkdir -p $redist_dir
    archive="$redist_dir/libfdk-aac-$(git describe | tail -c +2 | sed 's/g//')-win32-xpmod-sse"
    if [[ ! -f $archive.7z ]]; then # Pack shared library.
      sed "s/$/\r/" NOTICE > NOTICE.txt
      7z a -mx=9 -bb3 $archive.7z $mingw_w64_x86_64_prefix/bin/libfdk-aac-2.dll NOTICE.txt
      rm -v NOTICE.txt
    else
      echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
    fi
  cd ..
} # [dlfcn]

build_libmpg123() {
  download_and_unpack_file https://sourceforge.net/projects/mpg123/files/mpg123/1.26.3/mpg123-1.26.3.tar.bz2
  cd mpg123-1.26.3
    if [[ ! -f Makefile.in.bak ]]; then # Library only
      sed -i.bak "/^all-am/s/\$(PROG.*/\\\/;/^install-data-am/s/ install-man//;/^install-exec-am/s/ install-binPROGRAMS//" Makefile.in
    fi
    generic_configure --enable-yasm
    do_make install
  cd ..
} # [dlfcn]

build_libopenmpt() {
  download_and_unpack_file https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-0.4.15+release.autotools.tar.gz
  cd libopenmpt-0.4.15+release.autotools
    if [[ ! -f Makefile.in.bak ]]; then # Library only
      sed -i.bak "/^all-am/s/DATA/pkgconfig_DATA/;/^install-data-am/s/:.*/: \\\/;s/\tinstall-nobase_dist_docDATA /\t/" Makefile.in
    fi
    generic_configure --disable-openmpt123 --disable-examples --disable-tests
    do_make install
  cd ..
} # zlib, libmpg123, libogg, libvorbis, [dlfcn, mingw-std-threads]
# Without mingw-std-threads you'd get "libopenmpt/libopenmpt_impl.cpp:85:2: warning: #warning "Warning: Building libopenmpt with MinGW-w64 without std::thread support is not recommended and is deprecated. Please use MinGW-w64 with posix threading model (as opposed to win32 threading model), or build with mingw-std-threads." [-Wcpp]".

build_libgme() {
  do_git_checkout https://bitbucket.org/mpyne/game-music-emu.git
  cd game-music-emu_git
    if [[ ! -f CMakeLists.txt.bak ]]; then
      sed -i.bak "/EXCLUDE_FROM_ALL/d" CMakeLists.txt # Library only.
      sed -i.bak "s/ __declspec.*//" gme/blargg_source.h # Needed for building shared FFmpeg libraries.
    fi
    do_cmake $PWD -DBUILD_SHARED_LIBS=0 -DENABLE_UBSAN=0
    do_make install
  cd ..
} # zlib

build_libsoxr() {
  do_git_checkout https://git.code.sf.net/p/soxr/code soxr_git
  cd soxr_git
    if [[ ! -f CMakeLists.txt.bak ]]; then # Library only.
      sed -i.bak "/^install/,+5d" CMakeLists.txt
    fi
    do_cmake $PWD -DBUILD_SHARED_LIBS=0 -DHAVE_WORDS_BIGENDIAN_EXITCODE=0 -DWITH_OPENMP=0 -DBUILD_TESTS=0 -DBUILD_EXAMPLES=0
    do_make install
  cd ..
}

build_libflite() {
  download_and_unpack_file http://www.festvox.org/flite/packed/flite-2.1/flite-2.1-release.tar.bz2
  cd flite-2.1-release
    apply_patch file://$patch_dir/libflite-2.1.0_mingw-w64-fixes.diff # Fix MinGW-w64 stuff and library only. Without the patch it fails with "../build/i386-mingw32/lib/libflite.a(cst_val.o):cst_val.c:(.text+0xdcd): undefined reference to `c99_snprintf'".
    do_configure --host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-shared
    do_make
    do_make_install
  cd ..
}

build_libzimg() {
  do_git_checkout https://github.com/sekrit-twc/zimg.git
  cd zimg_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/dist_doc_DATA/,+19d" Makefile.am
    fi
    generic_configure
    do_make install
  cd ..
} # [dlfcn]

build_vidstab() {
  do_git_checkout https://github.com/georgmartius/vid.stab.git
  cd vid.stab_git
    if [[ ! -f CMakeLists.txt.bak ]]; then # Change GCC optimization level.
      sed -i.bak "s/O3/O2/;s/ -fPIC//" CMakeLists.txt
    fi
    do_cmake $PWD -DBUILD_SHARED_LIBS=0 -DUSE_OMP=0 # '-DUSE_OMP' is on by default, but somehow libgomp ('cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/omp.h') can't be found, so '-DUSE_OMP=0' to prevent a compilation error.
    do_make install
  cd ..
}

build_frei0r() {
  do_git_checkout https://github.com/dyne/frei0r.git
  cd frei0r_git
    do_cmake $PWD -DCMAKE_BUILD_TYPE=Release
    do_make install/strip

    mkdir -p $redist_dir
    archive="$redist_dir/frei0r-plugins-$(git describe --tags | tail -c +2 | sed 's/g//')-win32-xpmod-sse"
    if [[ ! -f $archive.7z ]]; then # Pack shared libraries.
      for doc in AUTHORS ChangeLog COPYING README.md; do
        sed "s/$/\r/" $doc > $mingw_w64_x86_64_prefix/lib/frei0r-1/$doc.txt
      done
      7z a -mx=9 -bb3 $archive.7z $mingw_w64_x86_64_prefix/lib/frei0r-1
      rm -v $mingw_w64_x86_64_prefix/lib/frei0r-1/*.txt
    else
      echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
    fi
  cd ..
} # dlfcn

build_fribidi() {
  do_git_checkout https://github.com/behdad/fribidi.git
  cd fribidi_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "s/ bin.*//" Makefile.am
    fi
    generic_configure --disable-deprecated
    do_make install
  cd ..
} # [dlfcn]

build_libass() {
  do_git_checkout https://github.com/libass/libass.git
  cd libass_git
    generic_configure
    do_make install
  cd ..
} # freetype >= 9.10.3 (see https://bugs.launchpad.net/ubuntu/+source/freetype1/+bug/78573 o_O), fribidi >= 0.19.0, [fontconfig >= 2.10.92, iconv, dlfcn]

build_avisynth() {
  do_git_checkout https://github.com/AviSynth/AviSynthPlus.git
  cd AviSynthPlus_git
    do_make_install "PREFIX=$mingw_w64_x86_64_prefix"
  cd ..
}

build_libxvid() {
  download_and_unpack_file https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz xvidcore
  cd xvidcore/build/generic
    if [[ ! -f Makefile.bak ]]; then
      sed -i.bak "/dll/i\disabled:" Makefile # Static library.
      sed -i.bak "s/\"xvidcore/\"libxvidcore/" configure # Compile 'libxvidcore.a'.
    fi
    export ac_yasm=no # Force the use of NASM.
    do_configure --host=$host_target --prefix=$mingw_w64_x86_64_prefix
    do_make
    do_make_install
    unset ac_yasm
  cd ../../..
}

build_libx264() {
  do_git_checkout http://git.videolan.org/git/x264.git
  cd x264_git
    if [[ ! -f configure.bak ]]; then # Change GCC optimization level.
      sed -i.bak "s/O3 -/O2 -/" configure
    fi
    do_configure --host=$host_target --cross-prefix=$cross_prefix --prefix=$mingw_w64_x86_64_prefix --enable-static --disable-cli --disable-win32thread # Use pthreads instead of win32threads.
    do_make install-lib-static
  cd ..
} # nasm >= 2.13 (unless '--disable-asm' is specified)

build_libx265() {
  do_hg_checkout http://hg.videolan.org/x265
  cd x265_hg/source
    do_cmake $PWD -DENABLE_SHARED=0 -DENABLE_CLI=0 -DWINXP_SUPPORT=1 # No '-DHIGH_BIT_DEPTH=1'. See 'x265_hg/source/CMakeLists.txt' why.
    do_make install
  cd ../..
} # nasm >= 2.13 (unless '-DENABLE_ASSEMBLY=0' is specified)

build_libvpx() {
  do_git_checkout https://chromium.googlesource.com/webm/libvpx.git
  cd libvpx_git
    if [[ ! -f vp8/common/threading.h.bak ]]; then
      sed -i.bak "/<semaphore.h/i\#include <sys/types.h>" vp8/common/threading.h # With 'cross_compilers/mingw-w64-i686/include/semaphore.h' you'd otherwise get: "semaphore.h:152:8: error: unknown type name 'mode_t'".
    fi
    export CROSS="$cross_prefix"
    do_configure --target=x86-win32-gcc --prefix=$mingw_w64_x86_64_prefix --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth
    do_make install
    unset CROSS
  cd ..
}

build_libaom() {
  do_git_checkout https://aomedia.googlesource.com/aom libaom_git
  cd libaom_git
    apply_patch file://$patch_dir/libaom_restore-winxp-compatibility.patch -p1 # See https://aomedia.googlesource.com/aom/+/64545cb00a29ff872473db481a57cdc9bc4f1f82%5E!/#F1 and https://aomedia.googlesource.com/aom/+/e5eec6c5eb14e66e2733b135ef1c405c7e6424bf%5E!/#F0.
    mkdir -p aom_build
    cd aom_build # Out-of-source build.
      do_cmake ${PWD%/*} -DCMAKE_TOOLCHAIN_FILE=build/cmake/toolchains/x86-mingw-gcc.cmake -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_NASM=1 -DENABLE_TESTS=0 -DENABLE_TOOLS=0
      do_make install
    cd ..
  cd ..
} # cmake >= 3.5

build_ffmpeg() {
  do_git_checkout https://github.com/FFmpeg/FFmpeg.git "" "" 1128aa875367f66ac11adc30364d5652919a2591
  cd FFmpeg_git
    apply_patch file://$patch_dir/ffmpeg_make-bcrypt-optional.patch -p1 # WinXP doesn't have 'bcrypt'. See https://github.com/FFmpeg/FFmpeg/commit/aedbf1640ced8fc09dc980ead2a387a59d8f7f68 and https://github.com/sherpya/mplayer-be/blob/master/patches/ff/0001-make-bcrypt-optional-on-win32.patch.
    apply_patch file://$patch_dir/ffmpeg_load-shared-libfdk-aac-library-dynamically.patch -p1 # See https://github.com/sherpya/mplayer-be/blob/master/patches/ff/0003-dynamic-loading-of-shared-fdk-aac-library.patch.
    apply_patch file://$patch_dir/ffmpeg_load-shared-frei0r-libraries-dynamically.patch -p1 # See https://github.com/sherpya/mplayer-be/blob/master/patches/ff/0004-avfilters-better-behavior-of-frei0r-on-win32.patch.
    if [[ ! -f libavformat/udp.c.bak ]]; then
      sed -i.bak "s/#ifdef _WIN32/#ifndef _WIN32_WINNT_WINXP/" libavformat/udp.c
      # Otherwise you'd get "The procedure entry point CancelIoEx could not be located in the dynamic link library KERNEL32.dll" while running ffmpeg, ffplay, or ffprobe, because CancelIoEx() is only available on Windows Vista and later.
      # See https://github.com/FFmpeg/FFmpeg/commit/53aa76686e7ff4f1f6625502503d7923cec8c10e#diff-612cd5096dca6b6969e9743c462bfad0 and https://trac.ffmpeg.org/ticket/5717. This obviously doesn't fix the ticket, but simply reverts the change.
    fi
    init_options=(--arch=x86 --target-os=mingw32 --prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix --extra-cflags="$CFLAGS")
    if [[ $1 == "shared" ]]; then
      init_options+=(--enable-shared --disable-static) # Building a static FFmpeg is the default, so no need to specify '--enable-static --disable-shared'.
    fi
    init_options+=(--pkg-config=pkg-config --pkg-config-flags=--static --extra-version=Reino --enable-gpl --enable-gray --enable-version3 --disable-bcrypt --disable-debug --disable-doc --disable-htmlpages --disable-manpages --disable-podpages --disable-txtpages --disable-w32threads)
    do_configure "${init_options[@]}" --enable-avisynth --enable-frei0r --enable-filter=frei0r --enable-gmp --enable-libaom --enable-libass --enable-libfdk-aac --enable-libflite --enable-libfontconfig --enable-libfreetype --enable-libfribidi --enable-libgme --enable-libmp3lame --enable-libopenmpt --enable-libopus --enable-libsoxr --enable-libtwolame --enable-libvidstab --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libx264 --enable-libx265 --enable-libxml2 --enable-libxvid --enable-libzimg --enable-mbedtls
    do_make # Build 'ffmpeg.exe', 'ffplay.exe' and 'ffprobe.exe' (+ '*.dll' for shared build). No install.

    mkdir -p $redist_dir
    archive="$redist_dir/ffmpeg-$(git describe --tags | tail -c +2 | sed 's/dev-//;s/g//')-win32-$1-xpmod-sse"
    if [[ $1 == "shared" ]]; then
      do_make_install
      if [[ ! -f $archive.7z ]]; then # Pack shared build.
        sed "s/$/\r/" COPYING.GPLv3 > COPYING.GPLv3.txt
        7z a -mx=9 -bb3 $archive.7z $mingw_w64_x86_64_prefix/bin/{ff*.exe,{av,sw,postproc}*.dll} COPYING.GPLv3.txt
        rm -v COPYING.GPLv3.txt
      else
        echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
      fi
      if [[ ! -f ${archive/shared/dev}.7z ]]; then # Pack shared dev build.
        cd $mingw_w64_x86_64_prefix
          cp -v bin/*.lib lib
          7z a -mx=9 -bb3 ${archive/shared/dev}.7z include/lib{av,sw,postproc}* lib/{*.lib,*.def,lib{av,sw,postproc}*.dll.a} share/ffmpeg
          rm -v lib/*.lib
        cd $OLDPWD
      else
        echo -e "\e[1;33mAlready made '$(basename ${archive/shared/dev}.7z)'.\e[0m"
      fi
    else
      if [[ ! -f $archive.7z ]]; then # Pack static build.
        sed "s/$/\r/" COPYING.GPLv3 > COPYING.GPLv3.txt
        7z a -mx=9 -bb3 $archive.7z ffmpeg.exe ffplay.exe ffprobe.exe COPYING.GPLv3.txt
        rm -v COPYING.GPLv3.txt
      else
        echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
      fi
    fi
  cd ..
} # SDL2 (only for FFplay)

build_dependencies() {
  build_mingw_std_threads
  build_cmake
  build_nasm
  build_dlfcn
  build_bzip2 # Bzlib (bzip2) in FFmpeg is autodetected, so no need for --enable-bzlib.
  build_liblzma # Lzma in FFmpeg is autodetected, so no need for --enable-lzma.
  build_zlib # Zlib in FFmpeg is autodetected, so no need for --enable-zlib.
  build_iconv # Iconv in FFmpeg is autodetected, so no need for --enable-iconv.
  build_sdl2 # Sdl2 in FFmpeg is autodetected, so no need for --enable-sdl2.
  build_libwebp
  build_freetype
  build_libxml2 # For DASH support configure FFmpeg with --enable-libxml2.
  build_fontconfig
  build_gmp # For RTMP support configure FFmpeg with --enable-gmp.
  build_mbedtls # For HTTPS TLS 1.2 support on WinXP configure FFmpeg with --enable-mbedtls.
  build_libogg
  build_libvorbis
  build_libopus
  build_lame
  build_twolame
  build_fdk-aac
  build_libmpg123
  build_libopenmpt
  build_libgme
  build_libsoxr
  build_libflite
  build_libzimg
  build_vidstab
  build_frei0r
  build_fribidi
  build_libass
  build_avisynth
  build_libxvid
  build_libx264
  build_libx265
  build_libvpx
  build_libaom
}

build_apps() {
  if [[ $build_ffmpeg_static = "y" ]]; then
    build_ffmpeg static
  else
    build_ffmpeg shared
  fi
}

build_openssl-1.0.2() {
  download_and_unpack_file https://www.openssl.org/source/openssl-1.0.2u.tar.gz
  cd openssl-1.0.2u
    if [[ ! -f Makefile.org.bak ]]; then
      sed -i.bak "/^DIRS/s/ apps.*//;/^build_all/s/ build_apps.*//;/install:/s/ install_docs//;550s/openssl.*/openssl/;551,553d" Makefile.org # Library only.
    fi
    export CC="${cross_prefix}gcc"
    export AR="${cross_prefix}ar"
    export RANLIB="${cross_prefix}ranlib"
    do_configure ./Configure --prefix=$mingw_w64_x86_64_prefix mingw zlib shared
    sed -i "s/-O3/-O2/" Makefile # Change GCC optimization level.
    do_make build_libs
    unset CC
    unset AR
    unset RANLIB

    mkdir -p $redist_dir
    archive="$redist_dir/openssl-1.0.2u-win32-xpmod-sse"
    if [[ ! -f $archive.7z ]]; then # Pack shared libraries.
      sed "s/$/\r/" LICENSE > LICENSE.txt
      ${cross_prefix}strip -ps libeay32.dll ssleay32.dll
      7z a -mx=9 -bb3 $archive.7z libeay32.dll ssleay32.dll LICENSE.txt
      rm -v LICENSE.txt
    else
      echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
    fi
  cd ..
}

build_openssl-1.1.1() {
  download_and_unpack_file https://www.openssl.org/source/openssl-1.1.1g.tar.gz
  cd openssl-1.1.1g
    if [[ ! -f Configurations/10-main.conf.bak ]]; then # Change GCC optimization level.
      sed -i.bak "s/-O3/-O2/" Configurations/10-main.conf
    fi
    export CC="${cross_prefix}gcc"
    export AR="${cross_prefix}ar"
    export RANLIB="${cross_prefix}ranlib"
    local config_options=(./Configure --prefix=$mingw_w64_x86_64_prefix mingw zlib no-async)
    # "Note: on older OSes, like CentOS 5, BSD 5, and Windows XP or Vista, you will need to configure with no-async when building OpenSSL 1.1.0 and above. The configuration system does not detect lack of the Posix feature on the platforms." (https://wiki.openssl.org/index.php/Compilation_and_Installation)
    if [ "$1" = "static" ]; then
      make distclean || exit 1
      do_configure "${config_options[@]}" no-shared no-dso # No 'no-engine' because Curl needs it when built with Libssh2.
      do_make install_dev
    else
      do_configure "${config_options[@]}" shared
      do_make build_libs

      mkdir -p $redist_dir
      archive="$redist_dir/openssl-1.1.1g-win32-xpmod-sse"
      if [[ ! -f $archive.7z ]]; then # Pack shared libraries.
        sed "s/$/\r/" LICENSE > LICENSE.txt
        ${cross_prefix}strip -ps libcrypto-1_1.dll libssl-1_1.dll
        7z a -mx=9 -bb3 $archive.7z libcrypto-1_1.dll libssl-1_1.dll LICENSE.txt
        rm -v LICENSE.txt
      else
        echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
      fi
    fi
    unset CC
    unset AR
    unset RANLIB
  cd ..
}

build_openssl-dlls() {
  build_openssl-1.0.2 # Only for building 'libeay32.dll' and 'ssleay32.dll' (for Xidel).
  build_openssl-1.1.1 # Only for building 'libcrypto-1_1.dll' and 'libssl-1_1.dll'.
}

build_curl() {
  download_and_unpack_file https://curl.haxx.se/download/curl-7.69.1.tar.bz2
  if [ "$1" = "openssl" ]; then # Compile Curl with OpenSSL for hlsdl.
    build_openssl-1.1.1 static
    cd curl-7.69.1
    export PKG_CONFIG="pkg-config --static" # Automatically detect all of OpenSSL its dependencies.
    generic_configure --without-ca-bundle --with-ca-fallback
    unset PKG_CONFIG
    do_make install-strip
  else # Compile Curl with MbedTLS and create archive.
    build_mbedtls
    cd curl-7.69.1
    generic_configure --without-ssl --with-mbedtls --with-ca-bundle=ca-bundle.crt LDFLAGS=-s # --with-ca-fallback only works with OpenSSL or GnuTLS.
    do_make # 'curl.exe' only. No install.
    if [[ ! -f ca-bundle.crt ]]; then # For 'ca-bundle.crt' see https://superuser.com/a/442797.
      echo -e "\e[1;33mDownloading 'https://curl.haxx.se/ca/cacert.pem' and renaming to 'ca-bundle.crt'.\e[0m"
      curl -o ca-bundle.crt https://curl.haxx.se/ca/cacert.pem
    fi

    mkdir -p $redist_dir
    archive="$redist_dir/curl-7.69.1_mbedtls_zlib-win32-static-xpmod-sse"
    if [[ ! -f $archive.7z ]]; then # Pack static 'curl.exe'.
      sed "s/$/\r/" COPYING > COPYING.txt
      7z a -mx=9 -bb3 $archive.7z ./src/curl.exe ca-bundle.crt COPYING.txt
      rm -v COPYING.txt
    else
      echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
    fi
  fi
  cd ..
} # mbedtls/openssl, [zlib, dlfcn]

build_hlsdl() {
  build_curl openssl
  do_git_checkout https://github.com/selsta/hlsdl.git
  cd hlsdl_git
    export LDFLAGS=-s # Strip 'hlsdl.exe' during make.
    do_make $make_prefix_options
    unset LDFLAGS

    mkdir -p $redist_dir
    archive="$redist_dir/hlsdl-$(grep -Po "(?<=hlsdl v)([0-9]+\.?)+" src/misc.c)-$(git rev-parse --short HEAD)-win32-static-xpmod-sse"
    if [[ ! -f $archive.7z ]]; then # Pack static 'hlsdl.exe'.
      sed "s/$/\r/" LICENSE > LICENSE.txt
      7z a -mx=9 -bb3 $archive.7z hlsdl.exe LICENSE.txt README.md
      rm -v LICENSE.txt
    else
      echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
    fi
  cd ..
} # curl(openssl)

build_ffms2_cplugin() {
  do_git_checkout https://github.com/FFmpeg/FFmpeg.git FFmpeg-ffms2_git "" 1128aa875367f66ac11adc30364d5652919a2591
  cd FFmpeg-ffms2_git
    ff_rev=$(git describe --tags | tail -c +2 | sed 's/dev-//;s/g//')
    apply_patch file://$patch_dir/ffmpeg_make-bcrypt-optional.patch -p1
    do_configure --arch=x86 --target-os=mingw32 --prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix --extra-cflags="$CFLAGS" --pkg-config=pkg-config --pkg-config-flags=--static --enable-gpl --enable-version3 --disable-bcrypt --disable-debug --disable-doc --disable-htmlpages --disable-manpages --disable-podpages --disable-schannel --disable-txtpages --disable-w32threads --disable-avdevice --disable-avfilter --disable-devices --disable-encoders --disable-filters --disable-hwaccels --disable-muxers --disable-network --disable-programs --disable-sdl2 --enable-libaom
    do_make
    do_make_install
  cd ..

  do_git_checkout https://github.com/qyot27/ffms2_cplugin.git "" c_plugin
  cd ffms2_cplugin_git
    if [[ ! -f configure.bak ]]; then
      sed -i.bak 's/\[\[.*\]\]/[ "${1##*-}" = "mingw32" ]/;s/cross_prefix%%-/host##*-/;s/${cross_prefix}pkg-config/pkg-config/' configure # Correctly detect MingW32 and use Cygwin's pkg-config.
      sed -i.bak 's/<mutex>/"mingw.mutex.h"/' src/core/ffms.cpp # Use "mingw-std-threads" implementation of standard C++11 threading classes, which are currently still missing on MinGW GCC.
      sed -i.bak 's/<thread>/"mingw.thread.h"/' src/core/videosource.cpp # Otherwise you'd get errors like "'mutex' in namespace 'std' does not name a type".
    fi
    export CFLAGS="${original_cflags/O2/O0}" # See https://forum.doom9.org/showthread.php?p=1910199#post1910199.
    do_configure --host=$host_target --prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix --enable-debug --extra-ldflags=-s --enable-shared --enable-avisynth --enable-vapoursynth
    do_make
    reset_cflags

    mkdir -p $redist_dir
    archive="$redist_dir/ffms2-$(git describe --tags | sed 's/g//')-avs-vsp_ffmpeg-$ff_rev-win32-xpmod-sse"
    if [[ ! -f $archive.7z ]]; then
      sed "s/$/\r/" etc/COPYING.GPLv3 > COPYING.GPLv3.txt
      7z a -mx=9 -bb3 $archive.7z ffms2.dll ffmsindex.exe ./etc/FFMS2-cplugin.avsi doc COPYING.GPLv3.txt
      rm -v COPYING.GPLv3.txt
    else
      echo -e "\e[1;33mAlready made '${archive##*/}.7z'.\e[0m"
    fi
  cd ..
} # ffmpeg, mingw-std-threads

reset_cflags() {
  export CFLAGS=$original_cflags
}

# set some parameters initial values
cur_dir="$PWD/sandbox"
patch_dir="${PWD%/*}/patches"
redist_dir="${PWD%/*}/redist"
cpu_count=1

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
original_cflags='-march=pentium3 -mtune=athlon-xp -O2 -mfpmath=sse -msse' # See https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html, https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html and https://stackoverflow.com/questions/19689014/gcc-difference-between-o3-and-os.
export ac_cv_func__mktemp_s=no   # _mktemp_s is not available on WinXP.
export ac_cv_func_vsnprintf_s=no # Mark vsnprintf_s as unavailable, as windows xp mscrt doesn't have it.

# parse command line parameters, if any
while true; do
  case $1 in
    -h | --help ) echo "available option=default_value:
      --build-ffmpeg-static=y  (ffmpeg.exe, ffplay.exe and ffprobe.exe)
      --build-ffmpeg-static=n  (ffmpeg.exe, ffplay.exe, ffprobe.exe and dll-files)
      --ffmpeg-git-checkout-version=[master] if you want to build a particular version of FFmpeg, ex: n3.1.1 or a specific git hash
      --sandbox-ok=n [skip sandbox prompt if y]
      -d [meaning \"defaults\" skip all prompts, just build ffmpeg static with some reasonable defaults like no git updates]
      --cflags=[default is $original_cflags, which works on any cpu, see README for options]
      --debug Make this script  print out each line as it executes
       "; exit 0 ;;
    --sandbox-ok=* ) sandbox_ok="${1#*=}"; shift ;;
    --cflags=* )
       original_cflags="${1#*=}"; echo "setting cflags as $original_cflags"; shift ;;
    -d         ) gcc_cpu_count=$cpu_count; sandbox_ok="y"; shift ;;
    --build-ffmpeg-static=* ) build_ffmpeg_static="${1#*=}"; shift ;;
    --debug ) set -x; shift ;;
    -- ) shift; break ;;
    -* ) echo "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

reset_cflags # also overrides any "native" CFLAGS, which we may need if there are some 'linux only' settings in there
check_missing_packages # do this first since it's annoying to go through prompts then be rejected
intro # remember to always run the intro, since it adjust pwd
install_cross_compiler

export PKG_CONFIG_LIBDIR= # disable pkg-config from finding [and using] normal linux system installed libs [yikes]

original_path="$PATH"
echo
echo -e "Starting 32-bit builds.\n"
host_target='i686-w64-mingw32'
mingw_w64_x86_64_prefix="$cur_dir/cross_compilers/mingw-w64-i686/$host_target"
mingw_bin_path="$cur_dir/cross_compilers/mingw-w64-i686/bin"
export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
export PATH="$mingw_bin_path:$original_path"
cross_prefix="$mingw_bin_path/i686-w64-mingw32-"
make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
mkdir -p win32
cd win32
  build_dependencies
  build_apps
cd ..
