--[[
    NightFall | Paint And SEEK!
    Hider ESP · Auto Paint · Seeker Auto Win
    PC + Mobile
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer

local Config = {
    HiderESP = false,
    SeekerESP = false,
    AutoPaint = false,
    AutoPaintInterval = 0.35,
    AutoLockStand = false,
    SeekerAutoWin = false,
    SeekerDelay = 0.45,
    SeekerBehindOffset = 3.5,
    AntiAFK = true,
}

local COLORS = {
    bg = Color3.fromRGB(13, 14, 18),
    sidebar = Color3.fromRGB(16, 17, 23),
    surface = Color3.fromRGB(22, 24, 31),
    surfaceHover = Color3.fromRGB(28, 30, 40),
    elevated = Color3.fromRGB(34, 36, 46),
    border = Color3.fromRGB(44, 46, 58),
    tabActive = Color3.fromRGB(99, 102, 241),
    tabActiveBg = Color3.fromRGB(28, 30, 48),
    text = Color3.fromRGB(236, 237, 242),
    textMuted = Color3.fromRGB(128, 132, 150),
    accent = Color3.fromRGB(99, 102, 241),
    accentLight = Color3.fromRGB(129, 140, 248),
    success = Color3.fromRGB(52, 211, 153),
    danger = Color3.fromRGB(239, 68, 68),
    toggleOff = Color3.fromRGB(55, 58, 72),
    toggleOn = Color3.fromRGB(99, 102, 241),
    hiderESP = Color3.fromRGB(56, 189, 248),
    seekerESP = Color3.fromRGB(239, 68, 68),
}

local RADIUS = { sm = 6, md = 10, lg = 14, xl = 20, full = 999 }
local SIDEBAR_WIDTH = 132
local PLACE_ID = 78724049937437

local UI = {}
local State = {
    isMobile = false,
    toggleCubeSize = 44,
    role = "Unknown",
    connections = {},
    espHighlights = {},
    espBillboards = {},
    statusText = "Ready",
    lastPaintColor = nil,
    seekerRunning = false,
}

local GameBridge = {
    paintRemotes = {},
    tagRemotes = {},
    knifeToolNames = { "Knife", "knife", "SeekerKnife", "Seeker Knife", "Blade" },
    paintToolNames = { "Paint", "Pipette", "Paint Tool", "Brush", "Color" },
}

local function bind(conn)
    table.insert(State.connections, conn)
    return conn
end

local function detectMobile()
    if typeof(getgenv) == "function" then
        local ok, g = pcall(getgenv)
        if ok and type(g) == "table" then
            if g.NF_FORCE_MOBILE == true then return true end
            if g.NF_FORCE_MOBILE == false then return false end
        end
    end
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return true end
    if UserInputService.TouchEnabled and UserInputService.GyroscopeEnabled then return true end
    local cam = Workspace.CurrentCamera
    if cam then
        local vp = cam.ViewportSize
        if vp.X > 0 and vp.Y > vp.X and vp.X < 980 then return true end
    end
    return UserInputService.TouchEnabled == true
end

State.isMobile = detectMobile()

local function getGuiParent()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    return pg or CoreGui
end

local function getCharacter(player)
    player = player or LocalPlayer
    return player and player.Character
end

local function getRoot(player)
    local char = getCharacter(player)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(player)
    local char = getCharacter(player)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(player)
    local hum = getHumanoid(player)
    return hum and hum.Health > 0
end

local function applyCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or RADIUS.md)
    c.Parent = parent
    return c
end

local function applyStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or COLORS.border
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0.55
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function tween(instance, props, duration)
    TweenService:Create(instance, TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props):Play()
end

local function setStatus(text)
    State.statusText = text
    if UI.StatusLabel then
        UI.StatusLabel.Text = text
    end
end

local function scanRemotes(root, bucket, keywords)
    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
            local name = string.lower(inst.Name)
            for _, kw in ipairs(keywords) do
                if string.find(name, kw, 1, true) then
                    table.insert(bucket, inst)
                    break
                end
            end
        end
    end
end

local function discoverGameBridge()
    GameBridge.paintRemotes = {}
    GameBridge.tagRemotes = {}
    scanRemotes(ReplicatedStorage, GameBridge.paintRemotes, {
        "paint", "color", "pipette", "camo", "blend", "dye", "brush",
    })
    scanRemotes(ReplicatedStorage, GameBridge.tagRemotes, {
        "tag", "stab", "hit", "kill", "seek", "knife", "attack", "catch", "found",
    })
end

discoverGameBridge()
bind(ReplicatedStorage.DescendantAdded:Connect(function(inst)
    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
        task.defer(discoverGameBridge)
    end
end))

local function readRoleFromPlayer(player)
    local attrs = { "Role", "role", "TeamRole", "CurrentRole", "PlayerRole", "Side" }
    for _, key in ipairs(attrs) do
        local ok, val = pcall(function() return player:GetAttribute(key) end)
        if ok and type(val) == "string" then
            local lower = string.lower(val)
            if string.find(lower, "seek", 1, true) then return "Seeker" end
            if string.find(lower, "hid", 1, true) then return "Hider" end
        end
    end
    local ls = player:FindFirstChild("leaderstats") or player:FindFirstChild("Leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            if v:IsA("StringValue") or v:IsA("ObjectValue") then
                local lower = string.lower(tostring(v.Value))
                if string.find(lower, "seek", 1, true) then return "Seeker" end
                if string.find(lower, "hid", 1, true) then return "Hider" end
            end
        end
    end
    return nil
end

local function playerHasToolLike(player, names)
    local function check(container)
        if not container then return false end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local n = string.lower(tool.Name)
                for _, want in ipairs(names) do
                    if string.find(n, string.lower(want), 1, true) then
                        return true
                    end
                end
            end
        end
        return false
    end
    return check(getCharacter(player)) or check(player:FindFirstChildOfClass("Backpack"))
end

local function refreshRole()
    local role = readRoleFromPlayer(LocalPlayer)
    if not role then
        if playerHasToolLike(LocalPlayer, GameBridge.knifeToolNames) then
            role = "Seeker"
        elseif playerHasToolLike(LocalPlayer, GameBridge.paintToolNames) then
            role = "Hider"
        else
            role = "Unknown"
        end
    end
    State.role = role
    if UI.RoleLabel then
        UI.RoleLabel.Text = "Role: " .. role
        UI.RoleLabel.TextColor3 = role == "Seeker" and COLORS.danger or (role == "Hider" and COLORS.success or COLORS.textMuted)
    end
    return role
end

local function isSeeker(player)
    player = player or LocalPlayer
    if player == LocalPlayer then
        return State.role == "Seeker"
    end
    local role = readRoleFromPlayer(player)
    if role == "Seeker" then return true end
    if role == "Hider" then return false end
    return playerHasToolLike(player, GameBridge.knifeToolNames)
end

local function isHider(player)
    player = player or LocalPlayer
    if player == LocalPlayer then
        return State.role == "Hider"
    end
    if player == LocalPlayer then return false end
    local role = readRoleFromPlayer(player)
    if role == "Hider" then return true end
    if role == "Seeker" then return false end
    return not playerHasToolLike(player, GameBridge.knifeToolNames)
end

local function findTool(names)
    local char = getCharacter()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({ char, backpack }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local n = string.lower(tool.Name)
                    for _, want in ipairs(names) do
                        if string.find(n, string.lower(want), 1, true) then
                            return tool
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function equipTool(tool)
    if not tool then return false end
    local hum = getHumanoid()
    if not hum then return false end
    pcall(function() hum:UnequipTools() end)
    if tool.Parent ~= LocalPlayer.Backpack and tool.Parent ~= getCharacter() then return false end
    pcall(function() hum:EquipTool(tool) end)
    return true
end

local function simulateClick()
    if State.isMobile then
        pcall(function()
            local cam = Workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(960, 540)
            local x, y = vp.X * 0.5, vp.Y * 0.5
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.03)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    else
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.03)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
        pcall(function()
            local tool = findTool(GameBridge.knifeToolNames)
            if tool then tool:Activate() end
        end)
    end
end

local function fireTagRemotes(target)
    local root = getRoot(target)
    if not root then return end
    for _, remote in ipairs(GameBridge.tagRemotes) do
        pcall(function()
            if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
                remote:FireServer(target, root, target.Character)
                remote:FireServer(root)
                remote:FireServer(target)
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer(target, root, target.Character)
            end
        end)
    end
    local char = getCharacter(target)
    if char then
        local hum = getHumanoid(target)
        pcall(function()
            if hum then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        firetouchinterest(getRoot(), part, 0)
                        firetouchinterest(getRoot(), part, 1)
                    end
                end
            end
        end)
    end
end

local function getRayIgnoreList()
    local list = { getCharacter(), Workspace.CurrentCamera }
    for _, h in pairs(State.espHighlights) do
        table.insert(list, h)
    end
    return list
end

local function sampleSurfaceColor()
    local root = getRoot()
    if not root then return nil, nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = getRayIgnoreList()
    params.IgnoreWater = true

    local origin = root.Position
    local dirs = {
        Vector3.new(0, -1, 0),
        root.CFrame.LookVector,
        -root.CFrame.LookVector,
        root.CFrame.RightVector,
        -root.CFrame.RightVector,
        (root.CFrame.LookVector + root.CFrame.RightVector).Unit,
        (root.CFrame.LookVector - root.CFrame.RightVector).Unit,
        (-root.CFrame.LookVector + root.CFrame.RightVector).Unit,
        (-root.CFrame.LookVector - root.CFrame.RightVector).Unit,
    }

    local bestPart, bestColor, bestDist = nil, nil, math.huge
    for _, dir in ipairs(dirs) do
        local result = Workspace:Raycast(origin, dir * 12, params)
        if result and result.Instance and result.Instance:IsA("BasePart") then
            local dist = (result.Position - origin).Magnitude
            if dist < bestDist then
                bestDist = dist
                bestPart = result.Instance
                bestColor = result.Instance.Color
            end
        end
    end
    return bestPart, bestColor
end

local function applyLocalBodyColor(color)
    if not color then return end
    local char = getCharacter()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.Color = color
        end
    end
    local bc = char:FindFirstChildOfClass("BodyColors")
    if bc then
        pcall(function()
            bc.HeadColor3 = color
            bc.TorsoColor3 = color
            bc.LeftArmColor3 = color
            bc.RightArmColor3 = color
            bc.LeftLegColor3 = color
            bc.RightLegColor3 = color
        end)
    end
end

local function tryPaintRemote(part, color)
    if not part or not color then return false end
    local sent = false
    for _, remote in ipairs(GameBridge.paintRemotes) do
        local ok = pcall(function()
            if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
                remote:FireServer(part, color)
                remote:FireServer(color)
                remote:FireServer(part)
                remote:FireServer(part, color, true)
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer(part, color)
            end
        end)
        sent = sent or ok
    end
    return sent
end

local function autoPaintOnce()
    local part, color = sampleSurfaceColor()
    if not color then
        setStatus("Auto Paint: no surface found")
        return
    end
    State.lastPaintColor = color
    tryPaintRemote(part, color)
    applyLocalBodyColor(color)
    if UI.PaintPreview then
        UI.PaintPreview.BackgroundColor3 = color
    end
    setStatus(string.format("Auto Paint: matched RGB(%d,%d,%d)", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255)))
end

local function clearESP()
    for _, obj in pairs(State.espHighlights) do
        pcall(function() obj:Destroy() end)
    end
    for _, obj in pairs(State.espBillboards) do
        pcall(function() obj:Destroy() end)
    end
    State.espHighlights = {}
    State.espBillboards = {}
end

local function ensureHighlight(player, color, labelText)
    if not player or player == LocalPlayer then return end
    local char = getCharacter(player)
    if not char then return end

    local key = player.UserId
    local highlight = State.espHighlights[key]
    if not highlight or not highlight.Parent then
        highlight = Instance.new("Highlight")
        highlight.Name = "NightFallPAS_ESP"
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = char
        State.espHighlights[key] = highlight
    end
    highlight.Adornee = char
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.55
    highlight.OutlineTransparency = 0.1

    local root = getRoot(player)
    if root then
        local bb = State.espBillboards[key]
        if not bb or not bb.Parent then
            bb = Instance.new("BillboardGui")
            bb.Name = "NightFallPAS_Tag"
            bb.Size = UDim2.new(0, 120, 0, 28)
            bb.StudsOffset = Vector3.new(0, 2.8, 0)
            bb.AlwaysOnTop = true
            bb.Parent = root
            local tl = Instance.new("TextLabel")
            tl.Name = "Label"
            tl.Size = UDim2.new(1, 0, 1, 0)
            tl.BackgroundTransparency = 0.35
            tl.BackgroundColor3 = COLORS.bg
            tl.TextColor3 = color
            tl.Font = Enum.Font.GothamBold
            tl.TextSize = 12
            tl.Text = labelText
            applyCorner(tl, RADIUS.sm)
            tl.Parent = bb
            State.espBillboards[key] = bb
        else
            local tl = bb:FindFirstChild("Label")
            if tl then tl.Text = labelText end
        end
    end
end

local function updateESP()
    clearESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isAlive(player) and getCharacter(player) then
            if Config.HiderESP and isHider(player) then
                ensureHighlight(player, COLORS.hiderESP, "HIDER · " .. player.Name)
            elseif Config.SeekerESP and isSeeker(player) then
                ensureHighlight(player, COLORS.seekerESP, "SEEKER · " .. player.Name)
            end
        end
    end
end

local function teleportBehind(target, offset)
    local myRoot = getRoot()
    local targetRoot = getRoot(target)
    if not myRoot or not targetRoot then return false end
    offset = offset or Config.SeekerBehindOffset
    local look = targetRoot.CFrame.LookVector
    local pos = targetRoot.Position - look * offset
    myRoot.CFrame = CFrame.new(pos, targetRoot.Position)
    return true
end

local function getSeekerTargets()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isAlive(player) and getCharacter(player) and isHider(player) then
            table.insert(list, player)
        end
    end
    table.sort(list, function(a, b)
        local ar, br = getRoot(a), getRoot(b)
        local mr = getRoot()
        if not mr then return false end
        if not ar then return false end
        if not br then return true end
        return (ar.Position - mr.Position).Magnitude < (br.Position - mr.Position).Magnitude
    end)
    return list
end

local function seekerAutoWinLoop()
    if State.seekerRunning then return end
    State.seekerRunning = true
    while Config.SeekerAutoWin do
        refreshRole()
        if State.role ~= "Seeker" then
            setStatus("Seeker Auto Win: you are not Seeker")
            task.wait(1)
        else
            local knife = findTool(GameBridge.knifeToolNames)
            if knife then equipTool(knife) end
            local targets = getSeekerTargets()
            if #targets == 0 then
                setStatus("Seeker Auto Win: no hiders left")
                task.wait(0.75)
            else
                for _, target in ipairs(targets) do
                    if not Config.SeekerAutoWin then break end
                    if isAlive(target) and getCharacter(target) then
                        teleportBehind(target)
                        task.wait(0.08)
                        if knife then equipTool(knife) end
                        simulateClick()
                        fireTagRemotes(target)
                        pcall(function()
                            if knife then
                                knife:Activate()
                                for _ = 1, 3 do
                                    knife:Activate()
                                    task.wait(0.05)
                                end
                            end
                        end)
                        setStatus("Seeker Auto Win: tagged " .. target.Name)
                        task.wait(Config.SeekerDelay)
                    end
                end
            end
        end
        task.wait(0.15)
    end
    State.seekerRunning = false
end

local function setHubToggle(btn, enabled)
    local track = btn:FindFirstChild("SwitchTrack")
    local knob = track and track:FindFirstChild("SwitchKnob")
    if track then
        track.BackgroundColor3 = enabled and COLORS.toggleOn or COLORS.toggleOff
    end
    if knob then
        tween(knob, {
            Position = enabled and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
        })
    end
end

local function createHubButton(parent, title, subtitle)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, subtitle and 54 or 46)
    btn.BackgroundColor3 = COLORS.surface
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = parent
    applyCorner(btn, RADIUS.md)
    applyStroke(btn, COLORS.border, 1, 0.65)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -110, 0, 18)
    titleLabel.Position = UDim2.new(0, 14, 0, subtitle and 10 or 14)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = COLORS.text
    titleLabel.TextSize = 14
    titleLabel.Font = Enum.Font.GothamSemibold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = btn

    if subtitle then
        local subLabel = Instance.new("TextLabel")
        subLabel.Size = UDim2.new(1, -110, 0, 14)
        subLabel.Position = UDim2.new(0, 14, 0, 30)
        subLabel.BackgroundTransparency = 1
        subLabel.Text = subtitle
        subLabel.TextColor3 = COLORS.textMuted
        subLabel.TextSize = 11
        subLabel.Font = Enum.Font.GothamMedium
        subLabel.TextXAlignment = Enum.TextXAlignment.Left
        subLabel.Parent = btn
    end

    local switchTrack = Instance.new("Frame")
    switchTrack.Name = "SwitchTrack"
    switchTrack.Size = UDim2.new(0, 44, 0, 22)
    switchTrack.Position = UDim2.new(1, -58, 0.5, -11)
    switchTrack.BackgroundColor3 = COLORS.toggleOff
    switchTrack.Parent = btn
    applyCorner(switchTrack, RADIUS.full)

    local switchKnob = Instance.new("Frame")
    switchKnob.Name = "SwitchKnob"
    switchKnob.Size = UDim2.new(0, 18, 0, 18)
    switchKnob.Position = UDim2.new(0, 2, 0.5, -9)
    switchKnob.BackgroundColor3 = COLORS.text
    switchKnob.Parent = switchTrack
    applyCorner(switchKnob, RADIUS.full)

    btn.MouseEnter:Connect(function() tween(btn, { BackgroundColor3 = COLORS.surfaceHover }) end)
    btn.MouseLeave:Connect(function() tween(btn, { BackgroundColor3 = COLORS.surface }) end)
    return btn
