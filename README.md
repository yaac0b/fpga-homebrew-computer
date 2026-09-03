# FPGA Computer System

A complete computer system designed from scratch using **Verilog HDL** and implemented on an FPGA. The project integrates a custom computer architecture with memory, SDRAM, video generation, and peripheral interfaces.

## Overview

This project focuses on designing and integrating the major building blocks of a computer system at the RTL level.

The system is developed incrementally, with individual hardware modules being designed, simulated, tested, and integrated into a complete FPGA-based computer.

The project serves as a practical exploration of:

- Computer architecture
- Digital system design
- RTL design
- FPGA development
- Memory interfacing
- Video generation
- Hardware–software interaction

## System Architecture

The overall system is built around a central processor connected to memory and peripheral subsystems.

```text
                    ┌──────────────────┐
                    │       CPU        │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   System Bus /   │
                    │ Memory Interface │
                    └───────┬────┬──────┘
                            │    │
                ┌───────────┘    └────────────┐
                ▼                             ▼
        ┌──────────────┐              ┌──────────────┐
        │    SDRAM     │              │    VIDEO     │
        │  Controller  │              │    SYSTEM    │
        └──────────────┘              └──────┬───────┘
                                             │
                                             ▼
                                          VGA Output
Main Components
CPU

The processor forms the core of the computer system and is responsible for executing instructions and controlling the system's operations.

Memory

Memory modules provide storage for program instructions and data.

SDRAM Controller

The SDRAM subsystem provides access to external dynamic memory and handles the required control and timing signals for SDRAM operation.

Video System

The video subsystem generates graphical output and interfaces with a VGA display.

VGA Controller

The VGA controller generates the required horizontal and vertical synchronization signals and produces pixel data for display output.

Peripherals

The architecture is designed to support additional hardware peripherals and interfaces as the system develops.

Hardware
FPGA development board
External SDRAM
VGA display/interface
Supporting electronic components and peripherals
Tools & Technologies
Verilog HDL
Gowin EDA
FPGA synthesis and implementation
RTL simulation
Digital logic design
Repository Structure
fpga-computer-system/
│
├── src/
│   ├── cpu/
│   ├── memory/
│   ├── sdram/
│   ├── video/
│   └── peripherals/
│
├── simulation/
├── constraints/
├── docs/
├── images/
└── README.md
Development Approach

The system is being developed in stages:

Design individual RTL modules
Simulate and verify each module
Integrate the modules
Synthesize the design
Perform FPGA implementation
Test the hardware
Debug timing and functional issues
Expand the architecture with additional features
Current Status

🚧 Work in Progress

The computer is currently under active development.

The project includes development and integration of the processor, memory subsystem, SDRAM interface, and VGA-based video subsystem.

Further hardware integration, verification, and optimization are ongoing.

Learning Objectives

This project is being developed to gain practical experience in:

Computer architecture
Verilog RTL design
FPGA architecture
Digital electronics
Memory controllers
SDRAM interfacing
VGA signal generation
Hardware debugging
Timing analysis
System-level hardware integration
Future Improvements
Complete CPU and system integration
Improve SDRAM controller reliability
Expand the video subsystem
Add additional peripheral interfaces
Develop a software/firmware environment
Expand the instruction set
Improve system performance
Optimize FPGA resource utilization
Add comprehensive simulation and verification
License

This project is released under the MIT License.

See the LICENSE file for details.

Author

Jacob Jibu

Electrical and Electronics Engineering
