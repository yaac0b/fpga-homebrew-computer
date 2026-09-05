GPU PROJECT - Tang Nano 20K

This is the GPU-side project intended to connect later to a friend's CPU.

Top module:
    gpu_top

Device:
    GW2AR-LV18QN88C8/I7

CPU-facing interface:
    cpu_we
    cpu_re
    cpu_addr[31:0]
    cpu_wdata[31:0]
    cpu_rdata[31:0]

Address map:
    0x80000000 + 0x000 : GPU enable (bit 0)
    0x80000000 + 0x004 : X coordinate
    0x80000000 + 0x008 : Y coordinate
    0x80000000 + 0x00C : RGB332 color
    0x80000000 + 0x010 : command
                             1 = draw pixel
                             2 = clear framebuffer
    0x80000000 + 0x014 : status (bit 0 = clear busy)

    0x80001000 .. 0x80005AFF : 160x120 RGB332 framebuffer

Framebuffer:
    160 x 120 x 8 bits = 19,200 bytes.
    Displayed at 3x scale as 480x360 centered on 720x480.

Important:
    The framebuffer is a dual-use memory: CPU/renderer writes and video reads.
    The exact read/write timing should be verified in synthesis/hardware.
    The CPU interface is intentionally simple so another CPU can connect later.

Add all files under src/ to a new Gowin project.
Set gpu_top as the top module.
Add the CST and SDC files.

Note:
    For 8-bit GPU registers/framebuffer writes, only cpu_wdata[7:0] is used.
    cpu_wdata[31:8] being unused is intentional.
