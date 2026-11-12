-- PortalGun (LocalScript only)
-- Run it with an executor (loadstring) or put it in StarterPlayer > StarterPlayerScripts.
-- Everything runs for the local player: the gun is built in your Backpack,
-- portals are drawn on your screen, and you move your own character
-- (your character's position replicates to the server automatically).
--
-- Admin panel: press RightShift or click the "PG" button on the left of the screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- running the script again replaces the old copy instead of doubling everything
if _G.PortalGunCleanup then
	pcall(_G.PortalGunCleanup)
end
local connections = {}
local function track(c)
	table.insert(connections, c)
	return c
end

---------------------------------------------------------------- settings
local TOOL_NAME = "PortalGun"
local SAVE_FILE = "PortalGun_settings.json"
local SHOT_SOUND_ID = ""        -- optional, e.g. "rbxassetid://123456"
local ADMIN_KEY = Enum.KeyCode.RightShift

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- portal colour themes (picked in the admin panel)
local THEMES = {
	{ name = "GREEN",  rim = rgb(0, 255, 42),   mid = rgb(90, 235, 40),   deep = rgb(0, 80, 18),  core = rgb(225, 255, 120) },
	{ name = "BLUE",   rim = rgb(0, 170, 255),  mid = rgb(70, 210, 255),  deep = rgb(0, 35, 100), core = rgb(215, 245, 255) },
	{ name = "ORANGE", rim = rgb(255, 130, 0),  mid = rgb(255, 190, 40),  deep = rgb(100, 35, 0), core = rgb(255, 245, 200) },
	{ name = "PURPLE", rim = rgb(170, 60, 255), mid = rgb(210, 120, 255), deep = rgb(45, 0, 95),  core = rgb(245, 215, 255) },
	{ name = "RED",    rim = rgb(255, 35, 35),  mid = rgb(255, 110, 80),  deep = rgb(95, 0, 0),   core = rgb(255, 220, 200) },
}

local DEFAULTS = {
	cooldown = 1.5,          -- seconds between gun shots
	maxDistance = 100000,    -- max teleport distance in studs (if the limit is on)
	noDistanceLimit = true,  -- teleport any distance
	aimRange = 5000,         -- how far the gun can aim
	portalSize = 9,          -- portal diameter in studs
	portalLifetime = 2.5,    -- seconds a portal stays open
	travelDelay = 0.45,      -- auto-jump: wait this long before jumping in
	theme = 1,
	showPortals = true,
	keepOpen = true,         -- portals stay until your next shot (or CLOSE PORTALS)
	autoJump = false,        -- jump through the new portal by yourself
	clickTeleport = true,
	showDimensions = true,
	saved = {},              -- saved spots: { name, x, y, z }
}

local cfg = {}
local function resetCfg(keepSaved)
	local saved = cfg.saved
	for k, v in pairs(DEFAULTS) do
		cfg[k] = (type(v) == "table") and {} or v
	end
	if keepSaved and saved then
		cfg.saved = saved
	end
end
resetCfg(false)

local canSave = typeof(writefile) == "function" and typeof(readfile) == "function"
local function saveCfg()
	if canSave then
		pcall(function()
			writefile(SAVE_FILE, HttpService:JSONEncode(cfg))
		end)
	end
end
local function loadCfg()
	if not canSave then return end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(SAVE_FILE))
	end)
	if ok and type(data) == "table" then
		for k, v in pairs(data) do
			if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then
				cfg[k] = v
			end
		end
	end
end
loadCfg()

local function theme()
	return THEMES[cfg.theme] or THEMES[1]
end

local GREEN = rgb(0, 255, 42)
local GREEN_HOT = rgb(200, 255, 90)
----------------------------------------------------------------

--==============================================================
--  gun model (built from the scanned model, part by part)
--==============================================================
-- The Handle is the vertical grip. In the model's own space +X is "up" and -Z is forward.
local BASE_GRIP = CFrame.Angles(0, 0, math.rad(-90))
local ORB_CENTER = CFrame.new(1.134, 0.016, -0.695)   -- the green ball on top
local ORB_SIZE = 0.48
local ARC_COUNT = 8         -- electric arcs inside the green orb
local ARC_SEGMENTS = 5       -- zigzag pieces per arc

local WHITE = rgb(231, 231, 236)
local BLACK = rgb(17, 17, 17)
local RED = rgb(117, 0, 0)
local CYL = Enum.PartType.Cylinder
local BLOCK = Enum.PartType.Block
local PLASTIC = Enum.Material.Plastic
local NEON = Enum.Material.Neon

local function at(x, y, z, rx, ry, rz)
	return CFrame.new(x, y, z) * CFrame.fromOrientation(math.rad(rx), math.rad(ry), math.rad(rz))
end

