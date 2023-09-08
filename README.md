# 3p-SDL

This is a fork of [Alchemy's](https://www.alchemyviewer.org/) [3p-SDL2](https://git.alchemyviewer.org/alchemy/thirdparty/3p-sdl2)
repository configured to build and package using [autobuild](https://wiki.secondlife.com/wiki/Autobuild).

[Simple DirectMedia Layer](SDL/docs/README.md) is a cross-platform development library designed
to provide low level access to audio, keyboard, mouse, joystick, and graphics
hardware via OpenGL and Direct3D.

# How to build:

* Install [autobuild](https://wiki.secondlife.com/wiki/Autobuild) utility.
* Invoke autobuild at the command line:
<pre>
        autobuild build
        autobuild package
</pre>

That will produce a bundled asset of SDL2 libs and header files called something like: `SDL2-2.24.1-linux-012345678.tar.bz2`
