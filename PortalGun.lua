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

	-- green energy orb on the back of the gun: glass shell, glowing core, two spinning rings
	local ORB_CENTER = CFrame.new(0, 0.42, 0.95)
	local shell = fixed("OrbShell", Vector3.new(0.5, 0.5, 0.5), ORB_CENTER, GREEN, Enum.Material.ForceField, Enum.PartType.Ball)
	shell.CastShadow = false
	fixed("OrbMount", Vector3.new(0.3, 0.14, 0.3), CFrame.new(0, 0.22, 0.95), Color3.fromRGB(165, 170, 180))
	local orbCore = part("OrbCore", Vector3.new(0.26, 0.26, 0.26), ORB_CENTER, GREEN_HOT, Enum.Material.Neon, Enum.PartType.Ball)
	orbCore.CastShadow = false
	local coreWeld = Instance.new("Weld")
	coreWeld.Part0 = handle
	coreWeld.Part1 = orbCore
	coreWeld.C0 = ORB_CENTER
	coreWeld.Parent = orbCore
	local orbLight = Instance.new("PointLight")
	orbLight.Color = GREEN
	orbLight.Range = 7
	orbLight.Brightness = 2
	orbLight.Parent = orbCore
	local orbRings = {}
	for i = 1, 2 do
		local ring = part("OrbRing" .. i, Vector3.new(0.03, 0.42, 0.42), ORB_CENTER, GREEN, Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.Transparency = 0.3
		ring.CastShadow = false
		local w = Instance.new("Weld")
		w.Part0 = handle
		w.Part1 = ring
		w.C0 = ORB_CENTER
		w.Parent = ring
		orbRings[i] = w
	end

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
		handle = handle,
		orbCenter = ORB_CENTER,
		coreWeld = coreWeld,
		orbCore = orbCore,
		orbLight = orbLight,
		orbRings = orbRings,
		slosh = Vector3.zero,
		lastPos = nil,
		lastVel = Vector3.zero,
		muzzle = muzzle,
		glow = glow,
		sound = sound,
		shotAt = 0,
	}
end

--==============================================================
--  portal effect: a swirling green vortex orb (only you see it)
--==============================================================
local ARMS = 5             -- spiral arms
local ARM_SEGMENTS = 9     -- pieces per arm

