# wchip8

This project is a Chip8 emulator implemented in Zig programming language utilizing WebGPU for rendering. The primary objective of this project was to learn WebGPU and API programming while creating a simple and efficient Chip8 emulator.

## Features

- Chip8 Emulation: The emulator accurately emulates the behavior of the Chip8 virtual machine, allowing users to run Chip8 programs and games.
- WebGPU Rendering: Utilizes WebGPU for rendering graphics, providing efficient and hardware-accelerated graphics rendering in the browser.
- Command-line Interface: Supports running Chip8 programs via the command-line interface, allowing users to specify ROM file paths and customize background and foreground colors.

## Getting Started

### Prerequisites

To run this project, you need to have `Zig version 0.12.0-dev.3180+83e578a18` installed on your system. 

### Build and run

1) Clone the repository:

```bash
git clone https://github.com/GiuseppeCesarano/wchip8
```

2) Build the project:

```bash
zig build -Doptimize=ReleaseFast -Dtarget=native-native
```

3) Run the emulator with the following command:

```bash
./wchip <path-to-rom-file> <optional:background-color> <optional:foreground-color>
```

- path-to-rom-file: Path to the Chip8 ROM file you want to run.
- background-color (optional): Background color for the emulator display in hexadecimal format (e.g., `RRGGBB`).
- foreground-color (optional): Foreground color for the emulator display in hexadecimal format.

## Special thanks

Big thanks to [Timendus for chip8-test-suite](https://github.com/Timendus/chip8-test-suite)! His ROM collection has been instrumental in testing and improving this emulator.