end

local function createActionButton(parent, title, subtitle)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, subtitle and 50 or 42)
    btn.BackgroundColor3 = COLORS.elevated
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = parent
    applyCorner(btn, RADIUS.md)
    applyStroke(btn, COLORS.border, 1, 0.55)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 18)
    titleLabel.Position = UDim2.new(0, 14, 0, subtitle and 8 or 12)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = COLORS.text
    titleLabel.TextSize = 14
    titleLabel.Font = Enum.Font.GothamSemibold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = btn

    if subtitle then
        local subLabel = Instance.new("TextLabel")
        subLabel.Size = UDim2.new(1, -20, 0, 14)
        subLabel.Position = UDim2.new(0, 14, 0, 28)
        subLabel.BackgroundTransparency = 1
        subLabel.Text = subtitle
        subLabel.TextColor3 = COLORS.textMuted
        subLabel.TextSize = 11
        subLabel.Font = Enum.Font.GothamMedium
        subLabel.TextXAlignment = Enum.TextXAlignment.Left
        subLabel.Parent = btn
    end

    btn.MouseEnter:Connect(function() tween(btn, { BackgroundColor3 = COLORS.surfaceHover }) end)
    btn.MouseLeave:Connect(function() tween(btn, { BackgroundColor3 = COLORS.elevated }) end)
    return btn