-- name, size, offset from Handle, colour, material, shape
local GUN_PARTS = {
	{ "BackCyl1",    Vector3.new(1.04, 0.3, 0.48),  at(0.635, 0, 0.156, 0.005, 173.62, 89.999),      WHITE, PLASTIC, CYL },
	{ "BackCyl2",    Vector3.new(1.04, 0.3, 0.48),  at(0.647, 0, 0.156, 0.005, 173.62, 89.999),      WHITE, PLASTIC, CYL },
	{ "BackCyl3",    Vector3.new(1.04, 0.3, 0.48),  at(0.615, -0.004, 0.156, 0.005, 173.62, 89.999), WHITE, PLASTIC, CYL },
	{ "BackCyl4",    Vector3.new(1.04, 0.3, 0.48),  at(0.623, 0, 0.152, 0.005, 173.62, 89.999),      WHITE, PLASTIC, CYL },
	{ "Body",        Vector3.new(1.31, 0.27, 1.03), at(0.719, -0.004, -0.434, -90, -100, 0),         WHITE, PLASTIC, BLOCK },
	{ "Knob",        Vector3.new(0.2, 0.2, 0.2),    at(0.696, 0.039, 0.184, 0, -18.03, 179.998),     BLACK, PLASTIC, CYL },
	{ "FrontPlate",  Vector3.new(0.2, 0.24, 0.99),  at(0.821, -0.02, -0.988, -90, -100, 0),          BLACK, PLASTIC, BLOCK },
	{ "Nozzle",      Vector3.new(0.2, 0.47, 0.45),  at(0.822, 0.012, -0.762, 0, -9.822, -179.998),   BLACK, PLASTIC, CYL },
	{ "EmitterL",    Vector3.new(0.25, 0.31, 0.2),  at(0.821, 0.328, -1.008, -90, -100, 0),          GREEN, NEON, CYL },
	{ "EmitterM",    Vector3.new(0.25, 0.31, 0.2),  at(0.818, 0.008, -1.02, -90, -100, 0),           GREEN, NEON, CYL },
	{ "EmitterR",    Vector3.new(0.25, 0.31, 0.2),  at(0.818, -0.363, -1.02, -90, -100, 0),          GREEN, NEON, CYL },
	{ "Display",     Vector3.new(0.24, 0.27, 0.54), at(0.697, 0.012, -0.172, -90, -100, 0),          RED, PLASTIC, BLOCK },
}

