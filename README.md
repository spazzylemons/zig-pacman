# zig-pacman

A PAC-MAN emulator written in Zig to showcase the
[zig80](https://github.com/spazzylemons/zig80) library. Requires
[Zig](https://ziglang.org/), [zigmod](https://github.com/nektro/zigmod), and
[SDL2](https://www.libsdl.org/).

## Usage

    usage: pacman [-htda] [-c <ratio>] [-l <num>] [-b <points>] <rom directory>
            -h, --help              display help and exit
            -t, --cocktail          cocktail mode - for tabletop play
            -c, --coinage <ratio>   coins to credits ratio - free, 1:1, 1:2, or 2:1
                                    default: free
            -l, --lives <num>       number of lives - 1, 2, 3, or 5
                                    default: 3
            -b, --bonus <points>    extra life bonus - 10k, 15k, 20k, or none
                                    default: 10k
            -d, --hard              hard mode
            -a, --alt-ghost-names   alternate ghost names
    controls:
            arrow keys  move
            wasd        move (player two, cocktail mode)
            c           insert coin
            1           start one player game
            2           start two player game
            p           pause game
            f1          toggle rack test
            f2          toggle service mode

## Acknowledgements

- <https://github.com/kuba--/zip/> - zip extraction library used
- <https://umlautllama.com/projects/pacdocs/> contains plenty of useful
information necessary to create this emulator.