end

local function makeDraggable(frame, handle)
    local dragging, dragStart, frameStart = false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            frameStart = frame.Position
        end
    end)
    bind(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + delta.X, frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
        end
    end))
    bind(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

-- UI
for _, name in ipairs({ "NightFallPAS", "PaintAndSeekNF" }) do
    local old = CoreGui:FindFirstChild(name)
    if old then old:Destroy() end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg and pg:FindFirstChild(name) then pg[name]:Destroy() end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NightFallPAS"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

UI.ToggleGui = Instance.new("Frame")
UI.ToggleGui.Size = UDim2.new(0, State.toggleCubeSize, 0, State.toggleCubeSize)
UI.ToggleGui.Position = UDim2.new(0.5, -math.floor(State.toggleCubeSize / 2), 0, 14)
UI.ToggleGui.BackgroundTransparency = 1
UI.ToggleGui.Parent = ScreenGui

UI.ToggleCube = Instance.new("TextButton")
UI.ToggleCube.Size = UDim2.new(1, 0, 1, 0)
UI.ToggleCube.BackgroundColor3 = COLORS.surface
UI.ToggleCube.Text = ""
UI.ToggleCube.AutoButtonColor = false
UI.ToggleCube.Parent = UI.ToggleGui
applyCorner(UI.ToggleCube, math.clamp(math.floor(State.toggleCubeSize * 0.22), 4, 14))
applyStroke(UI.ToggleCube, COLORS.accent, 1.5, 0.2)

UI.ToggleIcon = Instance.new("TextLabel")
UI.ToggleIcon.Size = UDim2.new(1, 0, 1, 0)
UI.ToggleIcon.BackgroundTransparency = 1
UI.ToggleIcon.Text = "NF"
UI.ToggleIcon.TextColor3 = COLORS.accentLight
UI.ToggleIcon.TextSize = math.clamp(math.floor(State.toggleCubeSize * 0.44), 10, 28)
UI.ToggleIcon.Font = Enum.Font.GothamBold
UI.ToggleIcon.Parent = UI.ToggleCube

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, State.isMobile and 360 or 620, 0, State.isMobile and 500 or 580)
MainFrame.Position = UDim2.new(0.5, State.isMobile and -180 or -310, 0.5, State.isMobile and -250 or -290)
MainFrame.BackgroundColor3 = COLORS.bg
MainFrame.BorderSizePixel = 0
MainFrame.Visible = false
MainFrame.Active = true
MainFrame.Parent = ScreenGui
applyCorner(MainFrame, RADIUS.xl)
applyStroke(MainFrame, COLORS.border, 1, 0.45)

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 52)
Header.BackgroundColor3 = COLORS.sidebar
Header.BorderSizePixel = 0
Header.Parent = MainFrame
applyCorner(Header, RADIUS.xl)

