local REMOTE_LOAD_ATTEMPTS = 3
local OBSIDIAN_REPO = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local CONFIG_ROOT = "DoomsdayUniversalHub"
local AUTOSAVE_PATH = CONFIG_ROOT .. "/universal_autosave.json"
local DOOMSDAY_SCRIPT_URL = getgenv().DOOMSDAY_SCRIPT_URL or "https://raw.githubusercontent.com/Milokinot/scripts/main/DOOMSDAY%20SCRIPT/DOOMSDAY.lua"
local MILO_UI_URL = getgenv().MILO_UI_URL or "https://raw.githubusercontent.com/Milokinot/scripts/main/DOOMSDAY%20SCRIPT/DOOMSDAY_OBSIDIAN_UNIVERSAL.lua"
local FIGURE_GRAB_OATS_URL = getgenv().FIGURE_GRAB_OATS_URL or "https://raw.githubusercontent.com/Milokinot/scripts/main/DOOMSDAY%20SCRIPT/modules/FIGURE_GRAB_OATS.lua"

local function hubWarn(message)
    warn("[DOOMSDAY UNIVERSAL] " .. tostring(message))
end

local function safeHttpLoad(url)
    local lastError

    for attempt = 1, REMOTE_LOAD_ATTEMPTS do
        local ok, source = pcall(function()
            return game:HttpGet(url)
        end)

        if ok and type(source) == "string" and source ~= "" then
            local compiled, chunk = pcall(loadstring, source)
            if compiled and chunk then
                local loaded, result = pcall(chunk)
                if loaded then
                    return result
                end

                lastError = result
            else
                lastError = chunk
            end
        else
            lastError = source
        end

        if attempt < REMOTE_LOAD_ATTEMPTS then
            task.wait(0.8)
        end
    end

    hubWarn("Falha ao carregar remoto: " .. url .. " | " .. tostring(lastError))
    return nil
end

local function isConfiguredUrl(url)
    return type(url) == "string"
        and url:match("^https?://") ~= nil
        and not url:find("COLE_AQUI", 1, true)
end

local Library = safeHttpLoad(OBSIDIAN_REPO .. "Library.lua")
local ThemeManager = safeHttpLoad(OBSIDIAN_REPO .. "addons/ThemeManager.lua")
local SaveManager = safeHttpLoad(OBSIDIAN_REPO .. "addons/SaveManager.lua")

if not Library or not ThemeManager or not SaveManager then
    return hubWarn("Obsidian/Managers nao puderam ser carregados.")
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Options = Library.Options
local Toggles = Library.Toggles

local DEFAULT_STATE = {
    optimization = {
        enabled = true,
        globalShadows = false,
        hideTextures = false,
        smoothMaterials = false,
        hideParticles = false,
        castShadows = false,
        brightness = 2,
        clockTime = 14,
        fogEnd = 100000,
        waterTransparency = 1,
        terrainDecoration = false,
    },
    visual = {
        fov = 70,
        zoom = 128,
        ambient = { r = 255, g = 255, b = 255 },
        outdoorAmbient = { r = 180, g = 180, b = 180 },
    },
    performance = {
        fpsUnlock = false,
        fpsCap = 240,
    },
    esp = {
        enabled = false,
        box = true,
        highlight = true,
        names = true,
        distance = true,
        tracers = false,
        teamCheck = false,
        useTeamColor = false,
        maxDistance = 2500,
        boxThickness = 2,
        fillTransparency = 0.8,
        outlineTransparency = 0,
        textSize = 13,
        color = { r = 255, g = 85, b = 85 },
        tracerThickness = 1.5,
    },
}

local trackedPartState = {}
local trackedDecalState = {}
local trackedEffectState = {}
local espCache = {}
local saveQueued = false
local selectedSpectatePlayer
local spectating = false
local selectedPlayerImage
local selectedPlayerNameLabel
local selectedPlayerInfoLabel

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copied = {}
    for key, inner in pairs(value) do
        copied[key] = deepCopy(inner)
    end

    return copied
end

local function deepMerge(base, incoming)
    for key, value in pairs(incoming or {}) do
        if type(value) == "table" and type(base[key]) == "table" then
            deepMerge(base[key], value)
        else
            base[key] = value
        end
    end

    return base
end

local function colorToTable(color)
    return {
        r = math.floor(color.R * 255 + 0.5),
        g = math.floor(color.G * 255 + 0.5),
        b = math.floor(color.B * 255 + 0.5),
    }
end

local function tableToColor(data, fallback)
    if type(data) ~= "table" then
        return fallback
    end

    return Color3.fromRGB(data.r or 255, data.g or 255, data.b or 255)
end

local state = deepCopy(DEFAULT_STATE)

local function ensureConfigFolder()
    if makefolder and not isfolder(CONFIG_ROOT) then
        makefolder(CONFIG_ROOT)
    end
end

local function saveAutosave()
    if not writefile then
        return
    end

    ensureConfigFolder()
    writefile(AUTOSAVE_PATH, HttpService:JSONEncode(state))
end

local function queueSave()
    if saveQueued then
        return
    end

    saveQueued = true
    task.delay(0.2, function()
        saveQueued = false
        pcall(saveAutosave)
    end)
end

local function loadAutosave()
    if not readfile or not isfile or not isfile(AUTOSAVE_PATH) then
        return
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(AUTOSAVE_PATH))
    end)

    if ok and type(decoded) == "table" then
        state = deepMerge(state, decoded)
    end
