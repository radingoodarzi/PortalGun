-- PortalGun (LocalScript only)
-- Put this ONE LocalScript in: StarterPlayer > StarterPlayerScripts
-- Everything runs for the local player: the gun is built in your Backpack,
-- portals are drawn on your screen, and you move your own character
-- (your character's position replicates to the server automatically).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

---------------------------------------------------------------- settings
local TOOL_NAME = "PortalGun"

local COOLDOWN = 1.5            -- seconds between shots
local MAX_DISTANCE = 5000       -- max teleport distance in studs
local AIM_RANGE = 1000
local PORTAL_SIZE = 9           -- portal diameter in studs
local TRAVEL_DELAY = 0.45       -- time between portal opening and the jump
local PORTAL_LIFETIME = 2.5
local SHOT_SOUND_ID = ""        -- optional, e.g. "rbxassetid://123456"

local GREEN = Color3.fromRGB(80, 255, 120)
local GREEN_DEEP = Color3.fromRGB(15, 70, 35)
local GREEN_HOT = Color3.fromRGB(200, 255, 210)
local DARK = Color3.fromRGB(18, 22, 26)
local MID = Color3.fromRGB(34, 40, 46)

-- plasma tube (position is relative to the gun's Handle; gun points toward -Z)
local PLASMA_COUNT = 6
local TUBE_CENTER = CFrame.new(0, 0.47, 0.15)
local TUBE_LENGTH = 1.0
local TUBE_DIAMETER = 0.44
local TUBE_HALF = TUBE_LENGTH / 2 - 0.14

local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder so it lies along the barrel
local BASE_GRIP = CFrame.new(0, -0.45, 0.5)
----------------------------------------------------------------

local player = Players.LocalPlayer

--==============================================================
--  gun model
--==============================================================
local function buildTool()
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.ToolTip = "Click to open a portal"
	tool.CanBeDropped = false
	tool.Grip = BASE_GRIP

	local graphite = Color3.fromRGB(42, 45, 54)
	local black = Color3.fromRGB(22, 23, 28)
	local steel = Color3.fromRGB(165, 170, 180)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.5, 1.8)
	handle.Color = graphite
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local function part(name, size, offset, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Metal
		if shape then
			p.Shape = shape
		end
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = handle.CFrame * offset
		p.Parent = tool
		return p
	end

	local function fixed(name, size, offset, color, material, shape)
		local p = part(name, size, offset, color, material, shape)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	-- grip, trigger guard, stock
	fixed("Grip", Vector3.new(0.36, 0.85, 0.42), CFrame.new(0, -0.6, 0.5) * CFrame.Angles(math.rad(-16), 0, 0), black)
	fixed("GuardBottom", Vector3.new(0.12, 0.08, 0.5), CFrame.new(0, -0.62, 0.02), steel)
	fixed("GuardFront", Vector3.new(0.12, 0.4, 0.08), CFrame.new(0, -0.44, -0.2), steel)
	fixed("Trigger", Vector3.new(0.08, 0.22, 0.08), CFrame.new(0, -0.36, 0.12) * CFrame.Angles(math.rad(20), 0, 0), GREEN, Enum.Material.Neon)
	fixed("Stock", Vector3.new(0.42, 0.42, 0.3), CFrame.new(0, 0.02, 1.0) * CFrame.Angles(math.rad(12), 0, 0), black)

	-- side armour plates and vents
	for _, side in ipairs({ -1, 1 }) do
		fixed("Plate", Vector3.new(0.06, 0.34, 1.2), CFrame.new(0.27 * side, -0.02, 0.05), black)
		for i = 0, 2 do
			fixed("Vent", Vector3.new(0.04, 0.2, 0.08),
				CFrame.new(0.3 * side, -0.02, -0.25 + i * 0.22) * CFrame.Angles(math.rad(25), 0, 0),
				GREEN, Enum.Material.Neon)
		end
	end

	-- barrel with three shrinking emitter rings
	fixed("Barrel", Vector3.new(0.7, 0.34, 0.34), CFrame.new(0, 0, -1.2) * ALONG_Z, steel, nil, Enum.PartType.Cylinder)
	for i = 0, 2 do
		local d = 0.74 - i * 0.13
		fixed("Ring" .. i, Vector3.new(0.07, d, d), CFrame.new(0, 0, -1.05 - i * 0.2) * ALONG_Z, black, nil, Enum.PartType.Cylinder)
		fixed("RingGlow" .. i, Vector3.new(0.03, d - 0.08, d - 0.08), CFrame.new(0, 0, -1.09 - i * 0.2) * ALONG_Z, GREEN, Enum.Material.Neon, Enum.PartType.Cylinder)
	end
	local muzzle = fixed("Muzzle", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0, -1.62), GREEN, Enum.Material.Neon, Enum.PartType.Ball)
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = GREEN
	glow.Range = 6
	glow.Brightness = 1
	glow.Parent = muzzle

	-- plasma tube: clear cylinder on top, held by two steel caps and a cradle
	fixed("Cradle", Vector3.new(0.3, 0.12, TUBE_LENGTH + 0.1), CFrame.new(0, 0.3, 0.15), black)
	local tube = fixed("PlasmaTube", Vector3.new(TUBE_LENGTH, TUBE_DIAMETER, TUBE_DIAMETER), TUBE_CENTER * ALONG_Z, GREEN, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	tube.Transparency = 0.72
	tube.CastShadow = false
	for _, z in ipairs({ -1, 1 }) do
		fixed("TubeCap", Vector3.new(0.1, TUBE_DIAMETER + 0.1, TUBE_DIAMETER + 0.1),
			TUBE_CENTER * CFrame.new(0, 0, z * (TUBE_LENGTH / 2 + 0.04)) * ALONG_Z, steel, nil, Enum.PartType.Cylinder)
	end
	fixed("FeedPipe", Vector3.new(0.5, 0.1, 0.1), CFrame.new(0, 0.3, -0.62) * CFrame.Angles(math.rad(-40), 0, 0) * ALONG_Z, GREEN, Enum.Material.Neon, Enum.PartType.Cylinder)

	-- soft glow and drifting sparks inside the tube
	local mist = fixed("PlasmaMist", Vector3.new(0.22, 0.22, TUBE_LENGTH - 0.2), TUBE_CENTER, GREEN)
	mist.Transparency = 1
	local tubeLight = Instance.new("PointLight")
	tubeLight.Name = "TubeLight"
	tubeLight.Color = GREEN
	tubeLight.Range = 5
	tubeLight.Brightness = 1.5
	tubeLight.Parent = mist
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(GREEN_HOT, GREEN)
	sparks.LightEmission = 1
	sparks.LockedToPart = true
	sparks.Rate = 30
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Speed = NumberRange.new(0.2, 0.7)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.RotSpeed = NumberRange.new(-200, 200)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = mist

	-- plasma blobs, each on its own Weld so we can move it every frame
	local blobs = {}
	for i = 1, PLASMA_COUNT do
		local size = 0.13 + (i % 3) * 0.035
		local blob = part("Plasma" .. i, Vector3.new(size, size, size), TUBE_CENTER,
			(i % 2 == 0) and GREEN_HOT or GREEN, Enum.Material.Neon, Enum.PartType.Ball)
		blob.CastShadow = false
		local weld = Instance.new("Weld")
		weld.Part0 = handle
		weld.Part1 = blob
		weld.C0 = TUBE_CENTER
		weld.Parent = blob
		table.insert(blobs, { part = blob, weld = weld, index = i, baseSize = size })
	end

	local sound
	if SHOT_SOUND_ID ~= "" then
		sound = Instance.new("Sound")
		sound.SoundId = SHOT_SOUND_ID
		sound.Volume = 0.8
		sound.Parent = handle
	end

	return tool, {
		blobs = blobs,
		tubeLight = tubeLight,
		muzzle = muzzle,
		glow = glow,
		sound = sound,
		shotAt = 0,
	}
end

--==============================================================
--  portal effect (only you see it)
--==============================================================
local function makePortal(position, facing)
	local cf = CFrame.lookAt(position, position + facing) * ALONG_Z
	local openInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local closeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local model = Instance.new("Model")
	model.Name = "Portal"

	local function disc(name, color, scale, thickness)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = Vector3.new(thickness, 0.1, 0.1)
		p.CFrame = cf
		p.Parent = model
		TweenService:Create(p, openInfo, { Size = Vector3.new(thickness, PORTAL_SIZE * scale, PORTAL_SIZE * scale) }):Play()
		task.delay(PORTAL_LIFETIME - 0.3, function()
			if p.Parent then
				TweenService:Create(p, closeInfo, { Size = Vector3.new(thickness, 0.1, 0.1) }):Play()
			end
		end)
		return p
	end

	local outer = disc("Outer", GREEN, 1, 0.25)
	disc("Core", GREEN_DEEP, 0.72, 0.3)

	local light = Instance.new("PointLight")
	light.Color = GREEN
	light.Range = 18
	light.Brightness = 2
	light.Parent = outer

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(GREEN)
	sparks.LightEmission = 1
	sparks.Rate = 60
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Speed = NumberRange.new(2, 6)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.RotSpeed = NumberRange.new(-180, 180)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = outer

	model.Parent = Workspace
	Debris:AddItem(model, PORTAL_LIFETIME)
end

--==============================================================
--  state
--==============================================================
local currentTool, gun
local equipped = false
local lastShot = 0
local busy = false
local saved = {}          -- { {name = "...", pos = Vector3}, ... }
local statusLabel

local function setStatus(text)
	if statusLabel then
		statusLabel.Text = text
	end
end

--==============================================================
--  shot animation
--==============================================================
local function playShotAnimation(tool)
	local kick = BASE_GRIP * CFrame.new(0, 0, -0.35) * CFrame.Angles(math.rad(-22), 0, 0)
	local back = TweenService:Create(tool, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Grip = kick })
	local forward = TweenService:Create(tool, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Grip = BASE_GRIP })
	back.Completed:Connect(function()
		if tool.Parent then
			forward:Play()
		end
	end)
	back:Play()

	gun.shotAt = os.clock()

	local flash = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(gun.glow, flash, { Brightness = 8, Range = 16 }):Play()
	TweenService:Create(gun.muzzle, flash, { Size = Vector3.new(0.7, 0.7, 0.7) }):Play()
	if gun.sound then
		gun.sound:Play()
	end