local HeaderAccent = Instance.new("Frame")
HeaderAccent.Size = UDim2.new(1, 0, 0, 3)
HeaderAccent.BackgroundColor3 = COLORS.accent
HeaderAccent.BorderSizePixel = 0
HeaderAccent.Parent = Header

local HubTitle = Instance.new("TextLabel")
HubTitle.Size = UDim2.new(1, -60, 0, 22)
HubTitle.Position = UDim2.new(0, 16, 0, 10)
HubTitle.BackgroundTransparency = 1
HubTitle.Text = "NightFall"
HubTitle.TextColor3 = COLORS.text
HubTitle.TextSize = 18
HubTitle.Font = Enum.Font.GothamBold
HubTitle.TextXAlignment = Enum.TextXAlignment.Left
HubTitle.Parent = Header

local HubSubtitle = Instance.new("TextLabel")
HubSubtitle.Size = UDim2.new(1, -60, 0, 16)
HubSubtitle.Position = UDim2.new(0, 16, 0, 30)
HubSubtitle.BackgroundTransparency = 1
HubSubtitle.Text = "Paint And SEEK!"
HubSubtitle.TextColor3 = COLORS.textMuted
HubSubtitle.TextSize = 11
HubSubtitle.Font = Enum.Font.GothamMedium
HubSubtitle.TextXAlignment = Enum.TextXAlignment.Left
HubSubtitle.Parent = Header

