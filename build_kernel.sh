#!/bin/bash

# Print help for this bash script
print_help() {
    echo "$PROG - Cross compile Linux Kernel for Android"
    echo ""
    echo "Usage $PROG [OPTION...] [COMMAND]... [-- ARGS]"
    echo ""
    echo "Options:"
    echo "  -c, --clang-path      Specify clang path for LLVM tools and compiler"
    echo "  -g, --gcc-path        Specify gcc tool path, only used if -u is set"
    echo "  -d, --defconfig       Specify defconfig to use"
    echo ""
    echo "Commands:"
    echo "  -b, --bear            Use \`bear\` to generate a compdb"
    echo "  -C, --clean           rm -rf the $OUT folder"
    echo "  -G, --gen-defconfig   Also generate a defconfig in out/defconfig"
    echo "  -n, --no-build        Stop right before building"
    echo "  -N, --nconfig         Run \`make nconfig\` before building"
    echo "  -u, --use-gcc         Use gcc, for 4.19 kernel"
    echo "                        This will automatically select -G"
    echo "  -t, --build-dtbo      Also build dtbo"
    echo "  -h, --help            Print this help message and exit"
    echo ""
    echo "* Arguments right after -- will make the script to run ARGS one by one separated by space and exit"
    echo "    !! No above arguments will take effect"
    echo ""
    echo "* Execution sequence:"
    echo "  0. make ARGS and exit [-- ARGS]"
    echo "  1. make defconfig [-d]"
    echo "  2. make nconfig [-N]"
    echo "  3. make gendefconfig [-N | -G]"
    echo "  4. make [-n | -b]"
    echo ""
}

if [ ! -d ./out ]; then
    mkdir out
fi

# Default value
GCC_PATH=/data/LineageOS/LineageOS_20/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin
CLANG_PATH=/data/LineageOS/LineageOS_20/prebuilts/clang/host/linux-x86/clang-r450784d/bin
DEFCONFIG=(gki_defconfig vendor/kalama_GKI.config vendor/sony/kalama_GKI.config)
GEN_DEFCONFIG=0
NO_BUILD=0
USE_BEAR=0
PROG=${0##*/}
OUT=out
dtbo=out/arch/arm64/boot/dts/vendor/qcom/kalama-yodo-pdx234_generic-overlay.dtbo

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bear)
            # Use `bear` to generate a compdb
            USE_BEAR=1
            shift
            ;;
        -c|--clang-path)
            # Specify Clang path for LLVM tools and compiler
            CLANG_PATH="$2"
            shift
            shift
            ;;
        -C|--clean)
            # rm -rf out before anything
            CLEAN=1
            shift
            ;;
        -d|--defconfig)
            # Specify defconfig to use
            read -ra DEFCONFIG <<< "$2"
            shift
            shift
            ;;
        -g|--gcc-path)
            # Specify gcc tool path
            GCC_PATH="$2"
            shift
            shift
            ;;
        -G|--gen-defconfig)
            # Also generate a defconfig in $OUT/defconfig
            GEN_DEFCONFIG=1
            shift
            ;;
        -h|--help)
            # Print help and exit
            print_help
            exit 0
            ;;
        -n|--no-build)
            # Stop right before building
            NO_BUILD=1
            shift
            ;;
        -N|--nconfig)
            # Run `make nconfig` before building
            # This will generate a defconfig in $OUT/defconfig
            NCONFIG=1
            GEN_DEFCONFIG=1
            shift
            ;;
        -u|--use-gcc)
            # Use gcc
            USE_GCC=1
            shift
            ;;
        -t|--build-dtbo)
            # Build DTBO
            BUILD_DTBO=1
            shift
            ;;
        --)
            # Specify arguments to run, and exit
            MORE_ARG=1
            shift
            # No longer parse arguments
            break
            ;;
        default)
            # Not supported argument
            echo "$1 is not a valid argument!"
            print_help
            exit 1
            ;;
    esac
done

# Process arguments
if [[ $CLEAN -eq 1 ]]; then
    rm -rf $OUT
fi

if [[ $USE_GCC -eq 1 ]]; then
    BUILD_CROSS_COMPILE=${GCC_PATH}/aarch64-linux-android-
    CROSS_COMPILE_CMD=(CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE="$BUILD_CROSS_COMPILE")
fi

BUILD_WRAPPER=(make -j28 -C "$(pwd)" O="$(pwd)"/"$OUT" ARCH=arm64
                LLVM=1 LLVM_IAS=1 "${CROSS_COMPILE_CMD[@]}" )

if [[ $USE_BEAR -eq 1 ]]; then
    BEAR_EXEC="bear -- "
else
    BEAR_EXEC=""
fi

export PATH=${CLANG_PATH}:${PATH}

if [[ $MORE_ARG -eq 1 ]]; then
    if [[ $# -le 0 ]]; then
        echo "No more arguments supplied after --, use usual build procedure"
    else
        set -x
        for var in "$@"; do
            "${BUILD_WRAPPER[@]}" "$var"
        done
        exit 0
    fi
fi

# Default build procedure
"${BUILD_WRAPPER[@]}" "${DEFCONFIG[@]}"

if [[ $NCONFIG -eq 1 ]]; then
    "${BUILD_WRAPPER[@]}" nconfig
fi

if [[ $GEN_DEFCONFIG -eq 1 ]]; then
    "${BUILD_WRAPPER[@]}" savedefconfig
fi

if [[ $NO_BUILD -eq 0 ]]; then
    $BEAR_EXEC "${BUILD_WRAPPER[@]}" 2>&1 | tee build.txt
fi

if [[ $BUILD_DTBO -eq 1 ]]; then
    python2 scripts/dtc/libfdt/mkdtboimg.py create "$(pwd)"/"$OUT"/dtbo.img --page_size=4096 $dtbo
fi
