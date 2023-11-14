import random
import strutils
import strformat

import mem
import display
import keyboard

# set seed
randomize()

type Instruction* = ref object of RootObj
    instruction*: uint16

    # might div in 4bits is more nice to executing
    ms_byte*: uint8 # most siginificant byte
    ls_byte*: uint8 # least significant byte

    # instruction: uint16
    opcode*: uint8   # and 0xF000
    operand1*: uint8 # and 0x0F00
    operand2*: uint8 # and 0x00F0
    operand3*: uint8 # and 0x000F

    execution: proc(mem: Memory, disp: Display, kb: KeyBoard): int8
    instruction_info*: string
    instruction_asm*: string

proc `$`*(this: Instruction): string =
    return fmt"0x{toHex(this.ms_byte, 2)}{toHex(this.ls_byte, 2)}"

#[
    it seems chip-8's instructions are stored in 
    big-endian
]#
type Cpu* = ref object of RootObj
    # registers
    pc*: uint16           # program counter
    sp*: uint8            # stack pointer
    V*: array[16, uint8]  # V0 ~ VF register
    I*: uint16            # I register
    delay_timer*: uint8
    sound_timer*: uint8

    stack: array[16, uint16]

proc newCpu*(): Cpu =
    new result

    return result

proc init*(this: Cpu, mem: Memory, startPC: uint16) =
    this.pc = startPC
    this.sp = 0
    this.I = 0

proc `$`*(this: Cpu): string =
    var s = fmt"pc: 0x{toHex(this.pc, 4)}"
    s = s & "\n"
    s = s & "register:\n"
    s = s & "     0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F\n    "
    for i in 0..15:
        s = s & fmt"{toHex(this.V[i], 2)} "
    s = s & "\n"
    s = s & fmt"I: {toHex(this.I, 4)}"
    s = s & "\n"

    return s

proc declDelayTimer(this: Cpu) = 
    if this.delay_timer > 0:
        this.delay_timer -= 1

proc declSoundTimer(this: Cpu) = 
    if this.sound_timer > 0:
        this.sound_timer -= 1

proc inclPC*(this: Cpu, inc_val: uint16=1) =
    # the instruction is 2 bytes, so step 2 bytes for 1 increment
    this.pc += inc_val*2

proc fetchInstruction*(this: Cpu, mem: Memory): uint16 =
    return (uint16(mem.read(this.pc)) shl 8) + mem.read(this.pc+1)