end

loadAutosave()

local function setPath(root, path, value)
    local cursor = root

    for index = 1, #path - 1 do
        local key = path[index]
        cursor[key] = cursor[key] or {}
        cursor = cursor[key]
    end

    cursor[path[#path]] = value
    queueSave()
end

local function safeNotify(title, description)
    pcall(function()
        Library:Notify({
            Title = title,
            Description = description,
            Time = 4,
        })
    end)
end

getgenv().DoomsdayNotify = function(title, description, duration)
    pcall(function()
        Library:Notify({
            Title = tostring(title),
            Description = tostring(description),
            Time = duration or 4,
        })
    end)
end

local function buildRemoteLoadstring(url)
    return ('loadstring(game:HttpGet("%s"))()'):format(url)
end

local function getQueueOnTeleport()
    return rawget(getgenv(), "queue_on_teleport")
        or rawget(getgenv(), "queueonteleport")
        or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
end

local function queueDoomsdayOnTeleport()
    if not isConfiguredUrl(DOOMSDAY_SCRIPT_URL) then
        safeNotify("Doomsday", "Configure DOOMSDAY_SCRIPT_URL com o raw do DOOMSDAY.lua.")
        return false
    end

    local queueFunction = getQueueOnTeleport()
    if type(queueFunction) ~= "function" then
        safeNotify("Rejoin", "Executor sem suporte para queue_on_teleport.")
        return false
    end

    local payload = buildRemoteLoadstring(DOOMSDAY_SCRIPT_URL)
    if isConfiguredUrl(MILO_UI_URL) then
        payload = payload .. "\n" .. buildRemoteLoadstring(MILO_UI_URL)
    end

    local ok, err = pcall(queueFunction, payload)
    if not ok then
        safeNotify("Rejoin", "Falha no queue_on_teleport: " .. tostring(err))
        return false
    end

    safeNotify("Rejoin", "Doomsday ficou na fila do teleport.")
    return true
end

local function rejoinWithDoomsday()
    if not queueDoomsdayOnTeleport() then
        return
    end

    local TeleportService = game:GetService("TeleportService")
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)

    if not ok then
        hubWarn("TeleportToPlaceInstance falhou, tentando Teleport: " .. tostring(err))
        pcall(function()
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end)
    end
end

local figureGrabModule

local function loadFigureGrabModule()
    if figureGrabModule then
        return figureGrabModule
    end

    if getgenv().FigureGrabModule and type(getgenv().FigureGrabModule.ToggleFigureGrab) == "function" then
        figureGrabModule = getgenv().FigureGrabModule
        return figureGrabModule
    end

    if not isConfiguredUrl(FIGURE_GRAB_OATS_URL) then
        safeNotify("Figure Grab", "Configure FIGURE_GRAB_OATS_URL com o raw do modulo Oats.")
        return nil
    end

    figureGrabModule = safeHttpLoad(FIGURE_GRAB_OATS_URL)
    if figureGrabModule and type(figureGrabModule.ToggleFigureGrab) == "function" then
        safeNotify("Figure Grab", "Modulo Oats carregado.")
        return figureGrabModule
    end

    figureGrabModule = nil
    safeNotify("Figure Grab", "Nao consegui carregar o modulo Oats.")
    return nil
end

local function withFigureGrab(callback)
    local module = loadFigureGrabModule()
    if module then
        callback(module)
    end
end

local function getFpsCapFunction()
    return rawget(getgenv(), "setfpscap")
        or rawget(getgenv(), "set_fps_cap")
        or rawget(getgenv(), "setfpslimit")
end

local function applyFpsCap()
    local fpsFunction = getFpsCapFunction()
    if type(fpsFunction) ~= "function" then
        return false
    end

    local targetCap = state.performance.fpsUnlock and 0 or state.performance.fpsCap
    local ok, err = pcall(fpsFunction, targetCap)
    if not ok then
        hubWarn("Falha ao aplicar fps cap: " .. tostring(err))
        return false
    end

    return true
end

local function rememberPart(part)
    if trackedPartState[part] then
        return trackedPartState[part]
    end

    trackedPartState[part] = {
        Material = part.Material,
        CastShadow = part.CastShadow,
        Reflectance = part.Reflectance,
    }

    return trackedPartState[part]
end

local function rememberDecal(instance)
    if trackedDecalState[instance] then
        return trackedDecalState[instance]
    end

    trackedDecalState[instance] = {
        Transparency = instance.Transparency,
    }

    return trackedDecalState[instance]
end

local function rememberEffect(instance)
    if trackedEffectState[instance] then
        return trackedEffectState[instance]
    end

    trackedEffectState[instance] = {
        Enabled = instance.Enabled,
    }

    return trackedEffectState[instance]
end

local function applyOptimizationToInstance(instance)
    if instance:IsA("BasePart") then
        local original = rememberPart(instance)

        if state.optimization.smoothMaterials then
            instance.Material = Enum.Material.SmoothPlastic
            instance.Reflectance = 0
        else
            instance.Material = original.Material
            instance.Reflectance = original.Reflectance
        end

        if state.optimization.castShadows then
            instance.CastShadow = false
        else
            instance.CastShadow = original.CastShadow
        end
    elseif instance:IsA("Decal") or instance:IsA("Texture") then
        local original = rememberDecal(instance)

        if state.optimization.hideTextures then
            instance.Transparency = 1
        else
            instance.Transparency = original.Transparency
        end
    elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") then
        local original = rememberEffect(instance)

        if state.optimization.hideParticles then
            instance.Enabled = false
        else
            instance.Enabled = original.Enabled
        end
    end
end

local function applyOptimization()
    if not state.optimization.enabled then
        for part, original in pairs(trackedPartState) do
            if part and part.Parent then
                part.Material = original.Material
                part.CastShadow = original.CastShadow
                part.Reflectance = original.Reflectance
            end
        end

        for decal, original in pairs(trackedDecalState) do
            if decal and decal.Parent then
                decal.Transparency = original.Transparency
            end
        end

        for effect, original in pairs(trackedEffectState) do
            if effect and effect.Parent then
                effect.Enabled = original.Enabled
            end
        end

        return
    end

    Lighting.GlobalShadows = state.optimization.globalShadows
    Lighting.Brightness = state.optimization.brightness
    Lighting.ClockTime = state.optimization.clockTime
    Lighting.FogEnd = state.optimization.fogEnd
    if Terrain then
        Terrain.WaterTransparency = state.optimization.waterTransparency
        Terrain.Decoration = state.optimization.terrainDecoration
    end

    for _, instance in ipairs(Workspace:GetDescendants()) do
        applyOptimizationToInstance(instance)
    end
end

local function getCharacter(player)
    return player.Character
end

local function getAliveHumanoid(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        return humanoid
    end
end

local function getRoot(character)
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHead(character)
    return character and character:FindFirstChild("Head")
end

local function getDistanceFromLocal(position)
    local localCharacter = getCharacter(LocalPlayer)
    local localRoot = getRoot(localCharacter)
    if not localRoot then
        return math.huge
    end

    return (localRoot.Position - position).Magnitude
end

local function getEspColor(targetPlayer)
    if state.esp.useTeamColor and targetPlayer.TeamColor then
        return targetPlayer.TeamColor.Color
    end

    return tableToColor(state.esp.color, Color3.fromRGB(255, 85, 85))
end

local function clearEspEntry(targetPlayer)
    local entry = espCache[targetPlayer]
    if not entry then
        return
    end

    if entry.highlight then
        entry.highlight:Destroy()
    end

    if entry.selection then
        entry.selection:Destroy()
    end

    if entry.billboard then
        entry.billboard:Destroy()
    end

    if entry.tracer then
        entry.tracer.Visible = false
        entry.tracer:Remove()
    end

    espCache[targetPlayer] = nil
end

local function getEspEntry(targetPlayer)
    local entry = espCache[targetPlayer]
    if entry then
        return entry
    end

    entry = {}

    local highlight = Instance.new("Highlight")
    highlight.Name = "DoomsdayHighlight"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = CoreGui
    entry.highlight = highlight

    local selection = Instance.new("SelectionBox")
    selection.Name = "DoomsdaySelection"
    selection.Parent = CoreGui
    selection.SurfaceTransparency = 1
    entry.selection = selection

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DoomsdayBillboard"
    billboard.Size = UDim2.fromOffset(220, 60)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Parent = CoreGui

    local label = Instance.new("TextLabel")
    label.Name = "Info"
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamSemibold
    label.TextStrokeTransparency = 0
    label.TextWrapped = true
    label.Parent = billboard

    entry.billboard = billboard
    entry.label = label

    if Drawing and Drawing.new then
        local tracer = Drawing.new("Line")
        tracer.Visible = false
        tracer.ZIndex = 2
        entry.tracer = tracer
    end

    espCache[targetPlayer] = entry
    return entry
end

local function shouldRenderPlayer(targetPlayer, character, root)
    if not state.esp.enabled or targetPlayer == LocalPlayer then
        return false
    end

    if not character or not root or not getAliveHumanoid(character) then
        return false
    end

    if state.esp.teamCheck and LocalPlayer.Team ~= nil and targetPlayer.Team == LocalPlayer.Team then
        return false
    end

    return getDistanceFromLocal(root.Position) <= state.esp.maxDistance
end

local function updateEspForPlayer(targetPlayer)
    local character = getCharacter(targetPlayer)
    local root = getRoot(character)
    local head = getHead(character)

    if not shouldRenderPlayer(targetPlayer, character, root) then
        clearEspEntry(targetPlayer)
        return
    end

    local color = getEspColor(targetPlayer)
    local distance = math.floor(getDistanceFromLocal(root.Position))
    local entry = getEspEntry(targetPlayer)

    entry.highlight.Adornee = character
    entry.highlight.Enabled = state.esp.highlight
    entry.highlight.FillColor = color
    entry.highlight.OutlineColor = color
    entry.highlight.FillTransparency = state.esp.fillTransparency
    entry.highlight.OutlineTransparency = state.esp.outlineTransparency

    entry.selection.Adornee = character
    entry.selection.Visible = state.esp.box
    entry.selection.Color3 = color
    entry.selection.LineThickness = state.esp.boxThickness

    entry.billboard.Adornee = head or root
    entry.billboard.Enabled = state.esp.names or state.esp.distance
    entry.billboard.StudsOffset = Vector3.new(0, 2.8, 0)
    entry.label.TextColor3 = color
    entry.label.TextSize = state.esp.textSize

    local lines = {}
    if state.esp.names then
        table.insert(lines, targetPlayer.Name)
    end
    if state.esp.distance then
        table.insert(lines, distance .. " studs")
    end
    entry.label.Text = table.concat(lines, "\n")

    if entry.tracer then
        if state.esp.tracers then
            local screenPoint, onScreen = Camera:WorldToViewportPoint(root.Position)
            if onScreen then
                entry.tracer.Visible = true
                entry.tracer.Color = color
                entry.tracer.Thickness = state.esp.tracerThickness
                entry.tracer.From = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y - 12)
                entry.tracer.To = Vector2.new(screenPoint.X, screenPoint.Y)
            else
                entry.tracer.Visible = false
            end
        else
            entry.tracer.Visible = false
        end
    end
end

local function updateAllEsp()
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= LocalPlayer then
            updateEspForPlayer(targetPlayer)
        end
    end
end

local function clearAllEsp()
    for targetPlayer in pairs(espCache) do
        clearEspEntry(targetPlayer)
    end
end

local function getPlayerNames()
    local names = {}
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= LocalPlayer then
            table.insert(names, targetPlayer.Name)
        end
    end

    table.sort(names)
    return names
end

local function getPlayerHeadshot(targetPlayer)
    if not targetPlayer then
        return "rbxassetid://0"
    end

    return "https://www.roblox.com/headshot-thumbnail/image?userId="
        .. tostring(targetPlayer.UserId)
        .. "&width=420&height=420&format=png"
end

local function updateSelectedPlayerCard()
    if not selectedPlayerImage or not selectedPlayerNameLabel or not selectedPlayerInfoLabel then
        return
    end

    local targetPlayer = selectedSpectatePlayer
    if not targetPlayer then
        selectedPlayerImage:SetImage(getPlayerHeadshot(LocalPlayer))
        selectedPlayerNameLabel:SetText("Nenhum player selecionado")
        selectedPlayerInfoLabel:SetText("Escolha um player na lista para ver avatar, distancia e status.")
        return
    end

    local character = targetPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = getRoot(character)
    local distance = root and math.floor(getDistanceFromLocal(root.Position)) or nil
    local health = humanoid and math.floor(humanoid.Health) or 0
    local displayName = targetPlayer.DisplayName ~= targetPlayer.Name
        and (targetPlayer.DisplayName .. " @" .. targetPlayer.Name)
        or targetPlayer.Name

    selectedPlayerImage:SetImage(getPlayerHeadshot(targetPlayer))
    selectedPlayerNameLabel:SetText(displayName)
    selectedPlayerInfoLabel:SetText(
        "HP: " .. tostring(health)
            .. " | Dist: " .. (distance and (tostring(distance) .. " studs") or "N/A")
            .. " | ID: " .. tostring(targetPlayer.UserId)
    )
end

local function setSpectateTargetByName(playerName)
    selectedSpectatePlayer = playerName and Players:FindFirstChild(playerName) or nil
    updateSelectedPlayerCard()
end

local function applySpectateState()
    if spectating and selectedSpectatePlayer and selectedSpectatePlayer.Character then
        local humanoid = selectedSpectatePlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            Camera.CameraSubject = humanoid
            return
        end
    end

    local localCharacter = LocalPlayer.Character
    local localHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")
    if localHumanoid then
        Camera.CameraSubject = localHumanoid
    end
end

local function applyVisual()
    if Camera then
        Camera.FieldOfView = state.visual.fov
    end

    LocalPlayer.CameraMaxZoomDistance = state.visual.zoom
    Lighting.Ambient = tableToColor(state.visual.ambient, Color3.fromRGB(255, 255, 255))
    Lighting.OutdoorAmbient = tableToColor(state.visual.outdoorAmbient, Color3.fromRGB(180, 180, 180))
    applySpectateState()
end

local Window = Library:CreateWindow({
    Title = "Milo Ui",
    Footer = "doomsday obsidian",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

local Tabs = {
    Doomsday = Window:AddTab("Doomsday", "flame"),
    Optimization = Window:AddTab("Optimization", "zap"),
    Visual = Window:AddTab("Visual", "eye"),
    Players = Window:AddTab("Players", "users"),
    FigureGrab = Window:AddTab("Figure Grab", "hand"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

local doomsdayMain = Tabs.Doomsday:AddLeftGroupbox("Loadstring", "terminal")
local doomsdayRejoin = Tabs.Doomsday:AddRightGroupbox("Rejoin", "refresh-cw")
local optimizeMain = Tabs.Optimization:AddLeftGroupbox("Performance Core", "cpu")
local optimizeWorld = Tabs.Optimization:AddRightGroupbox("World Render", "sun")

local visualMain = Tabs.Visual:AddLeftGroupbox("Camera / FOV", "scan-eye")
local visualPlayers = Tabs.Players:AddLeftGroupbox("Player Selector", "radar")
local playerCard = Tabs.Players:AddRightGroupbox("Selected Player", "badge-user")
local figureMain = Tabs.FigureGrab:AddLeftGroupbox("Oats Controls", "hand")
local figurePose = Tabs.FigureGrab:AddRightGroupbox("Pose Presets", "person-standing")
local figureAdjust = Tabs.FigureGrab:AddRightGroupbox("Quick Adjust", "sliders-horizontal")
local fpsGroup = Tabs["UI Settings"]:AddRightGroupbox("FPS", "gauge")

doomsdayMain:AddButton({
    Text = "Load DOOMSDAY",
    Func = function()
        if not isConfiguredUrl(DOOMSDAY_SCRIPT_URL) then
            safeNotify("Doomsday", "Configure DOOMSDAY_SCRIPT_URL no topo do arquivo.")
            return
        end

        safeHttpLoad(DOOMSDAY_SCRIPT_URL)
    end,
})

doomsdayMain:AddButton({
    Text = "Load Milo UI",
    Func = function()
        if not isConfiguredUrl(MILO_UI_URL) then
            safeNotify("Milo Ui", "Configure MILO_UI_URL no topo do arquivo.")
            return
        end

        safeHttpLoad(MILO_UI_URL)
    end,
})

doomsdayMain:AddButton({
    Text = "Load Figure Grab Oats",
    Func = function()
        loadFigureGrabModule()
    end,
})

doomsdayRejoin:AddButton({
    Text = "Queue DOOMSDAY",
    Func = queueDoomsdayOnTeleport,
})

doomsdayRejoin:AddButton({
    Text = "Rejoin with DOOMSDAY",
    Func = rejoinWithDoomsday,
})

figureMain:AddButton({
    Text = "Load Oats module",
    Func = function()
        loadFigureGrabModule()
    end,
})

figureMain:AddButton({
    Text = "Toggle Figure Grab",
    Func = function()
        withFigureGrab(function(module)
            module.ToggleFigureGrab()
        end)
    end,
})

figureMain:AddToggle("FigureGrabAnimCopy", {
    Text = "Copy my animations",
    Default = false,
    Callback = function(value)
        withFigureGrab(function(module)
            module.SetAnimationCopy(value)
            safeNotify("Figure Grab", value and "Copiando suas animacoes." or "Controle manual restaurado.")
        end)
    end,
})

figureMain:AddButton({
    Text = "Reset pose",
    Func = function()
        withFigureGrab(function(module)
            module.ResetPose()
            safeNotify("Figure Grab", "Pose resetada.")
        end)
    end,
})

figurePose:AddDropdown("FigureGrabPreset", {
    Values = { "Pose1", "Pose2", "Pose3", "Pose4", "Pose5", "Pose6", "Pose7", "JojoStand" },
    Default = "Pose1",
    Multi = false,
    Text = "Preset",
})

figurePose:AddButton({
    Text = "Apply preset",
    Func = function()
        withFigureGrab(function(module)
            module.ApplyPreset(Options.FigureGrabPreset.Value)
            safeNotify("Figure Grab", "Preset aplicado: " .. tostring(Options.FigureGrabPreset.Value))
        end)
    end,
})

figureAdjust:AddSlider("FigureGrabHoldX", {
    Text = "Hold X",
    Default = 0,
    Min = -50,
    Max = 50,
    Rounding = 1,
    Callback = function(value)
        withFigureGrab(function(module)
            module.UpdateConfig("HoldPosition", "X", value)
        end)
    end,
})

figureAdjust:AddSlider("FigureGrabHoldY", {
    Text = "Hold Y",
    Default = 0,
    Min = -50,
    Max = 50,
    Rounding = 1,
    Callback = function(value)
        withFigureGrab(function(module)
            module.UpdateConfig("HoldPosition", "Y", value)
        end)
    end,
})

figureAdjust:AddSlider("FigureGrabHoldZ", {
    Text = "Hold Z",
    Default = -5,
    Min = -50,
    Max = 50,
    Rounding = 1,
    Callback = function(value)
        withFigureGrab(function(module)
            module.UpdateConfig("HoldPosition", "Z", value)
        end)
    end,
})

figureAdjust:AddSlider("FigureGrabRotX", {
    Text = "Rotate X",
    Default = 0,
    Min = 0,
    Max = 360,
    Rounding = 0,
    Callback = function(value)
        withFigureGrab(function(module)
            module.UpdateConfig("HoldRotation", "X", value)
        end)
    end,
})

figureAdjust:AddSlider("FigureGrabRotY", {
    Text = "Rotate Y",
    Default = 0,
    Min = 0,
    Max = 360,
    Rounding = 0,
    Callback = function(value)
        withFigureGrab(function(module)
            module.UpdateConfig("HoldRotation", "Y", value)
        end)
    end,
})

figureAdjust:AddSlider("FigureGrabRotZ", {
    Text = "Rotate Z",
    Default = 0,
    Min = 0,
    Max = 360,
    Rounding = 0,
    Callback = function(value)
        withFigureGrab(function(module)
            module.UpdateConfig("HoldRotation", "Z", value)
        end)
    end,
})

optimizeMain:AddToggle("OptEnabled", {
    Text = "Optimization master",
    Default = state.optimization.enabled,
    Tooltip = "Liga/desliga todas as alteracoes client-side de performance.",
})

optimizeMain:AddToggle("OptHideParticles", {
    Text = "Disable particles / trails",
    Default = state.optimization.hideParticles,
})

optimizeMain:AddToggle("OptHideTextures", {
    Text = "Hide decals / textures",
    Default = state.optimization.hideTextures,
})

optimizeMain:AddToggle("OptSmoothMaterials", {
    Text = "Force smooth plastic",
    Default = state.optimization.smoothMaterials,
})

optimizeMain:AddToggle("OptDisableCastShadow", {
    Text = "Disable part shadows",
    Default = state.optimization.castShadows,
})

optimizeMain:AddSlider("OptWaterTransparency", {
    Text = "Water transparency",
    Default = state.optimization.waterTransparency,
    Min = 0,
    Max = 1,
    Rounding = 2,
})

optimizeWorld:AddToggle("OptGlobalShadows", {
    Text = "Global shadows",
    Default = state.optimization.globalShadows,
})

optimizeWorld:AddToggle("OptTerrainDecor", {
    Text = "Terrain decoration",
    Default = state.optimization.terrainDecoration,
})

optimizeWorld:AddSlider("OptBrightness", {
    Text = "Brightness",
    Default = state.optimization.brightness,
    Min = 0,
    Max = 5,
    Rounding = 1,
})

optimizeWorld:AddSlider("OptClockTime", {
    Text = "Clock time",
    Default = state.optimization.clockTime,
    Min = 0,
    Max = 24,
    Rounding = 1,
})

optimizeWorld:AddSlider("OptFogEnd", {
    Text = "Fog end",
    Default = state.optimization.fogEnd,
    Min = 500,
    Max = 100000,
    Rounding = 0,
    HideMax = false,
    FormatDisplayValue = function(_, value)
        if value >= 100000 then
            return "Very far"
        end

        return tostring(math.floor(value))
    end,
})

visualMain:AddSlider("VisualFov", {
    Text = "Field of view",
    Default = state.visual.fov,
    Min = 40,
    Max = 120,
    Rounding = 0,
})

visualMain:AddSlider("VisualZoom", {
    Text = "Max zoom distance",
    Default = state.visual.zoom,
    Min = 16,
    Max = 512,
    Rounding = 0,
})

visualMain:AddLabel("Ambient"):AddColorPicker("VisualAmbientColor", {
    Default = tableToColor(state.visual.ambient, Color3.fromRGB(255, 255, 255)),
    Title = "Ambient Color",
})

visualMain:AddLabel("Outdoor ambient"):AddColorPicker("VisualOutdoorAmbientColor", {
    Default = tableToColor(state.visual.outdoorAmbient, Color3.fromRGB(180, 180, 180)),
    Title = "Outdoor Ambient Color",
})

visualMain:AddButton({
    Text = "Reset visual defaults",
    Func = function()
        Options.VisualFov:SetValue(DEFAULT_STATE.visual.fov)
        Options.VisualZoom:SetValue(DEFAULT_STATE.visual.zoom)
        Options.VisualAmbientColor:SetValueRGB(tableToColor(DEFAULT_STATE.visual.ambient, Color3.new(1, 1, 1)))
        Options.VisualOutdoorAmbientColor:SetValueRGB(tableToColor(DEFAULT_STATE.visual.outdoorAmbient, Color3.new(1, 1, 1)))
        safeNotify("Visual", "FOV e iluminacao resetados.")
    end,
})

visualPlayers:AddToggle("EspEnabled", {
    Text = "Enable ESP",
    Default = state.esp.enabled,
})
    :AddColorPicker("EspColor", {
        Default = tableToColor(state.esp.color, Color3.fromRGB(255, 85, 85)),
        Title = "ESP Color",
    })

visualPlayers:AddToggle("EspBox", {
    Text = "Box ESP",
    Default = state.esp.box,
})

visualPlayers:AddToggle("EspHighlight", {
    Text = "Highlight ESP",
    Default = state.esp.highlight,
})

visualPlayers:AddToggle("EspNames", {
    Text = "Player names",
    Default = state.esp.names,
})

visualPlayers:AddToggle("EspDistance", {
    Text = "Distance text",
    Default = state.esp.distance,
})

visualPlayers:AddToggle("EspTracers", {
    Text = "Screen tracers",
    Default = state.esp.tracers,
})

visualPlayers:AddToggle("EspTeamCheck", {
    Text = "Ignore same team",
    Default = state.esp.teamCheck,
})

visualPlayers:AddToggle("EspUseTeamColor", {
    Text = "Use team color",
    Default = state.esp.useTeamColor,
})

visualPlayers:AddSlider("EspBoxThickness", {
    Text = "ESP thickness",
    Default = state.esp.boxThickness,
    Min = 1,
    Max = 5,
    Rounding = 0,
})

visualPlayers:AddSlider("EspFillTransparency", {
    Text = "Highlight fill",
    Default = state.esp.fillTransparency,
    Min = 0,
    Max = 1,
    Rounding = 2,
})

visualPlayers:AddSlider("EspOutlineTransparency", {
    Text = "Outline transparency",
    Default = state.esp.outlineTransparency,
    Min = 0,
    Max = 1,
    Rounding = 2,
})

visualPlayers:AddSlider("EspTextSize", {
    Text = "Label size",
    Default = state.esp.textSize,
    Min = 10,
    Max = 22,
    Rounding = 0,
})

visualPlayers:AddSlider("EspMaxDistance", {
    Text = "ESP max distance",
    Default = state.esp.maxDistance,
    Min = 100,
    Max = 5000,
    Rounding = 0,
})

visualPlayers:AddSlider("EspTracerThickness", {
    Text = "Tracer thickness",
    Default = state.esp.tracerThickness,
    Min = 1,
    Max = 5,
    Rounding = 1,
})

selectedPlayerImage = playerCard:AddImage("SelectedPlayerAvatar", {
    Image = getPlayerHeadshot(LocalPlayer),
    Height = 126,
    ScaleType = Enum.ScaleType.Fit,
    BackgroundTransparency = 0,
})
selectedPlayerNameLabel = playerCard:AddLabel({
    Text = "Nenhum player selecionado",
    Size = 15,
    DoesWrap = true,
})
selectedPlayerInfoLabel = playerCard:AddLabel({
    Text = "Escolha um player na lista para ver avatar, distancia e status.",
    DoesWrap = true,
})

visualPlayers:AddDropdown("SpectateTarget", {
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    Values = getPlayerNames(),
    Default = selectedSpectatePlayer and selectedSpectatePlayer.Name or nil,
    Multi = false,
    Searchable = true,
    Text = "Select player",
    Tooltip = "Lista automatica com players do servidor.",
})

visualPlayers:AddButton({
    Text = "Spectate selected player",
    Func = function()
        local playerName = Options.SpectateTarget.Value
        setSpectateTargetByName(playerName)
        spectating = selectedSpectatePlayer ~= nil
        applySpectateState()
        safeNotify("Spectate", spectating and ("Assistindo " .. playerName) or "Nenhum player selecionado.")
    end,
})

visualPlayers:AddButton({
    Text = "Stop spectate",
    Func = function()
        spectating = false
        applySpectateState()
        safeNotify("Spectate", "Camera voltou para voce.")
    end,
})

local menuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")
menuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open keybind menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})
menuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom cursor",
    Default = true,
    Callback = function(value)
        Library.ShowCustomCursor = value
    end,
})
menuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification side",
    Callback = function(value)
        Library:SetNotifySide(value)
    end,
})
menuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
menuGroup:AddButton({
    Text = "Refresh player list",
    Func = function()
        Options.SpectateTarget:SetValues(getPlayerNames())
        updateSelectedPlayerCard()
        safeNotify("Players", "Lista de players atualizada.")
    end,
})
menuGroup:AddButton({
    Text = "Unload",
    Func = function()
        clearAllEsp()
        Library:Unload()
    end,
})

