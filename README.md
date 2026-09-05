# FPGA GPU Core – Tang Nano 20K

A custom GPU/video rendering subsystem implemented in **Verilog HDL** for the **Sipeed Tang Nano 20K FPGA**.

This repository contains the GPU-side hardware being developed as part of a larger FPGA computer/system project. The GPU is designed to interface with a CPU through a **memory-mapped internal bus** and generate video output through an HDMI-compatible TMDS interface.

> **Development Status:** The GPU/HDMI subsystem is currently being developed independently. HDMI output and framebuffer functionality have been tested on the Tang Nano 20K. CPU bus integration is the next development stage.

---

## Project Overview

The goal of this project is to build a simple custom GPU from the ground up using FPGA logic.

The GPU is responsible for:

- Maintaining a framebuffer
- Writing pixels to the framebuffer
- Clearing the framebuffer
- Receiving drawing commands from a CPU
- Generating video timing
- Scaling the framebuffer for display
- Converting pixel data to RGB
- Generating TMDS signals for HDMI output

The CPU does **not** directly generate HDMI signals. Instead, the CPU communicates with the GPU using memory-mapped registers.

### Overall Architecture

```text
                    ┌─────────────────────┐
                    │     Custom CPU      │
                    │   (separate block)  │
                    └──────────┬──────────┘
                               │
                         CPU Memory Bus
                               │
                               ▼
                    ┌─────────────────────┐
                    │      GPU Core       │
                    │                     │
                    │ ┌─────────────────┐ │
                    │ │   GPU Registers │ │
                    │ └────────┬────────┘ │
                    │          │          │
                    │ ┌────────▼────────┐ │
                    │ │ GPU Renderer    │ │
                    │ └────────┬────────┘ │
                    │          │          │
                    │ ┌────────▼────────┐ │
                    │ │   Framebuffer   │ │
                    │ │      BRAM       │ │
                    │ └────────┬────────┘ │
                    │          │          │
                    │ ┌────────▼────────┐ │
                    │ │ Video Timing    │ │
                    │ └────────┬────────┘ │
                    │          │          │
                    │ ┌────────▼────────┐ │
                    │ │ TMDS Encoder &  │ │
                    │ │   Serializer    │ │
                    │ └────────┬────────┘ │
                    └──────────┼──────────┘
                               │
                               ▼
                          HDMI Output
```

---

# Hardware Platform

## FPGA Board

**Sipeed Tang Nano 20K**

FPGA:

```text
GW2AR-LV18QN88C8/I7
```

Main input clock:

```text
27 MHz
```

The design uses the FPGA's internal PLL and clock divider to generate the clocks required for video generation and TMDS serialization.

---

# GPU Architecture

The GPU currently uses a small framebuffer stored in FPGA block RAM.

## Framebuffer

Current framebuffer configuration:

```text
Resolution: 160 × 120 pixels
Color:      RGB332
Pixel size: 8 bits
Memory:     19,200 bytes
```

### RGB332 Format

Each pixel is represented using 8 bits:

```text
[7:5]  Red    3 bits
[4:2]  Green  3 bits
[1:0]  Blue   2 bits
```

This provides:

```text
8 × 8 × 4 = 256 colors
```

The reduced framebuffer resolution keeps the memory requirements small enough for FPGA block RAM.

---

# Display Output

The GPU generates a:

```text
720 × 480
```

video signal.

The framebuffer is scaled by:

```text
3×
```

Therefore:

```text
160 × 120
      ↓ 3×
480 × 360
```

The 480×360 image is positioned approximately in the center of the 720×480 display.

---

# Video Pipeline

```text
Framebuffer BRAM
      │
      ▼
Video Address Generation
      │
      ▼
RGB332 Pixel
      │
      ▼
RGB888 Conversion
      │
      ▼
TMDS Encoding
      │
      ▼
10-bit TMDS Data
      │
      ▼
TMDS Serialization
      │
      ▼
HDMI
```

---

# GPU Registers

The GPU is designed to be controlled through memory-mapped registers.

Current proposed address map:

| Address | Register | Description |
|--------:|----------|-------------|
| `0x80000000` | GPU_CONTROL | GPU enable |
| `0x80000004` | GPU_X | X coordinate |
| `0x80000008` | GPU_Y | Y coordinate |
| `0x8000000C` | GPU_COLOR | RGB332 pixel color |
| `0x80000010` | GPU_COMMAND | GPU command |
| `0x80000014` | GPU_STATUS | GPU status |
| `0x80001000` | FRAMEBUFFER | Framebuffer memory |

