#!/bin/bash

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

TOP="$(dirname "$0")"

SDL_SOURCE_DIR="SDL"
SDL_VERSION=$(sed -n -e 's/^Version: //p' "$TOP/$SDL_SOURCE_DIR/SDL.spec")

if [ -z "$AUTOBUILD" ] ; then
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

stage="$(pwd)"
ZLIB_INCLUDE="${stage}"/packages/include/zlib
PNG_INCLUDE="${stage}"/packages/include/libpng16

[ -f "$ZLIB_INCLUDE"/zlib.h ] || fail "You haven't installed the zlib package yet."
[ -f "$PNG_INCLUDE"/png.h ] || fail "You haven't installed the libpng package yet."

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/{debug,release}/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}

case "$AUTOBUILD_PLATFORM" in
    
    linux*)
        # Linux build environment at Linden comes pre-polluted with stuff that can
        # seriously damage 3rd-party builds.  Environmental garbage you can expect
        # includes:
        #
        #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
        #    DISTCC_LOCATION            top            branch      CC
        #    DISTCC_HOSTS               build_name     suffix      CXX
        #    LSDISTCC_ARGS              repo           prefix      CFLAGS
        #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
        #
        # So, clear out bits that shouldn't affect our configure-directed build
        # but which do nonetheless.
        #
        unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS
        
        # Default target per autobuild build --address-size
        opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
        DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
        RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -DPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2"
        DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
        RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
        DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
        RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
        DEBUG_CPPFLAGS="-DPIC"
        RELEASE_CPPFLAGS="-DPIC"

        JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
        
        # Handle any deliberate platform targeting
        if [ -z "${TARGET_CPPFLAGS:-}" ]; then
            # Remove sysroot contamination from build environment
            unset CPPFLAGS
        else
            # Incorporate special pre-processing flags
            export CPPFLAGS="$TARGET_CPPFLAGS"
        fi
        
        # Force static linkage to libz by moving .sos out of the way
        # (Libz is only packaging statics right now but keep this working.)
        trap restore_sos EXIT
        for solib in "${stage}"/packages/lib/{debug,release}/libz.so*; do
            if [ -f "$solib" ]; then
                mv -f "$solib" "$solib".disable
            fi
        done
        
        pushd "$TOP/$SDL_SOURCE_DIR"
        # do debug build of sdl
        PATH="$stage"/bin/:"$PATH" \
        CFLAGS="-I"$ZLIB_INCLUDE" -I"$PNG_INCLUDE" $DEBUG_CFLAGS" \
        CXXFLAGS="-I"$ZLIB_INCLUDE" -I"$PNG_INCLUDE" $DEBUG_CXXFLAGS" \
        CPPFLAGS="-I"$ZLIB_INCLUDE" -I"$PNG_INCLUDE" $DEBUG_CPPFLAGS" \
        LDFLAGS="-L"$stage/packages/lib/debug" -L"$stage/lib/debug" $opts" \
        ./configure --with-pic \
        --prefix="$stage" --libdir="$stage/lib/debug" --includedir="$stage/include"
        make -j$JOBS
        make install
        
        # clean the build tree
        make distclean
        
        # do release build of sdl
        PATH="$stage"/bin/:"$PATH" \
        CFLAGS="-I"$ZLIB_INCLUDE" -I"$PNG_INCLUDE" $RELEASE_CFLAGS" \
        CXXFLAGS="-I"$ZLIB_INCLUDE" -I"$PNG_INCLUDE" $RELEASE_CXXFLAGS" \
        CPPFLAGS="-I"$ZLIB_INCLUDE" -I"$PNG_INCLUDE" $RELEASE_CPPFLAGS" \
        LDFLAGS="-L"$stage/packages/lib/release" -L"$stage/lib/release" $opts" \
        ./configure --with-pic \
        --prefix="$stage" --libdir="$stage/lib/release" --includedir="$stage/include"
        make -j$JOBS
        make install
        
        # clean the build tree
        make distclean
        popd
    ;;
    
    *)
        exit -1
    ;;
esac


mkdir -p "$stage/LICENSES"
cp "$TOP/$SDL_SOURCE_DIR/COPYING" "$stage/LICENSES/SDL.txt"
mkdir -p "$stage"/docs/SDL/
cp -a "$TOP"/README.Linden "$stage"/docs/SDL/
echo "$SDL_VERSION" > "$stage/VERSION.txt"