end

--==============================================================
--  moving plasma
--==============================================================
RunService.RenderStepped:Connect(function()
	if not (gun and currentTool and currentTool.Parent) then return end
	local t = os.clock()
	local surge = math.clamp(1 - (t - gun.shotAt) / 0.7, 0, 1)

	for _, blob in ipairs(gun.blobs) do
		local i = blob.index
		local along = math.sin(t * (1.3 + i * 0.45) + i * 1.7) * TUBE_HALF
		local angle = t * (2.2 + i * 0.6) + i
		local radius = 0.05 + 0.03 * math.sin(t * 3 + i) + 0.05 * surge
		blob.weld.C0 = TUBE_CENTER * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, along)
		local s = blob.baseSize * (1 + 0.25 * math.sin(t * 5 + i * 2) + 0.6 * surge)
		blob.part.Size = Vector3.new(s, s, s)
	end
	gun.tubeLight.Brightness = 1.5 + 0.5 * math.sin(t * 7) + 4 * surge
end)

--==============================================================
--  teleport (local)
--==============================================================
local function teleport(target)
	if not equipped or busy then return end
	if typeof(target) ~= "Vector3" or target ~= target then return end

	local now = os.clock()
	if now - lastShot < COOLDOWN then
		setStatus("Recharging...")
		return
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 then return end
	if (target - root.Position).Magnitude > MAX_DISTANCE then
		setStatus("Too far (max " .. MAX_DISTANCE .. ")")
		return
	end

	lastShot = now
	busy = true
	setStatus(string.format("Portal to %d, %d, %d", target.X, target.Y, target.Z))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(target + Vector3.new(0, 5, 0), Vector3.new(0, -400, 0), params)
	local ground = hit and hit.Position or target

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	playShotAnimation(currentTool)
	makePortal(root.Position + flat * 6 + Vector3.new(0, 1, 0), flat)
	makePortal(ground + Vector3.new(0, PORTAL_SIZE / 2, 0), flat)

	task.wait(TRAVEL_DELAY)
	if char.Parent and humanoid.Health > 0 then
		local standAt = ground + Vector3.new(0, 3.5, 0) + flat * 3
		char:PivotTo(CFrame.lookAt(standAt, standAt + flat))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	busy = false
