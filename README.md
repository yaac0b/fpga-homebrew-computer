# Hack Computer on the Tang Nano 20K

A complete 16-bit computer built from scratch in Verilog on the **Sipeed Tang Nano 20K** FPGA
(Gowin GW2AR-18C, 27 MHz). It is based on the **Hack** architecture from the *Nand2Tetris* course,
and extended into something you can actually play with:

- load new programs **over USB (UART)** without re-synthesising the FPGA
- **HDMI graphics** (160×120, 256 colours, shown on a 720×480 screen)
- a **16-bit ADC** (ADS1115) so a potentiometer can control things
- **16 external LEDs**
- **SDRAM** as data memory
- **HackL**, a small C-like language with its own compiler and IDE, so you don't have to write assembly

Demo programs included: a live voltage meter, a scrolling voltage graph, ping-pong, and brick breaker
(all controlled with a potentiometer).

---

## How it fits together

```
 PC (HackL IDE) ──USB/UART──►  uart_rx ─► uart_loader ─► program_ram (32K × 16-bit)
                                                              │
                                                              ▼
                                  ┌───────────────────────  Hack CPU  ──────────────────────┐
                                  │            (A, D, PC registers + ALU)                    │
                                  └──────────────────────────┬───────────────────────────────┘
                                                             │ address / data
                                                             ▼
                                                      memory (address decoder)
                        ┌──────────────┬──────────────┬──────┴───────┬──────────────┐
                        ▼              ▼              ▼              ▼              ▼
                  SDRAM (data RAM)   GPU regs    ADS1115 (I2C)   16 LEDs        keyboard
                                        │
                                        ▼
                                  renderer ─► framebuffer (BRAM) ─► TMDS ─► HDMI
```

The CPU never waits for hardware by itself: the memory block tells it when it is **ready**.
While the SDRAM is busy, a refresh is due, or the GPU is drawing, the CPU simply pauses
(it is "stalled") and carries on when everything is ready again.

---

## What is in the box

| Part | What it does |
|---|---|
| **Hack CPU** (`cpu.v`, `alu.v`) | 16-bit Hack processor: A register, D register, program counter, ALU. |
| **Program RAM** (`program_ram.v`) | 32K words of block RAM that holds your program. Filled over UART. |
| **UART loader** (`uart_rx.v`, `uart_loader.v`) | Receives a program from the PC at 115200 baud, writes it into program RAM, then resets and starts the CPU. |
| **Memory system** (`memory.v`) | Address decoding, SDRAM access, and the "ready" signal that stalls the CPU when needed. |
| **SDRAM controller** (`sdram.v`) | Drives the on-board SDRAM, used as the data RAM. |
| **GPU** (`gpu_top.v`, `gpu_regs.v`, `gpu_renderer.v`, `framebuffer_bram.v`) | Draws pixels, clears the screen and fills rectangles into a framebuffer. |
| **HDMI output** (`tmds_encoder.v`, `tmds_serializer.v`, `Gowin_rPLL.v`) | Turns the framebuffer into a 720×480 HDMI signal. |
| **ADC interface** (`ads1115_i2c_master.v`) | I2C master that reads the ADS1115. The CPU just writes and reads a few memory addresses. |
| **Top level** (`top.v`) | Wires everything to the pins. Pin assignments are in `tangnano20k.cst`. |

---

## Memory map

The CPU talks to everything by reading and writing memory addresses. In HackL you can use the
built-in names (`P1`, `adc()`, `fill()`...) instead of these numbers.

| Address | Name | Read | Write |
|---|---|---|---|
| `0x0000`–`0x3FFF` | Data RAM (SDRAM) | stored value | store value |
| `0x6000` | GPU control | – | bit 0 = enable GPU |
| `0x6001` | GPU status | bit 0 = GPU busy | – |
| `0x6002` | GPU command | – | `1` pixel, `2` clear, `3` fill rectangle |
| `0x6003` / `0x6004` | GPU X / Y | – | start position |
| `0x6005` / `0x6006` | GPU X2 / Y2 | – | end position (for rectangles) |
| `0x6007` | GPU colour | – | colour (RGB332) |
| `0x6008`–`0x600A` | GPU size / param0 / param1 | – | reserved (stored, not used by commands 1–3) |
| `0x6010` | ADC channel | selected channel | channel 0–3 |
| `0x6011` | ADC control | bit 0 = busy, bit 1 = result ready | write `1` to start a reading |
| `0x6012` | ADC data | 16-bit result (signed) | – |
| `0x6014` | External LEDs (`P1`) | LED value | 16-bit LED value |
| `0x7FFF` | Keyboard | key code (currently always 0) | – |

---

## Graphics (GPU)

- **Screen:** 720×480 over HDMI (27 MHz pixel clock, about 60 Hz).
- **Drawing area:** 160×120 pixels, each pixel is shown 3×3 on screen, centred with a black border.
- **Colours:** 1 byte per pixel, **RGB332** (`RRRGGGBB`): 8 red levels, 8 green levels, 4 blue levels.
- **Commands:** draw a pixel, clear the screen, fill a rectangle. To draw, write X, Y (and X2, Y2), colour,
  and finally the command number. If the GPU is still busy, the CPU waits automatically.

---

## ADC (ADS1115)

- 16-bit, 4 single-ended inputs (**A0–A3**), read over I2C at 100 kHz, address `0x48` (ADDR pin to GND).
- Input range ±4.096 V; reading a 0–3.3 V signal gives a raw value of 0 to about 26 400.
- **Volts = raw ÷ 8000** (for example raw `26559` ≈ **3.32 V**). In millivolts: `raw / 8`.
- One reading takes roughly 11 ms (the chip converts at 128 samples/second).
- A potentiometer works great: outer legs to **3.3 V** and **GND**, middle leg to **A0**.

