#! /bin/bash
export PREFIX="$HOME/opt/cross"
export TARGET=i686-elf
export PATH="$PREFIX/bin:$PATH"

shell_folder=$(cd "$(dirname "$0")" || exit; pwd)
if [ ! -d "$shell_folder"/tools ]; then
    echo 'tools/ not exits, creating...'
    mkdir -p "$shell_folder"/tools/newlib
    echo 'Downloading cross-compiler...'
    echo '=> gcc: 10'
    wget -c --quiet --show-progress -P "$shell_folder"/tools https://ftp.gnu.org/gnu/gcc/gcc-10.4.0/gcc-10.4.0.tar.gz
    echo '=> binutils'
    wget -c --quiet --show-progress -P "$shell_folder"/tools https://ftp.gnu.org/gnu/binutils/binutils-2.38.tar.gz
    echo '=> newlib'
    git clone git://sourceware.org/git/newlib-cygwin.git "$shell_folder"/tools/newlib
    echo 'Cross-compile tools download successful, if you want to compile them, run: bash init -c'
fi

if [ "$1" = "-c" ] || [ "$1" = "--compile" ]; then
    log="$shell_folder"/tools/log
    mkdir -p "$log"

    echo "Target platform $TARGET"
    echo "Cross-compile tools will be installed: $PREFIX"
    echo "Compile may take 20~30 minutes, start in 3 seconds..."
    sleep 3s
    echo "=> Compile binutils"
    cd "$shell_folder"/tools || (echo "cd to tools fail, nothong changed, exiting..." && exit)
    echo "Extracting..."
    sleep 2s
    tar xzf "$shell_folder"/tools/binutils-2.38.tar.gz
    mkdir -p build-binutils && cd "$shell_folder"/tools/build-binutils || exit
    ../binutils-2.38/configure --target=$TARGET --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror 2>&1 | tee "$log"/binutil-configure.log
    make -j "$(nproc)" 2>&1 | tee "$log"/binutil-make.log
    make install 2>&1 | tee "$log"/binutil-make-install.log
    echo "binutils compiled!"

    echo "=> Compile gcc"
    cd "$shell_folder"/tools || (echo "cd to tools fail, nothong changed, exiting..." && exit)
    echo "search $TARGET-as..."
    which -- $TARGET-as || (echo "$TARGET-as is not in the PATH, aborting..."; exit)
    echo "Extracting..."
    sleep 2s
    tar xzf "$shell_folder"/tools/gcc-10.4.0.tar.gz
    mkdir -p build-gcc && cd "$shell_folder"/tools/build-gcc || exit
    ../gcc-10.4.0/configure --target=$TARGET --prefix="$PREFIX" --disable-nls --enable-language=c,c++ --without-headers 2>&1 | tee "$log"/gcc-configure.log
    make -j "$(nproc)" all-gcc 2>&1 | tee "$log"/gcc-make-all-gcc.log
    make -j "$(nproc)" all-target-gcc 2>&1 | tee "$log"/gcc-make-all-target-gcc.log
    make install-gcc 2>&1 | tee "$log"/gcc-make-install-gcc.log
    make install-target-gcc 2>&1 | tee "$log"/gcc-make-install-target-gcc.log
    echo "gcc compiled!"
    cd "$shell_folder" || exit;
    
    echo "You can run $TARGET-gcc, $TARGET-ld, $TARGET-as now"
fi

# export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/gcc-cross/i686-linux-gnu/10