UI.CloseBtn = Instance.new("TextButton")
UI.CloseBtn.Size = UDim2.new(0, 28, 0, 28)
UI.CloseBtn.Position = UDim2.new(1, -38, 0.5, -14)
UI.CloseBtn.BackgroundColor3 = COLORS.elevated
UI.CloseBtn.Text = "–"
UI.CloseBtn.TextColor3 = COLORS.textMuted
UI.CloseBtn.TextSize = 16
UI.CloseBtn.Font = Enum.Font.GothamBold
UI.CloseBtn.AutoButtonColor = false
UI.CloseBtn.Parent = Header
applyCorner(UI.CloseBtn, RADIUS.sm)

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -68)
Sidebar.Position = UDim2.new(0, 10, 0, 58)
Sidebar.BackgroundColor3 = COLORS.sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame
applyCorner(Sidebar, RADIUS.xl)

local NavList = Instance.new("Frame")
NavList.Size = UDim2.new(1, -12, 1, -12)
NavList.Position = UDim2.new(0, 6, 0, 6)
NavList.BackgroundTransparency = 1
NavList.Parent = Sidebar
Instance.new("UIListLayout", NavList).Padding = UDim.new(0, 6)

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 20), 1, -68)
Content.Position = UDim2.new(0, SIDEBAR_WIDTH + 10, 0, 58)
Content.BackgroundColor3 = COLORS.surface
Content.BorderSizePixel = 0
Content.Parent = MainFrame
applyCorner(Content, RADIUS.xl)