end

local function aimPosition()
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local hit = Workspace:Raycast(ray.Origin, ray.Direction * AIM_RANGE, params)
	if hit then
		return hit.Position
	end
	return ray.Origin + ray.Direction * 150
end

--==============================================================
--  panel
--==============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "PortalGunPanel"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function label(parent, text, size)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = size or 14
	l.TextColor3 = GREEN
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Size = UDim2.new(1, 0, 0, 20)
	l.Parent = parent
	return l
end

local function button(parent, text)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = GREEN
	b.TextColor3 = DARK
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	b.Size = UDim2.new(1, 0, 0, 30)
	b.Parent = parent
	corner(b, 6)
	return b
end

local function textBox(parent, placeholder)
	local t = Instance.new("TextBox")
	t.BackgroundColor3 = MID
	t.TextColor3 = Color3.new(1, 1, 1)
	t.PlaceholderColor3 = Color3.fromRGB(120, 130, 135)
	t.PlaceholderText = placeholder
	t.Text = ""
	t.ClearTextOnFocus = false
	t.Font = Enum.Font.Gotham
	t.TextSize = 14
	t.Size = UDim2.new(1, 0, 0, 30)
	t.Parent = parent
	corner(t, 6)
	return t
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true      -- clicks on the panel do not fire the gun
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -16, 0.5, 0)
panel.Size = UDim2.new(0, 250, 0, 400)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.08
panel.Parent = gui
corner(panel, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = GREEN
stroke.Thickness = 2
stroke.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

label(panel, "PORTAL GUN", 18).LayoutOrder = 1

label(panel, "Coordinates").LayoutOrder = 2
local coordRow = Instance.new("Frame")
coordRow.BackgroundTransparency = 1
coordRow.Size = UDim2.new(1, 0, 0, 30)
coordRow.LayoutOrder = 3
coordRow.Parent = panel
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(0, 6)
rowLayout.Parent = coordRow

local boxes = {}
for i, axis in ipairs({ "X", "Y", "Z" }) do
	local b = textBox(coordRow, axis)
	b.Size = UDim2.new(1 / 3, -4, 1, 0)
	boxes[i] = b
end

local goButton = button(panel, "Open portal to coordinates")
goButton.LayoutOrder = 4
goButton.Activated:Connect(function()
	local x, y, z = tonumber(boxes[1].Text), tonumber(boxes[2].Text), tonumber(boxes[3].Text)
	if x and y and z then
		task.spawn(teleport, Vector3.new(x, y, z))
	else
		setStatus("Enter three numbers")
	end
end)

label(panel, "Saved locations").LayoutOrder = 5
local nameBox = textBox(panel, "Name (e.g. Base)")
nameBox.LayoutOrder = 6
local saveButton = button(panel, "Save where I stand")
saveButton.LayoutOrder = 7

local list = Instance.new("ScrollingFrame")
list.LayoutOrder = 8
list.Size = UDim2.new(1, 0, 0, 120)
list.BackgroundColor3 = MID
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = GREEN
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = panel
corner(list, 6)
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 4)
listPad.PaddingLeft = UDim.new(0, 4)
listPad.PaddingRight = UDim.new(0, 8)
listPad.Parent = list