fpsGroup:AddToggle("FpsUnlock", {
    Text = "Unlock FPS",
    Default = state.performance.fpsUnlock,
    Tooltip = "Usa 0/uncap quando o executor suportar setfpscap.",
})

fpsGroup:AddDropdown("FpsCapPreset", {
    Values = { "60", "120", "144", "165", "240", "360" },
    Default = tostring(state.performance.fpsCap),
    Multi = false,
    Text = "FPS cap preset",
})

fpsGroup:AddButton({
    Text = "Apply FPS setting",
    Func = function()
        local ok = applyFpsCap()
        if ok then
            local label = state.performance.fpsUnlock and "FPS unlocked" or ("FPS cap " .. tostring(state.performance.fpsCap))
            safeNotify("FPS", label)
        else
            safeNotify("FPS", "Executor sem suporte para setfpscap.")
        end
    end,
})

Toggles.OptEnabled:OnChanged(function()
    setPath(state, { "optimization", "enabled" }, Toggles.OptEnabled.Value)
    applyOptimization()
end)

Toggles.OptHideParticles:OnChanged(function()
    setPath(state, { "optimization", "hideParticles" }, Toggles.OptHideParticles.Value)
    applyOptimization()
end)

Toggles.OptHideTextures:OnChanged(function()
    setPath(state, { "optimization", "hideTextures" }, Toggles.OptHideTextures.Value)
    applyOptimization()
end)