local function buildTool()
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.ToolTip = "Click to open a portal"
	tool.CanBeDropped = false
	tool.Grip = BASE_GRIP

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.045, 0.453, 0.453)
	handle.Color = WHITE
	handle.Material = PLASTIC
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local function part(name, size, offset, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or PLASTIC
		p.Shape = shape or BLOCK
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = handle.CFrame * offset
		p.Parent = tool
		return p
	end

	local function fixed(...)
		local p = part(...)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	-- moving pieces get a Weld whose C0 we change every frame
	local function moving(name, size, color, material, shape)
		local p = part(name, size, ORB_CENTER, color, material, shape)
		p.CastShadow = false
		local w = Instance.new("Weld")
		w.Part0 = handle
		w.Part1 = p
		w.C0 = ORB_CENTER
		w.Parent = p
		return p, w
	end

	local parts = {}
	for _, d in ipairs(GUN_PARTS) do
		parts[d[1]] = fixed(d[1], d[2], d[3], d[4], d[5], d[6])
	end

	-- muzzle = middle emitter
	local muzzle = parts.EmitterM
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = GREEN
	glow.Range = 6
	glow.Brightness = 1
	glow.Parent = muzzle

	-- display: put the text on the face that points back at the player (+Z)
	local panel = parts.Display
	local rel = handle.CFrame:ToObjectSpace(panel.CFrame)
	local bestFace, bestDot = Enum.NormalId.Back, -2
	for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
		local dot = rel:VectorToWorldSpace(Vector3.FromNormalId(face)):Dot(Vector3.new(0, 0, 1))
		if dot > bestDot then
			bestFace, bestDot = face, dot
		end
	end
	local sg = Instance.new("SurfaceGui")
	sg.Face = bestFace
	sg.LightInfluence = 0
	sg.CanvasSize = Vector2.new(200, 100)
	sg.Parent = panel
	local display = Instance.new("TextLabel")
	display.BackgroundTransparency = 1
	display.Size = UDim2.fromScale(1, 1)
	display.Font = Enum.Font.Arcade
	display.TextScaled = true
	display.TextColor3 = rgb(255, 120, 120)
	display.Text = "READY"
	display.Parent = sg

	-- green glass ball on top
	local orb = fixed("EnergyBall", Vector3.new(ORB_SIZE, ORB_SIZE, ORB_SIZE), ORB_CENTER, GREEN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	orb.Transparency = 0.5
	orb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = GREEN
	light.Range = 5
	light.Brightness = 1
	light.Parent = orb

	-- electric plasma: thin neon zigzags that jump from the centre to the glass (and past it after a shot)
	local arcs = {}
	for a = 1, ARC_COUNT do
		local segs = {}
		for s = 1, ARC_SEGMENTS do
			local p, w = moving("Arc" .. a .. "_" .. s, Vector3.new(0.018, 0.018, 0.05), GREEN_HOT, NEON, BLOCK)
			p.Transparency = 1
			segs[s] = { part = p, weld = w }
		end
		arcs[a] = segs
	end

	local sound
	if SHOT_SOUND_ID ~= "" then
		sound = Instance.new("Sound")
		sound.SoundId = SHOT_SOUND_ID
		sound.Volume = 0.8
		sound.Parent = handle
	end

	return tool, {
		handle = handle,
		light = light,
		display = display,
		muzzle = muzzle,
		muzzleSize = muzzle.Size,
		glow = glow,
		sound = sound,
		slosh = Vector3.zero,
		lastPos = nil,
		lastVel = Vector3.zero,
		shotAt = 0,
		arcs = arcs,
		nextArc = 0,
	}
end

--==============================================================
--  portal: flat liquid swirl with a wobbly glowing rim
--==============================================================
local ARMS = 4
local ARM_SEGMENTS = 10
local RIM_BLOBS = 22
local FACE = CFrame.Angles(0, math.rad(90), 0)   -- cylinders lie along X; turn them to face forward
local TAU = math.pi * 2

local activePortals = {}

-- bottom = Y of the floor under the portal; lifetime = nil uses the settings
local function makePortal(center, facing, bottom, lifetime)
	local th = theme()
	local base = CFrame.lookAt(center, center + facing)
	local size = cfg.portalSize
	if not lifetime then
		lifetime = cfg.keepOpen and math.huge or cfg.portalLifetime
	end

	local model = Instance.new("Model")
	model.Name = "Portal"

	local function piece(shape, color, material, transparency)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Material = material or NEON
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

	-- discs: inner ones are thicker, so they show from both sides
	local layers = {
		{ p = piece(CYL, th.rim, Enum.Material.ForceField), scale = 1.14, thick = 0.06 },
		{ p = piece(CYL, th.rim), scale = 1.0, thick = 0.12 },
		{ p = piece(CYL, th.mid), scale = 0.86, thick = 0.2 },
		{ p = piece(CYL, th.deep), scale = 0.64, thick = 0.28 },
		{ p = piece(CYL, th.mid), scale = 0.3, thick = 0.34 },
		{ p = piece(CYL, th.core), scale = 0.14, thick = 0.4 },
	}

	-- flat glowing streaks laid on spiral arms, on both faces
	local streaks = {}
	for side = -1, 1, 2 do
		for a = 1, ARMS do
			for s = 1, ARM_SEGMENTS do
				local f = s / ARM_SEGMENTS
				local p = piece(BLOCK, th.core:Lerp(th.mid, f))
				p.Transparency = 0.05 + 0.45 * f
				table.insert(streaks, { p = p, arm = a, f = f, side = side })
			end
		end
	end

	-- bubbly rim
	local rim = {}
	for i = 1, RIM_BLOBS do
		rim[i] = { p = piece(Enum.PartType.Ball, th.rim, NEON, 0.1), i = i }
	end

	local light = Instance.new("PointLight")
	light.Color = th.rim
	light.Range = math.clamp(size * 2.5, 8, 60)
	light.Brightness = 3
	light.Parent = layers[2].p

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(th.core, th.rim)
	sparks.LightEmission = 1
	sparks.Rate = 50
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(2, 6)
	sparks.Drag = 3
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.RotSpeed = NumberRange.new(-200, 200)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = layers[6].p

	model.Parent = Workspace

	local born = os.clock()
	local portal = {
		model = model,
		base = base,
		center = center,
		half = size / 2,
		bottom = bottom or (center.Y - size / 2),
		born = born,
		closeAt = born + lifetime,   -- fully closed at this time
		alive = true,
		partner = nil,
		prevZ = nil,
	}
	table.insert(activePortals, portal)

	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local age = now - born
		if now >= portal.closeAt or not model.Parent then
			conn:Disconnect()
			portal.alive = false
			model:Destroy()
			local i = table.find(activePortals, portal)
			if i then
				table.remove(activePortals, i)
			end
			return
		end
		-- open with a bounce, close with a quick shrink
		local open = math.clamp(age / 0.35, 0, 1)
		open = 1 + 2.2 * (open - 1) ^ 3 + 1.2 * (open - 1) ^ 2
		local close = math.clamp((portal.closeAt - now) / 0.3, 0, 1)
		local k = math.max(open * close, 0.01)
		local r = size / 2 * k
		local spin = age * 3

		for i, layer in ipairs(layers) do
			local wob = 1 + 0.025 * math.sin(age * 8 + i * 1.3)
			if i == #layers then
				wob = 1 + 0.25 * math.sin(age * 10)
			end
			local d = size * layer.scale * k * wob
			layer.p.Size = Vector3.new(layer.thick, d, d)
			layer.p.CFrame = base * FACE
		end

		for _, s in ipairs(streaks) do
			local ang = spin + s.arm * (TAU / ARMS) + s.f * 3.2
			local dist = r * (0.12 + 0.75 * s.f)
			s.p.Size = Vector3.new(r * (0.18 + 0.3 * s.f), r * (0.05 + 0.05 * s.f), 0.05)
			s.p.CFrame = base * CFrame.new(math.cos(ang) * dist, math.sin(ang) * dist, s.side * 0.24)
				* CFrame.Angles(0, 0, ang + math.pi / 2 - 0.5)
		end

		for _, b in ipairs(rim) do
			local ang = (b.i / RIM_BLOBS) * TAU - spin * 0.5
			local wob = 0.96 + 0.06 * math.sin(age * 7 + b.i * 1.9)
			local bs = r * (0.16 + 0.05 * math.sin(age * 9 + b.i))
			b.p.Size = Vector3.new(bs, bs, bs)
			b.p.CFrame = base * CFrame.new(math.cos(ang) * r * wob, math.sin(ang) * r * wob, 0)
		end

		light.Brightness = 3 + math.sin(age * 12)
		sparks.Enabled = close > 0.5
	end)

	return portal
end

local function closeAllPortals()
	local soon = os.clock() + 0.3
	for _, p in ipairs(activePortals) do
		p.closeAt = math.min(p.closeAt, soon)
		p.partner = nil
	end
end

--==============================================================
--  state
--==============================================================
local currentTool, gun
local equipped = false
local lastShot = 0
local busy = false
local statusLabels = {}
local dimGui, adminGui

local function setStatus(text)
	for _, l in ipairs(statusLabels) do
		l.Text = text
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
	TweenService:Create(gun.muzzle, flash, { Size = gun.muzzleSize * 1.6 }):Play()
	if gun.sound then
		gun.sound:Play()
	end
end

--==============================================================
--  energy ball animation (sloshes when the gun moves)
--==============================================================
track(RunService.RenderStepped:Connect(function(dt)
	if not (gun and currentTool and currentTool.Parent) then return end
	local t = os.clock()
	local surge = math.clamp(1 - (t - gun.shotAt) / 0.7, 0, 1)
	dt = math.max(dt, 1 / 240)

	local hcf = gun.handle.CFrame
	local pos = hcf.Position
	local vel = gun.lastPos and (pos - gun.lastPos) / dt or Vector3.zero
	local accel = (vel - gun.lastVel) / dt
	gun.lastPos, gun.lastVel = pos, vel
	local localAccel = hcf:VectorToObjectSpace(accel)
	local localDown = hcf:VectorToObjectSpace(Vector3.new(0, -1, 0))
	local target = localDown * 0.06 - localAccel * 0.002
	if target.Magnitude > 0.1 then
		target = target.Unit * 0.1
	end
	gun.slosh = gun.slosh:Lerp(target, math.clamp(dt * 9, 0, 1))
	gun.light.Brightness = 1 + 0.4 * math.sin(t * 4) + 3 * surge

	-- lightning: redraw the arcs in new random shapes many times a second
	if t >= gun.nextArc then
		gun.nextArc = t + 0.04 + math.random() * 0.06
		local reach = ORB_SIZE / 2 * (0.9 + 0.8 * surge)
		local start = gun.slosh * 0.3
		local lit = 0
		for _, segs in ipairs(gun.arcs) do
			local on = math.random() < (0.5 + 0.5 * surge)
			local finish
			if on then
				local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(1, 0, 0)
				finish = start + dir * reach * (0.8 + math.random() * 0.35)
				lit += 1
			end
			local prev = start
			local color = (math.random() < 0.5) and GREEN_HOT or GREEN
			for s, seg in ipairs(segs) do
				if on then
					local point = finish
					if s < #segs then
						local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.09
						point = start:Lerp(finish, s / #segs) + jitter
					end
					local len = (point - prev).Magnitude
					if len > 0.001 then
						seg.part.Size = Vector3.new(0.018, 0.018, len)
						seg.weld.C0 = ORB_CENTER * CFrame.lookAt(prev, point) * CFrame.new(0, 0, -len / 2)
						seg.part.Color = color
						seg.part.Transparency = 0
					else
						seg.part.Transparency = 1
					end
					prev = point
				else
					seg.part.Transparency = 1
				end
			end
		end
		gun.light.Brightness += lit * 0.25 * math.random()
	end

	local left = cfg.cooldown - (t - lastShot)
	gun.display.Text = (left > 0) and string.format("%.1f", left) or "READY"
end))

--==============================================================
--  walking through portals (both ways)
--==============================================================
local EXIT_OFFSET = 3.5      -- how far in front of the other portal you come out
local travelLockUntil = 0

local function rayParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	return params
end

-- raycast of any length (Roblox limits one ray, so go in 5000-stud steps)
local function longRaycast(origin, direction, length)
	local params = rayParams()
	local dir = direction.Unit
	local done = 0
	while done < length do
		local step = math.min(5000, length - done)
		local hit = Workspace:Raycast(origin + dir * done, dir * step, params)
		if hit then
			return hit
		end
		done += step
	end
	return nil
end

-- position of the floor under a point, or nil
local function groundBelow(pos, depth)
	local hit = longRaycast(pos, Vector3.new(0, -1, 0), depth)
	return hit and hit.Position
end

-- far away the map may not be loaded yet: freeze in place until there is ground (max 4 s)
local function holdUntilLoaded(pos)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or groundBelow(pos, 60) then return end
	root.Anchored = true
	setStatus("Loading the area...")
	local t0 = os.clock()
	while os.clock() - t0 < 4 and root.Parent and not groundBelow(pos, 60) do
		task.wait(0.1)
	end
	if root.Parent then
		root.Anchored = false
	end
	setStatus("")
end

-- side = +1 if you came from the portal's back (+Z) side, -1 from its front
local function travel(from, side)
	local to = from.partner
	if not (to and to.alive) then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local dir = to.base.LookVector * side
	dir = Vector3.new(dir.X, 0, dir.Z)
	dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, -1)
	local pos = Vector3.new(to.center.X, to.bottom + 3, to.center.Z) + dir * EXIT_OFFSET

	local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	char:PivotTo(CFrame.lookAt(pos, pos + dir))
	root.AssemblyLinearVelocity = dir * speed

	travelLockUntil = os.clock() + 0.5
	for _, p in ipairs(activePortals) do
		p.prevZ = nil
	end
	task.spawn(holdUntilLoaded, pos)
end

-- every frame: did you just step through a portal's disc?
track(RunService.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local now = os.clock()
	local locked = now < travelLockUntil

	for _, p in ipairs(activePortals) do
		local usable = p.alive and p.partner and p.partner.alive
			and now - p.born > 0.3 and now < p.closeAt - 0.3
		if usable then
			local lp = p.base:PointToObjectSpace(root.Position)
			local z = lp.Z
			local planar = math.sqrt(lp.X * lp.X + lp.Y * lp.Y)
			local inside = planar < p.half + 0.75 and math.abs(z) < 3
			if not locked and inside and p.prevZ and (z >= 0) ~= (p.prevZ >= 0) then
				travel(p, p.prevZ >= 0 and 1 or -1)
				return
			end
			p.prevZ = z
		else
			p.prevZ = nil
		end
	end
end))

