import docopt
import strutils

import emulator

const
    VERSION = "0.1.0"

let doc = """
chip8

Usage:
    chip8 [--tick_rate=<num>] <rom>
    chip8 (-h | --help)

Options:
    <rom>              Path to a chip8 ROM 
    --tick_rate=<num>  Number of tick rate in emulator [default: 60]
    -h --help          Show this screen.
    --version          Show version.
"""

if isMainModule:
    let args = docopt(doc, version=VERSION)
    
    var emu = newEmulator()

    emu.init()
    emu.loadROM($args["<rom>"])
    emu.run(tickRate=parseInt($args.getOrDefault("--tick_rate")))