Toggles.OptSmoothMaterials:OnChanged(function()
    setPath(state, { "optimization", "smoothMaterials" }, Toggles.OptSmoothMaterials.Value)
    applyOptimization()
end)

Toggles.OptDisableCastShadow:OnChanged(function()
    setPath(state, { "optimization", "castShadows" }, Toggles.OptDisableCastShadow.Value)
    applyOptimization()
end)

Toggles.OptGlobalShadows:OnChanged(function()
    setPath(state, { "optimization", "globalShadows" }, Toggles.OptGlobalShadows.Value)
    applyOptimization()
end)

Toggles.OptTerrainDecor:OnChanged(function()
    setPath(state, { "optimization", "terrainDecoration" }, Toggles.OptTerrainDecor.Value)
    applyOptimization()
end)

Options.OptWaterTransparency:OnChanged(function()
    setPath(state, { "optimization", "waterTransparency" }, Options.OptWaterTransparency.Value)
    applyOptimization()
end)

Options.OptBrightness:OnChanged(function()
    setPath(state, { "optimization", "brightness" }, Options.OptBrightness.Value)
    applyOptimization()
end)

Options.OptClockTime:OnChanged(function()
    setPath(state, { "optimization", "clockTime" }, Options.OptClockTime.Value)
    applyOptimization()
end)