--==============================================================
--  teleport (local)
--==============================================================
-- snap = true: land on the ground under the target (gun shots)
-- fromPanel = true: works without holding the gun and skips the gun cooldown
local function teleport(target, snap, fromPanel)
	if busy then return end
	if typeof(target) ~= "Vector3" or target ~= target then return end
	if not fromPanel then
		if not equipped then return end
		if os.clock() - lastShot < cfg.cooldown then
			setStatus("Recharging...")
			return
		end
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 then return end
	if not cfg.noDistanceLimit and (target - root.Position).Magnitude > cfg.maxDistance then
		setStatus("Too far (max " .. math.floor(cfg.maxDistance) .. ")")
		return
	end

	if not fromPanel then
		lastShot = os.clock()
	end
	busy = true
	setStatus(string.format("Portal to %d, %d, %d", math.floor(target.X), math.floor(target.Y), math.floor(target.Z)))

	local standAt
	if snap then
		local ground = groundBelow(target + Vector3.new(0, 5, 0), 3000)
		standAt = (ground or target) + Vector3.new(0, 3.5, 0)
	else
		standAt = target
	end

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	if equipped and currentTool and gun then
		playShotAnimation(currentTool)
	end

	-- portals off: just move there
	if not cfg.showPortals then
		closeAllPortals()
		char:PivotTo(CFrame.lookAt(standAt, standAt + flat))
		root.AssemblyLinearVelocity = Vector3.zero
		task.spawn(holdUntilLoaded, standAt)
		busy = false
		return
	end

	-- one pair at a time: the old pair closes
	closeAllPortals()
	local half = cfg.portalSize / 2
	-- real floor under you (not a guess), so the portal sits on the ground
	local floorHere = groundBelow(root.Position, 12)
	local feetHere = floorHere and floorHere.Y or (root.Position.Y - 3)
	-- don't put the portal inside a wall in front of you
	local dist = math.max(6, half + 2)
	local wall = longRaycast(root.Position, flat, dist + 1)
	if wall then
		dist = math.max(2.5, wall.Distance - 1)
	end
	local hereCenter = Vector3.new(root.Position.X, feetHere + half, root.Position.Z) + flat * dist
	local feetThere = standAt.Y - 3
	-- the exit sits a few studs before the target, so walking out puts you right on it
	local thereCenter = Vector3.new(standAt.X, feetThere + half, standAt.Z) - flat * EXIT_OFFSET
	local a = makePortal(hereCenter, flat, feetHere)
	local b = makePortal(thereCenter, flat, feetThere)
	a.partner, b.partner = b, a
	setStatus("Portals open - walk in (both ways)")

	if cfg.autoJump then
		task.wait(cfg.travelDelay)
		if a.alive and a.partner then
			travel(a, 1)
		end
	end
	busy = false
