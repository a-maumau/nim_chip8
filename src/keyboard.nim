import termios
import terminal

import util

const
    KEY_NUMS = 16    

type KeyBoard* = ref object of RootObj
    key_num: uint8
    keys*: array[KEY_NUMS, uint8]

proc newKeyBoard*(): KeyBoard =
    new result

    result.key_num = KEY_NUMS

    return result

proc getKeyInput*(this: KeyBoard): uint8 =
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

    var k: int8

    while true:
        k = ord(stdin.readChar()).int8
        k = parseKey(k)

        if k < 16:
            break

    return k.uint8

proc checkKeyInput*(this: KeyBoard) =
    if kbhit() > 0:
        let k = ord(stdin.readChar()).uint8 - 0x30
        if k < 0x10:
            this.keys[k] = 1
        else:
            discard

proc isPressed*(this: KeyBoard, key_id: uint8): bool =
    if this.keys[key_id] == 1:
        return true

    return false