local pages, tabButtons = {}, {}

local function createTab(name, icon)
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, -12, 1, -12)
    page.Position = UDim2.new(0, 6, 0, 6)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = COLORS.border
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = Content
    local layout = Instance.new("UIListLayout", page)
    layout.Padding = UDim.new(0, 8)
    local pad = Instance.new("UIPadding", page)
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 8)
    pages[name] = page

    local tabBtn = Instance.new("TextButton")
    tabBtn.Size = UDim2.new(1, 0, 0, 36)
    tabBtn.BackgroundColor3 = COLORS.sidebar
    tabBtn.Text = ""
    tabBtn.AutoButtonColor = false
    tabBtn.Parent = NavList
    applyCorner(tabBtn, RADIUS.md)

    local tabIcon = Instance.new("TextLabel")
    tabIcon.Size = UDim2.new(0, 18, 1, 0)
    tabIcon.Position = UDim2.new(0, 10, 0, 0)
    tabIcon.BackgroundTransparency = 1
    tabIcon.Text = icon
    tabIcon.TextColor3 = COLORS.textMuted
    tabIcon.TextSize = 12
    tabIcon.Font = Enum.Font.GothamBold
    tabIcon.Parent = tabBtn

    local tabLabel = Instance.new("TextLabel")
    tabLabel.Size = UDim2.new(1, -34, 1, 0)
    tabLabel.Position = UDim2.new(0, 28, 0, 0)
    tabLabel.BackgroundTransparency = 1
    tabLabel.Text = name
    tabLabel.TextColor3 = COLORS.textMuted
    tabLabel.TextSize = #name > 8 and 11 or 13
    tabLabel.Font = Enum.Font.GothamSemibold
    tabLabel.TextXAlignment = Enum.TextXAlignment.Left
    tabLabel.Parent = tabBtn

    tabButtons[name] = tabBtn
    return page