Options.OptFogEnd:OnChanged(function()
    setPath(state, { "optimization", "fogEnd" }, Options.OptFogEnd.Value)
    applyOptimization()
end)

Options.VisualFov:OnChanged(function()
    setPath(state, { "visual", "fov" }, Options.VisualFov.Value)
    applyVisual()
end)

Options.VisualZoom:OnChanged(function()
    setPath(state, { "visual", "zoom" }, Options.VisualZoom.Value)
    applyVisual()
end)

Options.VisualAmbientColor:OnChanged(function()
    setPath(state, { "visual", "ambient" }, colorToTable(Options.VisualAmbientColor.Value))
    applyVisual()
end)

Options.VisualOutdoorAmbientColor:OnChanged(function()
    setPath(state, { "visual", "outdoorAmbient" }, colorToTable(Options.VisualOutdoorAmbientColor.Value))
    applyVisual()
end)

Toggles.FpsUnlock:OnChanged(function()
    setPath(state, { "performance", "fpsUnlock" }, Toggles.FpsUnlock.Value)
    applyFpsCap()
end)

Options.FpsCapPreset:OnChanged(function()
    local value = tonumber(Options.FpsCapPreset.Value)
    if value then
        setPath(state, { "performance", "fpsCap" }, value)
        if not state.performance.fpsUnlock then
            applyFpsCap()
        end
    end
end)

