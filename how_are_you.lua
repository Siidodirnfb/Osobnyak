--[[
	How Are You?:) Builder — Litematica-style
	=================================================================
	Строит текст "How Are You?:)" перед игроком.
	Ориентация автоматически выбирается по направлению взгляда
	(привязка к ближайшей оси X/Z, чтобы блоки вставали на сетку).
	=================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
assert(Remotes, "[Text] нет ReplicatedStorage.Remotes")
local Change = Remotes:WaitForChild("Change", 15)
assert(Change, "[Text] нет ReplicatedStorage.Remotes.Change")
local IS_FUNC = Change:IsA("RemoteFunction")
print(("[Text] remote: %s (%s)"):format(
	Change:GetFullName(), if IS_FUNC then "RemoteFunction" else "RemoteEvent"))

local NORMAL = Vector3.new(0, 1, 0)
local PI = math.pi

-- ===================== НАСТРОЙКИ =====================
local REPAIR_PASSES   = 2
local LETTER_MATERIAL = "White Brick"
local BASE_MATERIAL   = "Stone Bricks"
local LETTER_HEIGHT   = 7          -- высота букв в клетках
local THICKNESS       = 2          -- толщина букв
local CHAR_SPACING    = 1          -- промежуток между буквами
-- =====================================================

local plan = {}
local sent, okCount, failCount = 0, 0, 0
local missing = {}

local function sendPlace(hitPos, cameraCFrame, name)
	if IS_FUNC then
		return pcall(Change.InvokeServer, Change,
			"Place", hitPos, cameraCFrame, name, NORMAL, "H", nil)
	else
		local ok = pcall(Change.FireServer, Change,
			"Place", hitPos, cameraCFrame, name, NORMAL, "H", nil)
		return ok, true
	end
end

--------------------------------------------------------------------------
-- Математика блоков
--------------------------------------------------------------------------

local EXACT_SPECIAL = {
	Ladder=true, Chair=true, Bed=true, Armchair=true, Verity=true, Keycap=true,
}

local function isSpecial(name: string): boolean
	return string.find(name, "Door") ~= nil
		or string.find(name, "Stairs") ~= nil
		or EXACT_SPECIAL[name] == true
end

local function rotOffset(name: string): number
	if string.find(name, "Stairs") or name == "Keycap" then return -(PI/2) end
	if name == "Bed" or name == "Armchair" then return 0 end
	return -PI
end

local function dims(name: string): (number, number)
	local H = if string.find(name, "Door") then 6 else 3
	local D = if name == "Bed" then 6 else 3
	return H, D
end

local function planPlace(name: string, x: number, y: number, z: number, yaw: number?)
	table.insert(plan, {name=name, x=x, y=y, z=z, yaw=yaw or 0})
end

--------------------------------------------------------------------------
-- Позиция и ориентация игрока
--------------------------------------------------------------------------

local lp = Players.LocalPlayer
local function waitForCharacter(player, timeout)
	if not player then return nil end
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if player.Character then return player.Character end
		task.wait(0.25)
	end
	return player.Character
end

local char = lp.Character or waitForCharacter(lp, 60)
assert(char, "[Text] персонаж не найден")
local hrp = char:WaitForChild("HumanoidRootPart", 15) :: BasePart?
assert(hrp, "[Text] HumanoidRootPart не найден")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = {char}

local ray = workspace:Raycast(hrp.Position + Vector3.new(0,4,0), Vector3.new(0,-90,0), rayParams)
local feetY = if ray then ray.Position.Y else hrp.Position.Y - 3

local OX = math.round(hrp.Position.X / 3) * 3
local OZ = math.round(hrp.Position.Z / 3) * 3
local FY = math.round(feetY / 3) * 3

-- Определяем направление текста по взгляду игрока (с привязкой к осям)
local look = hrp.CFrame.LookVector
local absX, absZ = math.abs(look.X), math.abs(look.Z)

-- rightDir — направление, вдоль которого идёт текст
-- forwardDir — направление "в глубину" (толщина букв)
local rightDir  -- Vector3 unit along text
local forwardDir

if absX > absZ then
	-- Смотрит больше по X
	if look.X > 0 then
		rightDir   = Vector3.new(0, 0, 1)   -- текст вдоль +Z
		forwardDir = Vector3.new(1, 0, 0)   -- толщина вдоль +X
	else
		rightDir   = Vector3.new(0, 0,-1)   -- текст вдоль -Z
		forwardDir = Vector3.new(-1,0, 0)
	end
else
	-- Смотрит больше по Z
	if look.Z > 0 then
		rightDir   = Vector3.new(-1,0, 0)   -- текст вдоль -X
		forwardDir = Vector3.new(0, 0, 1)
	else
		rightDir   = Vector3.new(1, 0, 0)   -- текст вдоль +X
		forwardDir = Vector3.new(0, 0,-1)
	end
end

print(("[Text] origin=(%d,%d,%d)  right=(%.0f,%.0f)  forward=(%.0f,%.0f)")
	:format(OX, FY, OZ, rightDir.X, rightDir.Z, forwardDir.X, forwardDir.Z))

-- Преобразование локальных координат буквы в мировые
-- li — вдоль текста (вправо), lk — высота, lj — толщина (вперёд)
local function worldPos(li: number, lk: number, lj: number): (number, number, number)
	local offset = rightDir * (li * 3) + Vector3.new(0, lk * 3, 0) + forwardDir * (lj * 3)
	return OX + offset.X, FY + 1.5 + offset.Y, OZ + offset.Z
end

--------------------------------------------------------------------------
-- Шрифт 5×7 (простые пиксельные буквы)
--------------------------------------------------------------------------

local FONT = {
	["H"] = {
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,1,1,1,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
	},
	["O"] = {
		{0,1,1,1,0},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{0,1,1,1,0},
	},
	["W"] = {
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,1,0,1},
		{1,0,1,0,1},
		{1,1,0,1,1},
		{1,0,0,0,1},
	},
	["A"] = {
		{0,1,1,1,0},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,1,1,1,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
	},
	["R"] = {
		{1,1,1,1,0},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,1,1,1,0},
		{1,0,1,0,0},
		{1,0,0,1,0},
		{1,0,0,0,1},
	},
	["E"] = {
		{1,1,1,1,1},
		{1,0,0,0,0},
		{1,0,0,0,0},
		{1,1,1,1,0},
		{1,0,0,0,0},
		{1,0,0,0,0},
		{1,1,1,1,1},
	},
	["Y"] = {
		{1,0,0,0,1},
		{1,0,0,0,1},
		{0,1,0,1,0},
		{0,0,1,0,0},
		{0,0,1,0,0},
		{0,0,1,0,0},
		{0,0,1,0,0},
	},
	["U"] = {
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{1,0,0,0,1},
		{0,1,1,1,0},
	},
	["?"] = {
		{0,1,1,1,0},
		{1,0,0,0,1},
		{0,0,0,0,1},
		{0,0,1,1,0},
		{0,0,1,0,0},
		{0,0,0,0,0},
		{0,0,1,0,0},
	},
	[":"] = {
		{0,0,0},
		{0,1,0},
		{0,1,0},
		{0,0,0},
		{0,1,0},
		{0,1,0},
		{0,0,0},
	},
	[")"] = {
		{1,0,0},
		{0,1,0},
		{0,0,1},
		{0,0,1},
		{0,0,1},
		{0,1,0},
		{1,0,0},
	},
	[" "] = { -- пробел
		{0,0,0},
		{0,0,0},
		{0,0,0},
		{0,0,0},
		{0,0,0},
		{0,0,0},
		{0,0,0},
	},
}

