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
    echo
    echo "Building in $PWD/sandbox, will use ~ 4GB space!"
    echo
  fi
  mkdir -p "$cur_dir"
  cd "$cur_dir"
  if [[ $disable_nonfree = "y" ]]; then
    non_free="n"
  else
    if  [[ $disable_nonfree = "n" ]]; then
      non_free="y"
    else
      yes_no_sel "Would you like to include non-free (non GPL compatible) libraries, like many high quality aac encoders [libfdk_aac]
The resultant binary may not be distributable, but can be useful for in-house use. Include these non-free-license libraries [y/N]?" "n"
      non_free="$user_input" # save it away
    fi
  fi
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
    echo "MinGW-w64 compilers for Win32 already installed, not re-installing."
  else
    mkdir -p cross_compilers
    cd cross_compilers
      unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
      # pthreads version to avoid having to use cvs for it
      echo "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count."
      echo

      # --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
      local zeranoe_script_name=mingw-w64-build-r24.local # https://files.1f0.de/mingw/scripts/
      local zeranoe_script_options="--default-configure --cpu-count=$gcc_cpu_count --pthreads-w32-ver=2-9-1 --disable-shared --clean-build --verbose"
      echo "Building win32 cross compiler."
      download_gcc_build_script $zeranoe_script_name
      if [[ `uname` =~ "5.1" ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
        sed -i "s/ --enable-secure-api//" $zeranoe_script_name
      fi
      nice ./$zeranoe_script_name $zeranoe_script_options --build-type=win32 || exit 1
      if [[ ! -f ../$win32_gcc ]]; then
        echo "Failure building 32 bit gcc? Recommend nuke sandbox (rm -fr sandbox) and start over."
        exit 1
      fi

      rm -f build.log # left over stuff...
      reset_cflags
    cd ..
    echo "Done building (or already built) MinGW-w64 cross-compiler(s) successfully."
    echo `date` # so they can see how long it took :)
  fi
}

do_svn_checkout() {
  local dir="$2"
  if [ ! -d $dir ]; then
    echo "Downloading (via svn checkout) $dir from $1."
    if [[ $3 ]]; then
      svn checkout -r $3 $1 $dir.tmp || exit 1
    else
      svn checkout $1 $dir.tmp --non-interactive --trust-server-cert || exit 1
    fi
    mv $dir.tmp $dir
  else
    cd $dir
    echo "Not updating svn $dir, because svn repo's aren't updated frequently enough."
    # XXX accomodate for desired revision here if I ever uncomment the next line...
    # svn up
    cd ..
  fi
}

do_git_checkout() {
  if [[ $2 ]]; then
    local dir="$2"
  else
    local dir=$(basename $1 | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  fi
  if [ ! -d $dir ]; then
    echo "Downloading (via git clone) $dir from $1."
    rm -fr $dir.tmp # just in case it was interrupted previously...
    git clone $1 $dir.tmp || exit 1
    # prevent partial checkouts by renaming it only after success
    mv $dir.tmp $dir
    echo "Done git cloning to $dir."
    cd $dir
  else
    cd $dir
    if [[ $git_get_latest = "y" ]]; then
      git fetch # need this no matter what
    else
      echo "Not doing git get latest pull for latest code $dir."
    fi
  fi

  if [[ $3 ]]; then
    echo "Doing git checkout $3."
    git reset --hard
    git clean -fdx
    git checkout "$3" || exit 1
    git merge "$3" || exit 1 # get incoming changes to a branch
  else
    if [[ $git_get_latest = "y" ]]; then
      if [[ $(git rev-parse HEAD) != $(git ls-remote -h $1 master | sed "s/\s.*//") ]]; then
        echo "Got upstream changes. Updating $dir to latest git version 'origin/master'."
        git reset --hard # Return files to their original state.
        git clean -fdx # Clean the working tree; build- as well as untracked files.
        git checkout master || exit 1
        git merge origin/master || exit 1
      else
        echo "Got no code changes. Local $dir repo is up-to-date."
      fi
    fi
  fi
  cd ..
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
  echo "$1_$(echo -- $2 $CFLAGS $LDFLAGS | /usr/bin/env md5sum | sed "s/ //g")" # md5sum to make it smaller, cflags to force rebuild if changes and sed to remove spaces that md5sum introduced.
}

do_configure() {
  if [[ $2 ]]; then
    local configure_name="$2"
  else
    local configure_name="./configure"
  fi
  local name=$(get_small_touchfile_name already_configured "$1 $configure_name")
  if [ ! -f "$name" ]; then # This is to generate 'configure', 'Makefile.in' and some other files.
    if [ ! -f $configure_name ] && [ -f autogen.sh ]; then
      ./autogen.sh
    fi
    if [ ! -f $configure_name ] && [ -f autobuild ]; then
      ./autobuild
    fi
    if [ ! -f $configure_name ] && [ -f buildconf ]; then
      ./buildconf
    fi
    if [ ! -f $configure_name ] && [ -f bootstrap ]; then
      ./bootstrap
    fi
    if [ ! -f $configure_name ] && [ -f bootstrap.sh ]; then
      ./bootstrap.sh
    fi
    if [ ! -f $configure_name ]; then
      autoreconf -fiv
    fi
    echo "Configuring $(basename $(pwd)) as $configure_name $1."
    "$configure_name" $1 || exit 1 # not nice on purpose, so that if some other script is running as nice, this one will get priority :)
    touch -- "$name"
    echo "Doing preventative make clean."
    nice make clean -j $cpu_count # sometimes useful when files change, etc.
  #else
  #  echo "Already configured $(basename $(pwd))."
  fi
}

do_make() {
  local extra_make_options="$1 -j $cpu_count"
  local name=$(get_small_touchfile_name already_ran_make "$extra_make_options" )
  if [ ! -f $name ]; then
    echo
    echo "Doing make in $(basename $(pwd)) as make $extra_make_options."
    echo
    if [ ! -f configure ]; then
      nice make clean -j $cpu_count # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
    fi
    nice make $extra_make_options || exit 1
    touch $name || exit 1 # only touch if the build was OK
  else
    echo "Already made $(basename $(pwd))."
  fi
}

do_make_and_make_install() {
  do_make "$1"
  do_make_install "$1"
}

do_make_install() {
  if [[ $2 ]]; then
    local make_install_options="$2 $1" # startingly, some need/use something different than just 'make install'
  else
    local make_install_options="install $1"
  fi
  local name=$(get_small_touchfile_name already_ran_make_install "$make_install_options")
  if [ ! -f $name ]; then
    echo "Installing $(basename $(pwd)) as make $make_install_options."
    nice make $make_install_options || exit 1
    touch $name || exit 1
  fi
}

do_cmake() {
  if [[ $2 ]]; then
    local dir="$2"
  else
    local dir=$(pwd)
  fi
  local name=$(get_small_touchfile_name already_ran_cmake "$1")
  if [ ! -f $name ]; then
    rm -f already_* # reset so that make will run again if option just changed
    echo "Doing cmake in $(basename $dir) as cmake –G”Unix Makefiles” $dir -DENABLE_STATIC_RUNTIME=1 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_RANLIB=${cross_prefix}ranlib.exe -DCMAKE_C_COMPILER=${cross_prefix}gcc.exe -DCMAKE_CXX_COMPILER=${cross_prefix}g++.exe -DCMAKE_RC_COMPILER=${cross_prefix}windres.exe -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $1."
    cmake –G”Unix Makefiles” $dir -DENABLE_STATIC_RUNTIME=1 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_RANLIB=${cross_prefix}ranlib.exe -DCMAKE_C_COMPILER=${cross_prefix}gcc.exe -DCMAKE_CXX_COMPILER=${cross_prefix}g++.exe -DCMAKE_RC_COMPILER=${cross_prefix}windres.exe -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $1 || exit 1
    touch $name || exit 1
  fi
}

do_cmake_and_install() {
  do_cmake "$1" "$2"
  do_make_and_make_install
}

apply_patch() {
  if [[ $2 ]]; then
    local type=$2 # Git patches need '-p1' (also see https://unix.stackexchange.com/a/26502).
  else
    local type="-p0"
  fi
  local name=$(basename $1)
  if [[ ! -e $name.done ]]; then
    if [[ -f $name ]]; then
      rm $name || exit 1 # remove old version in case it has been since updated on the server...
    fi
    curl -4 --retry 5 $1 -O --fail || exit 1
    echo "Applying patch '$name'."
    patch $type < "$name" || exit 1
    touch $name.done || exit 1
    rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
  else
    echo "Patch '$name' already applied."
  fi
}

download_and_unpack_file() {
  local name=$(basename $1)
  if [[ $2 ]]; then
    local dir="$2"
  else
    local dir=$(echo $name | sed s/\.tar\.*//) # remove .tar.xx
  fi
  if [ ! -f "$dir/unpacked.successfully" ]; then
    echo "Downloading $1."
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

generic_configure() {
  do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static $1"
}

generic_download_and_make_and_install() {
  if [[ $2 ]]; then
    local name="$2"
  else
    local name=$(basename $1 | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
  fi
  download_and_unpack_file $1 $name
  cd $name || exit "unable to cd, may need to specify dir it will unpack to as parameter"
  generic_configure "$3"
  do_make_and_make_install
  cd ..
}

do_git_checkout_and_make_install() {
  local git_checkout_name=$(basename $1 | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  do_git_checkout $1 $git_checkout_name
  cd $git_checkout_name
    generic_configure_make_install
  cd ..
}

generic_configure_make_install() {
  generic_configure # no parameters, force myself to break it up :)
  do_make_and_make_install
}

do_strip() {
  if [ ! -f "already_ran_strip" ]; then
    if [ -f "$1" ]; then
      echo "Doing ${host_target}-strip $2 $(basename $1)"
      ${cross_prefix}strip $2 $1 || exit 1
    else
      for files in $1/*.{dll,exe}; do
        [ -f "$files" ] || continue
        echo "Doing ${host_target}-strip $2 $(basename $files)"
        ${cross_prefix}strip $2 $files || exit 1
      done
    fi
    touch "already_ran_strip" || exit 1
  else
    if [ -f "$1" ]; then
      echo "Already stripped $(basename $1)."
    else
      echo "Already stripped $(basename $(pwd))."
    fi
  fi
} # do_strip file/dir [strip-parameters]

gen_ld_script() {
  lib=$mingw_w64_x86_64_prefix/lib/$1
  lib_s="${1:3:-2}_s"
  if [ ! -f "$mingw_w64_x86_64_prefix/lib/lib$lib_s.a" ] || [ "$lib" -nt "$mingw_w64_x86_64_prefix/lib/lib$lib_s.a" ]; then
    rm -f $mingw_w64_x86_64_prefix/lib/lib$lib_s.a
    echo "Generating linker script for $(basename $lib), adding $2".
    mv -f $lib $mingw_w64_x86_64_prefix/lib/lib$lib_s.a
    echo "GROUP ( -l$lib_s $2 )" > $lib
  else
    echo "Already generated linker script for $2."
  fi
} # gen_ld_script libxxx.a -lxxx

build_cmake() {
  download_and_unpack_file https://cmake.org/files/v3.11/cmake-3.11.1.tar.gz
  cd cmake-3.11.1
    if [[ ! -f CMakeLists.txt.bak ]]; then # https://gitlab.kitware.com/cmake/cmake/commit/99bf77f49c18f9947b2386c4f5b6308da793de9f.
      sed -i.bak "577s/CMAKE.*/DEFINED BUILD_CursesDialog)/;586,587d" CMakeLists.txt
    fi
    do_configure "--prefix=/usr -- -DBUILD_CursesDialog=0 -DBUILD_TESTING=0" # Don't build 'ccmake' (ncurses), or './configure' will fail otherwise.
    # Options after "--" are passed to CMake (Usage: ./bootstrap [<options>...] [-- <cmake-options>...])
    do_make
    do_make_install "install/strip" # This overwrites Cygwin's 'cmake.exe', 'cpack.exe' and 'ctest.exe'.
  cd ..
}

build_nasm() {
  download_and_unpack_file http://www.nasm.us/pub/nasm/releasebuilds/2.13.03/nasm-2.13.03.tar.xz
  cd nasm-2.13.03
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/man1/d" Makefile.in
    fi
    do_configure "--prefix=/usr"
    # No '--prefix=$mingw_w64_x86_64_prefix', because NASM has to be built with Cygwin's GCC. Otherwise it can't read Cygwin paths and you'd get errors like "nasm: fatal: unable to open output file `/cygdrive/c/DOCUME~1/Admin/LOCALS~1/Temp/ffconf.Ld8518el/test.o'" while configuring FFmpeg for instance.
    do_make
    do_strip . --strip-unneeded
    do_make_install # 'nasm.exe' and 'ndisasm.exe' will be installed in '/usr/bin' (Cygwin's bin map).
  cd ..
}

build_dlfcn() {
  do_git_checkout https://github.com/dlfcn-win32/dlfcn-win32.git
  cd dlfcn-win32_git
    if [[ ! -f Makefile.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/-O3/-O2/" Makefile
    fi
    do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # rejects some normal cross compile options so custom here
    do_make_and_make_install
    gen_ld_script libdl.a -lpsapi # dlfcn-win32's 'README.md': "If you are linking to the static 'dl.lib' or 'libdl.a', then you would need to explicitly add 'psapi.lib' or '-lpsapi' to your linking command, depending on if MinGW is used."
  cd ..
}

build_bzip2() {
  download_and_unpack_file http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz
  cd bzip2-1.0.6
    apply_patch file://$patch_dir/bzip2-1.0.6_brokenstuff.diff
    if [[ ! -f $mingw_w64_x86_64_prefix/lib/libbz2.a ]]; then # Library only.
      do_make "$make_prefix_options libbz2.a"
      install -m644 libbz2.a $mingw_w64_x86_64_prefix/lib/libbz2.a
      install -m644 bzlib.h $mingw_w64_x86_64_prefix/include/bzlib.h
    else
      echo "Already made bzip2-1.0.6."
    fi
  cd ..
}

build_liblzma() {
  #download_and_unpack_file https://sourceforge.net/projects/lzmautils/files/xz-5.2.3.tar.xz
  download_and_unpack_file https://github.com/xz-mirror/xz/archive/v5.2.3.tar.gz xz-5.2.3
  cd xz-5.2.3
    generic_configure "--disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --disable-nls"
    do_make_and_make_install
  cd ..
} # [dlfcn]

build_zlib() {
  download_and_unpack_file https://github.com/madler/zlib/archive/v1.2.11.tar.gz zlib-1.2.11
  cd zlib-1.2.11
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/man3dir/d" Makefile.in
    fi
    do_configure "--prefix=$mingw_w64_x86_64_prefix --static"
    do_make_and_make_install "$make_prefix_options"
  cd ..
}

build_iconv() {
  download_and_unpack_file https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.15.tar.gz
  cd libiconv-1.15
    generic_configure "--disable-nls"
    do_make "install-lib" # No need for 'do_make_install', because 'install-lib' already has install-instructions.
  cd ..
} # [dlfcn]

build_sdl2() {
  download_and_unpack_file https://libsdl.org/release/SDL2-2.0.8.tar.gz
  cd SDL2-2.0.8
    apply_patch file://$patch_dir/SDL2-2.0.8_lib-only.diff
    if [[ ! -f configure.bak ]]; then
      sed -i.bak "s/ -mwindows//" configure # Allow ffmpeg to output anything to console.
      sed -i.bak "/#ifndef DECLSPEC/i\#define DECLSPEC" include/begin_code.h # Needed for building shared FFmpeg libraries.
    fi
    generic_configure "--bindir=$mingw_bin_path"
    do_make_and_make_install
    if [[ ! -f $mingw_bin_path/${host_target}-sdl2-config ]]; then
      mv "$mingw_bin_path/sdl2-config" "$mingw_bin_path/${host_target}-sdl2-config" # At the moment FFmpeg's 'configure' doesn't use 'sdl2-config', because it gives priority to 'sdl2.pc', but when it does, it expects 'i686-w64-mingw32-sdl2-config' in 'cross_compilers/mingw-w64-i686/bin'.
    fi
  cd ..
} # [iconv, dlfcn]

build_libzimg() {
  do_git_checkout https://github.com/sekrit-twc/zimg.git
  cd zimg_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/dist_doc_DATA/,+19d" Makefile.am
    fi
    generic_configure_make_install
  cd ..
}

build_libopenjpeg() {
  do_git_checkout https://github.com/uclouvain/openjpeg.git
  cd openjpeg_git
    if [[ ! -f CMakeLists.txt.bak ]]; then # Library only.
      sed -i.bak "/#.*OPENJPEGTargets/,/#.*/d" CMakeLists.txt
    fi
    do_cmake_and_install "-DBUILD_SHARED_LIBS=0 -DBUILD_CODEC=0"
  cd ..
}

build_libpng() {
  do_git_checkout https://github.com/glennrp/libpng.git
  cd libpng_git
    generic_configure
    if [[ ! -f Makefile.bak ]]; then # Library only.
      sed -i.bak "/^install-data-am/s/ install-man//;/^install-exec-am/s/ install-binPROGRAMS//" Makefile
    fi
    do_make_and_make_install
  cd ..
}

build_libwebp() {
  do_git_checkout https://chromium.googlesource.com/webm/libwebp.git
  cd libwebp_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/=.*/= src/" Makefile.am
    fi
    generic_configure "--disable-png --disable-jpeg --disable-tiff --disable-gif --disable-wic" # These are only necessary for building the bundled tools/binaries.
    do_make_and_make_install
  cd ..
} # [dlfcn]

build_freetype() {
  #download_and_unpack_file https://sourceforge.net/projects/freetype/files/freetype2/2.9/freetype-2.9.tar.bz2
  download_and_unpack_file https://download.savannah.gnu.org/releases/freetype/freetype-2.9.tar.bz2
  cd freetype-2.9
    if [[ ! -f builds/unix/install.mk.bak ]]; then # Library only.
      sed -i.bak "/bindir) /s/\s*\\\//;/aclocal/d;/man1/d;/BUILD_DIR/d;/docs/d" builds/unix/install.mk
    fi
    generic_configure "--build=i686-pc-cygwin" # Without '--build=i686-pc-cygwin' you'd get: "could not open '/cygdrive/[...]/include/freetype/ttnameid.h' for writing".
    do_make_and_make_install
  cd ..
} # [zlib, bzip2, libpng]

build_libxml2() {
  download_and_unpack_file http://xmlsoft.org/sources/libxml2-2.9.8.tar.gz
  cd libxml2-2.9.8
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/^PROGRAMS/s/=.*/=/;/^SUBDIRS/s/ doc.*//;/^install-data-am/s/:.*/: install-pkgconfigDATA/;/\tinstall-m4dataDATA/d;/^install-exec-am/s/:.*/: install-libLTLIBRARIES/;/install-confexecDATA install-libLTLIBRARIES/d" Makefile.in
    fi
    generic_configure "--with-ftp=no --with-http=no --with-python=no"
    do_make_and_make_install
  cd ..
} # [zlib, liblzma, iconv, dlfcn]

build_fontconfig() {
  download_and_unpack_file https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.13.0.tar.bz2
  cd fontconfig-2.13.0
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/fc.*/src/;456,457d;/^install-data-am/s/:.*/: install-pkgconfigDATA/;/\tinstall-xmlDATA$/d" Makefile.in
    fi
    generic_configure "--enable-libxml2 --disable-docs" # Use Libxml2 instead of Expat.
    do_make_and_make_install
  cd ..
} # freetype, libxml >= 2.6, [iconv, dlfcn]

build_gmp() {
  download_and_unpack_file https://gmplib.org/download/gmp/gmp-6.1.2.tar.xz
  cd gmp-6.1.2
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/c\SUBDIRS = mpn mpz mpq mpf printf scanf rand cxx tune" Makefile.in
    fi
    generic_configure "ABI=32"
    do_make_and_make_install
  cd ..
} # [dlfcn]

build_libnettle() {
  download_and_unpack_file https://ftp.gnu.org/gnu/nettle/nettle-3.4.tar.gz
  cd nettle-3.4
    if [[ ! -f Makefile.in.bak ]]; then # Library only
      sed -i.bak "/^SUBDIRS/s/=.*/=/" Makefile.in
    fi
    generic_configure "--disable-documentation"
    do_make_and_make_install
  cd ..
} # gmp >= 3.0, [dlfcn]

build_gnutls() {
  download_and_unpack_file https://www.gnupg.org/ftp/gcrypt/gnutls/v3.6/gnutls-3.6.2.tar.xz
  cd gnutls-3.6.2
    # --disable-cxx don't need the c++ version, in an effort to cut down on size... XXXX test size difference...
    # --enable-local-libopts to allow building with local autogen installed,
    # --disable-guile is so that if it finds guile installed (cygwin did/does) it won't try and link/build to it and fail...
    if [[ ! -f lib/gnutls.pc.in.bak ]]; then
      sed -i.bak "s/Libs.private.*/& -lcrypt32/" lib/gnutls.pc.in
    fi
    # FFmpeg's 'configure' needs '-lcrypt32' for GnuTLS. Otherwise you'll get "undefined reference to `_imp__Cert[...]'" and "ERROR: gnutls not found using pkg-config" (https://gitlab.com/gnutls/gnutls/issues/412). Configuring FFmpeg with '--extra-libs=-lcrypt32' is another option.
    generic_configure "--disable-doc --disable-tools --disable-cxx --disable-tests --disable-gtk-doc-html --disable-libdane --disable-nls --enable-local-libopts --disable-guile --with-included-libtasn1 --with-included-unistring --without-p11-kit"
    do_make_and_make_install
  cd ..
} # nettle >= 3.1, hogweed(=nettle) >= 3.1, [zlib, dlfcn]

build_openssl-1.0.2() {
  download_and_unpack_file https://www.openssl.org/source/openssl-1.0.2o.tar.gz
  cd openssl-1.0.2o
    apply_patch file://$patch_dir/openssl-1.0.2o_lib-only.diff
    export CC="${cross_prefix}gcc"
    export AR="${cross_prefix}ar"
    export RANLIB="${cross_prefix}ranlib"
    local config_options="--prefix=$mingw_w64_x86_64_prefix zlib --with-zlib-include=$mingw_w64_x86_64_prefix/include --with-zlib-lib=$mingw_w64_x86_64_prefix/lib mingw "
    if [ "$1" = "dllonly" ]; then
      config_options+="shared"
    else
      config_options+="no-shared no-dso"
    fi
    do_configure "$config_options" ./Configure
    sed -i "s/-O3/-O2/" Makefile # Change CFLAGS.
    if [ "$1" = "dllonly" ]; then # Make, strip and pack shared libraries.
      do_make "build_libs"
      do_strip .
      mkdir -p $redist_dir
      archive="$redist_dir/openssl-x86-v1.0.2o"
      if [[ $original_cflags =~ "pentium3" ]]; then
        archive+="_legacy"
      fi
      if [[ ! -f $archive.7z ]]; then
        sed "s/$/\r/" LICENSE > LICENSE.txt
        7z a -mx=9 $archive.7z *.dll LICENSE.txt && rm -f LICENSE.txt
      else
        echo "Already made '$(basename $archive.7z)'."
      fi
    else
      do_make_and_make_install
    fi
    unset CC
    unset AR
    unset RANLIB
  cd ..
}

build_openssl-1.1.0() {
  download_and_unpack_file https://www.openssl.org/source/openssl-1.1.0h.tar.gz
  cd openssl-1.1.0h
    export CC="${cross_prefix}gcc"
    export AR="${cross_prefix}ar"
    export RANLIB="${cross_prefix}ranlib"
    local config_options="--prefix=$mingw_w64_x86_64_prefix zlib --with-zlib-include=$mingw_w64_x86_64_prefix/include --with-zlib-lib=$mingw_w64_x86_64_prefix/lib mingw no-async "
    # "Note: on older OSes, like CentOS 5, BSD 5, and Windows XP or Vista, you will need to configure with no-async when building OpenSSL 1.1.0 and above. The configuration system does not detect lack of the Posix feature on the platforms." (https://wiki.openssl.org/index.php/Compilation_and_Installation)
    if [ "$1" = "dllonly" ]; then
      config_options+="shared"
    else
      config_options+="no-shared no-dso" # No 'no-engine' because Curl needs it when built with Libssh2.
    fi
    do_configure "$config_options" ./Configure
    sed -i "s/-O3/-O2/" Makefile # Change CFLAGS.
    do_make "build_libs"
    if [ "$1" = "dllonly" ]; then # Strip and pack shared libraries.
      do_strip .
      mkdir -p $redist_dir
      archive="$redist_dir/openssl-x86-v1.1.0h"
      if [[ $original_cflags =~ "pentium3" ]]; then
        archive+="_legacy"
      fi
      if [[ ! -f $archive.7z ]]; then
        sed "s/$/\r/" LICENSE > LICENSE.txt
        7z a -mx=9 $archive.7z *.dll LICENSE.txt && rm -f LICENSE.txt
      else
        echo "Already made '$(basename $archive.7z)'."
      fi
    else
      do_make_install "" "install_dev"
    fi
    unset CC
    unset AR
    unset RANLIB
  cd ..
}

build_libogg() {
  do_git_checkout https://github.com/xiph/ogg.git
  cd ogg_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "s/ doc//;/m4data/,+2d" Makefile.am
    fi
    generic_configure_make_install
  cd ..
} # [dlfcn]

build_libvorbis() {
  do_git_checkout https://github.com/xiph/vorbis.git
  cd vorbis_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "s/ test.*//;/m4data/,+2d" Makefile.am
    fi
    generic_configure "--disable-docs --disable-examples --disable-oggtest"
    do_make_and_make_install
  cd ..
} # libogg >= 1.0, [dlfcn]

build_libopus() {
  do_git_checkout https://github.com/xiph/opus.git
  cd opus_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/m4data/,+2d;/install-data-local/,+2d" Makefile.am
    fi
    generic_configure "--disable-doc --disable-extra-programs --disable-stack-protector"
    # Without '--disable-stack-protector' FFmpeg's 'configure' fails with "undefined reference to `__stack_chk_fail'".
    do_make_and_make_install
  cd ..
} # [dlfcn]

build_libspeexdsp() {
  do_git_checkout https://github.com/xiph/speexdsp.git
  cd speexdsp_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "s/ doc.*//" Makefile.am
    fi
    generic_configure "--disable-examples"
    do_make_and_make_install
  cd ..
} # [libogg (only for 'examples'), dlfcn]

build_libspeex() {
  do_git_checkout https://github.com/xiph/speex.git
  cd speex_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/m4data/,+2d;/^SUBDIRS/s/ doc.*//" Makefile.am
    fi
    generic_configure "--disable-binaries" # If you do want the binaries, then 'speexdec.exe' needs 'LDFLAGS=-lwinmm'.
    do_make_and_make_install
  cd ..
} # [libspeexdsp, dlfcn]

build_libtheora() {
  do_git_checkout https://github.com/xiph/theora.git
  cd theora_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "s/ doc.*//" Makefile.am
    fi
    generic_configure "--disable-doc --disable-oggtest --disable-vorbistest --disable-examples"
    # 'examples/encoder_example.c' would otherwise cause problems; "encoder_example.c:56:15: error: static declaration of 'rint' follows non-static declaration".
    do_make_and_make_install
  cd ..
} # libogg >= 1.1, [(libvorbis >= 1.0.1, sdl and libpng only for 'test', 'programs' and 'examples'), dlfcn]

build_libsndfile() {
  do_git_checkout https://github.com/erikd/libsndfile.git
  cd libsndfile_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/=.*/= src/" Makefile.am
    fi
    generic_configure "--disable-sqlite --disable-external-libs --disable-full-suite"
    do_make_and_make_install
    if [ "$1" = "install-libgsm" ]; then
      if [ ! -f "$mingw_w64_x86_64_prefix/lib/libgsm.a" ] || [ "src/GSM610/.libs/libgsm.a" -nt "$mingw_w64_x86_64_prefix/lib/libgsm.a" ]; then
        rm -f $mingw_w64_x86_64_prefix/lib/libgsm.a
        echo "Installing GSM 6.10."
        install -m644 src/GSM610/.libs/libgsm.a $mingw_w64_x86_64_prefix/lib/libgsm.a
        install -m644 src/GSM610/gsm.h $mingw_w64_x86_64_prefix/include/gsm.h
      else
        echo "Already installed GSM 6.10."
      fi
    fi
  cd ..
} # [(libogg >= 1.1.3 and libvorbis >= 1.2.3 only for external support), dlfcn]

build_lame() {
  do_git_checkout https://github.com/rbrito/lame.git
  cd lame_git
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/ frontend//;/^SUBDIRS/s/ doc//" Makefile.in
    fi
    generic_configure "--enable-nasm --disable-decoder --disable-frontend"
    do_make_and_make_install
  cd ..
} # [dlfcn]

build_twolame() {
  do_git_checkout https://github.com/njh/twolame.git
  cd twolame_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/ frontend.*//" Makefile.am
    fi
    generic_configure_make_install
  cd ..
} # [libsndfile >= 1.0.0, dlfcn]

build_fdk-aac() {
  do_git_checkout https://github.com/mstorsjo/fdk-aac.git
  cd fdk-aac_git
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-static" # Build shared library ('libfdk-aac-1.dll').
    do_make
    do_strip .libs/libfdk-aac-1.dll
    do_make_install

    mkdir -p $redist_dir
    archive="$redist_dir/libfdk-aac-x86-$(git describe --tags)"
    if [[ $original_cflags =~ "pentium3" ]]; then
      archive+="_legacy"
    fi
    if [[ ! -f $archive.7z ]]; then # Pack shared library.
      sed "s/$/\r/" NOTICE > NOTICE.txt
      7z a -mx=9 $archive.7z $(pwd)/.libs/libfdk-aac-1.dll NOTICE.txt && rm -f NOTICE.txt
    else
      echo "Already made '$(basename $archive.7z)'."
    fi
  cd ..
} # [dlfcn]

build_libopencore() {
  generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-0.1.5.tar.gz
  #generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz
  generic_download_and_make_and_install https://github.com/mstorsjo/vo-amrwbenc/archive/v0.1.3.tar.gz vo-amrwbenc-0.1.3
} # [dlfcn]

build_libilbc() {
  do_git_checkout https://github.com/TimothyGu/libilbc.git
  cd libilbc_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/dist_doc/,+3d" Makefile.am
    fi
    generic_configure_make_install
  cd ..
} # [dlfcn]

build_libmpg123() {
  download_and_unpack_file https://downloads.sourceforge.net/project/mpg123/mpg123/1.25.10/mpg123-1.25.10.tar.bz2
  cd mpg123-1.25.10
    if [[ ! -f libmpg123.pc.in.bak ]]; then
      sed -i.bak "/Libs/a\Libs.private: @LIBS@" libmpg123.pc.in
    fi
    # FFmpeg's 'configure' needs '-lshlwapi' for LibOpenMPT. Otherwise you'll get "undefined reference to `_imp__PathIs[...]'" and "ERROR: libopenmpt not found using pkg-config" (https://sourceforge.net/p/mpg123/mailman/message/35653684/). Configuring FFmpeg with '--extra-libs=-lshlwapi' is another option.
    if [[ ! -f Makefile.in.bak ]]; then # Library only
      sed -i.bak "/^all-am/s/\$(PROG.*/\\\/;/^install-data-am/s/ install-man//;/^install-exec-am/s/ install-binPROGRAMS//" Makefile.in
    fi
    generic_configure "--enable-yasm"
    do_make_and_make_install
  cd ..
} # [dlfcn]

build_libopenmpt() {
  download_and_unpack_file https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-0.3.8+release.autotools.tar.gz
  cd libopenmpt-0.3.8+release.autotools
    if [[ ! -f Makefile.in.bak ]]; then # Library only
      sed -i.bak "/^all-am/s/DATA/pkgconfig_DATA/;/^install-data-am/s/:.*/: \\\/;s/\tinstall-nobase_dist_docDATA /\t/" Makefile.in
    fi
    generic_configure "--disable-openmpt123 --disable-examples --disable-tests"
    do_make_and_make_install
  cd ..
} # zlib, libmpg123, libogg, libvorbis, [dlfcn]

build_libgme() {
  do_git_checkout https://bitbucket.org/mpyne/game-music-emu.git
  cd game-music-emu_git
    if [[ ! -f CMakeLists.txt.bak ]]; then
      sed -i.bak "/EXCLUDE_FROM_ALL/d" CMakeLists.txt # Library only.
      sed -i.bak "s/ __declspec.*//" gme/blargg_source.h # Needed for building shared FFmpeg libraries.
    fi
    do_cmake_and_install "-DBUILD_SHARED_LIBS=0 -DENABLE_UBSAN=0 -DZLIB_INCLUDE_DIR=$mingw_w64_x86_64_prefix/include -DZLIB_LIBRARY=$mingw_w64_x86_64_prefix/lib/libz.a"
    # Otherwise they default to: "ZLIB_INCLUDE_DIR:PATH=/usr/include" and "ZLIB_LIBRARY:FILEPATH=/usr/lib/libz.a" and cmake would thus pick Cygwin's zlib, which leads to "warning: "errno" redefined" (LibGME) and "undefined reference to `__assert_func'" (FFmpeg).
  cd ..
} # zlib

build_libbluray() {
  do_git_checkout https://git.videolan.org/git/libbluray.git
  cd libbluray_git
    if [[ ! -d .git/modules ]]; then
      git submodule update --init --remote # For UDF support (default=enabled), which strangely enough is in another repository.
      # This can also be done with 'git clone --recursive', but since libbluray is the only one that actually requires a submodule, it's undesirable to have it in 'do_git_checkout()'.
    else
      if [[ $(git --git-dir=.git/modules/contrib/libudfread rev-parse HEAD) != $(git ls-remote -h git://git.videolan.org/libudfread.git | sed "s/\s.*//") ]]; then
        git submodule foreach -q 'git reset --hard' # Return files to their original state.
        git submodule foreach -q 'git clean -fdx' # Clean the working tree; build- as well as untracked files.
        echo "Got upstream changes. Updating the libudfread submodule to latest git version 'origin/master'."
        git submodule update --remote
        rm -f already_* # Force recompiling libbluray.
      else
        echo "Got no code changes. The libudfread submodule is up-to-date."
      fi
    fi
    cd contrib/libudfread
      if [[ ! -f src/udfread.c.bak ]]; then
        sed -i.bak "/WIN32$/,+4d" src/udfread.c # Fix WinXP incompatibility.
      fi
      if [[ ! -f src/udfread-version.h ]]; then
        generic_configure # Generate 'udfread-version.h', or building LibBluray fails otherwise.
      fi
    cd ../..
    if [[ ! -f jni/win32/jni_md.h.bak ]]; then
      sed -i.bak "s/ __declspec.*//" jni/win32/jni_md.h # Needed for building shared FFmpeg libraries.
    fi
    generic_configure "--disable-examples --disable-bdjava-jar"
    do_make_and_make_install
  cd ..
} # libxml >= 2.6, freetype, [fontconfig (-lgdi32 is used instead), dlfcn]

build_libbs2b() {
  download_and_unpack_file https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz
  cd libbs2b-3.1.0
    if [[ ! -f src/Makefile.in.bak ]]; then
      sed -i.bak "/^bin_PROGRAMS/s/=.*/=/" src/Makefile.in # Library only.
    fi
    generic_configure_make_install
  cd ..
} # libsndfile, [dlfcn]

build_libsoxr() {
  do_git_checkout https://git.code.sf.net/p/soxr/code soxr_git
  cd soxr_git
    if [[ ! -f CMakeLists.txt.bak ]]; then # Library only.
      sed -i.bak "/^install/,+5d" CMakeLists.txt
    fi
    do_cmake_and_install "-DBUILD_SHARED_LIBS=0 -DHAVE_WORDS_BIGENDIAN_EXITCODE=0 -DWITH_OPENMP=0 -DBUILD_TESTS=0 -DBUILD_EXAMPLES=0"
  cd ..
}

build_libflite() {
  download_and_unpack_file http://www.festvox.org/flite/packed/flite-2.0/flite-2.0.0-release.tar.bz2
  cd flite-2.0.0-release
    if [[ ! -f configure.bak ]]; then
      sed -i.bak "s|i386-mingw32-|$cross_prefix|" configure
      #sed -i.bak "/define const/i\#include <windows.h>" tools/find_sts_main.c # Needed for x86_64? Untested.
      sed -i.bak "128,134d" main/Makefile # Library only.
    fi
    generic_configure_make_install
  cd ..
}

build_libsnappy() {
  do_git_checkout https://github.com/google/snappy.git
  cd snappy_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/# Unit/,+7d;/^dist/s/=.*/=/" Makefile.am
    fi
    generic_configure_make_install
  cd ..
}

build_vamp_plugin() {
  download_and_unpack_file https://code.soundsoftware.ac.uk/attachments/download/2206/vamp-plugin-sdk-2.7.1.tar.gz
  cd vamp-plugin-sdk-2.7.1
    apply_patch file://$patch_dir/vamp-plugin-sdk-2.7.1_static-lib.diff # Create install-static target.
    if [[ ! -f configure.bak ]]; then # Fix for "'M_PI' was not declared in this scope" (see https://stackoverflow.com/a/29264536).
      sed -i.bak "s/c++98/gnu++98/" configure
    fi
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-programs"
    do_make "install-static" # No need for 'do_make_install', because 'install-static' already has install-instructions.
  cd ..
}

build_fftw() {
  download_and_unpack_file http://fftw.org/fftw-3.3.6-pl2.tar.gz
  cd fftw-3.3.6-pl2
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/api.*/api/;/^libbench2/d" Makefile.in
    fi
    generic_configure "--disable-doc"
    do_make_and_make_install
  cd ..
}

build_libsamplerate() {
  do_git_checkout https://github.com/erikd/libsamplerate.git
  cd libsamplerate_git
    generic_configure
    if [[ ! -f Makefile.bak ]]; then # Library only.
      sed -i.bak "/^all-am/s/ \$(PROGRAMS)//;/install-data-am/s/ install-dist_htmlDATA//;/install-exec-am/s/ install-binPROGRAMS//" Makefile
    fi
    do_make_and_make_install
  cd ..
}

build_librubberband() {
  do_git_checkout https://github.com/breakfastquay/rubberband.git
  cd rubberband_git
    apply_patch file://$patch_dir/rubberband_git_static-lib.diff # Create install-static target.
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix"
    do_make "install-static" # No need for 'do_make_install', because 'install-static' already has install-instructions.
  cd ..
}

build_frei0r() {
  do_git_checkout https://github.com/dyne/frei0r.git
  cd frei0r_git
    do_cmake_and_install

    mkdir -p $cur_dir/redist # Strip and pack shared libraries.
    if [ $bits_target = 32 ]; then
      local arch=x86
    else
      local arch=x86_64
    fi
    archive="$cur_dir/redist/frei0r-plugins-${arch}-$(git describe --tags).7z"
    if [[ ! -f $archive ]]; then
      for sharedlib in $mingw_w64_x86_64_prefix/lib/frei0r-1/*.dll; do
        ${cross_prefix}strip $sharedlib
      done
      for doc in AUTHORS ChangeLog COPYING README.md; do
        sed "s/$/\r/" $doc > $mingw_w64_x86_64_prefix/lib/frei0r-1/$doc.txt
      done
      7z a -mx=9 $archive $mingw_w64_x86_64_prefix/lib/frei0r-1 && rm -f $mingw_w64_x86_64_prefix/lib/frei0r-1/*.txt
    fi
  cd ..
}

build_vidstab() {
  do_git_checkout https://github.com/georgmartius/vid.stab.git vid.stab_git
  cd vid.stab_git
    if [[ ! -f CMakeLists.txt.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/O3/O2/;s/ -fPIC//" CMakeLists.txt
    fi
    do_cmake_and_install "-DBUILD_SHARED_LIBS=0 -DUSE_OMP=0" # '-DUSE_OMP' is on by default, but somehow libgomp ('cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/omp.h') can't be found, so '-DUSE_OMP=0' to prevent a compilation error.
  cd ..
}

build_libmysofa() {
  do_git_checkout https://github.com/hoene/libmysofa.git
  cd libmysofa_git
    if [[ ! -f CMakeLists.txt.bak ]]; then # Library only.
      sed -i.bak "/^install/,+1d" CMakeLists.txt
    fi
    do_cmake_and_install "-DBUILD_SHARED_LIBS=0 -DBUILD_TESTS=0"
  cd ..
}

build_libcaca() {
  do_git_checkout https://github.com/cacalabs/libcaca.git
  cd libcaca_git
    apply_patch file://$patch_dir/libcaca_git_stdio-cruft.diff # Fix WinXP incompatibility.
    if [[ ! -f Makefile.am.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/ src.*//;/cxx.*doc/d" Makefile.am
      sed -i.bak "/^SUBDIRS/s/ t//" caca/Makefile.am
    fi
    generic_configure "--libdir=$mingw_w64_x86_64_prefix/lib --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-doc"
    do_make_and_make_install
  cd ..
}

build_libdecklink() {
  if [[ ! -f $mingw_w64_x86_64_prefix/include/DeckLinkAPIVersion.h ]]; then
    # smaller files don't worry about partials for now, plus we only care about the last file anyway here...
    curl -4 file://$patch_dir/DeckLinkAPI.h --fail > $mingw_w64_x86_64_prefix/include/DeckLinkAPI.h || exit 1
    curl -4 file://$patch_dir/DeckLinkAPI_i.c --fail > $mingw_w64_x86_64_prefix/include/DeckLinkAPI_i.c.tmp || exit 1
    mv $mingw_w64_x86_64_prefix/include/DeckLinkAPI_i.c.tmp $mingw_w64_x86_64_prefix/include/DeckLinkAPI_i.c
    curl -4 file://$patch_dir/DeckLinkAPIVersion.h --fail > $mingw_w64_x86_64_prefix/include/DeckLinkAPIVersion.h || exit 1
  fi
}

build_zvbi() {
  download_and_unpack_file https://sourceforge.net/projects/zapping/files/zvbi/0.2.35/zvbi-0.2.35.tar.bz2
  cd zvbi-0.2.35
    apply_patch file://$patch_dir/zvbi-win32.patch
    #apply_patch file://$patch_dir/zvbi-ioctl.patch # Concerns 'contrib/ntsc-cc.c', but subdir 'contrib' doesn't get built, because it isn't needed for 'libzvbi.a'.
    if [[ ! -f Makefile.in.bak ]]; then # Library only.
      sed -i.bak "/^SUBDIRS/s/\\\/src/;/\tm4/,/\tdoc/d" Makefile.in
    fi
    # 'contrib/ntsc-cc.c' (with 'zvbi-ioctl.patch' applied) would otherwise cause problems; "ntsc-cc.c:1330:4: error: unknown type name 'fd_set'".
    # It probably needs '#include <sys/select.h>', because 'fd_set' is defined in 'cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/select.h'. It still fails though after having done so.
    generic_configure " --disable-dvb --disable-bktr --disable-proxy --disable-nls --without-doxygen --without-libiconv-prefix"
    # Without '--without-libiconv-prefix' 'configure' would otherwise search for and only accept a shared Libiconv library.
    do_make_and_make_install
  cd ..
}

build_fribidi() {
  do_git_checkout https://github.com/behdad/fribidi.git
  cd fribidi_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only and disable regeneration of 'configure' (which screws with the CPPFLAGS).
      sed -i.bak "s/ bin.*//;40s/ \\\//;41d" Makefile.am
    fi
    generic_configure "--disable-debug --disable-deprecated"
    do_make_and_make_install
  cd ..
}

build_libass() {
  do_git_checkout_and_make_install https://github.com/libass/libass.git
}

build_libxavs() {
  do_svn_checkout https://svn.code.sf.net/p/xavs/code/trunk xavs_svn
  cd xavs_svn
    if [[ ! -f Makefile.bak ]]; then
      sed -i.bak "/^install/s/:.*/:/;/install xavs/d" Makefile # Library only.
      sed -i.bak "s/O4/O2/" configure # Change CFLAGS.
    fi
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # see https://github.com/rdp/ffmpeg-windows-build-helpers/issues/3
    do_make_and_make_install "$make_prefix_options"
    rm -f NUL # cygwin causes windows explorer to not be able to delete this folder if it has this oddly named file in it...
  cd ..
}

build_libxvid() {
  download_and_unpack_file http://downloads.xvid.org/downloads/xvidcore-1.3.4.tar.gz xvidcore
  cd xvidcore/build/generic
    apply_patch file://$patch_dir/xvidcore-1.3.4_static-lib.diff
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix" # no static option...
    #sed -i.bak "s/-mno-cygwin//" platform.inc # remove old compiler flag that now apparently breaks us # Not needed for static library, but neither anymore for shared library (see 'configure#L5010').
    cpu_count=1 # possibly can't build this multi-thread ? http://betterlogic.com/roger/2014/02/xvid-build-woe/
    do_make_and_make_install
    cpu_count=$original_cpu_count
  cd ../../..
}

build_libvpx() {
  do_git_checkout https://chromium.googlesource.com/webm/libvpx.git
  cd libvpx_git
    if [[ ! -f vp8/common/threading.h.bak ]]; then
      sed -i.bak "/<semaphore.h/i\#include <sys/types.h>" vp8/common/threading.h
    fi
    # 'cross_compilers/mingw-w64-i686/include/semaphore.h' would otherwise cause problems; "semaphore.h:152:8: error: unknown type name 'mode_t'".
    if [[ "$bits_target" = "32" ]]; then
      local config_options="--target=x86-win32-gcc"
    else
      local config_options="--target=x86_64-win64-gcc"
    fi
    export CROSS="$cross_prefix"
    do_configure "$config_options --prefix=$mingw_w64_x86_64_prefix --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth"
    do_make_and_make_install
    unset CROSS
  cd ..
}

build_libx265() {
  # the only one that uses mercurial, so there's some extra initial junk in this method... XXX needs some cleanup :|
  local checkout_dir=x265
  if [[ $high_bitdepth == "y" ]]; then
    checkout_dir=x265_high_bitdepth_10
  fi

  if [[ $prefer_stable = "n" ]]; then
    local old_hg_version
    if [[ -d $checkout_dir ]]; then
      cd $checkout_dir
      if [[ $git_get_latest = "y" ]]; then
        echo "doing hg pull -u x265"
        old_hg_version=`hg --debug id -i`
        hg pull -u || exit 1
        hg update || exit 1 # guess you need this too if no new changes are brought down [what the...]
      else
        echo "not doing hg pull x265"
        old_hg_version=`hg --debug id -i`
      fi
    else
      echo "doing hg clone x265"
      hg clone https://bitbucket.org/multicoreware/x265 $checkout_dir || exit 1
      cd $checkout_dir
      old_hg_version=none-yet
    fi
    cd source

    local new_hg_version=`hg --debug id -i`
    if [[ "$old_hg_version" != "$new_hg_version" ]]; then
      echo "got upstream hg changes, forcing rebuild...x265"
      rm -f already*
    else
      echo "still at hg $new_hg_version x265"
    fi
  else
    # i.e. prefer_stable == "y" TODO clean this up these two branches are pretty similar...
    local old_hg_version
    if [[ -d $checkout_dir ]]; then
      cd $checkout_dir
      if [[ $git_get_latest = "y" ]]; then
        echo "doing hg pull -u x265"
        old_hg_version=`hg --debug id -i`
        hg pull -u || exit 1
        hg update || exit 1 # guess you need this too if no new changes are brought down [what the...]
      else
        echo "not doing hg pull x265"
        old_hg_version=`hg --debug id -i`
      fi
    else
      echo "doing hg clone x265"
      hg clone https://bitbucket.org/multicoreware/x265 -r stable $checkout_dir || exit 1
      cd $checkout_dir
      old_hg_version=none-yet
    fi
    cd source

    local new_hg_version=`hg --debug id -i`
    if [[ "$old_hg_version" != "$new_hg_version" ]]; then
      echo "got upstream hg changes, forcing rebuild...x265"
      rm -f already*
    else
      echo "still at hg $new_hg_version x265"
    fi
  fi # dont with prefer_stable = [y|n]
  apply_patch file://$patch_dir/libx265_git_declspec.diff # Needed for building shared FFmpeg libraries.

  local cmake_params="-DENABLE_SHARED=0 -DENABLE_CLI=0" # Library only.
  if [ "$bits_target" = "32" ]; then
    cmake_params+=" -DWINXP_SUPPORT=1" # enable windows xp/vista compatibility in x86 build
  fi
  if [[ $high_bitdepth == "y" ]]; then
    cmake_params+=" -DHIGH_BIT_DEPTH=1" # Enable 10 bits (main10) and 12 bits (???) per pixels profiles.
  fi

  do_cmake "$cmake_params"
  do_make
  echo force reinstall in case bit depth changed at all :|
  rm already_ran_make_install*
  do_make_install
  cd ../..
}

build_libopenh264() {
  do_git_checkout "https://github.com/cisco/openh264.git"
  cd openh264_git
    if [[ ! -f Makefile.bak ]]; then # Change CFLAGS and Library only.
      sed -i.bak "s/O3/O2/;/^all:/s/ binaries//" Makefile
    fi
    if [ $bits_target = 32 ]; then
      local arch=i686 # or x86?
    else
      local arch=x86_64
    fi
    do_make "$make_prefix_options OS=mingw_nt ARCH=$arch ASM=yasm install-static" # No need for 'do_make_install', because 'install-static' already has install-instructions.
  cd ..
}

build_libx264() {
  local checkout_dir="x264"
  if [[ $build_x264_with_libav == "y" ]]; then
    build_ffmpeg static --disable-libx264 ffmpeg_git_pre_x264 # installs libav locally so we can use it within x264.exe FWIW...
    checkout_dir="${checkout_dir}_with_libav"
    # they don't know how to use a normal pkg-config when cross compiling, so specify some manually: (see their mailing list for a request...)
    export LAVF_LIBS="$LAVF_LIBS $(pkg-config --libs libavformat libavcodec libavutil libswscale)"
    export LAVF_CFLAGS="$LAVF_CFLAGS $(pkg-config --cflags libavformat libavcodec libavutil libswscale)"
    export SWSCALE_LIBS="$SWSCALE_LIBS $(pkg-config --libs libswscale)"
  fi

  local x264_profile_guided=n # or y -- haven't gotten this proven yet...TODO
  if [[ $high_bitdepth == "y" ]]; then
    checkout_dir="${checkout_dir}_high_bitdepth_10"
  else
    checkout_dir="${checkout_dir}_normal_bitdepth"
  fi

  #if [[ $prefer_stable = "n" ]]; then
  #  do_git_checkout "http://git.videolan.org/git/x264.git" $checkout_dir "origin/master" # During 'configure': "Found no assembler. Minimum version is nasm-2.13".
  #else
    do_git_checkout "http://git.videolan.org/git/x264.git" $checkout_dir "origin/stable"
  #fi
  cd $checkout_dir
    if [[ ! -f configure.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/O3 -/O2 -/" configure
    fi

    local configure_flags="--host=$host_target --enable-static --cross-prefix=$cross_prefix --prefix=$mingw_w64_x86_64_prefix --enable-strip --disable-cli" # --enable-win32thread --enable-debug is another useful option here? # Library only.
    if [[ $build_x264_with_libav == "n" ]]; then
      configure_flags+=" --disable-lavf" # lavf stands for libavformat, there is no --enable-lavf option, either auto or disable...
    fi
    if [[ $high_bitdepth == "y" ]]; then
      configure_flags+=" --bit-depth=10" # Enable 10 bits (main10) per pixels profile. possibly affects other profiles as well (?)
    fi
    for i in $CFLAGS; do
      configure_flags+=" --extra-cflags=$i" # needs it this way seemingly :|
    done

    if [[ $x264_profile_guided = y ]]; then
      # I wasn't able to figure out how/if this gave any speedup...
      # TODO more march=native here?
      # TODO profile guided here option, with wine?
      do_configure "$configure_flags"
      curl -4 http://samples.mplayerhq.hu/yuv4mpeg2/example.y4m.bz2 -O --fail || exit 1
      rm -f example.y4m # in case it exists already...
      bunzip2 example.y4m.bz2 || exit 1
      # XXX does this kill git updates? maybe a more general fix, since vid.stab does also?
      sed -i.bak "s_\\, ./x264_, wine ./x264_" Makefile # in case they have wine auto-run disabled http://askubuntu.com/questions/344088/how-to-ensure-wine-does-not-auto-run-exe-files
      do_make_and_make_install "fprofiled VIDS=example.y4m" # guess it has its own make fprofiled, so we don't need to manually add -fprofile-generate here...
    else
      # normal path
      do_configure "$configure_flags"
      do_make
      echo force reinstall in case bit depth changed at all :|
      rm already_ran_make_install*
      do_make_install
    fi

    unset LAVF_LIBS
    unset LAVF_CFLAGS
    unset SWSCALE_LIBS
  cd ..
}

build_libcurl() {
  download_and_unpack_file https://curl.haxx.se/download/curl-7.54.1.tar.gz
  cd curl-7.54.1
    export PKG_CONFIG="pkg-config --static" # Automatically detect all GnuTLS's dependencies.
    generic_configure "--without-ssl --with-gnutls --without-ca-bundle --with-ca-fallback" # Use GnuTLS's built-in CA store instead of a separate 'ca-bundle.crt'.
    do_make # 'curl.exe' only. Don't install.
    unset PKG_CONFIG
  cd ..
}

build_ffmpeg() {
  local extra_postpend_configure_options=$2
  local output_dir=$3
  if [[ -z $output_dir ]]; then
    output_dir="ffmpeg_git"
  fi
  if [[ "$non_free" = "y" ]]; then
    output_dir+="_with_fdk_aac"
  fi
  if [[ $high_bitdepth == "y" ]]; then
    output_dir+="_x26x_high_bitdepth"
  fi
  if [[ $build_intel_qsv == "n" ]]; then
    output_dir+="_xp_compat"
  fi
  if [[ $enable_gpl == 'n' ]]; then
    output_dir+="_lgpl"
  fi

  local postpend_configure_opts=""

  # can't mix and match --enable-static --enable-shared unfortunately, or the final executable seems to just use shared if the're both present
  if [[ $1 == "shared" ]]; then
    output_dir+="_shared"
    postpend_configure_opts="--enable-shared --disable-static --prefix=$(pwd)/${output_dir}"
  else
    postpend_configure_opts="--enable-static --disable-shared --prefix=$mingw_w64_x86_64_prefix"
  fi

  do_git_checkout https://github.com/FFmpeg/FFmpeg.git $output_dir $ffmpeg_git_checkout_version
  cd $output_dir
    git clean -f # Throw away local changes; 'already_*', diff-, done- and bak-files. Somehow the patched files get back to their original state when doing a rerun.
    apply_patch file://$patch_dir/libfdk-aac_load-shared-library-dynamically.diff
    apply_patch file://$patch_dir/frei0r_load-shared-libraries-dynamically.diff
    if [[ ! -f configure.bak ]]; then # Changes being made to 'configure' are done with 'sed', because 'configure' gets updated a lot.
      sed -i.bak "/enabled libfdk_aac/s/&.*/\&\& { check_header fdk-aac\/aacenc_lib.h || die \"ERROR: aacenc_lib.h not found\"; }/;/require libfdk_aac/,/without pkg-config/d;/    libfdk_aac/d;/    libflite/i\    libfdk_aac" configure # Load 'libfdk-aac-1.dll' dynamically.
      sed -i "/enabled libtwolame/s/&&$/-DLIBTWOLAME_STATIC \&\& add_cppflags -DLIBTWOLAME_STATIC \&\&/;/enabled libmodplug/s/.*/& -DMODPLUG_STATIC \&\& add_cppflags -DMODPLUG_STATIC/;/enabled libcaca/s/.*/& -DCACA_STATIC \&\& add_cppflags -DCACA_STATIC/" configure # Add '-Dxxx_STATIC' to LibTwoLAME, LibModplug and Libcaca. FFmpeg should change this upstream, just like they did with libopenjpeg.
      # Alternative to 'do_configure "... --extra-cflags=-DLIBTWOLAME_STATIC --extra-cflags=-DMODPLUG_STATIC --extra-cflags=-DCACA_STATIC"'.
      sed -i.bak "s/ install-data//" Makefile # Binary only (don't install 'DATA_FILES' and 'EXAMPLES_FILES').
    fi

    if [ "$bits_target" = "32" ]; then
      local arch=x86
    else
      local arch=x86_64
    fi

    init_options="--arch=$arch --target-os=mingw32 --cross-prefix=$cross_prefix --pkg-config=pkg-config --pkg-config-flags=--static --extra-version=Reino --enable-gray --enable-version3 --disable-debug --disable-doc --disable-htmlpages --disable-manpages --disable-podpages --disable-txtpages --disable-w32threads"
    if [[ `uname` =~ "5.1" ]]; then
      init_options+=" --disable-schannel"
      # Fix WinXP incompatibility by disabling Microsoft's Secure Channel, because Windows XP doesn't support TLS 1.1 and 1.2, but with GnuTLS or OpenSSL it does. The main reason I started this journey!
    fi
    config_options="$init_options --enable-fontconfig --enable-gmp --enable-gnutls --enable-libass --enable-libbluray --enable-libbs2b --enable-libcaca --enable-libfdk-aac --enable-libflite --enable-libfreetype --enable-libfribidi --enable-libgme --enable-libgsm --enable-libilbc --enable-libmodplug --enable-libmp3lame --enable-libmysofa --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libopenh264 --enable-libopenjpeg --enable-libopus --enable-libsnappy --enable-libsoxr --enable-libspeex --enable-libtheora --enable-libtwolame --enable-libvo-amrwbenc --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libzimg --enable-libzvbi"
    # With the changes being made to 'configure' above and with '--pkg-config-flags=--static' there's no need anymore for '--extra-cflags=' and '--extra-libs='.
    if [[ $enable_gpl == 'y' ]]; then
      config_options+=" --enable-gpl --enable-avisynth --enable-frei0r --enable-filter=frei0r --enable-librubberband --enable-libvidstab --enable-libx264 --enable-libx265 --enable-libxavs --enable-libxvid"
    fi
    # other possibilities (you'd need to also uncomment the call to their build method):
    #   --enable-w32threads # [worse UDP than pthreads, so not using that]
    if [[ $build_intel_qsv = y ]]; then
      config_options+=" --enable-libmfx" # [note, not windows xp friendly]
    fi
    config_options+=" --enable-avresample" # guess this is some kind of libav specific thing (the FFmpeg fork) but L-Smash needs it so why not always build it :)

    for i in $CFLAGS; do
      config_options+=" --extra-cflags=$i" # --extra-cflags may not be needed here, but adds it to the final console output which I like for debugging purposes
    done

    config_options+=" $postpend_configure_opts"

    if [[ "$non_free" = "y" ]]; then
      config_options+=" --enable-nonfree --enable-decklink"
      # To use fdk-aac in VLC, we need to change FFMPEG's default (aac), but I haven't found how to do that... So I disabled it. This could be an new option for the script? (was --disable-decoder=aac )
      # other possible options: --enable-openssl [unneeded since we use gnutls]
    fi
    #apply_patch file://$patch_dir/nvresize2.patch "-p1" # uncomment if you want to test nvresize filter [et al] http://ffmpeg.org/pipermail/ffmpeg-devel/2015-November/182781.html patch worked with 7ab37cae34b3845

    do_debug_build=n # if you need one for backtraces/examining segfaults using gdb.exe ... change this to y :) XXXX make it affect x264 too...and make it param
    if [[ "$do_debug_build" = "y" ]]; then
      # not sure how many of these are actually needed/useful...possibly none LOL
      config_options+=" --disable-optimizations --extra-cflags=-Og --extra-cflags=-fno-omit-frame-pointer --enable-debug=3 --extra-cflags=-fno-inline $postpend_configure_opts"
      # this one kills gdb workability for static build? ai ai [?] XXXX
      config_options+=" --disable-libgme"
    fi
    config_options+=" $extra_postpend_configure_options"

    do_configure "$config_options"
    rm -f */*.a */*.dll *.exe # just in case some dependency library has changed, force it to re-link even if the ffmpeg source hasn't changed...
    rm -f already_ran_make*
    echo "doing ffmpeg make $(pwd)"
    do_make_and_make_install # install ffmpeg to get libavcodec libraries to be used as dependencies for other things, like vlc [XXX make this a parameter?] or install shared to a local dir

    # build ismindex.exe, too, just for fun
    if [[ $build_ismindex == "y" ]]; then
      make tools/ismindex.exe || exit 1
    fi

    # XXX really ffmpeg should have set this up right but doesn't, patch FFmpeg itself instead...
    if [[ $1 == "static" ]]; then
      if [[ $build_intel_qsv = y ]]; then
        sed -i.bak 's/-lavutil -lm.*/-lavutil -lm -lmfx -lstdc++ -lpthread/' "$PKG_CONFIG_PATH/libavutil.pc"
      else
        sed -i.bak 's/-lavutil -lm.*/-lavutil -lm -lpthread/' "$PKG_CONFIG_PATH/libavutil.pc"
      fi
      sed -i.bak 's/-lswresample -lm.*/-lswresample -lm -lsoxr/' "$PKG_CONFIG_PATH/libswresample.pc" # XXX patch ffmpeg
    fi

    sed -i.bak 's/-lswresample -lm.*/-lswresample -lm -lsoxr/' "$PKG_CONFIG_PATH/libswresample.pc" # XXX patch ffmpeg

    if [[ $non_free == "y" ]]; then
      if [[ $1 == "shared" ]]; then
        echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)/bin."
      else
        echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)."
      fi
    else
      mkdir -p $cur_dir/redist
      archive="$cur_dir/redist/ffmpeg-$(git describe --tags --match N)-win$bits_target-$1"
      if [[ $original_cflags =~ "pentium3" ]]; then
        archive+="_legacy"
      fi
      if [[ $1 == "shared" ]]; then
        echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)/bin."
        if [[ ! -f $archive.7z ]]; then
          sed "s/$/\r/" COPYING.GPLv3 > bin/COPYING.GPLv3.txt
          cd bin
            7z a -mx=9 $archive.7z *.exe *.dll COPYING.GPLv3.txt && rm -f COPYING.GPLv3.txt
          cd ..
        fi
      else
        echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)."
        if [[ ! -f $archive.7z ]]; then
          sed "s/$/\r/" COPYING.GPLv3 > COPYING.GPLv3.txt
          7z a -mx=9 $archive.7z ffmpeg.exe ffplay.exe ffprobe.exe COPYING.GPLv3.txt && rm -f COPYING.GPLv3.txt
        fi
      fi
      echo "You will find redistributable archives in $cur_dir/redist."
    fi
    echo `date`
  cd ..
} # SDL2 (only for FFplay)

build_dependencies() {
  build_cmake
  build_nasm
  build_dlfcn
  build_bzip2 # Bzlib (bzip2) in FFmpeg is autodetected, so no need for --enable-bzlib.
  build_liblzma # Lzma in FFmpeg is autodetected, so no need for --enable-lzma.
  build_zlib # Zlib in FFmpeg is autodetected, so no need for --enable-zlib.
  build_iconv # Iconv in FFmpeg is autodetected, so no need for --enable-iconv.
  build_sdl2 # Sdl2 in FFmpeg is autodetected, so no need for --enable-sdl2.
  build_libzimg # Uses dlfcn.
  build_libopenjpeg
  build_libpng # Needs zlib >= 1.0.4. Uses dlfcn.
  build_libwebp
  build_freetype
  build_libxml2 # For DASH support configure FFmpeg with --enable-libxml2.
  build_fontconfig
  build_gmp # For RTMP support configure FFmpeg with --enable-gmp.
  build_libnettle
  build_gnutls # For HTTPS TLS 1.2 support on WinXP configure FFmpeg with --enable-gnutls.
  #if [[ "$non_free" = "y" ]]; then # Nonfree alternative to GnuTLS.
  #  build_openssl-1.0.2
  #  build_openssl-1.1.0
  #fi
  #build_libcurl # Uses GnuTLS/OpenSSL, zlib and dlfcn. Only for building 'curl.exe'.
  build_libogg
  build_libvorbis
  build_libopus
  build_libspeexdsp
  build_libspeex
  build_libtheora
  build_libsndfile install-libgsm # 'build_libsndfile install-libgsm' to install the bundled LibGSM 6.10.
  build_lame
  build_twolame
  build_fdk-aac
  build_libopencore
  build_libilbc
  build_libmpg123
  build_libopenmpt
  build_libgme
  build_libbluray
  build_libbs2b
  build_libsoxr
  build_libflite
  build_libsnappy # Uses zlib (only for unittests [disabled]) and dlfcn.
  build_vamp_plugin # Needs libsndfile for 'vamp-simple-host.exe' [disabled].
  build_fftw # Uses dlfcn.
  build_libsamplerate # Needs libsndfile >= 1.0.6 and fftw >= 0.15.0 for tests. Uses dlfcn.
  build_librubberband # Needs libsamplerate, libsndfile, fftw and vamp_plugin. 'configure' will fail otherwise. Eventhough librubberband doesn't necessarily need them (libsndfile only for 'rubberband.exe' and vamp_plugin only for "Vamp audio analysis plugin"). How to use the bundled libraries '-DUSE_SPEEX' and '-DUSE_KISSFFT'?
  build_frei0r # Needs dlfcn.
  build_vidstab
  build_libmysofa # Needed for FFmpeg's SOFAlizer filter (https://ffmpeg.org/ffmpeg-filters.html#sofalizer). Uses dlfcn.
  build_libcaca # Uses zlib and dlfcn.
  if [[ "$non_free" = "y" ]]; then
    build_libdecklink
  fi
  build_zvbi # Uses iconv, libpng and dlfcn.
  build_fribidi # Uses dlfcn.
  build_libass # Needs freetype >= 9.10.3 (see https://bugs.launchpad.net/ubuntu/+source/freetype1/+bug/78573 o_O) and fribidi >= 0.19.0. Uses fontconfig >= 2.10.92, iconv and dlfcn.
  build_libxavs
  build_libxvid # FFmpeg now has native support, but libxvid still provides a better image.
  build_libvpx
  build_libx265
  build_libopenh264
  build_libx264 # at bottom as it might build a ffmpeg which needs all the above deps...
}

build_apps() {
  if [[ $build_ffmpeg_static = "y" ]]; then
    build_ffmpeg static
  else
    build_ffmpeg shared
  fi
}

build_openssl-dlls() {
  build_openssl-1.0.2 dllonly # Only for building 'libeay32.dll' and 'ssleay32.dll' (for Xidel).
  build_openssl-1.1.0 dllonly # Only for building 'libeay64.dll' and 'ssleay64.dll'.
}

reset_cflags() {
  export CFLAGS=$original_cflags
}

# set some parameters initial values
cur_dir="$(pwd)/sandbox"
patch_dir="$(dirname $(pwd))/patches" # Or $(cd $(pwd)/../patches && pwd).
redist_dir="$(dirname $(pwd))/redist"
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
git_get_latest=y
prefer_stable=y # Only for x264 and x265.
#disable_nonfree=n # have no value by default to force user selection
original_cflags='-march=pentium3 -O2 -mfpmath=sse -msse' # See https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html, https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html and https://stackoverflow.com/questions/19689014/gcc-difference-between-o3-and-os.
ffmpeg_git_checkout_version=
build_ismindex=n
enable_gpl=y
build_x264_with_libav=n # To build x264 with Libavformat.
export ac_cv_func_vsnprintf_s=no # Mark vsnprintf_s as unavailable, as windows xp mscrt doesn't have it.

# parse command line parameters, if any
while true; do
  case $1 in
    -h | --help ) echo "available option=default_value:
      --build-ffmpeg-static=y  (ffmpeg.exe, ffplay.exe and ffprobe.exe)
      --build-ffmpeg-static=n  (ffmpeg.exe, ffplay.exe, ffprobe.exe and dll-files)
      --ffmpeg-git-checkout-version=[master] if you want to build a particular version of FFmpeg, ex: n3.1.1 or a specific git hash
      --disable-nonfree=y (set to n to include nonfree like libfdk-aac)
      --sandbox-ok=n [skip sandbox prompt if y]
      -d [meaning \"defaults\" skip all prompts, just build ffmpeg static with some reasonable defaults like no git updates]
      --build-ismindex=n [builds ffmpeg utility ismindex.exe]
      --cflags=[default is $original_cflags, which works on any cpu, see README for options]
      --git-get-latest=y [do a git pull for latest code from repositories like FFmpeg--can force a rebuild if changes are detected]
      --build-x264-with-libav=n build x264.exe with bundled/included "libav" ffmpeg libraries within it
      --prefer-stable=y build a few libraries from releases instead of git master
      --high-bitdepth=n Enable high bit depth for x264 (10 bits) and x265 (10 and 12 bits, x64 build. Not officially supported on x86 (win32), but enabled by disabling its assembly).
      --debug Make this script  print out each line as it executes
      --enable-gpl=[y] set to n to do an lgpl build
       "; exit 0 ;;
    --sandbox-ok=* ) sandbox_ok="${1#*=}"; shift ;;
    --ffmpeg-git-checkout-version=* ) ffmpeg_git_checkout_version="${1#*=}"; shift ;;
    --build-ismindex=* ) build_ismindex="${1#*=}"; shift ;;
    --git-get-latest=* ) git_get_latest="${1#*=}"; shift ;;
    --build-x264-with-libav=* ) build_x264_with_libav="${1#*=}"; shift ;;
    --cflags=* )
       original_cflags="${1#*=}"; echo "setting cflags as $original_cflags"; shift ;;
    --disable-nonfree=* ) disable_nonfree="${1#*=}"; shift ;;
    -d         ) gcc_cpu_count=$cpu_count; disable_nonfree="y"; sandbox_ok="y"; git_get_latest="n"; shift ;;
    --build-ffmpeg-static=* ) build_ffmpeg_static="${1#*=}"; shift ;;
    --prefer-stable=* ) prefer_stable="${1#*=}"; shift ;;
    --enable-gpl=* ) enable_gpl="${1#*=}"; shift ;;
    --high-bitdepth=* ) high_bitdepth="${1#*=}"; shift ;;
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
echo "Starting 32-bit builds."
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