Toggles.EspEnabled:OnChanged(function()
    setPath(state, { "esp", "enabled" }, Toggles.EspEnabled.Value)
    if not Toggles.EspEnabled.Value then
        clearAllEsp()
    end
end)

Toggles.EspBox:OnChanged(function()
    setPath(state, { "esp", "box" }, Toggles.EspBox.Value)
end)

Toggles.EspHighlight:OnChanged(function()
    setPath(state, { "esp", "highlight" }, Toggles.EspHighlight.Value)
end)

Toggles.EspNames:OnChanged(function()
    setPath(state, { "esp", "names" }, Toggles.EspNames.Value)
end)

Toggles.EspDistance:OnChanged(function()
    setPath(state, { "esp", "distance" }, Toggles.EspDistance.Value)
end)

Toggles.EspTracers:OnChanged(function()
    setPath(state, { "esp", "tracers" }, Toggles.EspTracers.Value)
end)

Toggles.EspTeamCheck:OnChanged(function()
    setPath(state, { "esp", "teamCheck" }, Toggles.EspTeamCheck.Value)
end)

Toggles.EspUseTeamColor:OnChanged(function()
    setPath(state, { "esp", "useTeamColor" }, Toggles.EspUseTeamColor.Value)
end)

Options.EspColor:OnChanged(function()
    setPath(state, { "esp", "color" }, colorToTable(Options.EspColor.Value))
end)

