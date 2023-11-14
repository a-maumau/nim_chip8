import system
import termios
import strformat
import std/streams
import std/exitprocs

const
    DISPLAY_WIDTH* = 64
    DISPLAY_HEIGHT* = 32

type Display* = ref object of RootObj
    width: uint8
    height: uint8
    vram: array[DISPLAY_HEIGHT, array[DISPLAY_WIDTH, uint8]]

    displayStartPosX: uint
    displayStartPosY: uint

proc newDisplay*(): Display =
    new result

    result.width = DISPLAY_WIDTH
    result.height = DISPLAY_HEIGHT
    result.displayStartPosX = 0
    result.displayStartPosY = 0

    return result

proc setMargin*(this: Display, margin_w, margin_h: uint16) =
    this.displayStartPosX = margin_w
    this.displayStartPosY = margin_h

proc print*(this: Display, x, y: uint8, chr: char) =
    stdout.write fmt("\x1b[{y+1+this.displayStartPosY};{x+1+this.displayStartPosX}H{chr}")
    flushFile(stdout)

proc clear*(this: Display) =
    for y in uint8(0)..<this.height:
        for x in uint8(0)..<this.width:
            this.vram[y][x] = 0
            this.print(x, y, ' ')

proc write*(this: Display, x, y, val: uint8): bool {.discardable.} =
    # return pixel erasing has occurred or not
    var x_add, y_add: uint8

    # for warping
    y_add = y mod this.height
    x_add = x mod this.width

    if this.vram[y_add][x_add] == 1:
        this.vram[y_add][x_add] = this.vram[y_add][x_add] xor val

        if this.vram[y_add][x_add] == 0:
            this.print(x_add, y_add, ' ')
            return true
    else:
        this.vram[y_add][x_add] = this.vram[y_add][x_add] xor val
        if this.vram[y_add][x_add] == 1:
            this.print(x_add, y_add, '#')

    return false