statusLabel = label(panel, "Click anywhere to shoot", 12)
statusLabel.LayoutOrder = 9
statusLabel.TextColor3 = Color3.fromRGB(170, 180, 185)

local function refreshList()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, entry in ipairs(saved) do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 26)
		row.Parent = list

		local go = button(row, entry.name)
		go.Size = UDim2.new(1, -30, 1, 0)
		go.BackgroundColor3 = DARK
		go.TextColor3 = GREEN
		go.TextTruncate = Enum.TextTruncate.AtEnd
		go.Activated:Connect(function()
			task.spawn(teleport, entry.pos)
		end)

		local del = button(row, "X")
		del.Size = UDim2.new(0, 26, 1, 0)
		del.Position = UDim2.new(1, -26, 0, 0)
		del.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
		del.TextColor3 = Color3.new(1, 1, 1)
		del.Activated:Connect(function()
			table.remove(saved, index)
			refreshList()
		end)
	end
end

saveButton.Activated:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local name = nameBox.Text
	if name == "" then
		name = "Location " .. (#saved + 1)
	end
	table.insert(saved, { name = name, pos = root.Position - Vector3.new(0, 3, 0) })
	nameBox.Text = ""
	refreshList()
	setStatus("Saved " .. name)
end)

--==============================================================
--  give the gun (again after every respawn)
--==============================================================
local function giveGun()
	local backpack = player:WaitForChild("Backpack")
	if currentTool and currentTool.Parent then
		currentTool:Destroy()
	end
	equipped = false
	busy = false
	gui.Enabled = false

	local tool, data = buildTool()
	currentTool, gun = tool, data

	tool.Equipped:Connect(function()
		equipped = true
		gui.Enabled = true
	end)
	tool.Unequipped:Connect(function()
		equipped = false
		gui.Enabled = false
	end)
	tool.Activated:Connect(function()
		teleport(aimPosition())
	end)

	tool.Parent = backpack
end

player.CharacterAdded:Connect(function()
	task.wait(0.2) -- let the new Backpack appear
	giveGun()
end)
if player.Character then
	giveGun()
end