Options.EspBoxThickness:OnChanged(function()
    setPath(state, { "esp", "boxThickness" }, Options.EspBoxThickness.Value)
end)

Options.EspFillTransparency:OnChanged(function()
    setPath(state, { "esp", "fillTransparency" }, Options.EspFillTransparency.Value)
end)

Options.EspOutlineTransparency:OnChanged(function()
    setPath(state, { "esp", "outlineTransparency" }, Options.EspOutlineTransparency.Value)
end)

Options.EspTextSize:OnChanged(function()
    setPath(state, { "esp", "textSize" }, Options.EspTextSize.Value)
end)

Options.EspMaxDistance:OnChanged(function()
    setPath(state, { "esp", "maxDistance" }, Options.EspMaxDistance.Value)
end)

Options.EspTracerThickness:OnChanged(function()
    setPath(state, { "esp", "tracerThickness" }, Options.EspTracerThickness.Value)
end)

Options.SpectateTarget:OnChanged(function()
    setSpectateTargetByName(Options.SpectateTarget.Value)
    updateSelectedPlayerCard()
end)

Players.PlayerAdded:Connect(function()
    task.delay(0.2, function()
        if Options.SpectateTarget then
            Options.SpectateTarget:SetValues(getPlayerNames())
            updateSelectedPlayerCard()
        end
    end)
end)

