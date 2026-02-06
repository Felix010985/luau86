# Luau86

Luau86 is an emulator/virtual CPU designed to run in Roblox environment

## Usage

```lua
-- Change this by your nasm/fasm compiled binary
local prog = {
	0x31, 0xC0, 0x8E, 0xD8, 0x8E, 0xC0, 0xBE, 0x17, 0x7C, 0xAC, 
	0x84, 0xC0, 0x74, 0x06, 0xB4, 0x0E, 0xCD, 0x10, 0xEB, 0xF5, 
	0xF4, 0xEB, 0xFD, 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x70, 
	0x65, 0x61, 0x6E, 0x69, 0x73
}
```

## TODO/Current support

The project is almost raw and no actual Operating System will boot on it, here is an example of assembly that will run

```nasm
; calculate 5 + 3 and display number 8
mov al, 5
add al, 3
mov ah, 0Eh
add al, 30h
int 10h
```
Maybe other examples will be located it examples/ 

TODO:
- 32-bit Protected Mode
- 64-bit Long Mode
- ISO Booting
- Legacy BIOS Interupts (INT 10h, INT 13h, etc.)
- 60-70% accuracy in CPU work
- A game in Roblox (not only studio file)
- Render on Roblox screen and not in console
