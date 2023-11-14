const
    MEMORY_SIZE = 4096 # in byte

#[
    http://devernay.free.fr/hacks/chip8/C8TECH10.HTM
        Memory Map:
        +---------------+= 0xFFF (4095) End of Chip-8 RAM
        |               |
        |               |
        |               |
        |               |
        |               |
        | 0x200 to 0xFFF|
        |     Chip-8    |
        | Program / Data|
        |     Space     |
        |               |
        |               |
        |               |
        +- - - - - - - -+= 0x600 (1536) Start of ETI 660 Chip-8 programs
        |               |
        |               |
        |               |
        +---------------+= 0x200 (512) Start of most Chip-8 programs
        | 0x000 to 0x1FF|
        | Reserved for  |
        |  interpreter  |
        +---------------+= 0x000 (0) Start of Chip-8 RAM
]#

type Memory* = ref object of RootObj
    fontOffset*: uint16
    fontByteLen*: uint8
    startAddrOfProgramMemorySpace*: uint16
    ram*: array[MEMORY_SIZE, uint8]

proc newMemory*(fontOffset: uint16, fontByteLen: uint8, startAddrOfProgramMemorySpace: uint16): Memory =
    new result

    result.fontOffset = fontOffset
    result.fontByteLen = fontByteLen
    result.startAddrOfProgramMemorySpace = startAddrOfProgramMemorySpace

    return result

proc init*(this: Memory) =
    for n in 0..<this.ram.len:
        this.ram[n] = 0

proc getProgramMemoryStartAddr*(this: Memory): uint16 =
    return this.startAddrOfProgramMemorySpace

proc getFontOffset*(this: Memory): uint16 =
    return this.fontOffset

proc getFontByteLen*(this: Memory): uint16 =
    return this.fontByteLen

proc read*(this: Memory, src_addr: uint16): uint8 =
    # not checking it is in the memory array
    return this.ram[src_addr]

proc write*(this: Memory, dst_addr: uint16, val: uint8) =
    # not checking it is in the memory array
    this.ram[dst_addr] = val