end

local function aimPosition()
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local hit = longRaycast(ray.Origin, ray.Direction, cfg.aimRange)
	if hit then
		-- step back off the surface so you don't land inside a wall
		return hit.Position + hit.Normal * 1.5
	end
	-- aimed at the sky: go as far as the aim range allows
	return ray.Origin + ray.Direction.Unit * cfg.aimRange
end

--==============================================================
--  dimension panel ("SELECT A DIMENSION", shown while holding the gun)
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

local TEXT_COLOR = rgb(70, 255, 200)
local TEXT_STROKE = rgb(10, 60, 50)
local BTN_LIGHT = rgb(200, 205, 210)
local BTN_DARK = rgb(70, 74, 80)
local BORDER = rgb(30, 32, 36)
local FONT = Enum.Font.LuckiestGuy

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function outline(parent, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or BORDER
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
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

dimGui = Instance.new("ScreenGui")
dimGui.Name = "PortalGunPanel"
dimGui.ResetOnSpawn = false
dimGui.Enabled = false
dimGui.Parent = player:WaitForChild("PlayerGui")

local function refreshDimGui()
	dimGui.Enabled = equipped and cfg.showDimensions
end

do
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(1, 0.5)
	root.Position = UDim2.new(1, -12, 0.5, 0)
	root.Size = UDim2.new(0, 440, 0, 380)
	root.Parent = dimGui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Text = "SELECT A DIMENSION"
	title.Size = UDim2.new(0, 300, 0, 40)
	title.Position = UDim2.new(1, -300, 0, 0)
	title.Parent = root
	styleText(title, 32)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Active = true
	list.Position = UDim2.new(1, -290, 0, 50)
	list.Size = UDim2.new(0, 290, 0, 300)
	list.BackgroundColor3 = rgb(45, 48, 54)
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
				task.spawn(teleport, dim.pos, true, false)
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

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Text = ""
	status.Size = UDim2.new(0, 290, 0, 22)
	status.Position = UDim2.new(1, -290, 0, 356)
	status.Parent = root
	styleText(status, 18)
	table.insert(statusLabels, status)

	fillList()
end

--==============================================================
--  admin panel
--==============================================================
local giveGun -- defined below

local BG = rgb(14, 16, 20)
local BG2 = rgb(24, 27, 33)
local BG3 = rgb(38, 42, 50)
local TXT = rgb(230, 235, 240)
local SUB = rgb(140, 150, 162)
local ACCENT = GREEN
local UI_FONT = Enum.Font.GothamBold

adminGui = Instance.new("ScreenGui")
adminGui.Name = "PortalGunAdmin"
adminGui.ResetOnSpawn = false
adminGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
adminGui.Parent = player:WaitForChild("PlayerGui")

local refreshers = {}
local orderCounter = 0
local function nextOrder()
	orderCounter += 1
	return orderCounter
end

local function label(parent, text, size, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UI_FONT
	l.Text = text
	l.TextSize = size or 14
	l.TextColor3 = color or TXT
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function button(parent, text, color, textColor)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color or BG3
	b.Font = UI_FONT
	b.TextSize = 14
	b.TextColor3 = textColor or TXT
	b.Text = text
	b.Parent = parent
	corner(b, 6)
	return b
end

local function textbox(parent, placeholder)
	local t = Instance.new("TextBox")
	t.BackgroundColor3 = BG3
	t.Font = Enum.Font.Gotham
	t.TextSize = 14
	t.TextColor3 = TXT
	t.PlaceholderColor3 = SUB
	t.PlaceholderText = placeholder
	t.Text = ""
	t.ClearTextOnFocus = false
	t.Parent = parent
	corner(t, 6)
	return t
end

local function row(page, height, transparent)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = BG2
	f.BackgroundTransparency = transparent and 1 or 0
	f.Size = UDim2.new(1, 0, 0, height)
	f.LayoutOrder = nextOrder()
	f.Parent = page
	corner(f, 8)
	return f
end

local function section(page, text)
	local r = row(page, 22, true)
	label(r, text, 12, ACCENT).Size = UDim2.new(1, 0, 1, 0)
	return r
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function slider(page, text, key, min, max, step, fmt)
	local r = row(page, 54)
	local name = label(r, text, 14, TXT)
	name.Position = UDim2.new(0, 12, 0, 8)
	name.Size = UDim2.new(0.6, 0, 0, 18)
	local value = label(r, "", 14, ACCENT, Enum.TextXAlignment.Right)
	value.Position = UDim2.new(0.4, -12, 0, 8)
	value.Size = UDim2.new(0.6, 0, 0, 18)

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = BG3
	bar.Position = UDim2.new(0, 12, 0, 36)
	bar.Size = UDim2.new(1, -24, 0, 6)
	bar.Parent = r
	corner(bar, 3)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = ACCENT
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = bar
	corner(fill, 3)
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = TXT
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.Parent = bar
	corner(knob, 7)

	local function show()
		local a = math.clamp((cfg[key] - min) / (max - min), 0, 1)
		fill.Size = UDim2.new(a, 0, 1, 0)
		knob.Position = UDim2.new(a, 0, 0.5, 0)
		value.Text = string.format(fmt, cfg[key])
	end
	local function setFromX(x)
		local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		local v = min + a * (max - min)
		v = math.floor(v / step + 0.5) * step
		cfg[key] = math.clamp(v, min, max)
		show()
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Position = UDim2.new(0, 12, 0, 26)
	hit.Size = UDim2.new(1, -24, 0, 26)
	hit.Parent = r
	local dragging = false
	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and isMove(input) then
			setFromX(input.Position.X)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if dragging and isPress(input) then
			dragging = false
			saveCfg()
		end
	end))

	table.insert(refreshers, show)
	show()
