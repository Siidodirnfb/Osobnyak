--[[
	MansionBuilder — Litematica-style (сначала план, потом стройка)
	=================================================================
	1. Полностью рассчитывает все блоки (план)
	2. Затем моментально ставит их (с телепортом игрока)
	3. После стройки — автоматическая достройка пропусков
	=================================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
assert(Remotes, "[Mansion] нет ReplicatedStorage.Remotes — скрипт остановлен")
local Change = Remotes:WaitForChild("Change", 15)
assert(Change, "[Mansion] нет ReplicatedStorage.Remotes.Change — скрипт остановлен")
local IS_FUNC = Change:IsA("RemoteFunction")
print(("[Mansion] remote: %s (%s)"):format(
	Change:GetFullName(), if IS_FUNC then "RemoteFunction" else "RemoteEvent"))

local NORMAL = Vector3.new(0, 1, 0)
local PI = math.pi
local TARGET_NAME = "Prime_Neuer"

-- ===================== НАСТРОЙКИ =====================
local RUN = { all = true }          -- какие секции планировать
local REPAIR_PASSES = 2             -- сколько раз пытаться закрыть пропуски
-- =====================================================

local plan = {}                     -- полный план: {name, x, y, z, yaw}
local sent, okCount, failCount = 0, 0, 0
local missing = {}                  -- то, что не встало

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
-- 1. Математика сетки
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

-- Добавляет блок в план (никаких вызовов ремоута)
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
-- 2. Точка привязки
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

local target = Players:FindFirstChild(TARGET_NAME)
local char: Model? = waitForCharacter(target, 5)
if char then
	print(("[Mansion] строим вокруг %s"):format(TARGET_NAME))
else
	print(("[Mansion] %s нет в игре — строим вокруг себя"):format(TARGET_NAME))
	while not char do
		char = waitForCharacter(lp, 60)
		if not char then
			print("[Mansion] всё ещё жду появления персонажа...")
		end
	end
end
assert(char, "[Mansion] персонаж не найден — скрипт остановлен")

local localChar = lp.Character or waitForCharacter(lp, 30)
assert(localChar, "[Mansion] локальный персонаж не найден")
local hrp = localChar:WaitForChild("HumanoidRootPart", 15) :: BasePart?
assert(hrp, "[Mansion] HumanoidRootPart локального игрока не найден")

local targetHrp: BasePart? = nil
while not targetHrp do
	targetHrp = char:WaitForChild("HumanoidRootPart", 15) :: BasePart?
	if not targetHrp then
		print("[Mansion] жду HumanoidRootPart целевого персонажа...")
		local alt = waitForCharacter(lp, 30)
		if alt and alt ~= char then char = alt end
		task.wait(1)
	end
end

local exclude = { char }
if localChar ~= char then table.insert(exclude, localChar) end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = exclude

local ray = workspace:Raycast(targetHrp.Position + Vector3.new(0, 4, 0), Vector3.new(0, -90, 0), rayParams)
local feetY = if ray then ray.Position.Y else targetHrp.Position.Y - 3

local OX = math.round(targetHrp.Position.X / 3) * 3
local OZ = math.round(targetHrp.Position.Z / 3) * 3
local FY = math.round(feetY / 3) * 3

print(("[Mansion] игрок=%s  origin=(%d, %d, %d)  цоколь=%d")
	:format(char.Name, OX, FY, OZ, FY + 3))

--------------------------------------------------------------------------
-- 3. Сетка и высоты
--------------------------------------------------------------------------

local function cx(i: number): number return OX + (i - 16) * 3 end
local function cz(j: number): number return OZ + (j - 13) * 3 end

local Y_FLOOR = FY + 1.5
local function yW1(k: number): number return FY + 4.5 + 3 * k end
local Y_SLAB2 = FY + 16.5
local function yW2(k: number): number return FY + 19.5 + 3 * k end
local Y_SLAB3 = FY + 31.5
local function yRoof(k: number): number return FY + 34.5 + 3 * k end
local Y_DOOR1 = FY + 6
local Y_DOOR2 = FY + 21
local Y_F1 = yW1(0)
local Y_F2 = yW2(0)
local CH_I, CH_J = 28, 6

local function resolve(mat, a, b)
	if typeof(mat) == "string" then return mat end
	return mat(a, b)
end

local function fill(i1, j1, i2, j2, y, mat)
	for i = i1, i2 do
		for j = j1, j2 do
			local m = resolve(mat, i, j)
			if m then planPlace(m, cx(i), y, cz(j)) end
		end
	end
end

local function wallZ(i, j1, j2, k1, k2, yfn, mat)
	for j = j1, j2 do
		for k = k1, k2 do
			local m = resolve(mat, j, k)
			if m then planPlace(m, cx(i), yfn(k), cz(j)) end
		end
	end
end

local function wallX(j, i1, i2, k1, k2, yfn, mat)
	for i = i1, i2 do
		for k = k1, k2 do
			local m = resolve(mat, i, k)
			if m then planPlace(m, cx(i), yfn(k), cz(j)) end
		end
	end
end

local function doorAt(i, j, y, yaw)
	planPlace("Oak Door", cx(i), y, cz(j), yaw)
end

local function intMat(_, k)
	if k == 0 then return "Quartz" end
	return "White Brick"
end

--------------------------------------------------------------------------
-- 4. ПЛАНИРОВАНИЕ (никаких ремоутов)
--------------------------------------------------------------------------

local order = 0
local function step(name, fn)
	order += 1
	if not (RUN.all or RUN[name]) then
		print(("[Mansion] [%02d] %s — пропуск"):format(order, name))
		return
	end
	print(("[Mansion] [%02d] планирую %s ..."):format(order, name))
	fn()
end

-- Пол 1 этажа
local function groundFloorMat(i, j)
	if i == 0 or i == 32 or j == 0 or j == 26 then return "Stone Bricks" end
	if i == CH_I and j == CH_J then return "Stone Bricks" end
	if i >= 23 and i <= 31 and j >= 14 and j <= 25 then return "Smooth Stone" end
	if i >= 1 and i <= 9 and j >= 21 and j <= 25 then return "Smooth Stone" end
	return "Oak Planks"
end

step("floor1", function()
	fill(0, 0, 32, 26, Y_FLOOR, groundFloorMat)
end)

-- Наружные стены 1 этажа
local WIN_LONG = { [3]=true,[8]=true,[13]=true,[18]=true,[23]=true,[28]=true }
local WIN_FRONT = { [4]=true,[8]=true,[18]=true,[22]=true }
local WIN_BACK = { [4]=true,[8]=true,[13]=true,[18]=true,[22]=true }
local PIL_LONG = { [11]=true,[22]=true }
local PIL_GABLE = { [6]=true,[20]=true }

local function extLong(i, k)
	if i == 0 or i == 32 or PIL_LONG[i] then return "Quartz" end
	if WIN_LONG[i] and (k == 1 or k == 2) then return "Glass" end
	return "White Brick"
end

local function extFront1(j, k)
	if j == 13 then
		if k == 0 or k == 1 then return nil end
		return "White Brick"
	end
	if PIL_GABLE[j] then return "Quartz" end
	if WIN_FRONT[j] and (k == 1 or k == 2) then return "Glass" end
	return "White Brick"
end

local function extBack1(j, k)
	if PIL_GABLE[j] then return "Quartz" end
	if WIN_BACK[j] and (k == 1 or k == 2) then return "Glass" end
	return "White Brick"
end

step("extwalls1", function()
	wallX(0, 0, 32, 0, 3, yW1, extLong)
	wallX(26, 0, 32, 0, 3, yW1, extLong)
	wallZ(0, 1, 25, 0, 3, yW1, extFront1)
	wallZ(32, 1, 25, 0, 3, yW1, extBack1)
	doorAt(0, 13, Y_DOOR1, -PI / 2)
end)

-- Внутренние стены 1 этажа
step("intwalls1", function()
	wallZ(10, 1, 25, 0, 3, yW1, function(j, k)
		if (j == 8 or j == 18) and (k == 0 or k == 1) then return nil end
		return intMat(j, k)
	end)
	doorAt(10, 8, Y_DOOR1, PI / 2)
	doorAt(10, 18, Y_DOOR1, PI / 2)

	wallZ(22, 1, 25, 0, 3, yW1, function(j, k)
		if (j == 8 or j == 18) and (k == 0 or k == 1) then return nil end
		return intMat(j, k)
	end)
	doorAt(22, 8, Y_DOOR1, PI / 2)
	doorAt(22, 18, Y_DOOR1, PI / 2)

	wallX(13, 11, 21, 0, 3, yW1, function(i, k)
		if i == 16 and (k == 0 or k == 1) then return nil end
		return intMat(i, k)
	end)
	doorAt(16, 13, Y_DOOR1, 0)

	wallX(13, 23, 31, 0, 3, yW1, function(i, k)
		if (i == 26 or i == 27) and (k == 0 or k == 1) then return nil end
		return intMat(i, k)
	end)

	wallX(6, 1, 9, 0, 3, yW1, function(i, k)
		if i == 5 and (k == 0 or k == 1) then return nil end
		return intMat(i, k)
	end)
	doorAt(5, 6, Y_DOOR1, 0)

	wallX(20, 1, 9, 0, 3, yW1, function(i, k)
		if i == 5 and (k == 0 or k == 1) then return nil end
		return intMat(i, k)
	end)
	doorAt(5, 20, Y_DOOR1, 0)
end)

-- Лестница
step("stairs", function()
	for n = 0, 4 do
		local y = if n < 4 then yW1(n) else Y_SLAB2
		planPlace("Oak Stairs", cx(3 + n), y, cz(13), PI)
	end
end)

-- Перекрытие 2 этажа
local function slab2Mat(i, j)
	if i == 0 or i == 32 or j == 0 or j == 26 then return "Quartz" end
	if i == CH_I and j == CH_J then return "Stone Bricks" end
	if i >= 23 and i <= 31 and j >= 1 and j <= 12 then return "Smooth Stone" end
	return "Oak Planks"
end

step("floor2", function()
	fill(0, 0, 32, 26, Y_SLAB2, function(i, j)
		if j == 13 and (i == 5 or i == 6 or i == 7) then return nil end
		return slab2Mat(i, j)
	end)
end)

-- Наружные стены 2 этажа
local function extFront2(j, k)
	if PIL_GABLE[j] then return "Quartz" end
	if WIN_FRONT[j] and (k == 1 or k == 2) then return "Glass" end
	return "White Brick"
end

local function extBack2(j, k)
	if j == 13 then
		if k == 0 or k == 1 then return nil end
		return "White Brick"
	end
	if PIL_GABLE[j] then return "Quartz" end
	if WIN_BACK[j] and (k == 1 or k == 2) then return "Glass" end
	return "White Brick"
end

step("extwalls2", function()
	wallX(0, 0, 32, 0, 3, yW2, extLong)
	wallX(26, 0, 32, 0, 3, yW2, extLong)
	wallZ(0, 1, 25, 0, 3, yW2, extFront2)
	wallZ(32, 1, 25, 0, 3, yW2, extBack2)
	doorAt(32, 13, Y_DOOR2, PI / 2)
end)

-- Внутренние стены 2 этажа
step("intwalls2", function()
	wallZ(10, 1, 25, 0, 3, yW2, function(j, k)
		if (j == 8 or j == 18) and (k == 0 or k == 1) then return nil end
		return intMat(j, k)
	end)
	doorAt(10, 8, Y_DOOR2, PI / 2)
	doorAt(10, 18, Y_DOOR2, PI / 2)

	wallZ(22, 1, 25, 0, 3, yW2, function(j, k)
		if (j == 8 or j == 18) and (k == 0 or k == 1) then return nil end
		return intMat(j, k)
	end)
	doorAt(22, 8, Y_DOOR2, PI / 2)
	doorAt(22, 18, Y_DOOR2, PI / 2)

	wallX(13, 11, 21, 0, 3, yW2, function(i, k)
		if i == 16 and (k == 0 or k == 1) then return nil end
		return intMat(i, k)
	end)
	doorAt(16, 13, Y_DOOR2, 0)

	wallX(13, 23, 31, 0, 3, yW2, function(i, k)
		if (i == 26 or i == 27) and (k == 0 or k == 1) then return nil end
		return intMat(i, k)
	end)

	wallX(6, 1, 9, 0, 3, yW2, function(i, k)
		if i == 5 and (k == 0 or k == 1) then return nil end
		return intMat(i, k)
	end)
	doorAt(5, 6, Y_DOOR2, 0)

	wallX(20, 1, 9, 0, 3, yW2, function(i, k)
		if i == 5 and (k == 0 or k == 1) then return nil end
		return intMat(i, k)
	end)
	doorAt(5, 20, Y_DOOR2, 0)
end)

-- Чердачное перекрытие
local function slab3Mat(i, j)
	if i == 0 or i == 32 or j == 0 or j == 26 then return "Spruce Log" end
	if i == CH_I and j == CH_J then return "Stone Bricks" end
	return "Oak Planks"
end

step("floor3", function()
	fill(0, 0, 32, 26, Y_SLAB3, slab3Mat)
end)

-- Кровля
step("roof", function()
	for k = 0, 13 do
		local jS, jN = k, 26 - k
		for i = 0, 32 do
			if not (i == CH_I and jS == CH_J) then
				planPlace("Red Brick Stairs", cx(i), yRoof(k), cz(jS), PI / 2)
			end
			if jN ~= jS and not (i == CH_I and jN == CH_J) then
				planPlace("Red Brick Stairs", cx(i), yRoof(k), cz(jN), -PI / 2)
			end
		end
	end
end)

-- Фронтоны
step("gables", function()
	for _, iEnd in {0, 32} do
		for k = 0, 12 do
			for j = k + 1, 25 - k do
				planPlace("White Brick", cx(iEnd), yRoof(k), cz(j))
			end
		end
	end
end)

-- Камин
step("chimney", function()
	planPlace("Stone Bricks", cx(CH_I), Y_FLOOR, cz(CH_J))
	for k = 0, 3 do planPlace("Stone Bricks", cx(CH_I), yW1(k), cz(CH_J)) end
	planPlace("Stone Bricks", cx(CH_I), Y_SLAB2, cz(CH_J))
	for k = 0, 3 do planPlace("Stone Bricks", cx(CH_I), yW2(k), cz(CH_J)) end
	planPlace("Stone Bricks", cx(CH_I), Y_SLAB3, cz(CH_J))
	for k = 0, 9 do planPlace("Stone Bricks", cx(CH_I), yRoof(k), cz(CH_J)) end
end)

-- Крыльцо
step("porch", function()
	fill(-4, 9, -1, 17, Y_FLOOR, "Stone Bricks")
	for _, j in {11, 15} do
		for k = 0, 3 do planPlace("Quartz", cx(-1), yW1(k), cz(j)) end
	end
	planPlace("Lamp", cx(-1), yW1(0), cz(12))
	planPlace("Lamp", cx(-1), yW1(0), cz(14))
	fill(-1, 11, -1, 15, Y_SLAB2, "Quartz")
	for j = 9, 17 do
		planPlace("Stone Stairs", cx(-5), Y_FLOOR, cz(j), PI)
	end
end)

-- Балкон
step("balcony", function()
	fill(33, 10, 34, 16, Y_SLAB2, "Stone Bricks")
	for j = 10, 16 do planPlace("Quartz", cx(34), yW2(0), cz(j)) end
	planPlace("Quartz", cx(33), yW2(0), cz(10))
	planPlace("Quartz", cx(33), yW2(0), cz(16))
end)

-- Мебель 1 этаж
step("furniture1", function()
	planPlace("Lamp", cx(1), Y_F1, cz(7))
	planPlace("Lamp", cx(9), Y_F1, cz(19))
	planPlace("Table", cx(2), Y_F1, cz(17))
	planPlace("Table", cx(4), Y_F1, cz(3))
	planPlace("Chair", cx(4), Y_F1, cz(5), PI)
	planPlace("BookShelf", cx(1), Y_F1, cz(2))
	planPlace("Lamp", cx(9), Y_F1, cz(4))
	planPlace("Lamp", cx(2), Y_F1, cz(22))
	planPlace("Crate", cx(8), Y_F1, cz(24))
	planPlace("Table", cx(16), Y_F1, cz(6))
	planPlace("Armchair", cx(16), Y_F1, cz(8), PI)
	planPlace("Armchair", cx(13), Y_F1, cz(6), PI / 2)
	planPlace("Armchair", cx(19), Y_F1, cz(6), -PI / 2)
	planPlace("BookShelf", cx(11), Y_F1, cz(2))
	planPlace("Lamp", cx(21), Y_F1, cz(11))
	planPlace("Table", cx(16), Y_F1, cz(20))
	planPlace("Chair", cx(16), Y_F1, cz(22), PI)
	planPlace("Chair", cx(16), Y_F1, cz(18), 0)
	planPlace("Chair", cx(14), Y_F1, cz(20), PI / 2)
	planPlace("Chair", cx(18), Y_F1, cz(20), -PI / 2)
	planPlace("Lamp", cx(11), Y_F1, cz(25))
	planPlace("BookShelf", cx(31), Y_F1, cz(1))
	planPlace("BookShelf", cx(31), Y_F1, cz(2))
	planPlace("BookShelf", cx(23), Y_F1, cz(12))
	planPlace("Armchair", cx(27), Y_F1, cz(8), 0)
	planPlace("Lamp", cx(24), Y_F1, cz(1))
	planPlace("Table", cx(27), Y_F1, cz(20))
	planPlace("Chair", cx(27), Y_F1, cz(22), PI)
	planPlace("Chair", cx(27), Y_F1, cz(18), 0)
	planPlace("Chair", cx(25), Y_F1, cz(20), PI / 2)
	planPlace("Chair", cx(29), Y_F1, cz(20), -PI / 2)
	planPlace("Crate", cx(31), Y_F1, cz(14))
	planPlace("Crate", cx(31), Y_F1, cz(15))
	planPlace("Lamp", cx(24), Y_F1, cz(25))
end)

-- Мебель 2 этаж
step("furniture2", function()
	planPlace("Lamp", cx(1), Y_F2, cz(7))
	planPlace("Lamp", cx(9), Y_F2, cz(19))
	planPlace("BookShelf", cx(9), Y_F2, cz(17))
	planPlace("Bed", cx(3), Y_F2, cz(1) + 1.5, 0)
	planPlace("Lamp", cx(8), Y_F2, cz(4))
	planPlace("Bed", cx(3), Y_F2, cz(24) + 1.5, PI)
	planPlace("Lamp", cx(8), Y_F2, cz(22))
	planPlace("Bed", cx(14), Y_F2, cz(1) + 1.5, 0)
	planPlace("Table", cx(20), Y_F2, cz(11))
	planPlace("Lamp", cx(11), Y_F2, cz(12))
	planPlace("Bed", cx(18), Y_F2, cz(24) + 1.5, PI)
	planPlace("Lamp", cx(11), Y_F2, cz(15))
	planPlace("Lamp", cx(24), Y_F2, cz(2))
	planPlace("Crate", cx(31), Y_F2, cz(1))
	planPlace("BookShelf", cx(23), Y_F2, cz(12))
	planPlace("Bed", cx(27), Y_F2, cz(24) + 1.5, PI)
	planPlace("Table", cx(31), Y_F2, cz(16))
	planPlace("Lamp", cx(23), Y_F2, cz(15))
end)

-- Участок
step("land", function()
	for i = -6, -14, -1 do
		planPlace("Smooth Stone", cx(i), FY - 1.5, cz(13))
	end
	planPlace("Lamp", cx(-7), Y_FLOOR, cz(11))
	planPlace("Lamp", cx(-7), Y_FLOOR, cz(15))
	for _, j in {-2, 28} do
		for _, i in {5, 16, 27} do
			planPlace("Oak Leaves", cx(i), Y_FLOOR, cz(j))
		end
		for _, i in {8, 13, 20, 25} do
			planPlace(if (i + j) % 2 == 0 then "Rose Flower" else "Dandelion Flower", cx(i), Y_FLOOR, cz(j))
		end
	end
	for _, i in {-8, 40} do
		for _, j in {6, 20} do
			planPlace("Oak Leaves", cx(i), Y_FLOOR, cz(j))
		end
	end
end)

print(("[Mansion] План готов: %d блоков"):format(#plan))

--------------------------------------------------------------------------
-- 5. ИСПОЛНЕНИЕ ПЛАНА (моментально + телепорт)
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

	-- Телепорт к блоку
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
			warn("[Mansion] СТОП: сервер ответил " .. tostring(res))
			return false, true -- aborted
		end
		return false
	end
end

print("[Mansion] Начинаю стройку...")

local aborted = false
for i, info in ipairs(plan) do
	local success, isAbort = executeBlock(info)
	if isAbort then
		aborted = true
		break
	end
	if not success then
		table.insert(missing, info)
	end
end

print(("[Mansion] Основная стройка: отправлено=%d успешно=%d ошибок=%d"):format(sent, okCount, failCount))

--------------------------------------------------------------------------
-- 6. ДОСТРОЙКА ПРОПУСКОВ
--------------------------------------------------------------------------

for pass = 1, REPAIR_PASSES do
	if #missing == 0 or aborted then break end

	print(("[Mansion] Ремонтный проход %d/%d — осталось %d блоков"):format(pass, REPAIR_PASSES, #missing))

	local stillMissing = {}
	for _, info in ipairs(missing) do
		if aborted then break end
		local success, isAbort = executeBlock(info)
		if isAbort then
			aborted = true
			break
		end
		if not success then
			table.insert(stillMissing, info)
		end
	end
	missing = stillMissing
end

--------------------------------------------------------------------------
-- 7. Итог
--------------------------------------------------------------------------

print(("[Mansion] ГОТОВО: всего в плане=%d  успешно=%d  осталось пропусков=%d")
	:format(#plan, okCount, #missing))

pcall(function()
	if IS_FUNC then
		Change:InvokeServer("MansionDone")
	else
		Change:FireServer("MansionDone")
	end
end)