end

local function switchTab(name)
    for tabName, page in pairs(pages) do
        page.Visible = tabName == name
        local btn = tabButtons[tabName]
        if btn then
            btn.BackgroundColor3 = tabName == name and COLORS.tabActiveBg or COLORS.sidebar
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("TextLabel") then
                    child.TextColor3 = tabName == name and COLORS.tabActive or COLORS.textMuted
                end
            end
        end
    end
end

local HiderPage = createTab("Hider", "H")
local SeekerPage = createTab("Seeker", "S")
local InfoPage = createTab("Info", "i")
switchTab("Hider")
for name, btn in pairs(tabButtons) do btn.MouseButton1Click:Connect(function() switchTab(name) end) end

UI.RoleLabel = Instance.new("TextLabel")
UI.RoleLabel.Size = UDim2.new(1, -8, 0, 20)
UI.RoleLabel.BackgroundTransparency = 1
UI.RoleLabel.Text = "Role: Unknown"
UI.RoleLabel.TextColor3 = COLORS.textMuted
UI.RoleLabel.Font = Enum.Font.GothamBold
UI.RoleLabel.TextSize = 12
UI.RoleLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.RoleLabel.Parent = InfoPage

UI.StatusLabel = Instance.new("TextLabel")
UI.StatusLabel.Size = UDim2.new(1, -8, 0, 40)
UI.StatusLabel.BackgroundTransparency = 1
UI.StatusLabel.Text = State.statusText
UI.StatusLabel.TextColor3 = COLORS.textMuted
UI.StatusLabel.Font = Enum.Font.GothamMedium
UI.StatusLabel.TextSize = 11
UI.StatusLabel.TextWrapped = true
UI.StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
UI.StatusLabel.Parent = InfoPage

local paintPreviewRow = Instance.new("Frame")
paintPreviewRow.Size = UDim2.new(1, 0, 0, 42)
paintPreviewRow.BackgroundColor3 = COLORS.elevated
paintPreviewRow.Parent = InfoPage
applyCorner(paintPreviewRow, RADIUS.md)

