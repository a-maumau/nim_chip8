import posix
import termios
import terminal

proc kbhit*(): cint =
    var tv: Timeval
    tv.tv_sec = Time(0)
    tv.tv_usec = 0

    var fds: TFdSet
    FD_ZERO(fds)
    FD_SET(STDIN_FILENO, fds)
    discard select(STDIN_FILENO+1, fds.addr, nil, nil, tv.addr)
    return FD_ISSET(STDIN_FILENO, fds)

proc readKeyInput*(): int8 =
    if kbhit() > 0:
        return ord(stdin.readChar()).int8
    else:
        return -1

proc parseKey*(k: int8): int8 =
    #[
        original key
        1 2 3 C
        4 5 6 D
        7 8 9 E
        A 0 B F

        is mapped to 

        1 2 3 4
        q w e r
        a s d f
        z x c v
    ]#

    case k:
    # key on keyboard: 1
    of 0x31:
        return 0

    # key on keyboard: 2
    of 0x32:
        return 1

    # key on keyboard: 3
    of 0x33:
        return 2

    # key on keyboard: 4
    of 0x34:
        return 3

    # key on keyboard: q
    of 0x71:
        return 4

    # key on keyboard: w
    of 0x77:
        return 5

    # key on keyboard: e
    of 0x65:
        return 6

    # key on keyboard: r
    of 0x72:
        return 7

    # key on keyboard: a
    of 0x61:
        return 8

    # key on keyboard: s
    of 0x73:
        return 9

    # key on keyboard: d
    of 0x64:
        return 10

    # key on keyboard: f
    of 0x66:
        return 11

    # key on keyboard: z
    of 0x7A:
        return 12

    # key on keyboard: x
    of 0x78:
        return 13

    # key on keyboard: c
    of 0x63:
        return 14

    # key on keyboard: v
    of 0x76:
        return 15

    else:
        return -1

