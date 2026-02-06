local RunService = game:GetService("RunService")

-- ПАРАМЕТРЫ
local MEM_SIZE = 1024 * 1024
local RAM = buffer.create(MEM_SIZE)
local IS_RUNNING = true
local screen_buffer = ""

-- РЕГИСТРЫ
local REG = {
	EAX = 0, EBX = 0, ECX = 0, EDX = 0,
	ESI = 0, EDI = 0, EBP = 0, ESP = 0,
	IP = 0, CS = 0, DS = 0, ES = 0, SS = 0,
	FLAGS = 0,
	CR0 = 0
}

local function getAL() return bit32.extract(REG.EAX, 0, 8) end
local function getAH() return bit32.extract(REG.EAX, 8, 8) end
local function setAL(v) REG.EAX = bit32.replace(REG.EAX, v, 0, 8) end
local function setAH(v) REG.EAX = bit32.replace(REG.EAX, v, 8, 8) end
local function getAX() return bit32.extract(REG.EAX, 0, 16) end
local function setAX(v) REG.EAX = bit32.replace(REG.EAX, v, 0, 16) end

local function get_pc() return bit32.band(REG.CS * 16 + REG.IP, 0xFFFFF) end

-- ОБРАБОТКА ПРЕРЫВАНИЙ (BIOS)
local function handle_interrupt(vector)
	if vector == 0x10 then 
		if getAH() == 0x0E then -- Функция телетайпа (mov ah, 0x0E)
			local char = string.char(getAL())
			screen_buffer = screen_buffer .. char
			print(screen_buffer)
		end
	end
end

-- ТАБЛИЦА ОПКОДОВ
local OPCODES = {}

OPCODES[0x00] = function() 
	print("CPU: 0x00 detected. Ignoring.")
	-- IS_RUNNING = false
end

OPCODES[0x90] = function() end -- NOP

OPCODES[0xB0] = function() -- MOV AL, imm8
	setAL(buffer.readu8(RAM, get_pc()))
	REG.IP += 1
end

OPCODES[0xB4] = function() -- MOV AH, imm8
	setAH(buffer.readu8(RAM, get_pc()))
	REG.IP += 1
end

OPCODES[0x34] = function() -- XOR AL, imm8
	local val = buffer.readu8(RAM, get_pc())
	REG.IP += 1
	local result = bit32.bxor(getAL(), val)
	setAL(result)

	-- Обновляем флаг нуля (ZF)
	if result == 0 then
		REG.FLAGS = bit32.replace(REG.FLAGS, 1, 6, 1) -- 6-й бит FLAGS это ZF
	else
		REG.FLAGS = bit32.replace(REG.FLAGS, 0, 6, 1)
	end
end

OPCODES[0x04] = function() -- ADD AL, imm8
	local val = buffer.readu8(RAM, get_pc())
	REG.IP += 1
	local oldAL = getAL()
	local result = oldAL + val

	-- Проверка на перенос (Carry Flag - 0-й бит)
	if result > 0xFF then
		REG.FLAGS = bit32.replace(REG.FLAGS, 1, 0, 1)
		result = bit32.band(result, 0xFF) -- Отрезаем лишнее
	else
		REG.FLAGS = bit32.replace(REG.FLAGS, 0, 0, 1)
	end

	setAL(result)
end

OPCODES[0xEB] = function() -- JMP short
	local offset = buffer.readu8(RAM, get_pc())
	REG.IP += 1 -- Пропускаем сам байт смещения

	-- Превращаем unsigned 0..255 в signed -128..127
	if offset > 127 then
		offset = offset - 256
	end

	REG.IP += offset
	-- print("Jumping to IP:", REG.IP)
end

-- XOR r/m16, r16 (0x31)
OPCODES[0x31] = function()
	local modrm = buffer.readu8(RAM, get_pc()); REG.IP += 1
	if modrm == 0xC0 then -- XOR AX, AX
		REG.AX = 0
		REG.FLAGS = bit32.replace(REG.FLAGS, 1, 6, 1) -- ZF = 1
	end
end

-- MOV Sreg, r/m16 (0x8E)
OPCODES[0x8E] = function()
	local modrm = buffer.readu8(RAM, get_pc()); REG.IP += 1
	if modrm == 0xD8 then REG.DS = REG.AX end -- DS = AX
	if modrm == 0xC0 then REG.ES = REG.AX end -- ES = AX
end

-- MOV SI, imm16 (0xBE)
OPCODES[0xBE] = function()
	REG.SI = buffer.readu16(RAM, get_pc()); REG.IP += 2
end

-- LODSB (0xAC)
OPCODES[0xAC] = function()
	local addr = bit32.band(REG.DS * 16 + REG.SI, 0xFFFFF)
	setAL(buffer.readu8(RAM, addr))
	REG.SI += 1
end

-- TEST r/m8, r8 (0x84)
OPCODES[0x84] = function()
	local modrm = buffer.readu8(RAM, get_pc()); REG.IP += 1
	if modrm == 0xC0 then -- TEST AL, AL
		local al = getAL()
		local zf = (al == 0) and 1 or 0
		REG.FLAGS = bit32.replace(REG.FLAGS, zf, 6, 1)
	end
end

-- JZ rel8 (0x74)
OPCODES[0x74] = function()
	local offset = buffer.readu8(RAM, get_pc()); REG.IP += 1
	if bit32.extract(REG.FLAGS, 6, 1) == 1 then
		if offset > 127 then offset -= 256 end
		REG.IP += offset
	end
end

-- JMP rel8 (0xEB)
OPCODES[0xEB] = function()
	local offset = buffer.readu8(RAM, get_pc()); REG.IP += 1
	if offset > 127 then offset -= 256 end
	REG.IP += offset
end

OPCODES[0xB8] = function() -- MOV AX, imm16
	REG.AX = buffer.readu16(RAM, get_pc())
	REG.IP += 2
end

OPCODES[0xCD] = function() -- INT imm8
	local vector = buffer.readu8(RAM, get_pc())
	REG.IP += 1
	handle_interrupt(vector)
end

OPCODES[0xF4] = function() -- HLT
	print("CPU: Halted (HLT).")
	IS_RUNNING = false
end

-- ГЛАВНЫЙ ЦИКЛ
local function cpu_step()
	if not IS_RUNNING then return end

	local opcode = buffer.readu8(RAM, get_pc())
	REG.IP += 1

	local action = OPCODES[opcode]
	if action then
		action()
	else
		warn(string.format("Unknown Opcode: 0x%02X at 0x%X", opcode, REG.IP-1))
		IS_RUNNING = false
	end
end

-- ЗАГРУЗКА И ЗАПУСК
local prog = {
	0x31, 0xC0, 0x8E, 0xD8, 0x8E, 0xC0, 0xBE, 0x17, 0x7C, 0xAC, 
	0x84, 0xC0, 0x74, 0x06, 0xB4, 0x0E, 0xCD, 0x10, 0xEB, 0xF5, 
	0xF4, 0xEB, 0xFD, 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x70, 
	0x65, 0x61, 0x6E, 0x69, 0x73
}
local START_ADDR = 0x7C00
for i, byte in ipairs(prog) do 
	buffer.writeu8(RAM, START_ADDR + i - 1, byte) 
end
REG.IP = START_ADDR

RunService.Heartbeat:Connect(function()
	for i = 1, 10 do
		cpu_step()
	end
end)