## GPU_CONTROL

```text
Address:
0x80000000
```

```text
bit 0 = GPU enable
```

Example:

```text
0x00000001 → Enable GPU
0x00000000 → Disable GPU
```

## GPU_X

```text
Address:
0x80000004
```

Specifies the X coordinate.

Valid range:

```text
0 – 159
```

## GPU_Y

```text
Address:
0x80000008
```

Specifies the Y coordinate.

Valid range:

```text
0 – 119
```

## GPU_COLOR

```text
Address:
0x8000000C
```

Contains the RGB332 color.

Only the lower 8 bits are currently used.

## GPU_COMMAND

```text
Address:
0x80000010
```

Current commands:

```text
1 → Draw pixel
2 → Clear framebuffer
```

### Draw Pixel

The CPU writes:

```text
GPU_X
GPU_Y
GPU_COLOR
GPU_COMMAND = 1
```

The GPU then writes the selected pixel into the framebuffer.

Example:

```text
X     = 50
Y     = 30
COLOR = 0xE0
CMD   = 1
```

Result:

```text
Framebuffer[50,30] = 0xE0
```

### Clear Screen

Writing:

```text
GPU_COMMAND = 2
```

causes the GPU renderer to clear the framebuffer.

## GPU_STATUS

```text
Address:
0x80000014
```

Currently planned:

```text
bit 0 = GPU busy
```

The status interface may be extended as the GPU develops.

---

# Framebuffer Memory

Framebuffer base address:

```text
0x80001000
```

Framebuffer size:

```text
160 × 120 × 1 byte
= 19,200 bytes
```

Current framebuffer range:

```text
0x80001000 – 0x80005AFF
```

Each pixel occupies one byte.

Pixel address:

```text
address = framebuffer_base + (Y × 160) + X
```

Example:

```text
X = 10
Y = 20

offset = (20 × 160) + 10
       = 3210
```

---

# CPU Interface

The GPU is intended to connect to the CPU using an **internal FPGA bus**.

The currently planned interface is:

```verilog
input  wire        cpu_we,
input  wire        cpu_re,
input  wire [31:0] cpu_addr,
input  wire [31:0] cpu_wdata,
output wire [31:0] cpu_rdata
```

These signals are **not intended to be physical FPGA pins**.

They are internal signals connecting the CPU and GPU inside the FPGA.

The final system will look like:

```text
                 FPGA
┌─────────────────────────────────────────┐
│                                         │
│  ┌──────────────┐     ┌──────────────┐ │
│  │     CPU      │────▶│     GPU      │ │
│  │              │     │              │ │
│  └──────────────┘     └──────┬───────┘ │
│                              │         │
│                              ▼         │
│                            HDMI        │
│                                         │
└─────────────────────────────────────────┘
```

The final bus protocol will be adapted to match the CPU implementation.

> **Integration note:** The CPU bus must remain an internal FPGA connection. It should not be exposed as physical FPGA pins. A separate board-level wrapper is used for the physical Tang Nano 20K I/O.

---

# Repository Structure

```text
src/
├── gpu_top.v
├── gpu_regs.v
├── gpu_renderer.v
├── framebuffer_bram.v
├── video_timing.v
├── tmds_encoder.v
├── tmds_serializer.v
├── Gowin_rPLL.v
├── tang_nano_20k.cst
└── tang_nano_20k.sdc
```

### `gpu_top.v`

Top-level GPU/core integration module.

Connects:

- CPU interface
- GPU registers
- GPU renderer
- Framebuffer
- Video timing
- TMDS encoder
- TMDS serializer
- HDMI output

### `gpu_regs.v`

Implements the GPU control registers:

- GPU enable
- X coordinate
- Y coordinate
- Color
- Commands
- Status/readback

### `gpu_renderer.v`

Responsible for framebuffer rendering operations.

Current operations:

```text
Draw pixel
Clear framebuffer
```

This module is intended to be expanded with additional rendering functionality.

### `framebuffer_bram.v`

Implements the framebuffer using FPGA memory.

Current configuration:

```text
19,200 × 8-bit
```

The framebuffer is shared between GPU rendering and video output.

### `video_timing.v`

Generates the 720×480 video timing signals:

```text
Horizontal counter
Vertical counter
HSYNC
VSYNC
Display enable
```

### `tmds_encoder.v`

Converts RGB video data into 10-bit TMDS symbols.

Three TMDS channels are generated:

```text
Red
Green
Blue
```

