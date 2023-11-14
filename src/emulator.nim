import os
import system
import terminal
import termios
import strutils
import strformat
import std/streams
import std/exitprocs

import cpu
import mem
import display
import keyboard
import chip8
import util

const
    # add each edge padding
    MIN_TERM_WIDTH = DISPLAY_WIDTH+2
    MIN_TERM_HEIGHT = DISPLAY_HEIGHT+2

    # this is actually depending on DISPLAY_WIDTH/HEIGHT...
    MIN_DEBUG_WIDTH = 128
    MIN_DEBUG_HEIGHT = 47

var
    fd: cint
    oldTerminalSettings: Termios
    newTerminalSettings: Termios

    exec_inst_list: seq[Instruction]
    log_num: int = 44
    stopFlag: bool = false

type Emulator* = ref object of RootObj
    chip8*: Chip8

    # 0: only chip9 disp.,
    # 1: show debug
    printMode: int

proc enableAltScreen*() =
    stdout.write "\x1b[?1049h"
    flushFile(stdout)

proc disableAltScreen*() =
    stdout.write "\x1b[?1049l"
    flushFile(stdout)

proc restoreTerminalSettings*() =
    discard fd.tcsetattr(TCSADRAIN, oldTerminalSettings.addr)
    disableAltScreen()

proc showCursor() = 
    stdout.write "\x1b[?25h"
    flushFile(stdout)

proc hideCursor() = 
    stdout.write "\x1b[?25l"
    flushFile(stdout)

proc setRawMode() =
    fd = getFileHandle(stdin)

    discard tcGetAttr(fd, oldTerminalSettings.addr)
    discard tcGetAttr(fd, newTerminalSettings.addr)

    #newTerminalSettings.c_iflag = newTerminalSettings.c_iflag and not Cflag(BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    #newTerminalSettings.c_oflag = newTerminalSettings.c_oflag and not Cflag(OPOST)
    #newTerminalSettings.c_cflag = (newTerminalSettings.c_cflag and not Cflag(CSIZE or PARENB)) or CS8
    #newTerminalSettings.c_lflag = newTerminalSettings.c_lflag and not Cflag(ECHO or ICANON or IEXTEN or ISIG)
    newTerminalSettings.c_lflag = newTerminalSettings.c_lflag and not Cflag(ECHO) and not Cflag(ICANON)
    #newTerminalSettings.c_cc[VMIN] = 1.cuchar
    #newTerminalSettings.c_cc[VTIME] = 0.cuchar

    discard tcSetAttr(fd, TCSAFLUSH, newTerminalSettings.addr)

proc setup() =
    hideCursor()
    enableAltScreen()
    setRawMode()

proc cleanup() =
    showCursor()
    disableAltScreen()
    restoreTerminalSettings()

proc print_chip8_window() =
    const
        y = 1
        x = 1

    stdout.write(fmt("\x1b[{y};{x}H+--- window -----------------------------------------------------+\x1b[{y+1};{x}H"))
    for i in 1..32:
        stdout.write(fmt("\x1b[{y+i};{x}H|\x1b[{y+i};{x+65}H|"))
    stdout.write(fmt("\x1b[{y+33};{x}H+----------------------------------------------------------------+"))
    flushFile(stdout)

proc print_debug_info_window() =
    const
        y = 36
        x = 1

    stdout.write(fmt("\x1b[{y};{x}H"))
    stdout.write(fmt("+--- debug info -------------------------------------------------+\x1b[{y+1};{x}H"))
    for i in 1..10:
        stdout.write(fmt("\x1b[{y+i};{x}H|\x1b[{y+i};{x+65}H|"))
    stdout.write(fmt("\x1b[{y+11};{x}H+----------------------------------------------------------------+"))
    flushFile(stdout)

proc print_debug_info(cpu: Cpu, kb: KeyBoard) =
    const
        y = 37
        x = 3

    stdout.write(fmt("\x1b[{y};{x}H"))
    stdout.write(fmt("pc: 0x{toHex(cpu.pc, 4)}\x1b[{y+1};{x}H"))
    stdout.write(fmt("sp: 0x{toHex(cpu.sp, 4)}\x1b[{y+2};{x}H"))
    #stdout.write(fmt("stack:\x1b[{y+3};{x}H"))
    #stdout.write(fmt("  addr |  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F\x1b[{y+4};{x}H"))
    #stdout.write(fmt("  val  | "))
    #for i in 0..15:
    #    stdout.write(fmt("{toHex(cpu.V[i], 2)} "))
    #stdout.write(fmt("\x1b[{y+5};{x}H"))
    stdout.write(fmt("V:\x1b[{y+3};{x}H"))
    stdout.write(fmt("  addr |  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F\x1b[{y+4};{x}H"))
    stdout.write(fmt("  val  | "))
    for i in 0..15:
        stdout.write(fmt("{toHex(cpu.V[i], 2)} "))
    stdout.write(fmt("\x1b[{y+5};{x}H"))
    stdout.write(fmt("I : 0x{toHex(cpu.I, 4)}\x1b[{y+6};{x}H"))
    stdout.write(fmt("DT: 0x{toHex(cpu.delay_timer, 4)}\x1b[{y+7};{x}H"))
    stdout.write(fmt("ST: 0x{toHex(cpu.sound_timer, 4)}\x1b[{y+8};{x}H"))
    stdout.write(fmt("  key  |  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F\x1b[{y+9};{x}H"))
    stdout.write(fmt("  val  | "))
    for i in 0..15:
        stdout.write(fmt("{toHex(kb.keys[i], 2)} "))
    stdout.write(fmt("\x1b[{y+10};{x}H"))

    flushFile(stdout)