---

## HackL: the high-level language

You can write programs in a small C-like language instead of assembly.

```c
// Show the pot position as a green bar, and the raw value on the LEDs
var v;                                        // declare variables first
gpu_on();
clear();
while (1) {
    v = adc(0);
    P1 = v;                                   // 16 LEDs
    fill(10, 50, 10 + v / 200, 60, GREEN);    // bar on the HDMI screen
    fill(10 + v / 200 + 1, 50, 150, 60, BLACK);
    delay(50);                                // 50 ms
}
```

**Language features:** `var`, `const`, `if / else`, `while`, `break`, `continue`, `halt`,
`+ - * / %`, `& | ~ !`, `&& ||`, comparisons, `++`, `--`, `+=`, `-=`.

**Built-ins:**

| Name | What it does |
|---|---|
| `P1 = value;` | write the 16 external LEDs |
| `adc(ch)` | read ADC channel 0–3 |
| `delay(ms)` | wait for some milliseconds |
| `gpu_on()`, `clear()` | enable the GPU, clear the screen |
| `pixel(x, y, colour)` | draw one pixel |
| `fill(x, y, x2, y2, colour)` | draw a filled rectangle |
| `poke(addr, v)`, `peek(addr)` | read/write any memory address |
| `BLACK WHITE RED GREEN BLUE YELLOW CYAN MAGENTA ORANGE GRAY` | colour names |

**Examples** (`hackl/examples/`): LED blinker, 1-second counter, ADC bar graph, voltage readout,
scrolling voltage graph with axes, ping-pong, brick breaker.

---

## Hardware you need

- Sipeed **Tang Nano 20K**
- **HDMI** monitor and cable
- **ADS1115** breakout board and a **potentiometer** (10 kΩ is fine)
- **4.7 kΩ pull-up resistors** from SCL and SDA to **3.3 V** (many breakout boards already have them)
- 16 LEDs with resistors (optional, but fun)
- USB-C cable (power + programming + UART)

### Pin connections

| Signal | FPGA pin |
|---|---|
| ADS1115 SCL | 41 |
| ADS1115 SDA | 42 |
| ADS1115 VDD / GND | 3.3 V / GND |
| External LEDs 0–15 | 71, 72, 73, 74, 75, 86, 25, 26, 27, 28, 29, 30, 31, 77, 76, 85 |
| HDMI | on-board connector |
| UART | on-board USB (BL616) |

> **Voltage warning:** the FPGA pins are 3.3 V. Never pull SCL/SDA up to 5 V.

On-board LEDs show the CPU state for debugging: LED0–2 = low bits of the program counter,
LED3 = A register bit 0, LED4 = D register bit 0 (these LEDs are active-low).

---

## Getting started

1. **Build the FPGA design.** Open Gowin EDA, create a project for the GW2AR-18C, add all `.v` files and
   `tangnano20k.cst`, set `top` as the top module, then synthesise and place & route.
2. **Program the board** with the Gowin Programmer (or `openFPGALoader`).
3. **Install Python 3** and `pyserial` (`pip install pyserial`) on your PC.
4. **Start the IDE:** `python3 hackl/hack_ide.py`, choose the serial port (115200 baud).
5. Pick **HackL** (or Assembly), write or open a program, and press **Run**.
   The IDE compiles it, assembles it, sends it over UART and starts the CPU.

No re-synthesis is needed when you change your program, only when you change the Verilog.

### UART loader protocol (if you want to write your own tool)

Serial settings: **115200, 8 data bits, no parity, 1 stop bit.**

| Byte(s) | Meaning |
|---|---|
| `0x4C` (`L`) | start a load |
| 2 bytes | number of words, little-endian |
| 2 bytes per word | program words, low byte first |
| `0x52` (`R`) | reset the CPU and run |
| `0x53` (`S`) | stop the CPU |

After the last word, the loader automatically resets and starts the CPU.

---

## Suggested repository layout

```
rtl/            Verilog sources (cpu.v, alu.v, memory.v, gpu_*.v, ...)
constraints/    tangnano20k.cst
hackl/          hl.py (compiler), hack_ide.py (IDE), HackL_Reference.md, examples/
docs/           notes, photos, wiring diagram
README.md
```

---

## Known issues and notes

- **ADC occasionally returns an old value.** In the original `ads1115_i2c_master.v`, the state machine can
  move on from the I2C START condition before SDA has actually fallen, so some configuration writes are
  missed (roughly 1 in 4). A patched copy is in `hackl/ads1115_i2c_master.v`; use that version when you
  synthesise.
- **ADC + GPU together:** some programs that read the ADC and draw heavily at the same time have been seen
  to stall. GPU-only and ADC-only programs run fine. This is still being investigated.
- `video_timing.v` is a standalone copy of the timing generator; the one used by the design is inside `gpu_top.v`.
- `gpu_top.v` mentions GPU commands 4–7 in a comment, but only commands 1–3 are implemented.
- The ADS1115 master does not check for NACKs and has no timeout. If the chip is missing, an `adc()` call
  waits forever.

---

## Credits

- Based on the **Hack computer** from *The Elements of Computing Systems* (Nand2Tetris) by Noam Nisan and Shimon Schocken.
- Built for the Sipeed Tang Nano 20K with Gowin EDA.

## License

Add your preferred licence here (for example MIT).
