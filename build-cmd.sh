#!/usr/bin/env bash

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about undefined vars
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

TOP="$(dirname "$0")"

SDL_SOURCE_DIR="SDL2"

stage="$(pwd)"

# load autbuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/{debug,release}/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}

pushd "$TOP/$SDL_SOURCE_DIR"

case "$AUTOBUILD_PLATFORM" in
    windows*)
        load_vsvars

        mkdir -p "$stage/include/SDL2"
        mkdir -p "$stage/lib/debug"
        mkdir -p "$stage/lib/release"

        mkdir -p "build_debug"
        pushd "build_debug"
            cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" -DCMAKE_INSTALL_PREFIX=$(cygpath -m $stage)/debug

            cmake --build . --config Debug
            cmake --install . --config Debug

            # conditionally run unit tests
            #if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            #    ctest -C Debug
            #fi

            cp $stage/debug/bin/*.dll $stage/lib/debug/
            cp $stage/debug/lib/*.lib $stage/lib/debug/
        popd

        mkdir -p "build_release"
        pushd "build_release"
            cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" -DCMAKE_INSTALL_PREFIX=$(cygpath -m $stage)/release

            cmake --build . --config Release
            cmake --install . --config Release

            # conditionally run unit tests
            #if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            #    ctest -C Release
            #fi

            cp $stage/release/bin/*.dll $stage/lib/release/
            cp $stage/release/lib/*.lib $stage/lib/release/
            cp $stage/release/include/SDL2/*.h $stage/include/SDL2/
        popd
    ;;
    darwin*)
        export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

        for arch in x86_64 arm64 ; do
            ARCH_ARGS="-arch $arch"
            opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
            cc_opts="$(remove_cxxstd $opts)"
            ld_opts="$ARCH_ARGS"

            mkdir -p "build_$arch"
            pushd "build_$arch"
                CFLAGS="$cc_opts" \
                CXXFLAGS="$opts" \
                LDFLAGS="$ld_opts" \
                cmake .. -GNinja -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$cc_opts" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING="$arch" \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch"

                cmake --build . --config Release
                cmake --install . --config Release
            popd
        done


        # create universal libraries
        lipo -create -output ${stage}/lib/release/libSDL2.dylib ${stage}/lib/release/x86_64/libSDL2.dylib ${stage}/lib/release/arm64/libSDL2.dylib
        lipo -create -output ${stage}/lib/release/libSDL2_test.a ${stage}/lib/release/x86_64/libSDL2_test.a ${stage}/lib/release/arm64/libSDL2_test.a
        lipo -create -output ${stage}/lib/release/libSDL2main.a ${stage}/lib/release/x86_64/libSDL2main.a ${stage}/lib/release/arm64/libSDL2main.a

        pushd "${stage}/lib/release"
            install_name_tool -id "@rpath/libSDL2.dylib" "libSDL2.dylib"
            dsymutil libSDL2.dylib
            strip -x -S libSDL2.dylib
        popd
        ;;
    linux*)
        # Default target per autobuild build --address-size
        opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

        mkdir -p "$stage/include/SDL2"
        mkdir -p "$stage/lib/release"

        PREFIX_RELEASE="$stage/temp_release"
        mkdir -p $PREFIX_RELEASE

        mkdir -p "build_release"
        pushd "build_release"
            cmake .. -GNinja -DCMAKE_BUILD_TYPE="Release" \
                -DCMAKE_C_FLAGS="$(remove_cxxstd $opts)" \
                -DCMAKE_CXX_FLAGS="$opts" \
                -DCMAKE_INSTALL_PREFIX=$PREFIX_RELEASE

            cmake --build . --config Release
            cmake --install . --config Release
        popd

        cp -a $PREFIX_RELEASE/include/SDL2/*.* $stage/include/SDL2
        cp -a $PREFIX_RELEASE/lib/*.so* $stage/lib/release
        cp -a $PREFIX_RELEASE/lib/libSDL2main.a $stage/lib/release
    ;;

    *)
        exit -1
    ;;
esac
popd

# SDL3
pushd "$TOP/SDL3"

case "$AUTOBUILD_PLATFORM" in
    windows*)
        load_vsvars

        mkdir -p "$stage/include/SDL3"
        mkdir -p "$stage/lib/debug"
        mkdir -p "$stage/lib/release"

        mkdir -p "build_debug"
        pushd "build_debug"
            cmake .. -G "Ninja" -DCMAKE_INSTALL_PREFIX=$(cygpath -m $stage)/debug

            cmake --build . --config Debug
            cmake --install . --config Debug

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                ctest -C Debug
            fi

            cp $stage/debug/bin/*.dll $stage/lib/debug/
            cp $stage/debug/lib/*.lib $stage/lib/debug/
        popd

        mkdir -p "build_release"
        pushd "build_release"
            cmake .. -G "Ninja" -DCMAKE_INSTALL_PREFIX=$(cygpath -m $stage)/release

            cmake --build . --config Release
            cmake --install . --config Release

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                ctest -C Release
            fi

            cp $stage/release/bin/*.dll $stage/lib/release/
            cp $stage/release/lib/*.lib $stage/lib/release/
            cp $stage/release/include/SDL3/*.h $stage/include/SDL3/
        popd
    ;;
    darwin*)
        export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

        for arch in x86_64 arm64 ; do
            ARCH_ARGS="-arch $arch"
            opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
            cc_opts="$(remove_cxxstd $opts)"
            ld_opts="$ARCH_ARGS"

            mkdir -p "build_$arch"
            pushd "build_$arch"
                CFLAGS="$cc_opts" \
                CXXFLAGS="$opts" \
                LDFLAGS="$ld_opts" \
                cmake .. -GNinja -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$cc_opts" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING="$arch" \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch"

                cmake --build . --config Release
                cmake --install . --config Release
            popd
        done


        # create universal libraries
        lipo -create -output ${stage}/lib/release/libSDL3.0.dylib ${stage}/lib/release/x86_64/libSDL3.0.dylib ${stage}/lib/release/arm64/libSDL3.0.dylib
        lipo -create -output ${stage}/lib/release/libSDL3.dylib ${stage}/lib/release/x86_64/libSDL3.dylib ${stage}/lib/release/arm64/libSDL3.dylib
        lipo -create -output ${stage}/lib/release/libSDL3_test.a ${stage}/lib/release/x86_64/libSDL3_test.a ${stage}/lib/release/arm64/libSDL3_test.a

        pushd "${stage}/lib/release"
            install_name_tool -id "@rpath/libSDL3.dylib" "libSDL3.dylib"
            dsymutil libSDL3.dylib
            strip -x -S libSDL3.dylib
        popd
        ;;
    linux*)
        # Default target per autobuild build --address-size
        opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

        mkdir -p "$stage/include/SDL3"
        mkdir -p "$stage/lib/release"

        PREFIX_RELEASE="$stage/temp_release"
        mkdir -p $PREFIX_RELEASE

        mkdir -p "build_release"
        pushd "build_release"
            cmake .. -GNinja -DCMAKE_BUILD_TYPE="Release" \
                -DCMAKE_C_FLAGS="$(remove_cxxstd $opts)" \
                -DCMAKE_CXX_FLAGS="$opts" \
                -DCMAKE_INSTALL_PREFIX=$PREFIX_RELEASE

            cmake --build . --config Release
            cmake --install . --config Release
        popd

        cp -a $PREFIX_RELEASE/include/SDL3/*.* $stage/include/SDL3
        cp -a $PREFIX_RELEASE/lib/*.so* $stage/lib/release
        cp -a $PREFIX_RELEASE/lib/lib*.a $stage/lib/release
    ;;

    *)
        exit -1
    ;;
esac
popd

mkdir -p "$stage/LICENSES"
cp "$TOP/$SDL_SOURCE_DIR/LICENSE.txt" "$stage/LICENSES/SDL2.txt"