proc print_exec_log_window() =
    const
        y = 1
        x = 69

    stdout.write(fmt("\x1b[{y};{x}H"))
    stdout.write(fmt("+ inst | info ---------------------------------------------+\x1b[{y+1};{x}H"))
    for i in 1..log_num+1:
        stdout.write(fmt("\x1b[{y+i};{x}H|\x1b[{y+i};{x+59}H|"))
    stdout.write(fmt("\x1b[{y+log_num+2};{x}H+----------------------------------------------------------+"))
    flushFile(stdout)

proc print_exec_log(log: seq[Instruction]) =
    const
        y = 1
        x = 71

    for i in 0..<log.len:
        stdout.write(fmt("\x1b[{y+i+1};{x}H                                                         "))
        stdout.write(fmt("\x1b[{y+i+1};{x}H{toHex(log[i].instruction, 4)} | {log[i].instruction_info}"))
    flushFile(stdout)

proc print_exec_asm_log(log: seq[Instruction]) =
    const
        y = 1
        x = 71

    for i in 0..<log.len:
        stdout.write(fmt("\x1b[{y+i+1};{x}H                                                         "))
        stdout.write(fmt("\x1b[{y+i+1};{x}H{toHex(log[i].instruction, 4)} | {log[i].instruction_asm}"))
    flushFile(stdout)

proc newEmulator*(): Emulator =
    new result

    if terminalWidth() < MIN_TERM_WIDTH or terminalHeight() < MIN_TERM_HEIGHT:
        raiseAssert(fmt"your terminal size must be at least ({MIN_TERM_WIDTH}, {MIN_TERM_HEIGHT})")

    result.printMode = 0

    if MIN_DEBUG_WIDTH <= terminalWidth() and MIN_DEBUG_HEIGHT <= terminalHeight():
        result.printMode = 1

    result.chip8 = newChip8()

    return result

proc init*(this: Emulator) =
    this.chip8.init()

    setup()

    addExitProc(proc() = cleanup())

    print_chip8_window()
    
    if this.printMode == 1:
        print_debug_info_window()
        print_debug_info(this.chip8.cpu, this.chip8.kb)
        print_exec_log_window()


proc loadROM*(this: Emulator, file_path: string) =
    var file = open(file_path, fmRead)
    
    let loaded_bytes = this.chip8.load(file)

    if loaded_bytes < file.getFileSize():
        #echo "could not read all data from ROM."
        discard 1
    else:
        #echo "ROM was successfully loaded."
        discard 1

proc run*(this: Emulator, tickRate: int=20) = 
    var
        k: int8
        kp: int8 = 0
        prevKp: int8 = 0
        sleepTime: int

        # without some specific library,
        # we can not get the actual key state which is pressed or not in real time.
        # so we will emulate by remaining the keyinput in some ticks
        #
        # if there is no input,
        # the key input will live at least this tick count
        # I consider around 300ms is enough?
        # it depends on the programs though
        keyInputReaminingTickCount = int(0.300/(1/tickRate))        
        keyTickCount: int = 0

    if tickRate > 0:
        sleepTime = 1000 div tickRate
    else:
        sleepTime = 0

    while true:
        k = readKeyInput()

        # 0x20 is space
        if k == 0x20:
            stopFlag = not stopFlag
        # 0x1b is escape
        elif k == 0x1b:
            cleanup()
            quit(0)
        else:
            kp = parseKey(k)
            if kp >= 0:
                this.chip8.kb.keys[prevKp] = 0
                this.chip8.kb.keys[kp] = 1

                keyTickCount = 0
                prevKp = kp

        if stopFlag:
            # 0x0A is enter
            # if emulator is stopping,
            # pressing enter will execute one instruction
            if k == 0x0A:
                if this.chip8.tick() == -1:
                    cleanup()
                    echo "error occurred"
                    echo fmt("instruction: {toHex(this.chip8.currInst.instruction, 4)}")
                    echo fmt("info: {this.chip8.currInst.instruction_info}")
                    quit(-1)

                if exec_inst_list.len > log_num:
                    exec_inst_list.delete(0)

                exec_inst_list.add(this.chip8.currInst)

                if this.printMode == 1:
                    print_debug_info(this.chip8.cpu, this.chip8.kb)
                    #print_exec_log(exec_inst_list)
                    print_exec_asm_log(exec_inst_list)

                keyTickCount += 1
        else:
            if this.chip8.tick() == -1:
                restoreTerminalSettings()
                echo "error occurred"
                echo fmt("instruction: {toHex(this.chip8.currInst.instruction, 4)}")
                echo fmt("info: {this.chip8.currInst.instruction_info}")
                quit(-1)

            if exec_inst_list.len > log_num:
                exec_inst_list.delete(0)

            exec_inst_list.add(this.chip8.currInst)

            if this.printMode == 1:
                print_debug_info(this.chip8.cpu, this.chip8.kb)
                #print_exec_log(exec_inst_list)
                print_exec_asm_log(exec_inst_list)

            keyTickCount += 1

        if keyTickCount > keyInputReaminingTickCount:
            this.chip8.kb.keys[prevKp] = 0
            keyTickCount = 0

        sleep(sleepTime)
