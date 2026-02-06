import sys

if len(sys.argv) != 2:
    print("Usage: python bin2lua.py <file.bin>")
    sys.exit(1)

with open(sys.argv[1], "rb") as f:
    data = f.read()

if len(data) >= 2 and data[-2:] == b'\xaa\x55':
    data = data[:-2]

data = [b for b in data if b != 0]

out = ", ".join(f"0x{b:02X}" for b in data)

print(out)