### `tmds_serializer.v`

Serializes the 10-bit TMDS symbols using the FPGA's high-speed output serializer.

### `Gowin_rPLL.v`

Generated Gowin PLL configuration for the GPU video clock.

---

# Clocking

The design uses two main clocks:

```text
Pixel clock:
27 MHz

TMDS serial clock:
135 MHz
```

Clock relationship:

```text
135 MHz / 5 = 27 MHz
```

The PLL generates the 135 MHz serial clock and a clock divider produces the 27 MHz pixel clock.

---

# HDMI Interface

Physical HDMI-related signals:

```text
tmds_clk_p
tmds_clk_n

tmds_d0_p
tmds_d0_n

tmds_d1_p
tmds_d1_n

tmds_d2_p
tmds_d2_n
```

These are connected to the Tang Nano 20K HDMI output pins through the board constraint file.

---

# Current Development Status

### Completed

- [x] FPGA clock input
- [x] PLL generation
- [x] Pixel clock generation
- [x] 720×480 video timing
- [x] TMDS encoding
- [x] TMDS serialization
- [x] Physical HDMI output testing
- [x] Test color bars
- [x] Static image display
- [x] RGB332 framebuffer architecture
- [x] GPU register architecture
- [x] Pixel rendering
- [x] Framebuffer BRAM architecture

### In Progress

- [ ] Final CPU-to-GPU bus integration
- [ ] CPU memory-mapped GPU access
- [ ] Framebuffer CPU read/write testing
- [ ] GPU status/busy handling
- [ ] Additional rendering commands
- [ ] Final hardware verification with the CPU

---

# Planned GPU Features

Future versions may include:

```text
Pixel drawing
Rectangle drawing
Line drawing
Bitmap rendering
Sprite support
Color fill
Hardware scrolling
Double buffering
DMA/framebuffer transfer
GPU command queue
```

The architecture is intentionally kept simple so that additional GPU functionality can be added incrementally.

---

# Testing Strategy

The GPU is being developed independently from the CPU.

## Stage 1 – HDMI

```text
FPGA
 ↓
Video timing
 ↓
TMDS
 ↓
HDMI display
```

## Stage 2 – Framebuffer

```text
GPU renderer
 ↓
Framebuffer BRAM
 ↓
HDMI
```

## Stage 3 – GPU Registers

```text
Register write
 ↓
GPU command
 ↓
Renderer
 ↓
Framebuffer
 ↓
HDMI
```

## Stage 4 – CPU Integration

```text
CPU
 ↓
Memory-mapped bus
 ↓
GPU registers
 ↓
GPU renderer
 ↓
Framebuffer
 ↓
HDMI
```

---

# Example CPU Operation

A CPU program could conceptually perform:

```text
Write X coordinate
Write Y coordinate
Write color
Write draw command
```

Example:

```text
GPU_X     = 100
GPU_Y     = 50
GPU_COLOR = RED
GPU_CMD   = DRAW_PIXEL
```

The GPU then updates:

```text
Framebuffer[100,50]
```

and the modified framebuffer contents appear on the HDMI display.

---

# Design Philosophy

This project is implemented from the hardware level rather than relying on a commercial GPU or graphics framework.

Main goals:

- Learn FPGA-based graphics architecture
- Understand video timing
- Implement a framebuffer
- Implement hardware rendering logic
- Understand TMDS/HDMI transmission
- Create a CPU-controlled graphics accelerator
- Build a foundation for a larger custom FPGA computer

---

# Tools

Development environment:

```text
Gowin FPGA Designer
Version: V1.9.11.03 Education
```

HDL:

```text
Verilog HDL
```

Target FPGA:

```text
GW2AR-18C
```

Board:

```text
Sipeed Tang Nano 20K
```

---

# Important Integration Note

The GPU is designed as a **hardware peripheral**, not as a standalone CPU.

The final system is intended to contain:

```text
Custom CPU
     │
     │ Internal memory-mapped bus
     ▼
    GPU
     │
     ▼
Framebuffer
     │
     ▼
   HDMI
```

The CPU and GPU can therefore be developed independently as long as the final bus interface is agreed upon.

When integrating the CPU, the CPU-side memory/bus interface should be compared with the GPU interface and an adapter should be added if necessary.

---

# Author

**Jacob Jibu**

Electrical and Electronics Engineering

Custom FPGA GPU / Computer Architecture Project

---

# License

This project is currently intended for educational and personal FPGA development.

License information will be added when the project is finalized.