end

local function toggle(page, text, key, onChange)
	local r = row(page, 38)
	local name = label(r, text, 14, TXT)
	name.Position = UDim2.new(0, 12, 0, 0)
	name.Size = UDim2.new(1, -90, 1, 0)
	local b = button(r, "", BG3)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -10, 0.5, 0)
	b.Size = UDim2.new(0, 64, 0, 24)
	local function show()
		b.Text = cfg[key] and "ON" or "OFF"
		b.BackgroundColor3 = cfg[key] and ACCENT or BG3
		b.TextColor3 = cfg[key] and BG or SUB
	end
	b.Activated:Connect(function()
		cfg[key] = not cfg[key]
		show()
		saveCfg()
		if onChange then onChange() end
	end)
	table.insert(refreshers, show)
	show()
end

local function refreshAll()
	for _, f in ipairs(refreshers) do
		f()
	end
	refreshDimGui()
end

-- open button on the left edge
local openBtn = button(adminGui, "PG", BG, ACCENT)
openBtn.AnchorPoint = Vector2.new(0, 0.5)
openBtn.Position = UDim2.new(0, 10, 0.5, 0)
openBtn.Size = UDim2.new(0, 44, 0, 44)
openBtn.TextSize = 16
outline(openBtn, 2, ACCENT, 0.3)

-- window
local win = Instance.new("Frame")
win.Name = "Window"
win.AnchorPoint = Vector2.new(0.5, 0.5)
win.Position = UDim2.new(0.5, 0, 0.5, 0)
win.Size = UDim2.new(0, 440, 0, 430)
win.BackgroundColor3 = BG
win.Visible = false
win.Active = true
win.Parent = adminGui
corner(win, 12)
outline(win, 2, ACCENT, 0.5)

local header = Instance.new("Frame")
header.BackgroundColor3 = BG2
header.Size = UDim2.new(1, 0, 0, 42)
header.Active = true
header.Parent = win
corner(header, 12)
local title = label(header, "PORTAL GUN  ·  ADMIN", 16, ACCENT)
title.Position = UDim2.new(0, 14, 0, 0)
title.Size = UDim2.new(1, -60, 1, 0)
local closeBtn = button(header, "X", BG3, SUB)
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
closeBtn.Size = UDim2.new(0, 28, 0, 28)

local function setOpen(open)
	win.Visible = open
	if open then
		refreshAll()
	end
end
openBtn.Activated:Connect(function()
	setOpen(not win.Visible)
end)
closeBtn.Activated:Connect(function()
	setOpen(false)
end)
track(UserInputService.InputBegan:Connect(function(input, gpe)
	if not gpe and input.KeyCode == ADMIN_KEY then
		setOpen(not win.Visible)
	end
end))

-- drag the window by its header
do
	local dragStart, startPos
	header.InputBegan:Connect(function(input)
		if isPress(input) then
			dragStart, startPos = input.Position, win.Position
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if dragStart and isMove(input) then
			local d = input.Position - dragStart
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			dragStart = nil
		end
	end))
end

-- status line at the bottom
local adminStatus = label(win, "", 13, SUB)
adminStatus.Position = UDim2.new(0, 14, 1, -26)
adminStatus.Size = UDim2.new(1, -28, 0, 20)
table.insert(statusLabels, adminStatus)

-- tabs
local tabBar = Instance.new("Frame")
tabBar.BackgroundTransparency = 1
tabBar.Position = UDim2.new(0, 10, 0, 50)
tabBar.Size = UDim2.new(1, -20, 0, 30)
tabBar.Parent = win
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar

local pages, tabButtons = {}, {}
local function showPage(name)
	for n, page in pairs(pages) do
		page.Visible = (n == name)
		tabButtons[n].BackgroundColor3 = (n == name) and ACCENT or BG3
		tabButtons[n].TextColor3 = (n == name) and BG or TXT
	end
end