Players.PlayerRemoving:Connect(function(targetPlayer)
    if selectedSpectatePlayer == targetPlayer then
        spectating = false
        selectedSpectatePlayer = nil
        applySpectateState()
    end

    clearEspEntry(targetPlayer)

    task.delay(0.2, function()
        if Options.SpectateTarget then
            Options.SpectateTarget:SetValues(getPlayerNames())
            updateSelectedPlayerCard()
        end
    end)
end)

Workspace.DescendantAdded:Connect(function(instance)
    if not state.optimization.enabled then
        return
    end

    if instance:IsA("BasePart") or instance:IsA("Decal") or instance:IsA("Texture") or instance:IsA("ParticleEmitter")
        or instance:IsA("Trail") or instance:IsA("Beam")
    then
        task.defer(function()
            if instance.Parent then
                applyOptimizationToInstance(instance)
            end
        end)
    end
end)

RunService.RenderStepped:Connect(function()
    Camera = Workspace.CurrentCamera
    applySpectateState()

    if state.esp.enabled then
        updateAllEsp()
    end
end)

Library:OnUnload(function()
    clearAllEsp()
    pcall(saveAutosave)
end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind", "SpectateTarget" })
ThemeManager:SetFolder(CONFIG_ROOT)
SaveManager:SetFolder(CONFIG_ROOT .. "/profiles")
SaveManager:SetSubFolder(tostring(game.PlaceId))
ThemeManager.BuiltInThemes["Milo Ui"] = {
    0,
    {
        FontColor = "f2f2f2",
        MainColor = "191919",
        AccentColor = "9a9a9a",
        BackgroundColor = "0b0b0b",
        OutlineColor = "333333",
    },
}
ThemeManager:SetDefaultTheme("Milo Ui")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

applyOptimization()
applyVisual()
applyFpsCap()
updateSelectedPlayerCard()
safeNotify("Milo Ui", "Doomsday Obsidian carregado com autosave local.")