proc decodeInstruction*(this: Cpu, inst: uint16, mem: Memory, disp: Display, kb: KeyBoard): Instruction =
    new result

    let
        ms_byte = uint8(inst shr 8)
        ls_byte = uint8(inst and 0x00FF)

        opcode = uint8(inst shr 12)
        operand1 = uint8(inst shr 8) and 0x0F
        operand2 = uint8(inst and 0x00F0) shr 4
        operand3 = uint8(inst and 0x000F)

    result.instruction = inst

    result.ms_byte = ms_byte
    result.ls_byte = ls_byte

    result.opcode = opcode
    result.operand1 = operand1
    result.operand2 = operand2
    result.operand3 = operand3

    case opcode:
    of 0x0:
        case ls_byte:

        # 00E0 - CLS
        # Clear the display
        of 0xE0:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                disp.clear();
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = "CLS"
            result.instruction_info = "clear disp."

        # 00EE - RET
        # Return from a subroutine
        of 0xEE:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.sp -= 1;
                this.pc = this.stack[this.sp];

                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("RET 0x{toHex(this.stack[this.sp-1], 4)}")
            result.instruction_info = fmt("return to addr 0x{toHex(this.stack[this.sp-1], 4)}")

        # 0nnn - SYS addr
        # Jump to a machine code routine at nnn.
        else:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.pc = (uint16(operand1) shl 8) + ls_byte;

                return 0;
            )
            result.instruction_asm = fmt("SYS 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")
            result.instruction_info = fmt("jump to 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")

    # 1nnn - JP addr
    # Jump to location nnn
    of 0x1:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            this.pc = (uint16(operand1) shl 8) + ls_byte;

            return 0;
        )
        result.instruction_asm = fmt("JUMP 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")
        result.instruction_info = fmt("jump to 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")

    # 2nnn - CALL addr
    # Call subroutine at nnn
    of 0x2:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            this.stack[this.sp] = this.pc;
            this.sp += 1;
            this.pc = (uint16(operand1) shl 8) + ls_byte;

            return 0;
        )
        result.instruction_asm = fmt("CALL 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")
        result.instruction_info = fmt("call 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")

    # 3xkk - SE Vx, byte
    # Skip next instruction if Vx = kk
    of 0x3:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            if this.V[operand1] == ls_byte:
                this.inclPC(2);
            else:
                this.inclPC(1);

            return 0;
        )
        result.instruction_asm = fmt("SE V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), 0x{toHex(ls_byte, 2)}")
        result.instruction_info = fmt("check V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}) == 0x{toHex(ls_byte, 2)}")

    # 4xkk - SNE Vx, byte
    # Skip next instruction if Vx != kk.
    of 0x4:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            if this.V[operand1] != ls_byte:
                this.inclPC(2);
            else:
                this.inclPC(1);

            return 0;
        )
        result.instruction_asm = fmt("SNE V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), 0x{toHex(ls_byte, 2)}")
        result.instruction_info = fmt("check V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}) != 0x{toHex(ls_byte, 2)}")

    # 5xy0 - SE Vx, Vy
    # Skip next instruction if Vx = Vy.
    of 0x5:
        case operand3:
        of 0x0:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                if this.V[operand1] == this.V[operand2]:
                    this.inclPC(2);
                else:
                    this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("SE V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")
            result.instruction_info = fmt("check V{toHex(operand1, 1)} (0x{toHex(this.V[operand1])}) == V{toHex(operand2, 1)} (0x{toHex(this.V[operand2])})")

        else:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = return -1
            result.instruction_info = "unknown instruction"

    # 6xkk - LD Vx, byte
    # Set Vx = kk
    of 0x6:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            this.V[operand1] = ls_byte;
            this.inclPC(1);

            return 0;
        )
        result.instruction_asm = fmt("LD V{toHex(operand1, 1)}, 0x{toHex(ls_byte, 2)}")
        result.instruction_info = fmt("store V{toHex(operand1, 1)} = 0x{toHex(ls_byte, 2)}")

    # 7xkk - ADD Vx, byte
    # Set Vx = Vx + kk
    of 0x7:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            this.V[operand1] = this.V[operand1] + ls_byte;
            this.inclPC(1);

            return 0;
        )
        result.instruction_asm = fmt("ADD V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), 0x{toHex(ls_byte, 2)}")
        result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1])}) + 0x{toHex(ls_byte, 2)}")

    of 0x8:
        case operand3:
        # 8xy0 - LD Vx, Vy
        # Set Vx = Vy
        of 0x0:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.V[operand1] = this.V[operand2];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand2, 1)} (0x{toHex(this.V[operand2])})")

        # 8xy1 - OR Vx, Vy
        # Set Vx = Vx OR Vy
        of 0x1:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.V[operand1] = this.V[operand1] or this.V[operand2];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1])}) OR V{toHex(operand2, 1)} (0x{toHex(this.V[operand2])})")

        # 8xy2 - AND Vx, Vy
        # Set Vx = Vx AND Vy
        of 0x2:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.V[operand1] = this.V[operand1] and this.V[operand2];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("AND V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1])}) AND V{toHex(operand2, 1)} (0x{toHex(this.V[operand2])})")

        # 8xy3 - XOR Vx, Vy
        # Set Vx = Vx XOR Vy
        of 0x3:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.V[operand1] = this.V[operand1] xor this.V[operand2];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("XOR V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1])}) XOR V{toHex(operand2, 1)} (0x{toHex(this.V[operand2])})")

        # 8xy4 - ADD Vx, Vy
        # Set Vx = Vx + Vy, set VF = carry
        of 0x4:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                if this.V[operand1] + this.V[operand2] > 255:
                    this.V[0x0F] = 1;
                else:
                    this.V[0x0F] = 0;
                this.V[operand1] = this.V[operand1] + this.V[operand2];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("ADD V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1])}) + V{toHex(operand2, 1)} (0x{toHex(this.V[operand2])}), VF_c: 0x{toHex(this.V[0x0F], 1)}")

        # 8xy5 - SUB Vx, Vy
        # Set Vx = Vx - Vy, set VF = NOT borrow
        of 0x5:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                if this.V[operand1] > this.V[operand2]:
                    this.V[0x0F] = 1;
                else:
                    this.V[0x0F] = 0;
                this.V[operand1] = this.V[operand1] - this.V[operand2];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("SUB V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1])}) - V{toHex(operand2, 1)} (0x{toHex(this.V[operand2])}), VF_b: 0x{toHex(this.V[0x0F], 1)}")

        # 8xy6 - SHR Vx {, Vy}
        # Set Vx = Vx SHR 1
        of 0x6:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                # check LSB is 1 or not
                this.V[0x0F] = this.V[operand1] and 0x01;
                this.V[operand1] = this.V[operand1] shr 1;
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("SHR V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), 0x01")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}) shr 1")

        # 8xy7 - SUBN Vx, Vy
        # Set Vx = Vy - Vx, set VF = NOT borrow
        of 0x7:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                if this.V[operand2] > this.V[operand1]:
                    this.V[0x0F] = 1;
                else:
                    this.V[0x0F] = 0;
                this.V[operand1] = this.V[operand2] - this.V[operand1];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("SUBN V{toHex(operand1, 1)} (0x{toHex(this.V[operand1])}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2])})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)}) - V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), VF_c: 0x{toHex(this.V[0x0F], 1)}")

        # 8xyE - SHL Vx {, Vy}
        # Set Vx = Vx SHL 1
        of 0xE:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                # check MSB is 1 or not
                this.V[0x0F] = this.V[operand1] shr 7;
                this.V[operand1] = this.V[operand1] shl 1;
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("SHL V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), 0x01")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}) shl 1")

        else:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = return -1
            result.instruction_info = "unknown instruction"

    of 0x9:
        # 9xy0 - SNE Vx, Vy
        # Skip next instruction if Vx != Vy
        case operand3:
        of 0x0:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                if this.V[operand1] != this.V[operand2]:
                    this.inclPC(2);
                else:
                    this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("SNE V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")
            result.instruction_info = fmt("check V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}) != V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)})")

        else:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = return -1
            result.instruction_info = "unknown instruction"

    # Annn - LD I, addr
    # Set I = nnn
    of 0xA:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            this.I = (uint16(operand1) shl 8) + ls_byte;
            this.inclPC(1);

            return 0;
        )
        result.instruction_asm = fmt("LD I, 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")
        result.instruction_info = fmt("store I = 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")

    # Bnnn - JP V0, addr
    # Jump to location nnn + V0
    of 0xB:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            this.pc = ((uint16(operand1) shl 8) + ls_byte) + this.V[0x00];

            return 0;
        )
        result.instruction_asm = fmt("JUMP V0 (0x{toHex(this.V[operand1], 2)}), 0x{toHex((uint16(operand1) shl 8) + ls_byte, 4)}")
        result.instruction_info = fmt("jump to 0x{toHex((uint16(operand1) shl 8) + ls_byte + this.V[0x00], 4)}")

    # Cxkk - RND Vx, byte
    # Set Vx = random byte AND kk
    of 0xC:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            this.V[operand1] = uint8(rand(255)) and ls_byte;
            this.inclPC(1);

            return 0;
        )
        result.instruction_asm = fmt("RAND V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), 0x{toHex(ls_byte, 4)}")
        result.instruction_info = fmt("random V{toHex(operand1, 1)})")

    # Dxyn - DRW Vx, Vy, nibble
    # Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision
    of 0xD:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
            var
                v: uint8 = 0
                tmp: uint8 = 0
                x_i: uint8 = 0

            for n in uint8(0)..<operand3:
                tmp = mem.read(this.I+n);

                x_i = 0;
                for bit_shift_i in countdown(7, 0):
                    v = (tmp shr bit_shift_i) and 0b00000001;

                    if disp.write(this.V[operand1]+x_i, this.V[operand2]+n, v):
                        this.V[0x0F] = 1;

                    x_i += 1;

            this.inclPC(1);

            return 0;
        )
        result.instruction_asm = fmt("DRAW V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), V{toHex(operand2, 1)} (0x{toHex(this.V[operand2], 2)}), 0x{toHex(operand3, 1)}")
        result.instruction_info = fmt("disp out pos: (V{toHex(operand1, 1)}, V{toHex(operand2, 1)}) = (0x{toHex(this.V[operand1], 1)}, 0x{toHex(this.V[operand2], 1)}), I = 0x{toHex(this.I, 4)}")

    of 0xE:
        case ls_byte:
        # Ex9E - SKP Vx
        # Skip next instruction if key with the value of Vx is pressed
        of 0x9E:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                if kb.isPressed(this.V[operand1]):
                    this.inclPC(2);
                else:
                    this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("SKP V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")
            result.instruction_info = fmt("key press check V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")

        # ExA1 - SKNP Vx
        # Skip next instruction if key with the value of Vx is not pressed
        of 0xA1:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                if kb.isPressed(this.V[operand1]):
                    this.inclPC(1);
                else:
                    this.inclPC(2);

                return 0;
            )
            result.instruction_asm = fmt("SKNP V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")
            result.instruction_info = fmt("key not press check V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")

        else:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = return -1
            result.instruction_info = "unknown instruction"

    of 0xF:
        case ls_byte:
        # Fx07 - LD Vx, DT
        # Set Vx = delay timer value
        of 0x07:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.V[operand1] = this.delay_timer;
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD V{toHex(operand1, 1)}, DT (0x{toHex(this.delay_timer, 2)})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} = DT (0x{toHex(this.delay_timer, 2)})")

        # Fx0A - LD Vx, K
        # Wait for a key press, store the value of the key in Vx
        of 0x0A:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.V[operand1] = kb.getKeyInput();
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("DRAW V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}), K")
            result.instruction_info = fmt("wait key V{toHex(operand1, 1)} = key")

        # Fx15 - LD DT, Vx
        # Set delay timer = Vx
        of 0x15:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.delay_timer = this.V[operand1];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD DT, V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")
            result.instruction_info = fmt("store DT = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")

        # Fx18 - LD ST, Vx
        # Set sound timer = Vx
        of 0x18:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.sound_timer = this.V[operand1];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD ST, V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")
            result.instruction_info = fmt("store ST = V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")

        # Fx1E - ADD I, Vx
        # Set I = I + Vx
        of 0x1E:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.I = this.I + this.V[operand1];
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("ADD I (0x{toHex(this.I, 4)}), V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")
            result.instruction_info = fmt("store I = I (0x{toHex(this.I, 4)}) + V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")

        # Fx29 - LD F, Vx
        # Set I = location of sprite for digit Vx
        of 0x29:
            let
                fontOffset = mem.getFontOffset()
                fontByteLen = mem.getFontByteLen()

            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                this.I = this.V[operand1]*fontByteLen + fontOffset;
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD F, V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")
            result.instruction_info = fmt("store I = addr of digit V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)}) [{this.V[operand1]*fontByteLen+fontOffset}]")

        # Fx33 - LD B, Vx
        # Store BCD representation of Vx in memory locations I, I+1, and I+2
        of 0x33:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                mem.write(this.I, this.V[operand1] div 100);
                mem.write(this.I+1, (this.V[operand1] div 10) mod 10);
                mem.write(this.I+2, this.V[operand1] mod 10);

                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD B, V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")
            result.instruction_info = fmt("store V{toHex(operand1, 1)} {this.V[operand1] div 100}, {(this.V[operand1] div 10) mod 10}, {this.V[operand1] mod 10} ({this.V[operand1]}) to I (0x{toHex(this.I, 4)}) ~ I+2")

        # Fx55 - LD [I], Vx
        # Store registers V0 through Vx in memory starting at location I
        of 0x55:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                for x in uint8(0)..operand1:
                    mem.write(this.I+x, this.V[x]);
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD [I], V{toHex(operand1, 1)} (0x{toHex(this.V[operand1], 2)})")
            result.instruction_info = fmt("store V0~VF to mem start from 0x{toHex(this.I, 4)}")

        # Fx65 - LD Vx, [I]
        # Read registers V0 through Vx from memory starting at location I
        of 0x65:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = (
                for x in uint8(0)..operand1:
                    this.V[x] = mem.read(this.I+x);
                this.inclPC(1);

                return 0;
            )
            result.instruction_asm = fmt("LD V{toHex(operand1, 1)}, I (0x{toHex(this.I, 4)})")
            result.instruction_info = fmt("load V0~VF from I (0x{toHex(this.I, 4)})")

        else:
            result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = return -1
            result.instruction_info = "unknown instruction"

    else:
        result.execution = proc(mem: Memory, disp: Display, kb: KeyBoard): int8 = return -1
        result.instruction_info = "unknown instruction"

proc execute*(this: Cpu, inst: Instruction, mem: Memory, disp: Display, kb: KeyBoard): int8 =
    # should set x, y like
    # let x = inst.ms_byte and 0x0F
    # but I will parse like HW

    let exec_result = inst.execution(mem, disp, kb)

    this.declDelayTimer()
    this.declSoundTimer()

    return exec_result