local function makePortal(position, facing)
	local base = CFrame.lookAt(position, position + facing)   -- -Z = facing
	local model = Instance.new("Model")
	model.Name = "Portal"

	local function piece(shape, color, material, transparency)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Material = material or Enum.Material.Neon
		p.Color = color
		p.Transparency = transparency or 0
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = Vector3.new(0.1, 0.1, 0.1)
		p.CFrame = base
		p.Parent = model
		return p
	end

	-- layered discs (cylinders lie along X, so turn them to face forward)
	local FACE = CFrame.Angles(0, math.rad(90), 0)
	local layers = {
		{ part = piece(Enum.PartType.Cylinder, GREEN, Enum.Material.ForceField), scale = 1.15, thick = 0.2 },
		{ part = piece(Enum.PartType.Cylinder, GREEN), scale = 1.0, thick = 0.25 },
		{ part = piece(Enum.PartType.Cylinder, Color3.fromRGB(40, 200, 80)), scale = 0.8, thick = 0.3 },
		{ part = piece(Enum.PartType.Cylinder, GREEN_DEEP), scale = 0.45, thick = 0.35 },
		{ part = piece(Enum.PartType.Cylinder, GREEN_HOT), scale = 0.14, thick = 0.4 },
	}

	-- spiral arms: small glowing balls laid out on a spiral, spun every frame
	local arms = {}
	for a = 1, ARMS do
		for s = 1, ARM_SEGMENTS do
			local f = s / ARM_SEGMENTS
			local ball = piece(Enum.PartType.Ball, (s % 2 == 0) and GREEN_HOT or GREEN)
			ball.Transparency = 0.15 + f * 0.4
			table.insert(arms, { part = ball, arm = a, f = f })
		end
	end

	local light = Instance.new("PointLight")
	light.Color = GREEN
	light.Range = 22
	light.Brightness = 3
	light.Parent = layers[2].part

	-- sparks pulled in toward the middle
	local emitterHolder = layers[1].part
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(GREEN_HOT, GREEN)
	sparks.LightEmission = 1
	sparks.Rate = 90
	sparks.Lifetime = NumberRange.new(0.5, 1)
	sparks.Speed = NumberRange.new(-6, -3)        -- negative = inward
	sparks.Shape = Enum.ParticleEmitterShape.Disc
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparks.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	sparks.RotSpeed = NumberRange.new(-200, 200)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = emitterHolder

	model.Parent = Workspace

	local born = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - born
		if age >= PORTAL_LIFETIME or not model.Parent then
			conn:Disconnect()
			model:Destroy()
			return
		end
		-- open with a bounce, close with a quick shrink
		local open = math.clamp(age / 0.35, 0, 1)
		open = 1 + 2.2 * (open - 1) ^ 3 + 1.2 * (open - 1) ^ 2   -- "back" ease
		local close = math.clamp((PORTAL_LIFETIME - age) / 0.3, 0, 1)
		local k = math.max(open * close, 0.01)
		local r = PORTAL_SIZE / 2 * k
		local spin = age * 4

		for i, layer in ipairs(layers) do
			local d = PORTAL_SIZE * layer.scale * k * (1 + 0.03 * math.sin(age * 9 + i))
			layer.part.Size = Vector3.new(layer.thick, d, d)
			layer.part.CFrame = base * CFrame.new(0, 0, -0.05 * i) * CFrame.Angles(0, 0, spin * (i % 2 == 0 and 1 or -1)) * FACE
		end
		for _, seg in ipairs(arms) do
			local angle = spin * 1.6 + seg.arm * (2 * math.pi / ARMS) + seg.f * 4.5
			local dist = r * 0.95 * seg.f
			local size = (0.25 + 0.55 * seg.f) * k
			seg.part.Size = Vector3.new(size, size, size)
			seg.part.CFrame = base * CFrame.new(math.cos(angle) * dist, math.sin(angle) * dist, -0.4)
		end
		light.Brightness = 3 + math.sin(age * 12)
		sparks.Enabled = close > 0.5
	end)
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
RunService.RenderStepped:Connect(function(dt)
	if not (gun and currentTool and currentTool.Parent) then return end
	local t = os.clock()
	local surge = math.clamp(1 - (t - gun.shotAt) / 0.7, 0, 1)
	dt = math.max(dt, 1 / 240)

	-- real sloshing: the liquid lags behind when the gun moves and sinks toward "down"
	local hcf = gun.handle.CFrame
	local pos = hcf.Position
	local vel = gun.lastPos and (pos - gun.lastPos) / dt or Vector3.zero
	local accel = (vel - gun.lastVel) / dt
	gun.lastPos, gun.lastVel = pos, vel
	local localAccel = hcf:VectorToObjectSpace(accel)
	local localDown = hcf:VectorToObjectSpace(Vector3.new(0, -1, 0))
	local target = localDown * 0.07 - localAccel * 0.0025
	if target.Magnitude > 0.16 then
		target = target.Unit * 0.16
	end
	gun.slosh = gun.slosh:Lerp(target, math.clamp(dt * 9, 0, 1))
	local sx, sy = gun.slosh.X, gun.slosh.Y
	local sz = math.clamp(gun.slosh.Z * 3, -TUBE_HALF, TUBE_HALF)
	local wobble = 0.04 * math.clamp(localAccel.Magnitude / 60, 0, 1)

	for _, blob in ipairs(gun.blobs) do
		local i = blob.index
		local along = math.sin(t * (1.3 + i * 0.45) + i * 1.7) * TUBE_HALF * 0.6 + sz
		along = math.clamp(along, -TUBE_HALF, TUBE_HALF)
		local angle = t * (2.2 + i * 0.6) + i
		local radius = 0.04 + 0.02 * math.sin(t * 3 + i) + 0.05 * surge + wobble
		local x = math.clamp(math.cos(angle) * radius + sx, -0.13, 0.13)
		local y = math.clamp(math.sin(angle) * radius + sy, -0.13, 0.13)
		blob.weld.C0 = TUBE_CENTER * CFrame.new(x, y, along)
		local s = blob.baseSize * (1 + 0.25 * math.sin(t * 5 + i * 2) + 0.6 * surge)
		blob.part.Size = Vector3.new(s, s, s)
	end
	gun.tubeLight.Brightness = 1.5 + 0.5 * math.sin(t * 7) + 4 * surge

	-- orb: core pulses and drifts, rings spin faster after a shot
	local spin = t * (2 + 10 * surge)
	local c = 0.24 * (1 + 0.15 * math.sin(t * 4) + 0.5 * surge)
	gun.orbCore.Size = Vector3.new(c, c, c)
	gun.coreWeld.C0 = gun.orbCenter * CFrame.new(sx * 0.3, sy * 0.3, 0)
	gun.orbLight.Brightness = 2 + math.sin(t * 4) + 6 * surge
	gun.orbRings[1].C0 = gun.orbCenter * CFrame.Angles(spin, spin * 0.7, 0)
	gun.orbRings[2].C0 = gun.orbCenter * CFrame.Angles(0, -spin * 1.3, spin)
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
--  panel: "SELECT A DIMENSION"
--==============================================================
-- Edit these lists: each dimension is a name + the spot to teleport to.
local DIMENSIONS = {
	NEW = {
		{ name = "BASEPLATE",    pos = Vector3.new(0, 5, 0) },
		{ name = "INFERNO",      pos = Vector3.new(500, 5, 0) },
		{ name = "FROZENSPIKES", pos = Vector3.new(-500, 5, 0) },
		{ name = "VOIDISLANDS",  pos = Vector3.new(0, 5, 500) },
	},
	OG = {
		{ name = "BASEPLATE",    pos = Vector3.new(0, 5, 0) },
	},
}

local TEXT_COLOR = Color3.fromRGB(70, 255, 200)   -- cyan-green letters
local TEXT_STROKE = Color3.fromRGB(10, 60, 50)
local BTN_LIGHT = Color3.fromRGB(200, 205, 210)
local BTN_DARK = Color3.fromRGB(70, 74, 80)
local BORDER = Color3.fromRGB(30, 32, 36)
local FONT = Enum.Font.LuckiestGuy

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

local function outline(parent, thickness)
	local s = Instance.new("UIStroke")
	s.Color = BORDER
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function styleText(obj, size)
	obj.Font = FONT
	obj.TextColor3 = TEXT_COLOR
	obj.TextStrokeColor3 = TEXT_STROKE
	obj.TextStrokeTransparency = 0
	obj.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.Parent = obj
end

local function bigButton(parent, text, size, color)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color or BTN_DARK
	b.Text = text
	b.Parent = parent
	styleText(b, size)
	corner(b, 8)
	outline(b, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 2)
	pad.Parent = b
	return b
end

-- whole panel sits on the right side
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.AnchorPoint = Vector2.new(1, 0.5)
root.Position = UDim2.new(1, -12, 0.5, 0)
root.Size = UDim2.new(0, 440, 0, 380)
root.Parent = gui

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Text = "SELECT A DIMENSION"
title.Size = UDim2.new(0, 300, 0, 40)
title.Position = UDim2.new(1, -300, 0, 0)
title.Parent = root
styleText(title, 32)

-- dimension list
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Active = true
list.Position = UDim2.new(1, -290, 0, 50)
list.Size = UDim2.new(0, 290, 0, 300)
list.BackgroundColor3 = Color3.fromRGB(45, 48, 54)
list.BackgroundTransparency = 0.35
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = BTN_LIGHT
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = root
corner(list, 10)
outline(list, 2)
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 6)
listPad.PaddingBottom = UDim.new(0, 6)
listPad.PaddingLeft = UDim.new(0, 6)
listPad.PaddingRight = UDim.new(0, 14)
listPad.Parent = list