local paintPreviewLabel = Instance.new("TextLabel")
paintPreviewLabel.Size = UDim2.new(1, -54, 1, 0)
paintPreviewLabel.Position = UDim2.new(0, 14, 0, 0)
paintPreviewLabel.BackgroundTransparency = 1
paintPreviewLabel.Text = "Last auto paint color"
paintPreviewLabel.TextColor3 = COLORS.text
paintPreviewLabel.Font = Enum.Font.GothamSemibold
paintPreviewLabel.TextSize = 12
paintPreviewLabel.TextXAlignment = Enum.TextXAlignment.Left
paintPreviewLabel.Parent = paintPreviewRow

UI.PaintPreview = Instance.new("Frame")
UI.PaintPreview.Size = UDim2.new(0, 28, 0, 28)
UI.PaintPreview.Position = UDim2.new(1, -40, 0.5, -14)
UI.PaintPreview.BackgroundColor3 = COLORS.surface
UI.PaintPreview.Parent = paintPreviewRow
applyCorner(UI.PaintPreview, RADIUS.sm)
applyStroke(UI.PaintPreview, COLORS.border, 1, 0.4)

-- Hider tab
UI.AutoPaintToggle = createHubButton(HiderPage, "Auto Paint", "Match nearest surface color")
UI.AutoPaintToggle.MouseButton1Click:Connect(function()
    Config.AutoPaint = not Config.AutoPaint
    setHubToggle(UI.AutoPaintToggle, Config.AutoPaint)
    setStatus(Config.AutoPaint and "Auto Paint enabled" or "Auto Paint disabled")
end)

UI.HiderESPToggle = createHubButton(HiderPage, "Hider ESP", "Highlight hiders (Seeker only)")
UI.HiderESPToggle.MouseButton1Click:Connect(function()
    Config.HiderESP = not Config.HiderESP
    setHubToggle(UI.HiderESPToggle, Config.HiderESP)
    updateESP()
end)

local paintNowBtn = createActionButton(HiderPage, "Paint Now", "Sample closest surface once")
paintNowBtn.MouseButton1Click:Connect(function() autoPaintOnce() end)

-- Seeker tab
UI.SeekerAutoWinToggle = createHubButton(SeekerPage, "Seeker Auto Win", "TP behind hiders + knife")
UI.SeekerAutoWinToggle.MouseButton1Click:Connect(function()
    Config.SeekerAutoWin = not Config.SeekerAutoWin
    setHubToggle(UI.SeekerAutoWinToggle, Config.SeekerAutoWin)
    if Config.SeekerAutoWin then
        task.spawn(seekerAutoWinLoop)
    end
end)

UI.SeekerESPToggle = createHubButton(SeekerPage, "Seeker ESP", "Highlight other seekers")
UI.SeekerESPToggle.MouseButton1Click:Connect(function()
    Config.SeekerESP = not Config.SeekerESP
    setHubToggle(UI.SeekerESPToggle, Config.SeekerESP)
    updateESP()
end)

local rescanBtn = createActionButton(InfoPage, "Rescan Remotes", "Refresh paint/tag remote list")
rescanBtn.MouseButton1Click:Connect(function()
    discoverGameBridge()
    setStatus(string.format("Remotes: %d paint · %d tag", #GameBridge.paintRemotes, #GameBridge.tagRemotes))
end)

makeDraggable(MainFrame, Header)
UI.ToggleCube.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
UI.CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

-- Loops
bind(RunService.Heartbeat:Connect(function()
    if Config.HiderESP or Config.SeekerESP then
        updateESP()
    end
end))

task.spawn(function()
    while true do
        refreshRole()
        if Config.AutoPaint and State.role == "Hider" then
            autoPaintOnce()
        end
        task.wait(Config.AutoPaintInterval)
    end
end)

bind(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    refreshRole()
    clearESP()
end))

bind(Players.PlayerAdded:Connect(function() task.defer(updateESP) end))
bind(Players.PlayerRemoving:Connect(function() task.defer(updateESP) end))

if Config.AntiAFK then
    bind(LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Button2, false, game)
            task.wait(0.1)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Button2, false, game)
        end)
    end))
end

refreshRole()
setStatus(string.format("Loaded · %s · Place %s", State.isMobile and "Mobile" or "PC", tostring(game.PlaceId)))
print("[NightFall] Paint And SEEK loaded · v1.0")
