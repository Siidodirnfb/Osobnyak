--[[
	MansionBuilder — версия с телепортом игрока к каждому блоку
	=================================================================
	Основан на оригинальном скрипте.
	• Нет искусственных задержек — стройка моментальная
	• Перед каждой установкой блока LocalPlayer телепортируется
	  рядом с точкой размещения (решает проблему дистанции)
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

-- выборочный прогон секций (для достройки)
local RUN = { all = true }

local sent, okCount, failCount, aborted = 0, 0, 0, false
local bad, failLog = 0, 0

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

local order = 0
local function step(name, fn)
	order += 1
	if not (RUN.all or RUN[name]) then
		print(("[Mansion] [%02d] %s — пропуск"):format(order, name))
		return
	end
	print(("[Mansion] [%02d] %s ..."):format(order, name))
	fn()
	print(("[Mansion] [%02d] %s ok (успешно=%d ошибок=%d)"):format(order, name, okCount, failCount))
end

--------------------------------------------------------------------------
-- 1. Математика сетки (обратная к логике сервера)
--------------------------------------------------------------------------

local EXACT_SPECIAL = {
	Ladder = true,
	Chair = true,
	Bed = true,
	Armchair = true,
	Verity = true,
	Keycap = true,
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

-- hrp будет заполнен позже, после получения персонажа
local hrp: BasePart? = nil

--- Один вызов ремоута = один блок. Ошибки не роняют стройку.
local function place(name: string, x: number, y: number, z: number, yaw: number?)
	if aborted then
		return
	end
	yaw = yaw or 0
	local H, D = dims(name)
	local special = isSpecial(name)
	if not special then
		yaw = 0
	end

	local finalYaw = math.round(yaw / (PI / 2)) * (PI / 2)
	local camYaw = if special then finalYaw - rotOffset(name) else 0
	local cameraCFrame = CFrame.Angles(0, camYaw, 0)
	local rotation = if special then CFrame.Angles(0, finalYaw, 0) else CFrame.new()

	local world = rotation:VectorToWorldSpace(Vector3.new(3, H, D))
	local offX = if math.round(math.abs(world.X) / 3) % 2 == 0 then 1.5 else 0
	local offZ = if math.round(math.abs(world.Z) / 3) % 2 == 0 then 1.5 else 0

	local hitPos = Vector3.new(x, y - H / 2, z)

	-- контроль достижимости точки (без лишних вызовов ремоута)
	local rx = math.round((x - offX) / 3) * 3 + offX
	local rz = math.round((z - offZ) / 3) * 3 + offZ
	local ry = math.round((y - H / 2) / 3) * 3 + H / 2
	if math.abs(rx - x) > 0.01 or math.abs(rz - z) > 0.01 or math.abs(ry - y) > 0.01 then
		bad += 1
		if bad <= 12 then
			warn(("[Mansion] не достижимо: %s want(%.2f,%.2f,%.2f) -> got(%.2f,%.2f,%.2f)")
				:format(name, x, y, z, rx, ry, rz))
		end
	end

	-- Телепорт игрока рядом с точкой размещения (решает проблему дистанции)
	if hrp and hrp.Parent then
		hrp.CFrame = CFrame.new(hitPos + Vector3.new(0, 5, 0))
	end

	local ok, res = sendPlace(hitPos, cameraCFrame, name)
	sent += 1
	if ok and (res == true or res == nil) then
		okCount += 1
	else
		failCount += 1
		if failLog < 12 then
			failLog += 1
			warn(("[Mansion] блок не встал: %s (ответ: %s)"):format(name, tostring(res)))
		end
		if res == "Limit" or res == "Height" then
			aborted = true
			warn(("[Mansion] СТОП: сервер ответил " .. tostring(res)))
			return
		end
	end
end

--------------------------------------------------------------------------
-- 2. Точка привязки — позиция игрока Prime_Neuer
--------------------------------------------------------------------------

local lp = Players.LocalPlayer

local function waitForCharacter(player: any, timeout: number): Model?
	if player == nil then
		return nil
	end
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if player.Character then
			return player.Character
		end
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

-- Получаем HumanoidRootPart локального игрока (именно его будем телепортировать)
local localChar = lp.Character or waitForCharacter(lp, 30)
assert(localChar, "[Mansion] локальный персонаж не найден")
hrp = localChar:WaitForChild("HumanoidRootPart", 15) :: BasePart?
assert(hrp, "[Mansion] HumanoidRootPart локального игрока не найден")

-- На всякий случай также ждём HRP целевого персонажа (для расчёта позиции особняка)
local targetHrp: BasePart? = nil
while not targetHrp do
	targetHrp = char:WaitForChild("HumanoidRootPart", 15) :: BasePart?
	if not targetHrp then
		print("[Mansion] жду HumanoidRootPart целевого персонажа...")
		local alt: Model? = waitForCharacter(lp, 30)
		if alt and alt ~= char then
			char = alt
		end
		task.wait(1)
	end
end

local exclude: { Instance } = { char }
local myChar = lp.Character
if myChar and myChar ~= char then
	table.insert(exclude, myChar)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = exclude

local ray = workspace:Raycast(targetHrp.Position + Vector3.new(0, 4, 0), Vector3.new(0, -90, 0), rayParams)
local feetY = if ray then ray.Position.Y else targetHrp.Position.Y - 3

local OX = math.round(targetHrp.Position.X / 3) * 3 -- центр особняка по X
local OZ = math.round(targetHrp.Position.Z / 3) * 3 -- центр особняка по Z
local FY = math.round(feetY / 3) * 3          -- отметка земли (кратна 3)

print(("[Mansion] игрок=%s  origin=(%d, %d, %d)  цоколь=%d")
	:format(char.Name, OX, FY, OZ, FY + 3))

--------------------------------------------------------------------------
-- 3. Сетка: клетки 33 x 27 (99 x 81 стад), слои по высоте
--------------------------------------------------------------------------

local function cx(i: number): number
	return OX + (i - 16) * 3
end

local function cz(j: number): number
	return OZ + (j - 13) * 3
end

local Y_FLOOR = FY + 1.5          -- пол 1 этажа (кромка FY..FY+3)
local function yW1(k: number): number -- стены 1 этажа, k = 0..3  (FY+3..FY+15)
	return FY + 4.5 + 3 * k
end
local Y_SLAB2 = FY + 16.5          -- перекрытие (FY+15..FY+18)
local function yW2(k: number): number -- стены 2 этажа, k = 0..3  (FY+18..FY+30)
	return FY + 19.5 + 3 * k
end
local Y_SLAB3 = FY + 31.5          -- чердачное перекрытие (FY+30..FY+33)
local function yRoof(k: number): number -- кровля, k = 0..13 (FY+33..FY+75)
	return FY + 34.5 + 3 * k
end
local Y_DOOR1 = FY + 6             -- дверь 1 этажа (FY+3..FY+9)
local Y_DOOR2 = FY + 21            -- дверь 2 этажа (FY+18..FY+24)

local Y_F1 = yW1(0)                -- предметы, стоящие на полу 1 этажа
local Y_F2 = yW2(0)                -- предметы, стоящие на полу 2 этажа

local CH_I, CH_J = 28, 6           -- колодец камина

-- маленькие помощники -------------------------------------------------

local function resolve(mat, a: number, b: number)
	if typeof(mat) == "string" then
		return mat
	end
	return mat(a, b)
end

--- прямоугольная заливка в горизонтальной плоскости
local function fill(i1: number, j1: number, i2: number, j2: number, y: number, mat)
	for i = i1, i2 do
		for j = j1, j2 do
			local m = resolve(mat, i, j)
			if m then
				place(m, cx(i), y, cz(j))
			end
		end
	end
end

--- стена вдоль Z (фиксированная i), слои k1..k2; mat(j, k) может вернуть nil
local function wallZ(i: number, j1: number, j2: number, k1: number, k2: number, yfn, mat)
	for j = j1, j2 do
		for k = k1, k2 do
			local m = resolve(mat, j, k)
			if m then
				place(m, cx(i), yfn(k), cz(j))
			end
		end
	end
end

--- стена вдоль X (фиксированная j); mat(i, k) может вернуть nil
local function wallX(j: number, i1: number, i2: number, k1: number, k2: number, yfn, mat)
	for i = i1, i2 do
		for k = k1, k2 do
			local m = resolve(mat, i, k)
			if m then
				place(m, cx(i), yfn(k), cz(j))
			end
		end
	end
end

local function doorAt(i: number, j: number, y: number, yaw: number)
	place("Oak Door", cx(i), y, cz(j), yaw)
end

local function intMat(_: number, k: number)
	if k == 0 then
		return "Quartz" -- плинтус
	end
	return "White Brick"
end

--------------------------------------------------------------------------
-- 4. Пол 1 этажа
--------------------------------------------------------------------------

local function groundFloorMat(i: number, j: number)
	if i == 0 or i == 32 or j == 0 or j == 26 then
		return "Stone Bricks" -- цоколь по периметру
	end
	if i == CH_I and j == CH_J then
		return "Stone Bricks" -- очаг камина
	end
	if i >= 23 and i <= 31 and j >= 14 and j <= 25 then
		return "Smooth Stone" -- кухня-столовая
	end
	if i >= 1 and i <= 9 and j >= 21 and j <= 25 then
		return "Smooth Stone" -- санузел
	end
	return "Oak Planks"
end

step("floor1", function()
	fill(0, 0, 32, 26, Y_FLOOR, groundFloorMat)
end)

--------------------------------------------------------------------------
-- 5. Наружные стены 1 этажа
--------------------------------------------------------------------------

local WIN_LONG = { [3] = true, [8] = true, [13] = true, [18] = true, [23] = true, [28] = true }
local WIN_FRONT = { [4] = true, [8] = true, [18] = true, [22] = true }
local WIN_BACK = { [4] = true, [8] = true, [13] = true, [18] = true, [22] = true }
local PIL_LONG = { [11] = true, [22] = true }
local PIL_GABLE = { [6] = true, [20] = true }

local function extLong(i: number, k: number)
	if i == 0 or i == 32 then
		return "Quartz" -- угловые пилястры
	end
	if PIL_LONG[i] then
		return "Quartz"
	end
	if WIN_LONG[i] and (k == 1 or k == 2) then
		return "Glass"
	end
	return "White Brick"
end

local function extFront1(j: number, k: number)
	if j == 13 then
		if k == 0 or k == 1 then
			return nil -- проём под входную дверь
		end
		return "White Brick"
	end
	if PIL_GABLE[j] then
		return "Quartz"
	end
	if WIN_FRONT[j] and (k == 1 or k == 2) then
		return "Glass"
	end
	return "White Brick"
end

local function extBack1(j: number, k: number)
	if PIL_GABLE[j] then
		return "Quartz"
	end
	if WIN_BACK[j] and (k == 1 or k == 2) then
		return "Glass"
	end
	return "White Brick"
end

step("extwalls1", function()
	wallX(0, 0, 32, 0, 3, yW1, extLong)   -- южный фасад
	wallX(26, 0, 32, 0, 3, yW1, extLong)  -- северный фасад
	wallZ(0, 1, 25, 0, 3, yW1, extFront1) -- западный фасад (вход)
	wallZ(32, 1, 25, 0, 3, yW1, extBack1) -- восточный фасад
	doorAt(0, 13, Y_DOOR1, -PI / 2) -- входная дверь, лицом наружу
end)

--------------------------------------------------------------------------
-- 6. Внутренние стены 1 этажа
--------------------------------------------------------------------------

step("intwalls1", function()
	-- продольный разрез i = 10 (холл / средний блок)
	wallZ(10, 1, 25, 0, 3, yW1, function(j, k)
		if (j == 8 or j == 18) and (k == 0 or k == 1) then
			return nil
		end
		return intMat(j, k)
	end)
	doorAt(10, 8, Y_DOOR1, PI / 2)
	doorAt(10, 18, Y_DOOR1, PI / 2)

	-- продольный разрез i = 22 (средний блок / восточный блок)
	wallZ(22, 1, 25, 0, 3, yW1, function(j, k)
		if (j == 8 or j == 18) and (k == 0 or k == 1) then
			return nil
		end
		return intMat(j, k)
	end)
	doorAt(22, 8, Y_DOOR1, PI / 2)
	doorAt(22, 18, Y_DOOR1, PI / 2)

	-- поперечная стена j = 13 в среднем блоке
	wallX(13, 11, 21, 0, 3, yW1, function(i, k)
		if i == 16 and (k == 0 or k == 1) then
			return nil
		end
		return intMat(i, k)
	end)
	doorAt(16, 13, Y_DOOR1, 0)

	-- поперечная стена j = 13 в восточном блоке (широкая арка)
	wallX(13, 23, 31, 0, 3, yW1, function(i, k)
		if (i == 26 or i == 27) and (k == 0 or k == 1) then
			return nil
		end
		return intMat(i, k)
	end)

	-- перегородки западного блока (кабинет / санузел)
	wallX(6, 1, 9, 0, 3, yW1, function(i, k)
		if i == 5 and (k == 0 or k == 1) then
			return nil
		end
		return intMat(i, k)
	end)
	doorAt(5, 6, Y_DOOR1, 0)

	wallX(20, 1, 9, 0, 3, yW1, function(i, k)
		if i == 5 and (k == 0 or k == 1) then
			return nil
		end
		return intMat(i, k)
	end)
	doorAt(5, 20, Y_DOOR1, 0)
end)

--------------------------------------------------------------------------
-- 7. Лестница 1 -> 2 этаж (подъём в +X по холлу, j = 13)
--------------------------------------------------------------------------

step("stairs", function()
	for n = 0, 4 do
		local y = if n < 4 then yW1(n) else Y_SLAB2
		place("Oak Stairs", cx(3 + n), y, cz(13), PI)
	end
end)

--------------------------------------------------------------------------
-- 8. Перекрытие 2 этажа (с проёмом под лестницу)
--------------------------------------------------------------------------

local function slab2Mat(i: number, j: number)
	if i == 0 or i == 32 or j == 0 or j == 26 then
		return "Quartz" -- карниз под стенами 2 этажа
	end
	if i == CH_I and j == CH_J then
		return "Stone Bricks"
	end
	if i >= 23 and i <= 31 and j >= 1 and j <= 12 then
		return "Smooth Stone" -- ванная
	end
	return "Oak Planks"
end

step("floor2", function()
	fill(0, 0, 32, 26, Y_SLAB2, function(i, j)
		if j == 13 and (i == 5 or i == 6 or i == 7) then
			return nil -- лестничный проём
		end
		return slab2Mat(i, j)
	end)
end)

--------------------------------------------------------------------------
-- 9. Наружные стены 2 этажа
--------------------------------------------------------------------------

local function extFront2(j: number, k: number)
	if PIL_GABLE[j] then
		return "Quartz"
	end
	if WIN_FRONT[j] and (k == 1 or k == 2) then
		return "Glass"
	end
	return "White Brick"
end

local function extBack2(j: number, k: number)
	if j == 13 then
		if k == 0 or k == 1 then
			return nil -- выход на балкон
		end
		return "White Brick"
	end
	if PIL_GABLE[j] then
		return "Quartz"
	end
	if WIN_BACK[j] and (k == 1 or k == 2) then
		return "Glass"
	end
	return "White Brick"
end

step("extwalls2", function()
	wallX(0, 0, 32, 0, 3, yW2, extLong)
	wallX(26, 0, 32, 0, 3, yW2, extLong)
	wallZ(0, 1, 25, 0, 3, yW2, extFront2)
	wallZ(32, 1, 25, 0, 3, yW2, extBack2)
	doorAt(32, 13, Y_DOOR2, PI / 2) -- дверь на балкон
end)

--------------------------------------------------------------------------
-- 10. Внутренние стены 2 этажа (та же планировка)
--------------------------------------------------------------------------

step("intwalls2", function()
	wallZ(10, 1, 25, 0, 3, yW2, function(j, k)
		if (j == 8 or j == 18) and (k == 0 or k == 1) then
			return nil
		end
		return intMat(j, k)
	end)
	doorAt(10, 8, Y_DOOR2, PI / 2)
	doorAt(10, 18, Y_DOOR2, PI / 2)

	wallZ(22, 1, 25, 0, 3, yW2, function(j, k)
		if (j == 8 or j == 18) and (k == 0 or k == 1) then
			return nil
		end
		return intMat(j, k)
	end)
	doorAt(22, 8, Y_DOOR2, PI / 2)
	doorAt(22, 18, Y_DOOR2, PI / 2)

	wallX(13, 11, 21, 0, 3, yW2, function(i, k)
		if i == 16 and (k == 0 or k == 1) then
			return nil
		end
		return intMat(i, k)
	end)
	doorAt(16, 13, Y_DOOR2, 0)

	wallX(13, 23, 31, 0, 3, yW2, function(i, k)
		if (i == 26 or i == 27) and (k == 0 or k == 1) then
			return nil
		end
		return intMat(i, k)
	end)

	wallX(6, 1, 9, 0, 3, yW2, function(i, k)
		if i == 5 and (k == 0 or k == 1) then
			return nil
		end
		return intMat(i, k)
	end)
	doorAt(5, 6, Y_DOOR2, 0)

	wallX(20, 1, 9, 0, 3, yW2, function(i, k)
		if i == 5 and (k == 0 or k == 1) then
			return nil
		end
		return intMat(i, k)
	end)
	doorAt(5, 20, Y_DOOR2, 0)
end)

--------------------------------------------------------------------------
-- 11. Чердачное перекрытие
--------------------------------------------------------------------------

local function slab3Mat(i: number, j: number)
	if i == 0 or i == 32 or j == 0 or j == 26 then
		return "Spruce Log" -- тёмный карниз под свесом кровли
	end
	if i == CH_I and j == CH_J then
		return "Stone Bricks"
	end
	return "Oak Planks"
end

step("floor3", function()
	fill(0, 0, 32, 26, Y_SLAB3, slab3Mat)
end)

--------------------------------------------------------------------------
-- 12. Двускатная кровля (Red Brick Stairs, уклон 45°)
--     конёк вдоль X (33 клетки), пролёт 27 клеток -> подъём 13 клеток
--------------------------------------------------------------------------

step("roof", function()
	for k = 0, 13 do
		local jS = k            -- южный скат: подъём в +Z
		local jN = 26 - k       -- северный скат: подъём в -Z
		for i = 0, 32 do
			if not (i == CH_I and jS == CH_J) then
				place("Red Brick Stairs", cx(i), yRoof(k), cz(jS), PI / 2)
			end
			if jN ~= jS and not (i == CH_I and jN == CH_J) then
				place("Red Brick Stairs", cx(i), yRoof(k), cz(jN), -PI / 2)
			end
		end
	end
end)

--------------------------------------------------------------------------
-- 13. Фронтоны (треугольные стены на торцах)
--------------------------------------------------------------------------

step("gables", function()
	for _, iEnd in { 0, 32 } do
		for k = 0, 12 do
			for j = k + 1, 25 - k do
				place("White Brick", cx(iEnd), yRoof(k), cz(j))
			end
		end
	end
end)

--------------------------------------------------------------------------
-- 14. Камин: сквозной колодец в (28, 6)
--------------------------------------------------------------------------

step("chimney", function()
	place("Stone Bricks", cx(CH_I), Y_FLOOR, cz(CH_J))
	for k = 0, 3 do
		place("Stone Bricks", cx(CH_I), yW1(k), cz(CH_J))
	end
	place("Stone Bricks", cx(CH_I), Y_SLAB2, cz(CH_J))
	for k = 0, 3 do
		place("Stone Bricks", cx(CH_I), yW2(k), cz(CH_J))
	end
	place("Stone Bricks", cx(CH_I), Y_SLAB3, cz(CH_J))
	for k = 0, 9 do
		place("Stone Bricks", cx(CH_I), yRoof(k), cz(CH_J))
	end
end)

--------------------------------------------------------------------------
-- 15. Крыльцо: терраса, колонны, фонари, навес, ступени
--------------------------------------------------------------------------

step("porch", function()
	fill(-4, 9, -1, 17, Y_FLOOR, "Stone Bricks") -- терраса

	for _, j in { 11, 15 } do                    -- колонны портика
		for k = 0, 3 do
			place("Quartz", cx(-1), yW1(k), cz(j))
		end
	end

	place("Lamp", cx(-1), yW1(0), cz(12)) -- фонари у двери
	place("Lamp", cx(-1), yW1(0), cz(14))

	fill(-1, 11, -1, 15, Y_SLAB2, "Quartz") -- навес

	for j = 9, 17 do                         -- ступени с террасы
		place("Stone Stairs", cx(-5), Y_FLOOR, cz(j), PI)
	end
end)

--------------------------------------------------------------------------
-- 16. Балкон на восточном торце (2 этаж)
--------------------------------------------------------------------------

step("balcony", function()
	fill(33, 10, 34, 16, Y_SLAB2, "Stone Bricks")
	for j = 10, 16 do
		place("Quartz", cx(34), yW2(0), cz(j))
	end
	place("Quartz", cx(33), yW2(0), cz(10))
	place("Quartz", cx(33), yW2(0), cz(16))
end)

--------------------------------------------------------------------------
-- 17. Мебель и свет — 1 этаж
--------------------------------------------------------------------------

step("furniture1", function()
	-- холл
	place("Lamp", cx(1), Y_F1, cz(7))
	place("Lamp", cx(9), Y_F1, cz(19))
	place("Table", cx(2), Y_F1, cz(17))

	-- кабинет (i=1..9, j=1..5)
	place("Table", cx(4), Y_F1, cz(3))
	place("Chair", cx(4), Y_F1, cz(5), PI)
	place("BookShelf", cx(1), Y_F1, cz(2))
	place("Lamp", cx(9), Y_F1, cz(4))

	-- санузел / кладовая (i=1..9, j=21..25)
	place("Lamp", cx(2), Y_F1, cz(22))
	place("Crate", cx(8), Y_F1, cz(24))

	-- гостиная (i=11..21, j=1..12)
	place("Table", cx(16), Y_F1, cz(6))
	place("Armchair", cx(16), Y_F1, cz(8), PI)
	place("Armchair", cx(13), Y_F1, cz(6), PI / 2)
	place("Armchair", cx(19), Y_F1, cz(6), -PI / 2)
	place("BookShelf", cx(11), Y_F1, cz(2))
	place("Lamp", cx(21), Y_F1, cz(11))

	-- столовая (i=11..21, j=14..25)
	place("Table", cx(16), Y_F1, cz(20))
	place("Chair", cx(16), Y_F1, cz(22), PI)
	place("Chair", cx(16), Y_F1, cz(18), 0)
	place("Chair", cx(14), Y_F1, cz(20), PI / 2)
	place("Chair", cx(18), Y_F1, cz(20), -PI / 2)
	place("Lamp", cx(11), Y_F1, cz(25))

	-- библиотека (i=23..31, j=1..12)
	place("BookShelf", cx(31), Y_F1, cz(1))
	place("BookShelf", cx(31), Y_F1, cz(2))
	place("BookShelf", cx(23), Y_F1, cz(12))
	place("Armchair", cx(27), Y_F1, cz(8), 0)
	place("Lamp", cx(24), Y_F1, cz(1))

	-- кухня-столовая (i=23..31, j=14..25)
	place("Table", cx(27), Y_F1, cz(20))
	place("Chair", cx(27), Y_F1, cz(22), PI)
	place("Chair", cx(27), Y_F1, cz(18), 0)
	place("Chair", cx(25), Y_F1, cz(20), PI / 2)
	place("Chair", cx(29), Y_F1, cz(20), -PI / 2)
	place("Crate", cx(31), Y_F1, cz(14))
	place("Crate", cx(31), Y_F1, cz(15))
	place("Lamp", cx(24), Y_F1, cz(25))
end)

--------------------------------------------------------------------------
-- 18. Мебель и свет — 2 этаж (6 комнат)
--------------------------------------------------------------------------

step("furniture2", function()
	-- площадка лестницы
	place("Lamp", cx(1), Y_F2, cz(7))
	place("Lamp", cx(9), Y_F2, cz(19))
	place("BookShelf", cx(9), Y_F2, cz(17))

	-- спальня запад-север
	place("Bed", cx(3), Y_F2, cz(1) + 1.5, 0)
	place("Lamp", cx(8), Y_F2, cz(4))

	-- спальня запад-юг
	place("Bed", cx(3), Y_F2, cz(24) + 1.5, PI)
	place("Lamp", cx(8), Y_F2, cz(22))

	-- спальня средняя-север
	place("Bed", cx(14), Y_F2, cz(1) + 1.5, 0)
	place("Table", cx(20), Y_F2, cz(11))
	place("Lamp", cx(11), Y_F2, cz(12))

	-- спальня средняя-юг
	place("Bed", cx(18), Y_F2, cz(24) + 1.5, PI)
	place("Lamp", cx(11), Y_F2, cz(15))

	-- ванная (восток-север)
	place("Lamp", cx(24), Y_F2, cz(2))
	place("Crate", cx(31), Y_F2, cz(1))
	place("BookShelf", cx(23), Y_F2, cz(12))

	-- спальня восток-юг
	place("Bed", cx(27), Y_F2, cz(24) + 1.5, PI)
	place("Table", cx(31), Y_F2, cz(16))
	place("Lamp", cx(23), Y_F2, cz(15))
end)

--------------------------------------------------------------------------
-- 19. Участок: дорожка, кусты, цветы, фонари
--------------------------------------------------------------------------

step("land", function()
	for i = -6, -14, -1 do
		place("Smooth Stone", cx(i), FY - 1.5, cz(13)) -- дорожка в уровень земли
	end

	place("Lamp", cx(-7), Y_FLOOR, cz(11))
	place("Lamp", cx(-7), Y_FLOOR, cz(15))

	for _, j in { -2, 28 } do
		for _, i in { 5, 16, 27 } do
			place("Oak Leaves", cx(i), Y_FLOOR, cz(j))
		end
		for _, i in { 8, 13, 20, 25 } do
			place(if (i + j) % 2 == 0 then "Rose Flower" else "Dandelion Flower", cx(i), Y_FLOOR, cz(j))
		end
	end

	for _, i in { -8, 40 } do
		for _, j in { 6, 20 } do
			place("Oak Leaves", cx(i), Y_FLOOR, cz(j))
		end
	end
end)

--------------------------------------------------------------------------
-- 20. Итог
--------------------------------------------------------------------------

print(("[Mansion] ГОТОВО: отправлено=%d успешно=%d ошибок=%d недостижимых=%d")
	:format(sent, okCount, failCount, bad))
pcall(function()
	if IS_FUNC then
		Change:InvokeServer("MansionDone")
	else
		Change:FireServer("MansionDone")
	end
end)