-- NEW / OG tabs on the left of the list
local tabs = {}
local currentTab = "NEW"

local function fillList()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for i, dim in ipairs(DIMENSIONS[currentTab] or {}) do
		local b = bigButton(list, dim.name, 36, (i % 2 == 0) and BTN_LIGHT or BTN_DARK)
		b.Size = UDim2.new(1, 0, 0, 58)
		b.LayoutOrder = i
		b.Activated:Connect(function()
			task.spawn(teleport, dim.pos)
		end)
	end
	for name, tab in pairs(tabs) do
		tab.BackgroundColor3 = (name == currentTab) and BTN_DARK or BTN_LIGHT
	end
end

for i, name in ipairs({ "NEW", "OG" }) do
	local tab = bigButton(root, name, 34)
	tab.Size = UDim2.new(0, 120, 0, 60)
	tab.Position = UDim2.new(1, -420, 0, 150 + (i - 1) * 72)
	tab.Activated:Connect(function()
		currentTab = name
		fillList()
	end)
	tabs[name] = tab
end

-- small status line under the list (cooldown / errors)
statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.Size = UDim2.new(0, 290, 0, 22)
statusLabel.Position = UDim2.new(1, -290, 0, 356)
statusLabel.Parent = root
styleText(statusLabel, 18)

fillList()

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