local function makePage(name)
	local b = button(tabBar, name, BG3)
	b.Size = UDim2.new(1 / 3, -4, 1, 0)
	tabButtons[name] = b

	local page = Instance.new("ScrollingFrame")
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Position = UDim2.new(0, 10, 0, 88)
	page.Size = UDim2.new(1, -20, 1, -120)
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = ACCENT
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.Visible = false
	page.Parent = win
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = page
	pages[name] = page

	b.Activated:Connect(function()
		showPage(name)
	end)
	return page
end

local function myPosition()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

---------------------------------------------------------------- TELEPORT tab
local tpPage = makePage("TELEPORT")
local refreshSaved, refreshPlayers

do
	section(tpPage, "COORDINATES")
	local r = row(tpPage, 40, true)
	local boxes = {}
	for i, axis in ipairs({ "X", "Y", "Z" }) do
		local b = textbox(r, axis)
		b.Size = UDim2.new(1 / 3, -6, 1, 0)
		b.Position = UDim2.new((i - 1) / 3, (i - 1) * 3, 0, 0)
		boxes[i] = b
	end

	local r2 = row(tpPage, 36, true)
	local goBtn = button(r2, "TELEPORT", ACCENT, BG)
	goBtn.Size = UDim2.new(0.5, -4, 1, 0)
	local hereBtn = button(r2, "MY POSITION")
	hereBtn.Position = UDim2.new(0.5, 4, 0, 0)
	hereBtn.Size = UDim2.new(0.5, -4, 1, 0)

	local function readBoxes()
		local x, y, z = tonumber(boxes[1].Text), tonumber(boxes[2].Text), tonumber(boxes[3].Text)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end

	goBtn.Activated:Connect(function()
		local v = readBoxes()
		if v then
			task.spawn(teleport, v, false, true)
		else
			setStatus("Type numbers in X, Y and Z")
		end
	end)
	hereBtn.Activated:Connect(function()
		local p = myPosition()
		if p then
			boxes[1].Text = tostring(math.floor(p.X + 0.5))
			boxes[2].Text = tostring(math.floor(p.Y + 0.5))
			boxes[3].Text = tostring(math.floor(p.Z + 0.5))
		end
	end)

	section(tpPage, "SAVED PLACES")
	local r3 = row(tpPage, 36, true)
	local nameBox = textbox(r3, "Name")
	nameBox.Size = UDim2.new(0.6, -4, 1, 0)
	local saveBtn = button(r3, "SAVE")
	saveBtn.Position = UDim2.new(0.6, 4, 0, 0)
	saveBtn.Size = UDim2.new(0.4, -4, 1, 0)

	local savedList = Instance.new("Frame")
	savedList.BackgroundTransparency = 1
	savedList.Size = UDim2.new(1, 0, 0, 0)
	savedList.AutomaticSize = Enum.AutomaticSize.Y
	savedList.LayoutOrder = nextOrder()
	savedList.Parent = tpPage
	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 6)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = savedList

	refreshSaved = function()
		for _, c in ipairs(savedList:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		if #cfg.saved == 0 then
			local e = row(savedList, 30, true)
			label(e, "  Nothing saved yet (uses X/Y/Z, or where you stand)", 12, SUB).Size = UDim2.new(1, 0, 1, 0)
			return
		end
		for i, spot in ipairs(cfg.saved) do
			local e = row(savedList, 36)
			e.LayoutOrder = i
			local l = label(e, string.format("%s   (%d, %d, %d)", spot.name, spot.x, spot.y, spot.z), 13, TXT)
			l.Position = UDim2.new(0, 10, 0, 0)
			l.Size = UDim2.new(1, -130, 1, 0)
			local go = button(e, "GO", ACCENT, BG)
			go.Position = UDim2.new(1, -116, 0.5, -13)
			go.Size = UDim2.new(0, 56, 0, 26)
			local del = button(e, "DEL", rgb(90, 30, 30))
			del.Position = UDim2.new(1, -54, 0.5, -13)
			del.Size = UDim2.new(0, 46, 0, 26)
			go.Activated:Connect(function()
				task.spawn(teleport, Vector3.new(spot.x, spot.y, spot.z), false, true)
			end)
			del.Activated:Connect(function()
				table.remove(cfg.saved, i)
				saveCfg()
				refreshSaved()
			end)
		end
	end

	saveBtn.Activated:Connect(function()
		local v = readBoxes() or myPosition()
		if not v then return end
		local name = nameBox.Text ~= "" and nameBox.Text or ("Spot " .. (#cfg.saved + 1))
		table.insert(cfg.saved, { name = name, x = math.floor(v.X + 0.5), y = math.floor(v.Y + 0.5), z = math.floor(v.Z + 0.5) })
		nameBox.Text = ""
		saveCfg()
		refreshSaved()
		setStatus("Saved " .. name)
	end)

	section(tpPage, "PLAYERS")
	local playerList = Instance.new("Frame")
	playerList.BackgroundTransparency = 1
	playerList.Size = UDim2.new(1, 0, 0, 0)
	playerList.AutomaticSize = Enum.AutomaticSize.Y
	playerList.LayoutOrder = nextOrder()
	playerList.Parent = tpPage
	local pl = Instance.new("UIListLayout")
	pl.Padding = UDim.new(0, 6)
	pl.SortOrder = Enum.SortOrder.LayoutOrder
	pl.Parent = playerList

	refreshPlayers = function()
		for _, c in ipairs(playerList:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local count = 0
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				count += 1
				local e = row(playerList, 36)
				e.LayoutOrder = count
				local l = label(e, other.DisplayName .. "  @" .. other.Name, 13, TXT)
				l.Position = UDim2.new(0, 10, 0, 0)
				l.Size = UDim2.new(1, -80, 1, 0)
				local go = button(e, "GO", ACCENT, BG)
				go.Position = UDim2.new(1, -66, 0.5, -13)
				go.Size = UDim2.new(0, 56, 0, 26)
				go.Activated:Connect(function()
					local hrp = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						task.spawn(teleport, hrp.Position + Vector3.new(0, 0, 4), false, true)
					else
						setStatus(other.DisplayName .. " has no character")
					end
				end)
			end
		end
		if count == 0 then
			local e = row(playerList, 30, true)
			label(e, "  No other players", 12, SUB).Size = UDim2.new(1, 0, 1, 0)
		end
	end
	track(Players.PlayerAdded:Connect(function() refreshPlayers() end))
	track(Players.PlayerRemoving:Connect(function() task.defer(refreshPlayers) end))

	refreshSaved()
	refreshPlayers()
end

---------------------------------------------------------------- PORTAL tab
local portalPage = makePage("PORTAL")
do
	section(portalPage, "PORTAL")
	toggle(portalPage, "Keep portals open (until next shot)", "keepOpen")
	slider(portalPage, "Portal lifetime (if not kept open)", "portalLifetime", 1, 120, 1, "%.0f s")
	slider(portalPage, "Portal size", "portalSize", 3, 30, 1, "%.0f studs")
	toggle(portalPage, "Jump in automatically", "autoJump")
	slider(portalPage, "Auto-jump delay", "travelDelay", 0, 2, 0.05, "%.2f s")
	toggle(portalPage, "Show portals (off = instant teleport)", "showPortals")

	local rc = row(portalPage, 36, true)
	local closeAll = button(rc, "CLOSE PORTALS", rgb(90, 30, 30))
	closeAll.Size = UDim2.new(1, 0, 1, 0)
	closeAll.Activated:Connect(function()
		closeAllPortals()
		setStatus("Portals closed")
	end)

	section(portalPage, "COLOR")
	local r = row(portalPage, 40, true)
	local strokes = {}
	for i, th in ipairs(THEMES) do
		local b = button(r, "", th.rim)
		b.Size = UDim2.new(1 / #THEMES, -6, 1, 0)
		b.Position = UDim2.new((i - 1) / #THEMES, 3, 0, 0)
		strokes[i] = outline(b, 3, TXT, 1)
		b.Activated:Connect(function()
			cfg.theme = i
			saveCfg()
			refreshAll()
		end)
	end
	table.insert(refreshers, function()
		for i, s in ipairs(strokes) do
			s.Transparency = (i == cfg.theme) and 0 or 1
		end
	end)

	local r2 = row(portalPage, 36, true)
	local test = button(r2, "TEST PORTAL (in front of you)")
	test.Size = UDim2.new(1, 0, 1, 0)
	test.Activated:Connect(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
			makePortal(root.Position + flat * math.max(8, cfg.portalSize / 2 + 4) + Vector3.new(0, cfg.portalSize / 2 - 3, 0), flat, nil, 4)
		end
	end)
end

---------------------------------------------------------------- GUN tab
local gunPage = makePage("GUN")
do
	section(gunPage, "GUN")
	slider(gunPage, "Cooldown", "cooldown", 0, 5, 0.1, "%.1f s")
	toggle(gunPage, "No distance limit", "noDistanceLimit")
	slider(gunPage, "Max teleport distance (if limited)", "maxDistance", 100, 1000000, 100, "%.0f studs")
	slider(gunPage, "Aim range", "aimRange", 100, 50000, 100, "%.0f studs")
	toggle(gunPage, "Click with the gun to teleport", "clickTeleport")
	toggle(gunPage, "Show \"Select a dimension\" panel", "showDimensions", refreshDimGui)

	section(gunPage, "OTHER")
	local r = row(gunPage, 36, true)
	local give = button(r, "GIVE GUN AGAIN")
	give.Size = UDim2.new(0.5, -4, 1, 0)
	give.Activated:Connect(function()
		giveGun()
		setStatus("Gun is in your backpack")
	end)
	local reset = button(r, "RESET SETTINGS", rgb(90, 30, 30))
	reset.Position = UDim2.new(0.5, 4, 0, 0)
	reset.Size = UDim2.new(0.5, -4, 1, 0)
	reset.Activated:Connect(function()
		resetCfg(true)
		saveCfg()
		refreshAll()
		setStatus("Settings reset (saved places kept)")
	end)

	local note = row(gunPage, 40, true)
	local n = label(note, canSave and "Settings are saved to " .. SAVE_FILE or "Settings reset when you leave (no writefile)", 12, SUB)
	n.Size = UDim2.new(1, 0, 1, 0)
	n.TextWrapped = true
end

showPage("TELEPORT")
refreshAll()

--==============================================================
--  give the gun (again after every respawn)
--==============================================================
giveGun = function()
	local backpack = player:WaitForChild("Backpack")
	if currentTool and currentTool.Parent then
		currentTool:Destroy()
	end
	for _, old in ipairs({ backpack:FindFirstChild(TOOL_NAME), player.Character and player.Character:FindFirstChild(TOOL_NAME) }) do
		if old then old:Destroy() end
	end
	equipped = false
	busy = false
	refreshDimGui()

	local tool, data = buildTool()
	currentTool, gun = tool, data

	tool.Equipped:Connect(function()
		equipped = true
		refreshDimGui()
	end)
	tool.Unequipped:Connect(function()
		equipped = false
		refreshDimGui()
	end)
	tool.Activated:Connect(function()
		if cfg.clickTeleport then
			teleport(aimPosition(), true, false)
		end
	end)

	tool.Parent = backpack
end

track(player.CharacterAdded:Connect(function()
	task.wait(0.2) -- let the new Backpack appear
	giveGun()
end))
if player.Character then
	giveGun()
end

_G.PortalGunCleanup = function()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	if dimGui then dimGui:Destroy() end
	if adminGui then adminGui:Destroy() end
	if currentTool then currentTool:Destroy() end
	for _, p in ipairs(activePortals) do
		p.model:Destroy()
	end
end
