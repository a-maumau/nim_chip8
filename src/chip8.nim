import system
import termios
import strutils
import strformat
import std/streams
import std/exitprocs

import cpu
import mem
import display
import keyboard

const
    INTERPRETER_BEGIN_ADDR = 0x000
    INTERPRETER_END_ADDR = 0x1FF
    FONT_BEGIN_ADDR = 0x0000
    FONT_CHAR_BYTE_SIZE = 0x05
    FONTSET: array[80, uint8] = [
        uint8(0xF0), 0x90, 0x90, 0x90, 0xF0, # 0
        0x20, 0x60, 0x20, 0x20, 0x70, # 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, # 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, # 3
        0x90, 0x90, 0xF0, 0x10, 0x10, # 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, # 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, # 6
        0xF0, 0x10, 0x20, 0x40, 0x40, # 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, # 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, # 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, # A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, # B
        0xF0, 0x80, 0x80, 0x80, 0xF0, # C
        0xE0, 0x90, 0x90, 0x90, 0xE0, # D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, # E
        0xF0, 0x80, 0xF0, 0x80, 0x80  # F
    ]

type Chip8* = ref object of RootObj
    cpu*: Cpu
    mem*: Memory
    disp*: Display
    kb*: KeyBoard

    currInst*: Instruction

proc newChip8*(): Chip8 =
    new result

    result.cpu = newCpu()
    result.mem = newMemory(FONT_BEGIN_ADDR, FONT_CHAR_BYTE_SIZE, INTERPRETER_END_ADDR+1)
    result.disp = newDisplay()
    result.kb = newKeyBoard()

    result.currInst = Instruction()

    return result

proc initMemory(this: Chip8) =
    for n in 0..<FONTSET.len:
        this.mem.ram[n+FONT_BEGIN_ADDR] = FONTSET[n]

proc init*(this: Chip8) =
    this.cpu.init(this.mem, INTERPRETER_END_ADDR+1)
    this.mem.init()
    this.disp.setMargin(1, 1)
    #this.kb.init()

    this.initMemory()

proc load*(this: Chip8, file: File): int =
    let loaded_bytes = file.readBytes(this.mem.ram, INTERPRETER_END_ADDR+1, this.mem.ram.len - (INTERPRETER_END_ADDR+1))

    return loaded_bytes

proc tick*(this: Chip8): int8 =
    let inst_uint16 = this.cpu.fetchInstruction(this.mem)
    this.currInst = this.cpu.decodeInstruction(inst_uint16, this.mem, this.disp, this.kb)

    return this.cpu.execute(this.currInst, this.mem, this.disp, this.kb)
