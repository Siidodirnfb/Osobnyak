--[[
	HI Builder — Litematica-style
	=================================================================
	Строит слово "HI" из блоков вокруг игрока.
	Сначала полностью планирует, потом моментально ставит (с телепортом).
	=================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
assert(Remotes, "[HI] нет ReplicatedStorage.Remotes — скрипт остановлен")
local Change = Remotes:WaitForChild("Change", 15)
assert(Change, "[HI] нет ReplicatedStorage.Remotes.Change — скрипт остановлен")
local IS_FUNC = Change:IsA("RemoteFunction")
print(("[HI] remote: %s (%s)"):format(
	Change:GetFullName(), if IS_FUNC then "RemoteFunction" else "RemoteEvent"))

local NORMAL = Vector3.new(0, 1, 0)
local PI = math.pi

-- ===================== НАСТРОЙКИ =====================
local REPAIR_PASSES = 2
local LETTER_MATERIAL = "White Brick"   -- основной материал букв
local BASE_MATERIAL  = "Stone Bricks"   -- материал подставки
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
-- Математика
--------------------------------------------------------------------------

local EXACT_SPECIAL = {
	Ladder = true, Chair = true, Bed = true,
	Armchair = true, Verity = true, Keycap = true,
}

local function isSpecial(name: string): boolean
	return string.find(name, "Door") ~= nil
		or string.find(name, "Stairs") ~= nil
		or EXACT_SPECIAL[name] == true
end

local function rotOffset(name: string): number
	if string.find(name, "Stairs") or name == "Keycap" then
		return -(PI / 2)
	elseif name == "Bed" or name == "Armchair" then
		return 0
	end
	return -PI
end

local function dims(name: string): (number, number)
	local H = if string.find(name, "Door") then 6 else 3
	local D = if name == "Bed" then 6 else 3
	return H, D
end

local function planPlace(name: string, x: number, y: number, z: number, yaw: number?)
	table.insert(plan, {
		name = name,
		x = x,
		y = y,
		z = z,
		yaw = yaw or 0
	})
end

--------------------------------------------------------------------------
-- Позиция игрока
--------------------------------------------------------------------------

local lp = Players.LocalPlayer

local function waitForCharacter(player: any, timeout: number): Model?
	if player == nil then return nil end
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if player.Character then return player.Character end
		task.wait(0.25)
	end
	return player.Character
end

local char = lp.Character or waitForCharacter(lp, 60)
assert(char, "[HI] персонаж не найден")
local hrp = char:WaitForChild("HumanoidRootPart", 15) :: BasePart?
assert(hrp, "[HI] HumanoidRootPart не найден")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { char }

local ray = workspace:Raycast(hrp.Position + Vector3.new(0, 4, 0), Vector3.new(0, -90, 0), rayParams)
local feetY = if ray then ray.Position.Y else hrp.Position.Y - 3

local OX = math.round(hrp.Position.X / 3) * 3
local OZ = math.round(hrp.Position.Z / 3) * 3
local FY = math.round(feetY / 3) * 3

print(("[HI] origin=(%d, %d, %d)"):format(OX, FY, OZ))

local function cx(i: number): number return OX + i * 3 end
local function cz(j: number): number return OZ + j * 3 end
local function cy(k: number): number return FY + 1.5 + k * 3 end   -- k = 0 — пол

--------------------------------------------------------------------------
-- ПАТТЕРНЫ БУКВ (7 клеток в высоту)
-- 1 = блок, 0 = пусто
--------------------------------------------------------------------------

-- Буква H (5 клеток в ширину)
local H_PATTERN = {
	-- k = 0 (низ) → k = 6 (верх)
	{1,0,0,0,1}, -- 0
	{1,0,0,0,1}, -- 1
	{1,0,0,0,1}, -- 2
	{1,1,1,1,1}, -- 3  ← перекладина
	{1,0,0,0,1}, -- 4
	{1,0,0,0,1}, -- 5
	{1,0,0,0,1}, -- 6
}

-- Буква I (3 клетки в ширину)
local I_PATTERN = {
	{1,1,1}, -- 0
	{0,1,0}, -- 1
	{0,1,0}, -- 2
	{0,1,0}, -- 3
	{0,1,0}, -- 4
	{0,1,0}, -- 5
	{1,1,1}, -- 6
}

--------------------------------------------------------------------------
-- ПЛАНИРОВАНИЕ
--------------------------------------------------------------------------

print("[HI] Планирую слово HI...")

-- Подставка под всё слово
local function planBase()
	-- Ширина: H (5) + промежуток (2) + I (3) = 10 клеток
	-- Делаем подставку чуть шире
	for i = -6, 5 do
		for j = -1, 1 do
			planPlace(BASE_MATERIAL, cx(i), cy(-1), cz(j)) -- чуть ниже пола
		end
	end
end

-- Ставит букву по паттерну
-- startI — левый край буквы по оси i
-- thickness — толщина буквы по оси j
local function planLetter(pattern, startI: number, thickness: number)
	local height = #pattern
	local width = #pattern[1]

	for k = 0, height - 1 do
		local row = pattern[k + 1]
		for di = 0, width - 1 do
			if row[di + 1] == 1 then
				for dj = 0, thickness - 1 do
					planPlace(LETTER_MATERIAL, cx(startI + di), cy(k), cz(dj))
				end
			end
		end
	end
end

planBase()

-- H слева, I справа
planLetter(H_PATTERN, -5, 2)  -- H: i = -5..-1, толщина 2
planLetter(I_PATTERN,  2, 2)  -- I: i =  2..4 , толщина 2

print(("[HI] План готов: %d блоков"):format(#plan))

--------------------------------------------------------------------------
-- ИСПОЛНЕНИЕ
--------------------------------------------------------------------------

local function executeBlock(info)
	local name, x, y, z, yaw = info.name, info.x, info.y, info.z, info.yaw
	local H, D = dims(name)
	local special = isSpecial(name)
	if not special then yaw = 0 end

	local finalYaw = math.round(yaw / (PI / 2)) * (PI / 2)
	local camYaw = if special then finalYaw - rotOffset(name) else 0
	local cameraCFrame = CFrame.Angles(0, camYaw, 0)
	local hitPos = Vector3.new(x, y - H / 2, z)

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
			warn("[HI] СТОП: сервер ответил " .. tostring(res))
			return false, true
		end
		return false
	end
end

print("[HI] Начинаю стройку...")

local aborted = false
for _, info in ipairs(plan) do
	local success, isAbort = executeBlock(info)
	if isAbort then
		aborted = true
		break
	end
	if not success then
		table.insert(missing, info)
	end
end

print(("[HI] Основная стройка: отправлено=%d успешно=%d ошибок=%d"):format(sent, okCount, failCount))

--------------------------------------------------------------------------
-- РЕМОНТ
--------------------------------------------------------------------------

for pass = 1, REPAIR_PASSES do
	if #missing == 0 or aborted then break end
	print(("[HI] Ремонт %d/%d — осталось %d"):format(pass, REPAIR_PASSES, #missing))

	local still = {}
	for _, info in ipairs(missing) do
		if aborted then break end
		local success, isAbort = executeBlock(info)
		if isAbort then aborted = true; break end
		if not success then table.insert(still, info) end
	end
	missing = still
end

print(("[HI] ГОТОВО: в плане=%d  успешно=%d  пропусков=%d"):format(#plan, okCount, #missing))

pcall(function()
	if IS_FUNC then
		Change:InvokeServer("MansionDone")
	else
		Change:FireServer("MansionDone")
	end
end)