-- Ширина каждого символа
local function charWidth(ch: string): number
	local pat = FONT[ch]
	if not pat then return 3 end
	return #pat[1]
end

--------------------------------------------------------------------------
-- ПЛАНИРОВАНИЕ ТЕКСТА
--------------------------------------------------------------------------

local TEXT = "How Are You?:)"

print("[Text] Планирую \"" .. TEXT .. "\" ...")

-- Считаем общую ширину текста в клетках
local totalWidth = 0
for i = 1, #TEXT do
	local ch = string.sub(TEXT, i, i)
	totalWidth += charWidth(ch)
	if i < #TEXT then totalWidth += CHAR_SPACING end
end

-- Центрируем текст относительно игрока
local startLi = -math.floor(totalWidth / 2)

-- Подставка
for li = startLi - 1, startLi + totalWidth do
	for lj = 0, THICKNESS - 1 do
		local x, y, z = worldPos(li, -1, lj)
		planPlace(BASE_MATERIAL, x, y, z)
	end
end

-- Буквы
local cursor = startLi
for i = 1, #TEXT do
	local ch = string.sub(TEXT, i, i)
	local pattern = FONT[ch]
	if pattern then
		local w = #pattern[1]
		for k = 0, LETTER_HEIGHT - 1 do
			local row = pattern[k + 1]
			for di = 0, w - 1 do
				if row[di + 1] == 1 then
					for lj = 0, THICKNESS - 1 do
						local x, y, z = worldPos(cursor + di, k, lj)
						planPlace(LETTER_MATERIAL, x, y, z)
					end
				end
			end
		end
		cursor += w + CHAR_SPACING
	else
		cursor += 3 + CHAR_SPACING
	end
end

print(("[Text] План готов: %d блоков"):format(#plan))

--------------------------------------------------------------------------
-- ИСПОЛНЕНИЕ
--------------------------------------------------------------------------

local function executeBlock(info)
	local name, x, y, z, yaw = info.name, info.x, info.y, info.z, info.yaw
	local H = dims(name)
	local special = isSpecial(name)
	if not special then yaw = 0 end

	local finalYaw = math.round(yaw / (PI/2)) * (PI/2)
	local camYaw = if special then finalYaw - rotOffset(name) else 0
	local cameraCFrame = CFrame.Angles(0, camYaw, 0)
	local hitPos = Vector3.new(x, y - H/2, z)

	if hrp and hrp.Parent then
		hrp.CFrame = CFrame.new(hitPos + Vector3.new(0, 5, 0))
	end

	local ok, res = sendPlace(hitPos, cameraCFrame, name)
	sent += 1

	if ok and (res == true or res == nil) then
		okCount += 1
		return true
	else
		failCount += 1
		if res == "Limit" or res == "Height" then
			warn("[Text] СТОП: " .. tostring(res))
			return false, true
		end
		return false
	end
end

print("[Text] Начинаю стройку...")

local aborted = false
for _, info in ipairs(plan) do
	local success, isAbort = executeBlock(info)
	if isAbort then aborted = true; break end
	if not success then table.insert(missing, info) end
end

print(("[Text] Основная стройка: %d / %d"):format(okCount, sent))

for pass = 1, REPAIR_PASSES do
	if #missing == 0 or aborted then break end
	print(("[Text] Ремонт %d — осталось %d"):format(pass, #missing))
	local still = {}
	for _, info in ipairs(missing) do
		if aborted then break end
		local success, isAbort = executeBlock(info)
		if isAbort then aborted = true; break end
		if not success then table.insert(still, info) end
	end
	missing = still
end

print(("[Text] ГОТОВО: план=%d  успешно=%d  пропусков=%d"):format(#plan, okCount, #missing))

pcall(function()
	if IS_FUNC then
		Change:InvokeServer("MansionDone")
	else
		Change:FireServer("MansionDone")
	end
end)
