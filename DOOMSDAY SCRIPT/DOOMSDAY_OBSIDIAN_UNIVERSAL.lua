local OBSIDIAN_REPO = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local CONFIG_ROOT = "DoomsdayObsidianOriginal"
local FIGURE_GRAB_OATS_URL = getgenv().FIGURE_GRAB_OATS_URL or "https://raw.githubusercontent.com/Milokinot/scripts/main/DOOMSDAY%20SCRIPT/modules/FIGURE_GRAB_OATS.lua"

local function createDoomsdayObsidianAdapter(httpLoader)
    local Library = httpLoader(OBSIDIAN_REPO .. "Library.lua")
    local ThemeManager = httpLoader(OBSIDIAN_REPO .. "addons/ThemeManager.lua")
    local SaveManager = httpLoader(OBSIDIAN_REPO .. "addons/SaveManager.lua")

    if not Library or not ThemeManager or not SaveManager then
        warn("[DOOMSDAY OBSIDIAN] Obsidian nao carregou; usando stub.")
        return nil
    end

    Library.ForceCheckbox = false
    Library.ShowToggleFrameInKeybinds = true

    local OrionAdapter = {
        Flags = {},
        _elementIndex = 0,
        _window = nil,
    }

    local function nextId(prefix, config)
        OrionAdapter._elementIndex += 1
        local rawName = tostring((config and (config.Flag or config.Name or config.Title or config.Text)) or prefix or "Item")
        rawName = rawName:gsub("[^%w_]", "_")
        return tostring(prefix or "Doomsday") .. "_" .. rawName .. "_" .. tostring(OrionAdapter._elementIndex)
    end

    local function notify(title, text, duration)
        pcall(function()
            Library:Notify({
                Title = tostring(title or "Doomsday"),
                Description = tostring(text or ""),
                Time = duration or 4,
            })
        end)
    end

    getgenv().DoomsdayNotify = notify

    local function safeCallback(callback, ...)
        if type(callback) ~= "function" then
            return
        end

        local ok, err = pcall(callback, ...)
        if not ok then
            warn("[DOOMSDAY OBSIDIAN] callback error: " .. tostring(err))
        end
    end

    local function bindFlag(config, element, defaultValue)
        if config and config.Flag then
            OrionAdapter.Flags[config.Flag] = element
        end

        if element.Value == nil then
            element.Value = defaultValue
        end

        return element
    end

    local function makeGroupApi(group)
        local api = {}

        function api:AddButton(config)
            config = config or {}
            return group:AddButton({
                Text = config.Name or config.Title or config.Text or "Button",
                Func = function()
                    safeCallback(config.Callback or config.Func)
                end,
            })
        end

        function api:AddToggle(config)
            config = config or {}
            local id = nextId("Toggle", config)
            local proxy = { Value = config.Default == true }
            local toggle = group:AddToggle(id, {
                Text = config.Name or config.Title or config.Text or "Toggle",
                Default = config.Default == true,
                Tooltip = config.Tooltip,
                Callback = function(value)
                    proxy.Value = value
                    safeCallback(config.Callback, value)
                end,
            })
            proxy._raw = toggle
            function proxy:Set(value)
                self.Value = value
                if toggle and type(toggle.SetValue) == "function" then
                    toggle:SetValue(value)
                end
                safeCallback(config.Callback, value)
            end
            function proxy:SetValue(value)
                self:Set(value)
            end
            function proxy:Destroy() end
            return bindFlag(config, proxy, config.Default == true)
        end

        function api:AddSlider(config)
            config = config or {}
            local id = nextId("Slider", config)
            local default = config.Default or config.Value or config.Min or (config.Range and config.Range[1]) or 0
            local proxy = { Value = default }
            local slider = group:AddSlider(id, {
                Text = config.Name or config.Title or config.Text or "Slider",
                Default = default,
                Min = config.Min or (config.Range and config.Range[1]) or 0,
                Max = config.Max or (config.Range and config.Range[2]) or 100,
                Rounding = config.Increment and tostring(config.Increment):find("%.") and 1 or 0,
                Suffix = config.ValueName or config.Suffix,
                Callback = function(value)
                    proxy.Value = value
                    safeCallback(config.Callback, value)
                end,
            })
            proxy._raw = slider
            return bindFlag(config, proxy, default)
        end

        function api:AddDropdown(config)
            config = config or {}
            local id = nextId("Dropdown", config)
            local values = config.Options or config.Values or {}
            local default = config.Default or config.CurrentOption or values[1]
            local proxy = { Value = default }
            local dropdown = group:AddDropdown(id, {
                Text = config.Name or config.Title or config.Text or "Dropdown",
                Values = values,
                Default = default,
                Multi = config.MultipleSelection or config.Multi or false,
                Searchable = true,
                Callback = function(value)
                    proxy.Value = value
                    safeCallback(config.Callback, value)
                end,
            })
            proxy._raw = dropdown
            function proxy:SetValues(newValues)
                values = newValues
                if dropdown and type(dropdown.SetValues) == "function" then
                    dropdown:SetValues(newValues)
                end
            end
            return bindFlag(config, proxy, default)
        end

        function api:AddPlayersDropdown(config)
            config = config or {}
            local Players = game:GetService("Players")
            local localPlayer = Players.LocalPlayer

            local function playerNames()
                local names = {}
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= localPlayer then
                        table.insert(names, player.Name)
                    end
                end
                table.sort(names)
                if #names == 0 then
                    names = { "Nenhum player" }
                end
                return names
            end

            local dropdown = api:AddDropdown({
                Name = config.Name or "Players",
                Options = playerNames(),
                MultipleSelection = config.MultipleSelection,
                Callback = function(value)
                    if value == "Nenhum player" then
                        value = config.MultipleSelection and {} or nil
                    elseif type(value) == "table" then
                        local filtered = {}
                        for _, name in ipairs(value) do
                            if name ~= "Nenhum player" then
                                table.insert(filtered, name)
                            end
                        end
                        value = filtered
                    end
                    safeCallback(config.Callback, value)
                end,
            })

            local function refresh()
                if dropdown and type(dropdown.SetValues) == "function" then
                    dropdown:SetValues(playerNames())
                end
            end

            Players.PlayerAdded:Connect(function()
                task.defer(refresh)
            end)
            Players.PlayerRemoving:Connect(function()
                task.defer(refresh)
            end)

            dropdown.Refresh = refresh
            return dropdown
        end

        function api:AddBind(config)
            config = config or {}
            local UserInputService = game:GetService("UserInputService")
            local key = config.Default or config.Key or Enum.KeyCode.Unknown
            local label = group:AddLabel((config.Name or "Bind") .. ": " .. tostring(key):gsub("Enum.KeyCode.", ""))

            UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if gameProcessed then return end
                if input.KeyCode == key then
                    safeCallback(config.Callback)
                end
            end)

            return label
        end

        api.AddKeybind = api.AddBind

        function api:AddLabel(text)
            return group:AddLabel(tostring(text or ""))
        end

        function api:AddParagraph(config)
            config = config or {}
            return group:AddLabel({
                Text = tostring(config.Title or config.Name or config.Content or config.Text or ""),
                DoesWrap = true,
            })
        end

        function api:AddSection(config)
            local text = type(config) == "table" and (config.Name or config.Title or config.Text) or config
            return group:AddLabel("-- " .. tostring(text or "Section") .. " --")
        end

        function api:AddTextbox(config)
            config = config or {}
            local id = nextId("Textbox", config)
            local input = group:AddInput(id, {
                Text = config.Name or config.Title or config.Text or "Input",
                Default = config.Default or "",
                Numeric = false,
                Finished = true,
                Callback = function(value)
                    safeCallback(config.Callback, value)
                end,
            })
            return bindFlag(config, input or {}, config.Default or "")
        end

        return api
    end

    local function installFigureGrab(windowApi)
        local tab = windowApi:MakeTab({ Name = "Figure Grab", Icon = "hand", PremiumOnly = false })
        local figureModule

        local function loadFigureGrab()
            if figureModule then
                return figureModule
            end

            if getgenv().FigureGrabModule and type(getgenv().FigureGrabModule.ToggleFigureGrab) == "function" then
                figureModule = getgenv().FigureGrabModule
                return figureModule
            end

            figureModule = httpLoader(FIGURE_GRAB_OATS_URL)
            if figureModule and type(figureModule.ToggleFigureGrab) == "function" then
                notify("Figure Grab", "Modulo Oats carregado.")
                return figureModule
            end

            figureModule = nil
            notify("Figure Grab", "Nao consegui carregar o modulo Oats.")
            return nil
        end

        local function withFigure(callback)
            local module = loadFigureGrab()
            if module then
                safeCallback(callback, module)
            end
        end

        tab:AddButton({ Name = "Load Figure Grab Oats", Callback = loadFigureGrab })
        tab:AddButton({ Name = "Toggle Figure Grab", Callback = function()
            withFigure(function(module) module.ToggleFigureGrab() end)
        end })
        tab:AddToggle({ Name = "Copy My Animations", Default = false, Callback = function(value)
            withFigure(function(module) module.SetAnimationCopy(value) end)
        end })
        tab:AddButton({ Name = "Reset Pose", Callback = function()
            withFigure(function(module) module.ResetPose() end)
        end })
        tab:AddDropdown({ Name = "Pose Preset", Options = { "Pose1", "Pose2", "Pose3", "Pose4", "Pose5", "Pose6", "Pose7", "JojoStand" }, Callback = function(value)
            withFigure(function(module) module.ApplyPreset(value) end)
        end })
        tab:AddSlider({ Name = "Hold Z", Min = -50, Max = 50, Default = -5, Increment = 0.1, Callback = function(value)
            withFigure(function(module) module.UpdateConfig("HoldPosition", "Z", value) end)
        end })
        tab:AddSlider({ Name = "Hold Rotation X", Min = 0, Max = 360, Default = 0, Increment = 1, Callback = function(value)
            withFigure(function(module) module.UpdateConfig("HoldRotation", "X", value) end)
        end })
    end

    function OrionAdapter:MakeNotification(config)
        config = config or {}
        notify(config.Name or config.Title or "Doomsday", config.Content or config.Description or "", config.Time or config.Duration)
    end

    function OrionAdapter:MakeWindow(config)
        config = config or {}
        local obsidianWindow = Library:CreateWindow({
            Title = config.Name or "DOOMSDAY",
            Footer = "doomsday original em obsidian",
            Icon = config.IntroIcon or 95816097006870,
            NotifySide = "Right",
            ShowCustomCursor = true,
        })

        local windowApi = {}
        local tabCount = 0

        function windowApi:MakeTab(tabConfig)
            tabConfig = tabConfig or {}
            tabCount += 1
            local tab = obsidianWindow:AddTab(tabConfig.Name or ("Tab " .. tabCount), tabConfig.Icon or "box")
            local group = tab:AddLeftGroupbox(tabConfig.Name or ("Tab " .. tabCount), tabConfig.Icon or "box")
            return makeGroupApi(group)
        end

        OrionAdapter._window = windowApi
        installFigureGrab(windowApi)
        notify("Milo Ui", "Doomsday original carregado em Obsidian.")
        return windowApi
    end

    function OrionAdapter:Init() end
    function OrionAdapter:Destroy() pcall(function() Library:Unload() end) end

    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    ThemeManager:SetFolder(CONFIG_ROOT)
    SaveManager:SetFolder(CONFIG_ROOT .. "/profiles")
    ThemeManager.BuiltInThemes["Milo Obsidian"] = {
        0,
        {
            FontColor = "f2f2f2",
            MainColor = "191919",
            AccentColor = "9a9a9a",
            BackgroundColor = "0b0b0b",
            OutlineColor = "333333",
        },
    }
    ThemeManager:SetDefaultTheme("Milo Obsidian")

    return OrionAdapter
end

local BOOT_WAIT_TIMEOUT = 2
local REMOTE_LOAD_ATTEMPTS = 3

local function hubWarn(message)
    warn("[DOOMSDAY] " .. tostring(message))
end

local function createUiStubNode()
    return setmetatable({}, {
        __index = function()
            return function()
                return createUiStubNode()
            end
        end
    })
end

local function createOrionStub()
    local windowStub = createUiStubNode()

    return setmetatable({
        Flags = {}
    }, {
        __index = function(_, key)
            if key == "MakeWindow" then
                return function()
                    return windowStub
                end
            end

            return function()
                return windowStub
            end
        end
    })
end

local function safeHttpLoad(url, optional)
    local lastError = nil

    for attempt = 1, REMOTE_LOAD_ATTEMPTS do
        local ok, source = pcall(function()
            return game:HttpGet(url)
        end)

        if ok and type(source) == "string" and source ~= "" then
            local loaded, result = pcall(function()
                local chunk, compileError = loadstring(source)
                if not chunk then
                    error(compileError or "loadstring returned nil")
                end

                return chunk()
            end)

            if loaded then
                return result
            end

            lastError = result
        else
            lastError = source
        end

        if attempt < REMOTE_LOAD_ATTEMPTS then
            task.wait(1)
        end
    end

    local label = optional and "Optional remote load failed" or "Required remote load failed"
    hubWarn(label .. ": " .. url .. " | " .. tostring(lastError))
    return nil
end

local function safeWaitForChild(parent, childName, timeout)
    if not parent then
        return nil
    end

    local child = parent:FindFirstChild(childName)
    if child then
        return child
    end

    if timeout and timeout <= 0 then
        return nil
    end

    return parent:WaitForChild(childName, timeout or BOOT_WAIT_TIMEOUT)
end

local function safeResolvePath(root, pathParts, timeout)
    local current = root

    for _, partName in ipairs(pathParts) do
        current = safeWaitForChild(current, partName, timeout)
        if not current then
            return nil
        end
    end

    return current
end

local function safeGetPlayerToyFolder(targetPlayer, timeout)
    if not targetPlayer then
        return nil
    end

    local workspaceService = game:GetService("Workspace")
    local playerName = typeof(targetPlayer) == "Instance" and targetPlayer.Name or tostring(targetPlayer)

    return workspaceService:FindFirstChild(playerName .. "SpawnedInToys")
        or safeWaitForChild(workspaceService, playerName .. "SpawnedInToys", timeout)
end

local function safeGetPlayerFlagValue(targetPlayer, flagName, timeout)
    if not targetPlayer then
        return nil
    end

    return targetPlayer:FindFirstChild(flagName)
        or safeWaitForChild(targetPlayer, flagName, timeout)
end

local function safeGetCharacterEvents(timeout)
    local replicatedStorage = game:GetService("ReplicatedStorage")
    local characterEvents = replicatedStorage:FindFirstChild("CharacterEvents")
        or safeWaitForChild(replicatedStorage, "CharacterEvents", timeout)

    if not characterEvents then
        return nil, nil, nil
    end

    local struggleRemote = characterEvents:FindFirstChild("Struggle")
        or safeWaitForChild(characterEvents, "Struggle", timeout)
    local ragdollRemote = characterEvents:FindFirstChild("RagdollRemote")
        or safeWaitForChild(characterEvents, "RagdollRemote", timeout)

    return characterEvents, struggleRemote, ragdollRemote
end

local OrionLib = createDoomsdayObsidianAdapter(safeHttpLoad) or createOrionStub()
safeHttpLoad("https://raw.githubusercontent.com/DarkNetworks/Infinite-Yield/main/latest.lua", true)

local Window = OrionLib:MakeWindow({
        Name = "DOOMSDAY",
        HidePremium = false,
        SaveConfig = true,
        ConfigFolder = "FunScript",
        IntroEnabled = false,
        KeyToOpenWindow = "M",
        FreeMouse = true,
        IntroText = "「 Familia Gomes (FMG) 」",
        IntroIcon = "rbxassetid://130521044774541",
        SearchBar = {Default = "🔍 Search Everything"}
    })

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local rs = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local LP = player
local mouse = player:GetMouse()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

LocalPlayer.Chatted:Connect(function(msg)
    msg = msg:lower()

    if msg == "Expansão de Domínio" then
        
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local LocalPlayer = Players.LocalPlayer


local GrabRemote = ReplicatedStorage
    :WaitForChild("GrabEvents")
    :WaitForChild("ExtendGrabLine")


local CONFIG = {
    PayloadKB = 690,      
    Threads = 3,          
    PacketsPerCycle = 20, 
    PacketDelay = 0.12,   
    CycleDelay = 1        
}


local payload = string.rep("🔥GENERALG🔥", CONFIG.PayloadKB * 1024)


local function sendPackets()
    for i = 1, CONFIG.PacketsPerCycle do
        GrabRemote:FireServer(payload)
        task.wait(CONFIG.PacketDelay)
    end
end


for i = 1, CONFIG.Threads do
    task.spawn(function()
        while true do
            sendPackets()
            task.wait(CONFIG.CycleDelay)
        end
    end)
end
    end
end)

local localplayer = {
    character = player.Character,
    hrp = nil,
    ExtinguishPart = nil,
    antifire = false
}

player.CharacterAdded:Connect(function(char)
    localplayer.character = char
    localplayer.hrp = char:WaitForChild("HumanoidRootPart")
    localplayer.ExtinguishPart = char:WaitForChild("ExtinguishPart")
end)

if localplayer.character then
    localplayer.hrp = localplayer.character:FindFirstChild("HumanoidRootPart")
    localplayer.ExtinguishPart = localplayer.character:FindFirstChild("ExtinguishPart")
end

local function getHumanoid()
    local char = player.Character
    if char then
        return char:FindFirstChild("Humanoid")
    end
end

local Hum = getHumanoid()

player.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    Hum = char:WaitForChild("Humanoid")
end)
--------------------------------------------PLAYER TAB INC---------------------------------------------
local PlayerTab = Window:MakeTab({
    Name = "Player",
    Icon = "rbxassetid://117259180607823",
    PremiumOnly = false
})

PlayerTab:AddButton({
    Name = "Delete member",
    Callback = function()
        local Players = game:GetService("Players")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local Workspace = game:GetService("Workspace")

        local LocalPlayer = Players.LocalPlayer
        local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

        local FallHeight = Workspace.FallenPartsDestroyHeight
        local Parts = {
            "Left Leg",
            "Right Leg",
            "Left Arm",
            "Right Arm"
        }

        for cycle = 1, 5 do
            ReplicatedStorage.CharacterEvents.RagdollRemote:FireServer(
                Character:WaitForChild("HumanoidRootPart"),
                5
            )

            local Welds = {}

            for _, PartName in ipairs(Parts) do
                local Limb = Character:FindFirstChild(PartName)
                if Limb then
                    for _, Weld in ipairs(Workspace:GetDescendants()) do
                        if Weld:IsA("WeldConstraint") and (Weld.Part0 == Limb or Weld.Part1 == Limb) then
                            Weld.Enabled = false
                            table.insert(Welds, Weld)
                        end
                    end

                    for _, Motor in ipairs(Limb:GetChildren()) do
                        if Motor:IsA("Motor6D") or Motor:IsA("Weld") then
                            Motor.Enabled = false
                            table.insert(Welds, Motor)
                        end
                    end

                    Limb.Anchored = false
                    Limb.CFrame = CFrame.new(
                        Limb.Position.X,
                        FallHeight - 100,
                        Limb.Position.Z
                    )

                    task.wait(0.1)
                end
            end

            for _, Weld in ipairs(Welds) do
                Weld.Enabled = true
            end

            task.wait(0.25)
        end
    end
})

local twalk = false
local speed = 15

PlayerTab:AddToggle({
    Name = "TeleportWalk",
    Default = false,
    Callback = function(v)
        twalk = v
    end
})

PlayerTab:AddSlider({
    Name = "Speed",
    Min = 15,
    Max = 200,
    Default = 15,
    Callback = function(v)
        speed = v
    end
})

RunService.RenderStepped:Connect(function()
    if twalk and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
        local hrp = LP.Character.HumanoidRootPart
        local dir = LP.Character.Humanoid.MoveDirection
        if dir.Magnitude > 0 then
            hrp.CFrame = hrp.CFrame + (dir * (speed / 50))
        end
    end
end)

local infjump = false

PlayerTab:AddToggle({
    Name = "InfiniteJump",
    Default = false,
    Callback = function(v)
        infjump = v
    end
})

UserInputService.JumpRequest:Connect(function()
    if infjump and Hum then
        Hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

PlayerTab:AddSlider({
    Name = "JumpPower",
    Min = 25,
    Max = 500,
    Default = 25,
    Callback = function(v)
        if Hum then
            Hum.UseJumpPower = true
            Hum.JumpPower = v
        end
    end
})

PlayerTab:AddToggle({
    Name = "ThirdPerson",
    Default = false,
    Callback = function(v)
        if v then
            LP.CameraMaxZoomDistance = 50
            LP.CameraMode = Enum.CameraMode.Classic
        else
            LP.CameraMaxZoomDistance = 8
            LP.CameraMode = Enum.CameraMode.LockFirstPerson
        end
    end
})

local spinEnabled = false
local spinSpeed = 5
local spinConnection = nil

local function stopSpin()
    if spinConnection then
        spinConnection:Disconnect()
        spinConnection = nil
    end
end

local function startSpin()
    stopSpin()
    spinConnection = RunService.Heartbeat:Connect(function()
        if not spinEnabled then
            return
        end

        local character = LP.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(spinSpeed), 0)
        end
    end)
end

PlayerTab:AddToggle({
    Name = "Auto Spin",
    Default = false,
    Callback = function(v)
        spinEnabled = v
        if v then
            startSpin()
        else
            stopSpin()
        end
    end
})

PlayerTab:AddSlider({
    Name = "Spin Speed",
    Min = 1,
    Max = 50,
    Default = 5,
    Callback = function(v)
        spinSpeed = v
    end
})
--------------------------------------------PLAYER TAB END---------------------------------------------

--------------------------------------------InvenTAB INC---------------------------------------------
local I1Tab = Window:MakeTab({
    Name = "Invulnerability",
    Icon = "rbxassetid://11322093465",
    PremiumOnly = false
})

local Players = game:GetService("Players")
local RepStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local CharEvents, Struggle, Ragdoll = safeGetCharacterEvents(BOOT_WAIT_TIMEOUT)
local IsHeld = safeGetPlayerFlagValue(LocalPlayer, "IsHeld", BOOT_WAIT_TIMEOUT)
local isHeldChangedConnection

local loop
local hrp, hum
local lastCF
local enabled = false

local function refreshAntiGrabDependencies(timeout)
    CharEvents, Struggle, Ragdoll = safeGetCharacterEvents(timeout or 0)
    IsHeld = safeGetPlayerFlagValue(LocalPlayer, "IsHeld", timeout or 0)
    return Struggle and Ragdoll and IsHeld
end

local function breakRoot()
    local r = hrp:FindFirstChild("RootAttachment")
    if r then
        r:Remove()
        local a = Instance.new("Attachment")
        a.Name = "RootAttachment"
        a.Parent = hrp
    end
end

local function microAnchor()
    hrp.Anchored = true
    hrp.Anchored = false
end

local function start()
    if loop then loop:Disconnect() end

    loop = RunService.Heartbeat:Connect(function()
        if not (IsHeld and Struggle and Ragdoll) then
            refreshAntiGrabDependencies(0)
        end

        if enabled and IsHeld and IsHeld.Value and hrp and hum and Struggle and Ragdoll then
            if not lastCF then
                lastCF = hrp.CFrame
            end

            breakRoot()
            microAnchor()

            Struggle:FireServer()
            Ragdoll:FireServer(hrp, 0)

            hum.PlatformStand = false
            hum.Sit = false
            hum.AutoRotate = true
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)

            if (hrp.Position - lastCF.Position).Magnitude > 6 then
                hrp.CFrame = lastCF
            end
        else
            lastCF = nil
        end
    end)
end

I1Tab:AddToggle({
    Name = "Anti-Grab",
    Default = false,
    Callback = function(v)
        enabled = v

        if not v then
            if loop then
                loop:Disconnect()
                loop = nil
            end
            lastCF = nil
        else
            local char = LocalPlayer.Character
            if char then
                hrp = char:FindFirstChild("HumanoidRootPart")
                hum = char:FindFirstChild("Humanoid")
                if hrp and hum then
                    start()
                end
            end
        end
    end
})

local function onIsHeldChanged(v)
    if not enabled then return end

    local char = LocalPlayer.Character
    if not char then return end

    hrp = char:FindFirstChild("HumanoidRootPart")
    hum = char:FindFirstChild("Humanoid")

    if v and hrp and hum then
        start()
    end
end

local function bindIsHeldChanged()
    if isHeldChangedConnection then
        isHeldChangedConnection:Disconnect()
        isHeldChangedConnection = nil
    end

    if not IsHeld then
        return
    end

    isHeldChangedConnection = IsHeld.Changed:Connect(onIsHeldChanged)
end

bindIsHeldChanged()

LocalPlayer.ChildAdded:Connect(function(child)
    if child.Name == "IsHeld" then
        IsHeld = child
        bindIsHeldChanged()
    end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    hrp = safeWaitForChild(char, "HumanoidRootPart", 5)
    hum = safeWaitForChild(char, "Humanoid", 5)

    if not hrp or not hum then
        return
    end

    hum.PlatformStand = false
    hum.Sit = false
    hum.AutoRotate = true

    if enabled then
        start()
    end
end)

I1Tab:AddButton({
    Name = "Break PCLD",
    Callback = function()
        local character = LocalPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChild("Humanoid")
        
        if not (rootPart and humanoid) then
            return
        end
        
        local originalCFrame = rootPart.CFrame
        rootPart.CFrame = originalCFrame + Vector3.new(0, 50000, 0)
        task.wait(0.05)
        humanoid.Health = 0
        
        LocalPlayer.CharacterAdded:Once(function(newCharacter)
            local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 5)
            local newHumanoid = newCharacter:WaitForChild("Humanoid", 5)
            if newRoot and newHumanoid then
                task.wait(0.1)
                newRoot.CFrame = originalCFrame
                task.wait(0.05)
                newHumanoid.Health = 0
            end
        end)
    end
})


_G.ShurikenAntiKick = false

I1Tab:AddToggle({
    Name = "Anti Kick",
    Default = false,
    Callback = function(value)
        _G.ShurikenAntiKick = value
        
        local function Cleanup()
            local spawnedToys = Workspace:FindFirstChild(LocalPlayer.Name .. "SpawnedInToys")
            local destroyToy = ReplicatedStorage:FindFirstChild("MenuToys") and ReplicatedStorage.MenuToys:FindFirstChild("DestroyToy")
            
            if spawnedToys and destroyToy then
                for _, toy in pairs(spawnedToys:GetChildren()) do
                    if toy.Name == "AntiKick" or toy.Name == "NinjaShuriken" then
                        pcall(function()
                            destroyToy:FireServer(toy)
                        end)
                    end
                end
            end
        end
        
        if value then
            task.spawn(function()
                local player = LocalPlayer
                local repStorage = ReplicatedStorage
                local setNetworkOwner = repStorage.GrabEvents.SetNetworkOwner
                local stickyPart = repStorage.PlayerEvents.StickyPartEvent
                local spawnToy = repStorage.MenuToys.SpawnToyRemoteFunction
                local destroyToy = repStorage.MenuToys.DestroyToy
                local canSpawnToy = player:WaitForChild("CanSpawnToy")
                
                local function GetHumanoidRootPart()
                    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                        return player.Character.HumanoidRootPart
                    else
                        local character = player.CharacterAdded:Wait()
                        return character:WaitForChild("HumanoidRootPart")
                    end
                end
                
                local function IsInPlot()
                    if not Workspace.PlotItems.PlayersInPlots:FindFirstChild(player.Name) then
                        return false
                    end
                    
                    for _, plot in pairs(Workspace.Plots:GetChildren()) do
                        local plotSign = plot:FindFirstChild("PlotSign")
                        local owners = plotSign and plotSign:FindFirstChild("ThisPlotsOwners")
                        if owners then
                            for _, owner in pairs(owners:GetChildren()) do
                                if owner.Value == player.Name then
                                    local plotItems = Workspace.PlotItems:FindFirstChild(plot.Name)
                                    if plotItems then
                                        return true, plotItems
                                    end
                                end
                            end
                        end
                    end
                    return false
                end
                
                local function AnchorToy(toy)
                    if not toy or not toy:FindFirstChild("StickyPart") then return end
                    
                    local rootPart = GetHumanoidRootPart()
                    if not rootPart then return end
                    
                    if toy:FindFirstChild("SoundPart") then
                        if not toy.SoundPart:FindFirstChild("PartOwner") or toy.SoundPart.PartOwner.Value ~= player.Name then
                            setNetworkOwner:FireServer(toy.SoundPart, toy.SoundPart.CFrame)
                        end
                    end
                    
                    local firePart = rootPart:FindFirstChild("FirePlayerPart") or rootPart:WaitForChild("FirePlayerPart", 5)
                    if firePart then
                        stickyPart:FireServer(toy.StickyPart, firePart, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), math.rad(90)))
                    end
                    
                    for _, part in pairs(toy:GetChildren()) do
                        if part.Name == "Pyramid" then
                            part.CanTouch = false
                            part.CanCollide = false
                            part.CanQuery = false
                            part.Transparency = 1
                            if not part:FindFirstChild("Highlight") then
                                local highlight = Instance.new("Highlight", part)
                                highlight.FillColor = Color3.fromRGB(0, 0, 0)
                            end
                        elseif part.Name == "Main" then
                            part.CanTouch = false
                            part.CanCollide = false
                            part.CanQuery = false
                            part.Transparency = 1
                            if not part:FindFirstChild("Highlight") then
                                local highlight = Instance.new("Highlight", part)
                                highlight.FillColor = Color3.fromRGB(255, 255, 255)
                            end
                        elseif part:IsA("BasePart") then
                            part.CanTouch = false
                            part.CanCollide = false
                            part.CanQuery = false
                            part.Transparency = 1
                        end
                    end
                end
                
                local function SpawnAntiKick()
                    local startTime = tick()
                    while not canSpawnToy.Value do
                        if not _G.ShurikenAntiKick or tick() - startTime > 5 then
                            return nil
                        end
                        task.wait(0.1)
                    end
                    
                    local rootPart = GetHumanoidRootPart()
                    if rootPart then
                        task.spawn(function()
                            pcall(function()
                                spawnToy:InvokeServer("NinjaShuriken", rootPart.CFrame * CFrame.new(0, 12, 20), Vector3.new(0, 0, 0))
                            end)
                        end)
                    end
                    
                    local inPlot, plotItems = IsInPlot()
                    local spawnedToys = Workspace:FindFirstChild(player.Name .. "SpawnedInToys")
                    
                    if inPlot and plotItems then
                        return plotItems:WaitForChild("NinjaShuriken", 2)
                    elseif not Workspace.PlotItems.PlayersInPlots:FindFirstChild(player.Name) and spawnedToys then
                        return spawnedToys:WaitForChild("NinjaShuriken", 2)
                    end
                    
                    return nil
                end
                
                while _G.ShurikenAntiKick do
                    task.wait(0.005)
                    
                    if not player.Character or not player.Character:FindFirstChild("Humanoid") or player.Character.Humanoid.Health <= 0 then
                        continue
                    end
                    
                    local spawnedToys = Workspace:FindFirstChild(player.Name .. "SpawnedInToys")
                    local antiKick = spawnedToys and spawnedToys:FindFirstChild("AntiKick")
                    
                    if Workspace.PlotItems.PlayersInPlots:FindFirstChild(player.Name) then
                        local inPlot, plotItems = IsInPlot()
                        if inPlot and plotItems and Workspace.Plots:FindFirstChild(plotItems.Name) then
                            local plotSign = Workspace.Plots[plotItems.Name]:FindFirstChild("PlotSign")
                            if plotSign and plotSign.ThisPlotsOwners.Value.TimeRemainingNum.Value > 89 then
                                antiKick = SpawnAntiKick()
                                if antiKick == nil then
                                    continue
                                end
                                antiKick.Name = "AntiKick"
                                AnchorToy(antiKick)
                            end
                        end
                    end
                    
                    if not antiKick then
                        if Workspace.PlotItems.PlayersInPlots:FindFirstChild(player.Name) then
                            continue
                        end
                        
                        antiKick = SpawnAntiKick()
                        if antiKick == nil then
                            continue
                        end
                        antiKick.Name = "AntiKick"
                        if not antiKick then
                            continue
                        end
                    end
                    
                    repeat
                        if antiKick and antiKick:FindFirstChild("StickyPart") and antiKick.StickyPart.CanTouch == true then
                            AnchorToy(antiKick)
                            antiKick.Name = "AntiKick"
                        end
                        task.wait(0.3)
                    until not antiKick or not _G.ShurikenAntiKick or not antiKick:FindFirstChild("StickyPart") or antiKick.StickyPart.CanTouch == false or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") or not antiKick:FindFirstChild("StickyPart") or (player.Character.HumanoidRootPart.Position - antiKick.StickyPart.Position).Magnitude >= 20
                    
                    if not antiKick or not antiKick:FindFirstChild("StickyPart") or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") or (player.Character.HumanoidRootPart.Position - antiKick.StickyPart.Position).Magnitude >= 20 then
                        Cleanup()
                    end
                    
                    pcall(function()
                        repeat task.wait(0.05)
                        until not _G.ShurikenAntiKick or not player.Character or not player.Character:FindFirstChild("Humanoid") or not antiKick or not antiKick:FindFirstChild("StickyPart") or not antiKick.StickyPart:FindFirstChild("StickyWeld") or not antiKick.StickyPart.StickyWeld.Part1
                        
                        if not antiKick or not antiKick:FindFirstChild("StickyPart") or (player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health <= 0) or not antiKick.StickyPart:FindFirstChild("StickyWeld").Part1 then
                            Cleanup()
                        end
                    end)
                end
            end)
        else
            _G.ShurikenAntiKick = false
            Cleanup()
        end
    end
})

local kickResetEnabled = false

I1Tab:AddToggle({
    Name = "anti kick reset",
    Default = false,
    Callback = function(value)
        kickResetEnabled = value
        if kickResetEnabled then
            local gameCorrections = ReplicatedStorage:FindFirstChild("GameCorrectionEvents")
            local struggle = ReplicatedStorage:FindFirstChild("CharacterEvents") and ReplicatedStorage.CharacterEvents:FindFirstChild("Struggle")
            
            if gameCorrections and struggle then
                Connections = Connections or {}
                Connections["GameNotify"] = gameCorrections.OnClientEvent:Connect(function(message)
                    if message == "Flying" then
                        struggle:FireServer(LocalPlayer)
                        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
                        if humanoid then
                            humanoid.Health = 0
                        end
                    end
                end)
            end
        else
            if Connections and Connections["GameNotify"] then
                Connections["GameNotify"]:Disconnect()
                Connections["GameNotify"] = nil
            end
        end
    end
})

_G.Headless = false

I1Tab:AddToggle({
    Name = "Anti Banana",
    Default = false,
    Callback = function(value)
        _G.Headless = value
        
        local function SetupHeadless()
            local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            if not character then return end
            
            local humanoid = character:FindFirstChild("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not humanoid or not rootPart then return end
            
            local head = character:WaitForChild("Head", 3)
            if not head then return end
            
            local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
            if not torso then return end
            
            game:GetService("ReplicatedStorage").CharacterEvents.RagdollRemote:FireServer(rootPart, 3)
            task.wait(0.2)
            
            local torsoCFrame = torso.CFrame
            local headCFrame = head.CFrame
            local rootCFrame = rootPart.CFrame
            
            local limbs = {
                character:FindFirstChild("Left Leg"),
                character:FindFirstChild("Right Leg"),
                character:FindFirstChild("LeftUpperLeg"),
                character:FindFirstChild("RightUpperLeg"),
                character:FindFirstChild("LeftLowerLeg"),
                character:FindFirstChild("RightLowerLeg"),
                character:FindFirstChild("LeftFoot"),
                character:FindFirstChild("RightFoot")
            }
            
            local function MoveLimbs(y1, y2)
                for _, limb in ipairs(limbs) do
                    if limb then
                        limb.CFrame = CFrame.new(10000, y2, 10000)
                    end
                end
                rootPart.Velocity = Vector3.zero
                head.Velocity = Vector3.zero
                head.CFrame = headCFrame
                rootPart.CFrame = rootCFrame
                torso.CFrame = CFrame.new(10000, y1, 10000)
            end
            
            MoveLimbs(92, -150)
            task.wait()
            torso.CFrame = torsoCFrame
            task.wait(0.1)
            MoveLimbs(-150, -200)
            task.wait(0.1)
            
            for i = 1, 15 do
                task.wait()
                torso.CFrame = torsoCFrame
                torso.Velocity = Vector3.zero
                rootPart.Velocity = Vector3.zero
            end
            
            torso.Anchored = true
            task.wait(2)
            torso.Anchored = false
            
            humanoid.HipHeight = 2
            
            task.spawn(function()
                while _G.Headless and humanoid.Health > 0 do
                    task.wait(2)
                    humanoid.HipHeight = 2
                end
            end)
        end
        
        if value then
            task.spawn(function()
                SetupHeadless()
            end)
            task.spawn(function()
                while _G.Headless do
                    LocalPlayer.CharacterAdded:Wait()
                    task.wait(0.5)
                    if _G.Headless then
                        SetupHeadless()
                    end
                end
            end)
        end
    end
})

local antiExplode = false

I1Tab:AddToggle({
    Name = "Anti-Explode",
    Default = false,
    Callback = function(value)
        antiExplode = value
    end
})


Workspace.ChildAdded:Connect(function(part)
    if part.Name == "Part" and antiExplode then
        local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if rootPart and (part.Position - rootPart.Position).Magnitude <= 18 then
            rootPart.Anchored = true
            task.wait(0.5)
            rootPart.Anchored = false
        end
    end
end)
--------------------------------------------InvenTAB end---------------------------------------------

local ITab = Window:MakeTab({
    Name = "Invulnerability more option",
    Icon = "rbxassetid://11322093465",
    PremiumOnly = false
})

 playersService = game:GetService("Players")
 workspaceService = game:GetService("Workspace")
 replicatedStorageService = game:GetService("ReplicatedStorage")
 runService = game:GetService("RunService")

 localPlayer = playersService.LocalPlayer
 characterEventsFolder = safeWaitForChild(replicatedStorageService, "CharacterEvents", BOOT_WAIT_TIMEOUT)
 isHeldValue = safeGetPlayerFlagValue(localPlayer, "IsHeld", BOOT_WAIT_TIMEOUT)
 struggleEvent = characterEventsFolder and (characterEventsFolder:FindFirstChild("Struggle") or safeWaitForChild(characterEventsFolder, "Struggle", BOOT_WAIT_TIMEOUT))
 ragdollRemoteEvent = characterEventsFolder and (characterEventsFolder:FindFirstChild("RagdollRemote") or safeWaitForChild(characterEventsFolder, "RagdollRemote", BOOT_WAIT_TIMEOUT))
 ragdollEvent = ragdollRemoteEvent
 spawnedInToysFolder = safeGetPlayerToyFolder(localPlayer, BOOT_WAIT_TIMEOUT)

_G.AntiGrab = false
 player = game.Players.LocalPlayer
 runService = game:GetService("RunService")


local function findEvents()
    local rs = game:GetService("ReplicatedStorage")
    local charEvents = rs:FindFirstChild("CharacterEvents")
    
    if charEvents then
        struggleEvent = charEvents:FindFirstChild("Struggle")
        ragdollEvent = charEvents:FindFirstChild("RagdollRemote")
    end
    
    isHeldValue = player:FindFirstChild("IsHeld")
    if not isHeldValue then
        isHeldValue = safeGetPlayerFlagValue(player, "IsHeld", 2)
    end
end

local function setupCharacter()
    local char = player.Character or player.CharacterAdded:Wait()
    local humanoidRootPart = safeWaitForChild(char, "HumanoidRootPart", 5)
    if not humanoidRootPart then return end
    
    if isHeldValue then
        isHeldValue.Changed:Connect(function(isBeingHeld)
            if isBeingHeld and _G.AntiGrab then
                local connection
                connection = runService.Heartbeat:Connect(function()
                    if isHeldValue.Value then
                        humanoidRootPart.Velocity = Vector3.new()
                        humanoidRootPart.Anchored = true
                        
                        if struggleEvent then
                            struggleEvent:FireServer(player)
                        end
                        
                        if ragdollEvent then
                            ragdollEvent:FireServer(humanoidRootPart, 0)
                        end
                    else
                        humanoidRootPart.Anchored = false
                        if connection then
                            connection:Disconnect()
                        end
                    end
                end)
            end
        end)
    end
end

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local AntiLagEnabled = false
local AutoAntiLagEnabled = true
local balancedOptimizeEnabled = false
local manualBalancedEnabled = false
local autoBalancedApplied = false

local avgFPS = 60
local smoothing = 0.05
local dropThreshold = 0.5
local checkDelay = 2.75
local dropTimer = 0
local autoOptimizePingThresholdMs = 180
local autoOptimizeRecoverPingMs = 120
local autoOptimizeFpsThreshold = 42
local autoOptimizeRecoverFps = 56

local characterScript = Players.LocalPlayer.PlayerScripts:FindFirstChild("CharacterAndBeamMove")

ITab:AddToggle({
    Name = "Anti Lag",
    Default = false,
    Callback = function(v)
        AntiLagEnabled = v
        if characterScript then
            characterScript.Disabled = v
        end
    end
})

local performanceMode = "off"
local low3DConnections = {}
local low3DPartStates = {}
local low3DEffectStates = {}
local low3DTerrainState = nil
local low3DLightingState = nil

local function disconnectLow3DConnections()
    for _, connection in ipairs(low3DConnections) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(low3DConnections)
end

local function cachePartState(part)
    if low3DPartStates[part] then
        return
    end

    low3DPartStates[part] = {
        Material = part.Material,
        Reflectance = part.Reflectance,
        CastShadow = part.CastShadow,
    }
end

local function applyPerformanceToPart(part)
    if not part:IsA("BasePart") then
        return
    end

    cachePartState(part)

    if performanceMode == "aggressive" then
        part.Material = Enum.Material.SmoothPlastic
        part.Reflectance = 0
        part.CastShadow = false
        return
    end

    if performanceMode == "balanced" then
        if part.Material == Enum.Material.Glass
            or part.Material == Enum.Material.ForceField
            or part.Material == Enum.Material.Neon then
            part.Material = Enum.Material.SmoothPlastic
        end

        part.Reflectance = math.min(part.Reflectance, 0.05)
        part.CastShadow = part.Transparency < 0.35 and part.Size.Magnitude >= 6
    end
end

local function cacheEffectState(effect)
    if low3DEffectStates[effect] then
        return
    end

    local state = {
        Enabled = effect.Enabled,
    }

    if effect:IsA("ParticleEmitter") then
        state.Rate = effect.Rate
    elseif effect:IsA("BloomEffect") then
        state.Intensity = effect.Intensity
    end

    low3DEffectStates[effect] = state
end

local function applyPerformanceToEffect(effect)
    if effect:IsA("ParticleEmitter") then
        cacheEffectState(effect)
        if performanceMode == "aggressive" then
            effect.Enabled = false
        elseif performanceMode == "balanced" then
            effect.Rate = math.max(0, effect.Rate * 0.35)
        end
    elseif effect:IsA("Trail") or effect:IsA("Beam") then
        cacheEffectState(effect)
        effect.Enabled = false
    elseif effect:IsA("Fire") or effect:IsA("Smoke") or effect:IsA("Sparkles") then
        cacheEffectState(effect)
        effect.Enabled = false
    end
end

local function applyPerformanceScene()
    if not low3DLightingState then
        low3DLightingState = {
            GlobalShadows = Lighting.GlobalShadows,
            FogEnd = Lighting.FogEnd,
            Brightness = Lighting.Brightness,
            Technology = Lighting.Technology,
        }
    end

    if not low3DTerrainState then
        low3DTerrainState = {
            WaterWaveSize = Workspace.Terrain.WaterWaveSize,
            WaterWaveSpeed = Workspace.Terrain.WaterWaveSpeed,
            WaterReflectance = Workspace.Terrain.WaterReflectance,
            WaterTransparency = Workspace.Terrain.WaterTransparency,
        }
    end

    if performanceMode == "aggressive" then
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 100000
        Lighting.Brightness = math.min(Lighting.Brightness, 2)
        Lighting.Technology = Enum.Technology.Compatibility

        Workspace.Terrain.WaterWaveSize = 0
        Workspace.Terrain.WaterWaveSpeed = 0
        Workspace.Terrain.WaterReflectance = 0
        Workspace.Terrain.WaterTransparency = 1
    elseif performanceMode == "balanced" then
        Lighting.GlobalShadows = false
        Lighting.FogEnd = math.max(Lighting.FogEnd, 50000)
        Lighting.Brightness = math.min(Lighting.Brightness, 2.5)

        Workspace.Terrain.WaterWaveSize = math.min(Workspace.Terrain.WaterWaveSize, 0.05)
        Workspace.Terrain.WaterWaveSpeed = math.min(Workspace.Terrain.WaterWaveSpeed, 0.05)
        Workspace.Terrain.WaterReflectance = math.min(Workspace.Terrain.WaterReflectance, 0)
        Workspace.Terrain.WaterTransparency = math.max(Workspace.Terrain.WaterTransparency, 0.65)
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            applyPerformanceToPart(obj)
        else
            applyPerformanceToEffect(obj)
        end
    end

    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("BlurEffect") or obj:IsA("SunRaysEffect") or obj:IsA("DepthOfFieldEffect") then
            cacheEffectState(obj)
            obj.Enabled = false
        elseif obj:IsA("BloomEffect") then
            cacheEffectState(obj)
            if performanceMode == "aggressive" then
                obj.Enabled = false
            elseif performanceMode == "balanced" then
                obj.Intensity = math.min(obj.Intensity, 0.35)
            end
        end
    end
end

local function restorePerformanceScene()
    disconnectLow3DConnections()

    for part, state in pairs(low3DPartStates) do
        if part and part.Parent then
            part.Material = state.Material
            part.Reflectance = state.Reflectance
            part.CastShadow = state.CastShadow
        end
    end
    table.clear(low3DPartStates)

    for effect, state in pairs(low3DEffectStates) do
        if effect and effect.Parent then
            effect.Enabled = state.Enabled
            if effect:IsA("ParticleEmitter") and state.Rate ~= nil then
                effect.Rate = state.Rate
            elseif effect:IsA("BloomEffect") and state.Intensity ~= nil then
                effect.Intensity = state.Intensity
            end
        end
    end
    table.clear(low3DEffectStates)

    if low3DLightingState then
        Lighting.GlobalShadows = low3DLightingState.GlobalShadows
        Lighting.FogEnd = low3DLightingState.FogEnd
        Lighting.Brightness = low3DLightingState.Brightness
        Lighting.Technology = low3DLightingState.Technology
    end

    if low3DTerrainState then
        Workspace.Terrain.WaterWaveSize = low3DTerrainState.WaterWaveSize
        Workspace.Terrain.WaterWaveSpeed = low3DTerrainState.WaterWaveSpeed
        Workspace.Terrain.WaterReflectance = low3DTerrainState.WaterReflectance
        Workspace.Terrain.WaterTransparency = low3DTerrainState.WaterTransparency
    end
end

local function enablePerformanceMode(mode)
    performanceMode = mode
    applyPerformanceScene()
    disconnectLow3DConnections()

    table.insert(low3DConnections, Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("BasePart") then
            applyPerformanceToPart(obj)
        else
            applyPerformanceToEffect(obj)
        end
    end))

    table.insert(low3DConnections, game.DescendantAdded:Connect(function(obj)
        if obj:IsA("BlurEffect") or obj:IsA("SunRaysEffect") or obj:IsA("DepthOfFieldEffect") then
            cacheEffectState(obj)
            obj.Enabled = false
        elseif obj:IsA("BloomEffect") then
            cacheEffectState(obj)
            if performanceMode == "aggressive" then
                obj.Enabled = false
            elseif performanceMode == "balanced" then
                obj.Intensity = math.min(obj.Intensity, 0.35)
            end
        end
    end))
end

local function disablePerformanceMode()
    performanceMode = "off"
    restorePerformanceScene()
end

local function setBalancedOptimization(enabled, isAuto)
    balancedOptimizeEnabled = enabled

    if isAuto then
        autoBalancedApplied = enabled
    else
        manualBalancedEnabled = enabled
        autoBalancedApplied = false
    end

    if enabled then
        enablePerformanceMode("balanced")
    elseif performanceMode == "balanced" then
        disablePerformanceMode()
    end
end

ITab:AddToggle({
    Name = "Balanced Optimization",
    Default = false,
    Callback = function(v)
        setBalancedOptimization(v, false)
    end
})

ITab:AddToggle({
    Name = "Auto Smart Optimize",
    Default = true,
    Callback = function(v)
        AutoAntiLagEnabled = v

        if not v and autoBalancedApplied then
            setBalancedOptimization(false, true)
            if not manualBalancedEnabled and performanceMode == "balanced" then
                disablePerformanceMode()
            end
        end
    end
})

ITab:AddToggle({
    Name = "Disable 3D Graphics",
    Default = false,
    Callback = function(v)
        if v then
            balancedOptimizeEnabled = false
            manualBalancedEnabled = false
            autoBalancedApplied = false
            enablePerformanceMode("aggressive")
        else
            if performanceMode == "aggressive" then
                disablePerformanceMode()
            end
        end
    end
})

RunService.Heartbeat:Connect(function(dt)
    dt = math.max(dt or 0, 1 / 240)
    local currentFPS = 1 / dt
    avgFPS = avgFPS + (currentFPS - avgFPS) * smoothing

    if not AutoAntiLagEnabled or performanceMode == "aggressive" or manualBalancedEnabled then
        dropTimer = 0
        return
    end

    local pingMs = LocalPlayer:GetNetworkPing() * 1000
    local underPressure = avgFPS < autoOptimizeFpsThreshold or pingMs > autoOptimizePingThresholdMs
    local recovered = avgFPS > autoOptimizeRecoverFps and pingMs < autoOptimizeRecoverPingMs

    if underPressure then
        dropTimer = math.min(dropTimer + dt, checkDelay + 2)
        if dropTimer >= checkDelay and not autoBalancedApplied then
            setBalancedOptimization(true, true)
        end
    elseif autoBalancedApplied and recovered then
        dropTimer = math.max(dropTimer - dt * 2, 0)
        if dropTimer <= 0.1 then
            setBalancedOptimization(false, true)
        end
    else
        dropTimer = math.max(dropTimer - dt, 0)
    end
end)


findEvents()

if player.Character then
    setupCharacter()
end

player.CharacterAdded:Connect(setupCharacter)

local mainPlayer = game:GetService("Players").LocalPlayer
local spawnFunction = safeResolvePath(game:GetService("ReplicatedStorage"), {"MenuToys", "SpawnToyRemoteFunction"}, BOOT_WAIT_TIMEOUT)
variavelStorage = game:GetService("ReplicatedStorage")
variavelEnabled = false
heartbeatLink = nil
executionRunning = false
procedureFlag = false
function FetchPlot()
    for _, plotObject in pairs(workspace.Plots:GetChildren()) do
        local signObject = plotObject:FindFirstChild("PlotSign")
        if not signObject then continue end
        local ownerContainer = signObject:FindFirstChild("ThisPlotsOwners")
        if not ownerContainer then continue end
        local ownerData = ownerContainer:FindFirstChild("Value")
        if ownerData and ownerData.Value == mainPlayer.Name then
            return plotObject
        end
    end
    return nil
end
function MoveToPlot(plotObject)
    if not plotObject then return false end
    local character = mainPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return false end
    
    local grabComponent = plotObject:FindFirstChild("PlusGrabPart", true)
    if grabComponent then
        character.HumanoidRootPart.CFrame = grabComponent.CFrame
        return true
    end
    return false
end
function AutoAcquirePlot()
    local ownedPlot = FetchPlot()
    if ownedPlot then
        MoveToPlot(ownedPlot)
        return ownedPlot
    end
    
    for _, plotObject in pairs(workspace.Plots:GetChildren()) do
        local signObject = plotObject:FindFirstChild("PlotSign")
        if not signObject then continue end
        local ownerContainer = signObject:FindFirstChild("ThisPlotsOwners")
        if not ownerContainer then continue end
        local ownerData = ownerContainer:FindFirstChild("Value")
        
        if not ownerData or ownerData.Value == "" then
            local grabComponent = plotObject:FindFirstChild("PlusGrabPart", true)
            if grabComponent then
                local character = mainPlayer.Character
                if not character or not character:FindFirstChild("HumanoidRootPart") then 
                    repeat wait() until mainPlayer.Character and mainPlayer.Character:FindFirstChild("HumanoidRootPart")
                    character = mainPlayer.Character
                end
                
                character.HumanoidRootPart.CFrame = grabComponent.CFrame
                
                for i = 1, 15 do
                    variavelStorage.GrabEvents.SetNetworkOwner:FireServer(grabComponent, grabComponent.CFrame)
                    wait(0.1)
                    
                    local updatedSign = plotObject:FindFirstChild("PlotSign")
                    local updatedOwners = updatedSign and updatedSign:FindFirstChild("ThisPlotsOwners")
                    local updatedOwnerData = updatedOwners and updatedOwners:FindFirstChild("Value")
                    
                    if updatedOwnerData and updatedOwnerData.Value == mainPlayer.Name then
                        return plotObject
                    end
                end
            end
        end
    end
    return nil
end
function FindBlobman()
    local plotObject = FetchPlot()
    if not plotObject then return nil end
    if not workspace:FindFirstChild("PlotItems") then return nil end
    local plotFolder = workspace.PlotItems:FindFirstChild(plotObject.Name)
    if not plotFolder then return nil end
    return plotFolder:FindFirstChild("CreatureBlobman")
end
function PerformGrabAction()
    local blobmanObject = FindBlobman()
    if not blobmanObject then return false end
    
    local character = mainPlayer.Character
    if not character then return false end
    if not mainPlayer:FindFirstChild("IsHeld") then return false end
    
    if character:GetAttribute("GrabDone") then return true end
    
    local leftDetector = blobmanObject.LeftDetector
    local attachPoint = leftDetector.Attachment
    varSoundLatch = attachPoint.LatchSound
    while not varSoundLatch.Playing do
        if not character:GetAttribute("GrabDone") then
            if blobmanObject:FindFirstChild("VehicleSeat") then
                local seatObject = blobmanObject.VehicleSeat
                varProximityPrompt = seatObject:FindFirstChild("ProximityPrompt")
                if varProximityPrompt then
                    fireproximityprompt(varProximityPrompt)
                end
                seatObject:Sit(character.Humanoid)
                wait(0.5)
                character:SetAttribute("GrabDone", true)
            end
            
            if blobmanObject:FindFirstChild("BlobmanSeatAndOwnerScript") then
                varScript = blobmanObject.BlobmanSeatAndOwnerScript
                if varScript:FindFirstChild("CreatureDrop") then
                    varScript.CreatureDrop:Destroy()
                end
                
                if character.HumanoidRootPart:FindFirstChild("RootAttachment") then
                    character.HumanoidRootPart.RootAttachment:Destroy()
                end
                
                varScript.CreatureGrab:FireServer(leftDetector, character.HumanoidRootPart, leftDetector.LeftWeld)
                mainPlayer.IsHeld.Value = true
                mainPlayer.IsHeld.Value = false
                variavelStorage.CharacterEvents.RagdollRemote:FireServer(character.HumanoidRootPart, 0)
            end
        end
        wait(0.1)
    end
    
    blobmanObject.PrimaryPart.Anchored = true
    blobmanObject.PrimaryPart.CFrame = character.HumanoidRootPart.CFrame + Vector3.new(0, 20, 0)
    
    heartbeatLink = game:GetService("RunService").Heartbeat:Connect(function()
        if mainPlayer.IsHeld.Value then
            escapeAttempts = 0
            maxEscapeAttempts = 10
            
            while mainPlayer.IsHeld.Value and escapeAttempts < maxEscapeAttempts do
                task.wait(0.1)
                variavelStorage.CharacterEvents.Struggle:FireServer(character.HumanoidRootPart)
                variavelStorage.GrabEvents.SetNetworkOwner:FireServer(character.Head, character.Head.CFrame)
                variavelStorage.CharacterEvents.RagdollRemote:FireServer(character.HumanoidRootPart, 0)
                escapeAttempts += 1
                
                if escapeAttempts >= maxEscapeAttempts then
                    mainPlayer.IsHeld.Value = false
                    character.HumanoidRootPart.Massless = false
                end
            end
        end
    end)
    
    wait(5)
    if heartbeatLink then
        heartbeatLink:Disconnect()
        heartbeatLink = nil
    end
    
    return true
end
function CreateBlobman()
    local character = mainPlayer.Character
    if not character then return false end
    varHead = character:FindFirstChild("Head")
    if not varHead then return false end
    if not spawnFunction then
        spawnFunction = safeResolvePath(game:GetService("ReplicatedStorage"), {"MenuToys", "SpawnToyRemoteFunction"}, 2)
    end
    if not spawnFunction then return false end
    
    spawnFunction:InvokeServer("CreatureBlobman", varHead.CFrame, Vector3.new(0, 44.22800064086914, 0))
    
    for i = 1, 50 do
        if FindBlobman() then
            return true
        end
        wait(0.1)
    end
    return false
end
function CleanupPlayer()
    if mainPlayer.Character then
        if mainPlayer.Character:GetAttribute("AlreadyCompleted") then
            mainPlayer.Character:SetAttribute("AlreadyCompleted", nil)
        end
        if mainPlayer.Character:GetAttribute("GrabDone") then
            mainPlayer.Character:SetAttribute("GrabDone", nil)
        end
    end
end
function ExecutionSequence()
    if not procedureFlag then
        procedureFlag = true
        
        mainPlayer.CharacterAdded:Connect(function()
            CleanupPlayer()
        end)
        
        if mainPlayer.Character then
            CleanupPlayer()
        end
    end
    
    while variavelEnabled and executionRunning do
        varSuccess = false
        
        if mainPlayer.Character and mainPlayer.Character:GetAttribute("AlreadyCompleted") then
            wait(2)
            continue
        end
        
        varPlotObject = FetchPlot()
        if varPlotObject then
            MoveToPlot(varPlotObject)
        else
            varPlotObject = AutoAcquirePlot()
            if not varPlotObject then
                wait(2)
                continue
            end
        end
        
        wait(1)
        
        varBlobmanObject = FindBlobman()
        if not varBlobmanObject then
            if not CreateBlobman() then
                wait(2)
                continue
            end
        end
        
        if not PerformGrabAction() then
            wait(2)
            continue
        end
        
        if mainPlayer.Character then
            mainPlayer.Character:SetAttribute("AlreadyCompleted", true)
        end
        
        varSuccess = true
        
        if varSuccess then
            for i = 1, 30 do
                if not mainPlayer.Character or mainPlayer.Character:FindFirstChild("Humanoid") and mainPlayer.Character.Humanoid.Health <= 0 then
                    varSuccess = false
                    break
                end
                wait(1)
            end
        end
        
        if not varSuccess then
            wait(3)
        else
            wait(10)
        end
    end
    executionRunning = false
    procedureFlag = false
end
ITab:AddToggle({
    Name = "Super Anti Grab",
    Default = false,
    Callback = function(varValue)
        variavelEnabled = varValue
        
        if variavelEnabled then
            if not executionRunning then
                executionRunning = true
                spawn(ExecutionSequence)
            end
        else
            executionRunning = false
            if heartbeatLink then
                heartbeatLink:Disconnect()
                heartbeatLink = nil
            end
        end
    end
})
ITab:AddButton({
    Name = "Fixed Button (Mobile)",
    Callback = function()
        if game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("BlobmanGui") then
            game:GetService("Players").LocalPlayer.PlayerGui.BlobmanGui:Destroy()
        end
        
        if game:GetService("Players").LocalPlayer.Character and 
           game:GetService("Players").LocalPlayer.Character:FindFirstChild("GrabbingScript") then
            game:GetService("Players").LocalPlayer.Character.GrabbingScript.ToggleMobileButtonVisibility:Fire()
        end
    end
})

getgenv().isnetworkowner = function(part)
    if part.ReceiveAge == 0 and not part.Anchored then
        return true
    else
        return false
    end
end

if workspace:FindFirstChild("TeleportToGround") then
    workspace:FindFirstChild("TeleportToGround").Parent = game.ReplicatedStorage:FindFirstChild("GameCorrectionEvents")
end

 Players = game.Players
 LocalPlayer = Players.LocalPlayer
 ReplicatedStorage = game.ReplicatedStorage
 WorkspaceService = game.Workspace

 spawnedInToysFolder = safeGetPlayerToyFolder(LocalPlayer, BOOT_WAIT_TIMEOUT)

function GetHousePlot()
    local Plots = WorkspaceService:FindFirstChild("Plots")
    if not Plots then return nil end
    for _, p in ipairs(Plots:GetChildren()) do
        local s = p:FindFirstChild("PlotSign")
        if s then
            local o = s:FindFirstChild("ThisPlotsOwners")
            if o then
                if o:IsA("StringValue") then
                    if o.Value == LocalPlayer.Name then return p end
                elseif o:FindFirstChild("Value") then
                    local v = o.Value
                    if typeof(v) == "Instance" and v:IsA("StringValue") and v.Value == LocalPlayer.Name then
                        return p
                    end
                end
            end
        end
    end
    return nil
end

function shouldIgnoreBlob(blob)
    if not blob or blob.Name ~= "CreatureBlobman" then return true end
    local HousePlot = GetHousePlot()
    if HousePlot and blob:IsDescendantOf(HousePlot) then return true end
    local PlotItems = WorkspaceService:FindFirstChild("PlotItems")
    if PlotItems then
        local plotName = HousePlot and HousePlot.Name
        if plotName then
            local houseItems = PlotItems:FindFirstChild(plotName)
            if houseItems and blob:IsDescendantOf(houseItems) then return true end
        end
    end
    spawnedInToysFolder = spawnedInToysFolder or safeGetPlayerToyFolder(LocalPlayer, 0)
    if spawnedInToysFolder and blob:IsDescendantOf(spawnedInToysFolder) then return true end
    return false
end

local function manageRootAttachment(hrp)
    if not hrp then return end
    local existing = hrp:FindFirstChild("RootAttachment")
    if existing then existing:Destroy() end
    local newAttach = Instance.new("Attachment")
    newAttach.Name = "RootAttachment"
    newAttach.Parent = hrp
end

local function fixMassless(character)
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Massless then
            part.Massless = false
        end
    end
end

local function checkBlobmanDetectors(character)
    if not character then return end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end
    
    for _, blob in ipairs(WorkspaceService:GetDescendants()) do
        if blob.Name == "CreatureBlobman" and not shouldIgnoreBlob(blob) then
            local leftDetector = blob:FindFirstChild("LeftDetector")
            local rightDetector = blob:FindFirstChild("RightDetector")
            
            if leftDetector then
                for _, constraint in ipairs(leftDetector:GetChildren()) do
                    if (constraint:IsA("AlignPosition") or constraint:IsA("AlignOrientation")) then
                        local a0, a1 = constraint.Attachment0, constraint.Attachment1
                        if (a0 and a0.Parent == humanoidRootPart) or (a1 and a1.Parent == humanoidRootPart) then
                            constraint.Enabled = false
                        end
                    end
                end
            end
            
            if rightDetector then
                for _, constraint in ipairs(rightDetector:GetChildren()) do
                    if (constraint:IsA("AlignPosition") or constraint:IsA("AlignOrientation")) then
                        local a0, a1 = constraint.Attachment0, constraint.Attachment1
                        if (a0 and a0.Parent == humanoidRootPart) or (a1 and a1.Parent == humanoidRootPart) then
                            constraint.Enabled = false
                        end
                    end
                end
            end
        end
    end
end

local function Reconnect2()
    local character = LocalPlayer.Character
    if not character then return end
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    
    fixMassless(character)
    checkBlobmanDetectors(character)
    manageRootAttachment(humanoidRootPart)
    
    humanoidRootPart:GetPropertyChangedSignal("Massless"):Connect(function()
        if humanoidRootPart.Massless then
            fixMassless(character)
            checkBlobmanDetectors(character)
            manageRootAttachment(humanoidRootPart)
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(Reconnect2)
if LocalPlayer.Character then
    Reconnect2()
end

ITab:AddToggle({
    Name = "Anti-Grab 4art (Better)",
    Default = false,
    Save = true,
    Flag = "antigrabBy4art_toggle",
    Callback = function(Value)
        if Value then
            workspace.FallenPartsDestroyHeight = -50000
            
            local AntiGrabConnection
            local AnticheatAntiGrabConnection
            local AntiKickAuraConnection
            
            local RS = game:GetService("ReplicatedStorage")
            local CE = safeWaitForChild(RS, "CharacterEvents", 2)
            local R = game:GetService("RunService")
            local BeingHeld = safeGetPlayerFlagValue(LocalPlayer, "IsHeld", 2)
            local StruggleEvent = CE and (CE:FindFirstChild("Struggle") or safeWaitForChild(CE, "Struggle", 2))
            local LookRemote = CE and (CE:FindFirstChild("Look") or safeWaitForChild(CE, "Look", 2))
            local RagdollRemote = CE and (CE:FindFirstChild("RagdollRemote") or safeWaitForChild(CE, "RagdollRemote", 2))
            
            local gamecorrections = RS:FindFirstChild("GameCorrectionEvents")
            if gamecorrections then
                local tptoground = gamecorrections:FindFirstChild("TeleportToGround")
                if tptoground then
                    tptoground.Parent = workspace
                end
            end
            
            if not (BeingHeld and StruggleEvent and RagdollRemote) then
                return
            end

            AntiGrabConnection = BeingHeld.Changed:Connect(function(C)
                if C == true then
                    local Character = LocalPlayer.Character
                    if Character then
                        local HRP = Character:FindFirstChild("HumanoidRootPart")
                        if HRP then
                            local savedPositions = {}
                            for _, part in ipairs(Character:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    savedPositions[part] = part.CFrame
                                end
                            end
                            
                            local BeforeGrabCFrame = HRP.CFrame
                            local Event
                            Event = R.RenderStepped:Connect(function()
                                if BeingHeld.Value == true then
                                    for _, part in ipairs(Character:GetDescendants()) do
                                        if part:IsA("BasePart") then
                                            part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                                            part.Velocity = Vector3.new(0, 0, 0)
                                        end
                                    end
                                    HRP.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                                    HRP.Velocity = Vector3.new()
                                    for part, savedCF in pairs(savedPositions) do
                                        part.CFrame = savedCF
                                    end
                                    HRP.CFrame = BeforeGrabCFrame
                                    RagdollRemote:FireServer(HRP, 0)
                                    StruggleEvent:FireServer()
                                    
                                    local Hum = Character:FindFirstChild("Humanoid")
                                    if Hum then
                                        Hum.BreakJointsOnDeath = false
                                        Hum:ChangeState(Enum.HumanoidStateType.Dead)
                                        Hum.Sit = false
                                        Hum.Jump = false
                                        Hum.AutoRotate = true
                                        Hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                                        Hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
                                        Hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
                                        Hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
                                        
                                        local CAS = game:GetService("ContextActionService")
                                        CAS:UnbindAction("Escape")
                                        CAS:UnbindAction("JumpRemover")
                                        Players.LocalPlayer.PlayerGui.ControlsGui.ActionEvent:Fire("EscapeControls", false)
                                    end
                                elseif BeingHeld.Value == false then
                                    for part, savedCF in pairs(savedPositions) do
                                        part.CFrame = savedCF
                                    end
                                    HRP.CFrame = BeforeGrabCFrame
                                    if Event then
                                        Event:Disconnect()
                                    end
                                    task.wait(0.2)
                                    HRP.CFrame = BeforeGrabCFrame
                                    for part, savedCF in pairs(savedPositions) do
                                        part.CFrame = savedCF
                                    end
                                end
                            end)
                        end
                    end
                end
            end)
            
            AnticheatAntiGrabConnection = BeingHeld.Changed:Connect(function(C)
                if C == true then
                    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                    if character then
                        local myHRP = character:FindFirstChild("HumanoidRootPart")
                        if myHRP then
                            local oldCF = myHRP.CFrame
                            task.defer(function()
                                while true do
                                    local priorities = {"high", "medium", "low", "lowest"}
                                    for _, priority in ipairs(priorities) do
                                        local args = {
                                            [1] = CFrame.new(100000000000,100000000000,100000000000),
                                            [2] = CFrame.new(100000000000,100000000000,100000000000),
                                            [3] = CFrame.new(100000000000,100000000000,100000000000),
                                            [4] = priority
                                        }
                                        LookRemote:FireServer(unpack(args))
                                    end
                                    
                                    if not BeingHeld.Value then
                                        task.defer(function()
                                            for i = 1,5 do
                                                myHRP.AssemblyLinearVelocity = Vector3.new(0,0,0)
                                                myHRP.CFrame = oldCF
                                                task.wait()
                                            end
                                        end)
                                        break
                                    end
                                    task.wait()
                                end
                            end)
                        end
                    end
                end
            end)
            
            AntiKickAuraConnection = R.RenderStepped:Connect(function()
                local character = LocalPlayer.Character
                if character then
                    local HRP = character:FindFirstChild("HumanoidRootPart")
                    if HRP then
                        if not isnetworkowner(HRP) then
                            local args = {[1] = HRP, [2] = 0}
                            RagdollRemote:FireServer(unpack(args))
                        end
                    end
                end
            end)
            
            getgenv().AntiGrabConnections = {
                AntiGrab = AntiGrabConnection,
                AnticheatAntiGrab = AnticheatAntiGrabConnection,
                AntiKickAura = AntiKickAuraConnection
            }
            
        else
            workspace.FallenPartsDestroyHeight = -100
            
            if getgenv().AntiGrabConnections then
                if getgenv().AntiGrabConnections.AntiGrab then
                    getgenv().AntiGrabConnections.AntiGrab:Disconnect()
                end
                if getgenv().AntiGrabConnections.AnticheatAntiGrab then
                    getgenv().AntiGrabConnections.AnticheatAntiGrab:Disconnect()
                end
                if getgenv().AntiGrabConnections.AntiKickAura then
                    getgenv().AntiGrabConnections.AntiKickAura:Disconnect()
                end
                getgenv().AntiGrabConnections = nil
            end
            
            local gamecorrections = ReplicatedStorage:FindFirstChild("GameCorrectionEvents")
            if gamecorrections and workspace:FindFirstChild("TeleportToGround") then
                workspace.TeleportToGround.Parent = gamecorrections
            end
        end
    end
})



spawnFoodEnabled = false

ITab:AddToggle({
    Name = "Anti Ownership Blob",
    Default = false,
    Callback = function(value)
        spawnFoodEnabled = value
    end
})

ReplicatedStorage = game:GetService("ReplicatedStorage")
RunService = game:GetService("RunService")
Workspace = game:GetService("Workspace")

LocalPlayer = Players.LocalPlayer
local folder, RemoteFolder
currentFood = nil
lastSpawn = 0
spawnCooldown = 0.5
Root = nil
connections = {}

local function initialize()
    folder = safeGetPlayerToyFolder(LocalPlayer, 3)
    RemoteFolder = ReplicatedStorage:FindFirstChild("MenuToys") or safeWaitForChild(ReplicatedStorage, "MenuToys", 3)
    
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    connections = {}

    if not folder or not RemoteFolder then
        return false
    end
    
    connections[1] = folder.ChildAdded:Connect(function(child)
        if child.Name == "FoodHamburger" then
            currentFood = child
        end
    end)
    
    connections[2] = folder.ChildRemoved:Connect(function(child)
        if child == currentFood then
            currentFood = nil
        end
    end)

    return true
end

LocalPlayer.CharacterAdded:Connect(function(character)
    local rootPart = safeWaitForChild(character, "HumanoidRootPart", 5)
    if rootPart then
        Root = rootPart
    end
end)

if LocalPlayer.Character then
    local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        Root = hrp
    end
end

local function spawnFood()
    local currentTime = tick()
    if currentTime - lastSpawn < spawnCooldown then return end
    if not Root then return end
    if not RemoteFolder then
        RemoteFolder = ReplicatedStorage:FindFirstChild("MenuToys") or safeWaitForChild(ReplicatedStorage, "MenuToys", 0)
    end
    if not RemoteFolder then return end
    local spawnRemote = RemoteFolder:FindFirstChild("SpawnToyRemoteFunction")
    if not spawnRemote then return end
    
    lastSpawn = currentTime
    local spawnCFrame = Root.CFrame * CFrame.new(5, 0, 5)
    local spawnVector = Vector3.new(0, 33.0880012512207, 0)
    
    spawnRemote:InvokeServer("FoodHamburger", spawnCFrame, spawnVector)
end

local function holdAndDrop(food)
    if not food or not food.Parent then return end
    
    local holdPart = food:FindFirstChild("HoldPart")
    if not holdPart then return end

    local Character = LocalPlayer.Character
    if not Character then return end

    local holdRemote = holdPart:FindFirstChild("HoldItemRemoteFunction")
    local dropRemote = holdPart:FindFirstChild("DropItemRemoteFunction")
    
    if holdRemote and dropRemote then
        holdRemote:InvokeServer(food, Character)
        
        if Root then
            local dropPosition = Root.Position + Vector3.new(0, 1000, 0)
            dropRemote:InvokeServer(food, CFrame.new(dropPosition), Vector3.new(0, 1000, 0))
        end
    end
end

initialize()

Workspace.ChildAdded:Connect(function(child)
    if child.Name == LocalPlayer.Name .. "SpawnedInToys" and not folder then
        initialize()
    end
end)

RunService.Heartbeat:Connect(function()
    if not spawnFoodEnabled then return end
    
    if not currentFood or not currentFood.Parent then
        spawnFood()
    else
        holdAndDrop(currentFood)
    end
end)

itemCollector = {
    active = false,
    localPlayer = game.Players.LocalPlayer,
    workspaceRef = game.Workspace,
    dropLocation = CFrame.new(-238.98, -256.01, -123.97)
}

function CollectAllItems()
    while itemCollector.active do
        local function ProcessFolder(folder)
            local items = {}
            for _, descendant in pairs(folder:GetDescendants()) do
                if descendant:IsA("Model") and descendant:FindFirstChild("HoldPart") and descendant:FindFirstChild("HoldPart"):FindFirstChild("HoldItemRemoteFunction") then
                    table.insert(items, descendant)
                end
            end
            
            for i = #items, 1, -1 do
                local itemModel = items[i]
                local holdPart = itemModel:FindFirstChild("HoldPart")
                if holdPart then
                    local holdFunction = holdPart:FindFirstChild("HoldItemRemoteFunction")
                    if holdFunction then
                        pcall(function()
                            holdFunction:InvokeServer(itemModel, itemCollector.localPlayer.Character)
                        end)
                    end
                    
                    local dropFunction = holdPart:FindFirstChild("DropItemRemoteFunction")
                    if dropFunction then
                        pcall(function()
                            dropFunction:InvokeServer(itemModel, itemCollector.dropLocation, Vector3.new())
                        end)
                    end
                end
                table.remove(items, i)
                task.wait(0.2)
            end
        end
        
        for _, child in pairs(itemCollector.workspaceRef:GetChildren()) do
            if child:IsA("Folder") and child.Name:find("SpawnedInToys") then
                ProcessFolder(child)
            end
        end
        
        local plotItems = itemCollector.workspaceRef:FindFirstChild("PlotItems")
        if plotItems then
            for _, plotFolder in pairs(plotItems:GetChildren()) do
                if plotFolder:IsA("Folder") then
                    ProcessFolder(plotFolder)
                end
            end
        end
        task.wait(0.001)
    end
end

ITab:AddToggle({
    Name = "Grab All Items",
    Default = false,
    Callback = function(value)
        itemCollector.active = value
        if value then
            task.spawn(CollectAllItems)
        end
    end
})

ReplicatedStorage = game:GetService("ReplicatedStorage")

player = Players.LocalPlayer
antiGucciEnabled = false
local antiGucciConnection
local seatWeldConnection

local function resetPlayer()
    if player.Character then
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.Health = 0
        end
    end
end

local function executeAntiGucci()
    if not player or not player.Character then return end
    
    if player.CanSpawnToy.Value then
        local toyFolderName = player.Name .. "SpawnedInToys"
        local toyFolder = workspace:FindFirstChild(toyFolderName)
        
        if not toyFolder then return end
        
        local blobman = toyFolder:FindFirstChild("CreatureBlobman")
        
        if not blobman then
            local head = player.Character:FindFirstChild("Head")
            if head then
                ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer("CreatureBlobman", head.CFrame, Vector3.new(0, 0, 0))
            end
        else
            local vehicleSeat = blobman:FindFirstChild("VehicleSeat")
            if vehicleSeat then
                local seatWeld = vehicleSeat:FindFirstChild("SeatWeld")
                if seatWeld then
                    if not seatWeldConnection then
                        seatWeldConnection = seatWeld.Changed:Connect(function()
                            if seatWeld.Part1 then
                                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                                if humanoidRootPart and seatWeld.Part1 ~= humanoidRootPart then
                                    ReplicatedStorage.MenuToys.DestroyToy:FireServer(blobman)
                                    seatWeldConnection:Disconnect()
                                    seatWeldConnection = nil
                                end
                            end
                        end)
                    end
                end
            end
            
            local character = player.Character
            local humanoid = character:FindFirstChild("Humanoid")
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            local trainSeat = blobman:FindFirstChild("VehicleSeat")
            
            if humanoid and humanoidRootPart and trainSeat then
                if humanoidRootPart.Massless then
                    humanoidRootPart.Massless = false
                end
                trainSeat:Sit(humanoid)
                if fireproximityprompt then
                    fireproximityprompt(trainSeat:FindFirstChild("ProximityPrompt"), 1, humanoid)
                    fireproximityprompt(trainSeat:FindFirstChild("ProximityPrompt"), 0, humanoid)
                end
                ReplicatedStorage.CharacterEvents.RagdollRemote:FireServer(humanoidRootPart, 0)
            end
        end
    end
end

ITab:AddToggle({
    Name = "Auto Gucci",
    Default = false,
    Callback = function(Value)
        antiGucciEnabled = Value
        
        if Value then
            if not player:GetAttribute("AntiGucciActive") then
                player:SetAttribute("AntiGucciActive", true)
            end
            
            antiGucciConnection = RunService.Heartbeat:Connect(executeAntiGucci)
            
        else
            if antiGucciConnection then
                antiGucciConnection:Disconnect()
                antiGucciConnection = nil
            end
            
            if seatWeldConnection then
                seatWeldConnection:Disconnect()
                seatWeldConnection = nil
            end
            
            if player:GetAttribute("AntiGucciActive") then
                player:SetAttribute("AntiGucciActive", false)
                resetPlayer()
            end
        end
    end
})

state = nil

ITab:AddToggle({
    Name = "Auto Gucci V2 <font color='#ffaa00'>「Lobotomy」</font>",
    Default = false,
    Callback = function(Value)
        local ok, err = pcall(function()
             Players = game:GetService("Players")
             ReplicatedStorage = game:GetService("ReplicatedStorage")
             LocalPlayer = Players.LocalPlayer
             RunService = game:GetService("RunService")

            local function storeConnection(conn)
                if not state then
                    if conn and conn.Disconnect then
                        pcall(function() conn:Disconnect() end)
                    end
                    return
                end
                state.connections = state.connections or {}
                table.insert(state.connections, conn)
            end

            local function clearConnections()
                if not state or not state.connections then return end
                for _, c in ipairs(state.connections) do
                    pcall(function()
                        if c and c.Disconnect then c:Disconnect() end
                    end)
                end
                state.connections = {}
            end

            if Value then
                local plr = LocalPlayer
                if plr.Character and plr.Character:GetAttribute("AntiGucci") then return end

                state = {
                    autoGucci      = { active = true, destroy = true },
                    sitJump        = { active = false, loopDebounce = false },
                    blobmanInstance= nil,
                    plotBlobman    = nil,
                    currentPlot    = nil,
                    currentRetries = 0,
                    maxRetries     = 3,
                    retryDelay     = 1.5,
                    lastExecutionTime = 0,
                    isRetrying     = false,
                    ragdollPingActive = false,
                    connections    = {},
                }

                local function getCurrentToyFolder()
                    local ok2, folder, plot = pcall(function()
                        local inPlot = LocalPlayer:FindFirstChild("InPlot")
                        if inPlot and inPlot:IsA("BoolValue") and inPlot.Value then
                            local plots = workspace:FindFirstChild("Plots")
                            if plots then
                                for i = 1,5 do
                                    local plot2 = plots["Plot"..i]
                                    if plot2 and plot2:FindFirstChild("PlotSign") then
                                        for _, name in ipairs({"ThisPlotsOwners","ThisPlotsOwner","ThisPlotOwners"}) do
                                            local container = plot2.PlotSign:FindFirstChild(name)
                                            local val = container
                                            if container and container:IsA("Folder") then
                                                val = container:FindFirstChildOfClass("StringValue")
                                                      or container:FindFirstChild("Value")
                                                      or container:FindFirstChild("Owner")
                                            end
                                            if val and val:IsA("StringValue") then
                                                local tries = 0
                                                while val.Value == "" and inPlot.Value and tries < 50 do
                                                    task.wait(0.1)
                                                    tries += 1
                                                end
                                                if not inPlot.Value then break end
                                                if val.Value == LocalPlayer.Name then
                                                    local items = workspace:FindFirstChild("PlotItems")
                                                    if items and items["Plot"..i] then
                                                        state.currentPlot = plot2
                                                        return items["Plot"..i], plot2
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        state.currentPlot = nil
                        return workspace:FindFirstChild(plr.Name.."SpawnedInToys"), nil
                    end)
                    if ok2 then
                        return folder, plot
                    else
                        return nil, nil
                    end
                end

                local function destroyBlobman()
                    pcall(function()
                        if state == nil then return end
                        if state.blobmanInstance == state.plotBlobman and state.currentPlot then return end
                        if state.blobmanInstance and state.autoGucci.destroy then
                            local rem = ReplicatedStorage:FindFirstChild("MenuToys")
                                        and ReplicatedStorage.MenuToys:FindFirstChild("DestroyToy")
                            if rem then
                                pcall(function() rem:FireServer(state.blobmanInstance) end)
                            end
                            if state.blobmanInstance == state.plotBlobman then
                                state.plotBlobman = nil
                            end
                            state.blobmanInstance = nil
                        end
                    end)
                end

                local function getBlobman()
                    local ok2, b = pcall(function()
                        local folder, plot = getCurrentToyFolder()
                        if folder then
                            local b2 = folder:FindFirstChild("CreatureBlobman")
                            if plot and b2 and not state.plotBlobman then
                                state.plotBlobman = b2
                            end
                            return b2
                        end
                        return nil
                    end)
                    if ok2 then return b else return nil end
                end

                local function spawnBlobman(char)
                    pcall(function()
                        if not state or not char or not char:FindFirstChild("HumanoidRootPart") then return end
                        local folder, plot = getCurrentToyFolder()
                        if plot and state.plotBlobman and state.plotBlobman.Parent then
                            state.blobmanInstance = state.plotBlobman
                            return
                        end
                        local hrp = char.HumanoidRootPart
                        local invoke = safeResolvePath(ReplicatedStorage, {"MenuToys", "SpawnToyRemoteFunction"}, 2)
                        if not invoke then return end
                        pcall(function()
                            invoke:InvokeServer("CreatureBlobman", hrp.CFrame * CFrame.new(0,0,-5), Vector3.new(0,-15.716,0))
                        end)
                        task.wait(0.03)
                        state.blobmanInstance = getBlobman()
                        if state and not state.blobmanInstance and state.currentRetries < state.maxRetries then
                            state.currentRetries = (state.currentRetries or 0) + 1
                            task.wait(1)
                            spawnBlobman(char)
                        end
                    end)
                end

                local function addBodyVelocity(seat)
                    pcall(function()
                        if not seat then return end
                        for _, v in ipairs(seat:GetChildren()) do
                            if v:IsA("BodyVelocity") then v:Destroy() end
                        end
                        local bv = Instance.new("BodyVelocity")
                        bv.Velocity = Vector3.new(0,99999,0)
                        bv.MaxForce = Vector3.new(0,math.huge,0)
                        bv.P = 15000
                        bv.Parent = seat
                    end)
                end

                local function checkAntiGucci(char)
                    pcall(function()
                        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
                        local evt = ReplicatedStorage:FindFirstChild("CharacterEvents")
                        if evt then
                            evt = evt:FindFirstChild("RagdollRemote")
                        end
                        if evt then
                            pcall(function()
                                evt:FireServer(char.HumanoidRootPart, 1)
                            end)
                        end
                    end)
                end

                local function startContinuousRagdollPing(char)
                    if not state then return end
                    if state.ragdollPingActive then return end
                    state.ragdollPingActive = true
                    task.spawn(function()
                        while state and state.autoGucci and state.autoGucci.active and state.ragdollPingActive do
                            pcall(function()
                                if not char or not char.Parent then return end
                                local hrp = char:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local evt = ReplicatedStorage:FindFirstChild("CharacterEvents")
                                    if evt then
                                        evt = evt:FindFirstChild("RagdollRemote")
                                    end
                                    if evt then
                                        pcall(function() evt:FireServer(hrp, 0) end)
                                    end
                                end
                            end)
                            local delay = 0.03
                            if char and char:GetAttribute("AntiGucci") then
                                delay = 0.5
                            end
                            task.wait(delay)
                        end
                        if state then state.ragdollPingActive = false end
                    end)
                end

                local function stopContinuousRagdollPing()
                    if state then
                        state.ragdollPingActive = false
                    end
                end

                local function startRagdollMonitor(char)
                    pcall(function()
                        if not char then return end
                        local hum = char:WaitForChild("Humanoid")
                        local rag = hum:WaitForChild("Ragdolled")
                        if not rag or not rag:IsA("BoolValue") then return end

                        local conn
                        conn = rag.Changed:Connect(function()
                            pcall(function()
                                if not state then
                                    if conn then conn:Disconnect() end
                                    return
                                end
                                if not char or not char.Parent then if conn then conn:Disconnect() end return end
                                if state.isRetrying then return end

                                char:SetAttribute("AntiGucci", not rag.Value)
                                state.lastExecutionTime = tick()

                                if char:GetAttribute("AntiGucci") and state.blobmanInstance then
                                    local seat = state.blobmanInstance:FindFirstChildWhichIsA("VehicleSeat")
                                    if seat then
                                        task.delay(2, function()
                                            addBodyVelocity(seat)
                                        end)
                                    end
                                    task.spawn(function()
                                        while state and state.blobmanInstance and char:GetAttribute("AntiGucci") do
                                            checkAntiGucci(char)
                                            task.wait(0.5)
                                        end
                                    end)
                                elseif not char:GetAttribute("AntiGucci") and state and not state.isRetrying then
                                    state.isRetrying = true
                                    if state.blobmanInstance ~= state.plotBlobman then
                                        destroyBlobman()
                                        task.wait(state.retryDelay)
                                        executeSequence(char)
                                    else
                                        executeSequence(char)
                                    end
                                    task.wait(0.1)
                                    if state then state.isRetrying = false end
                                end
                            end)
                        end)

                        storeConnection(conn)
                        char:SetAttribute("AntiGucci", not rag.Value)
                    end)
                end

                local function sitJump(char)
                    pcall(function()
                        if not state or not char then return end
                        local hum = char:FindFirstChild("Humanoid")
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if not hum or not hrp then return end
                        if state and state.blobmanInstance then
                            local seat = state.blobmanInstance:FindFirstChildWhichIsA("VehicleSeat")
                            if seat and seat.Occupant ~= hum then
                                pcall(function()
                                    if firetouchinterest then
                                        pcall(function()
                                            firetouchinterest(hrp, seat, 0)
                                            task.wait()
                                            firetouchinterest(hrp, seat, 1)
                                        end)
                                    end
                                    task.wait()
                                    seat:Sit(hum)
                                    task.delay(2, function()
                                        addBodyVelocity(seat)
                                        hum.Jump = true
                                    end)
                                end)
                            end
                        end
                        task.wait()
                        pcall(function()
                            hum:ChangeState(Enum.HumanoidStateType.Jumping)
                            checkAntiGucci(char)
                        end)
                    end)
                end

                local function ragdollLoop(char)
                    if not state then return end
                    if state.sitJump.loopDebounce then return end
                    state.sitJump.loopDebounce = true
                    while state and state.sitJump.active do
                        pcall(function()
                            local evt = ReplicatedStorage:FindFirstChild("CharacterEvents")
                            if evt then evt = evt:FindFirstChild("RagdollRemote") end
                            if evt and char and char:FindFirstChild("HumanoidRootPart") then
                                evt:FireServer(char.HumanoidRootPart, 0)
                            end
                        end)
                        task.wait()
                    end
                    state.sitJump.loopDebounce = false
                end

                function executeSequence(char)
                    pcall(function()
                        if not state or not state.autoGucci or not state.autoGucci.active or not char then return end
                        state.sitJump.active = false
                        task.wait(0.03)
                        if state.blobmanInstance ~= state.plotBlobman then
                            destroyBlobman()
                            task.wait(0.03)
                        end
                        state.lastExecutionTime = tick()
                        state.currentRetries = 0
                        spawnBlobman(char)
                        task.wait(0.03)
                        state.sitJump.active = true
                        task.spawn(function() sitJump(char) end)
                        task.spawn(function() ragdollLoop(char) end)
                        startContinuousRagdollPing(char)
                        startRagdollMonitor(char)
                    end)
                end

                local function autoReset()
                    pcall(function()
                        if not state then return end
                        local char = LocalPlayer.Character
                        if not char or not char:FindFirstChild("Humanoid") then return end
                        local hum = char:FindFirstChild("Humanoid")
                        local rag = hum:FindFirstChild("Ragdolled")
                        if not rag or not rag:IsA("BoolValue") then return end
                        if rag.Value == true and not state.isRetrying and tick() - (state.lastExecutionTime or 0) > 1.5 then
                            state.lastExecutionTime = tick()
                            state.currentRetries = 0
                            state.isRetrying = false
                            state.sitJump.active = false
                            state.sitJump.loopDebounce = false
                            if state.blobmanInstance and state.blobmanInstance ~= state.plotBlobman then
                                destroyBlobman()
                            end
                            pcall(function() hum.Health = 1e6 end)
                            task.wait(3)
                            executeSequence(char)
                        end
                    end)
                end

                local function fireGrabbingEvent()
                    pcall(function()
                        local char = plr.Character or plr.CharacterAdded:Wait()
                        local scriptObj = char:FindFirstChild("GrabbingScript")
                        if scriptObj then
                            local evt = scriptObj:FindFirstChild("ToggleMobileButtonVisibility")
                            if evt then pcall(function() evt:Fire() end) end
                        end
                    end)
                end

                local function removeBlobmanGuis()
                    pcall(function()
                        if not plr or not plr.PlayerGui then return end
                        for _, gui in ipairs(plr.PlayerGui:GetChildren()) do
                            if gui.Name and type(gui.Name) == "string" and gui.Name:lower():find("blobman") then
                                pcall(function()
                                    if gui and gui.Parent then gui:Destroy() end
                                    fireGrabbingEvent()
                                end)
                            end
                        end
                    end)
                end

                storeConnection(plr.PlayerGui.ChildAdded:Connect(function(gui)
                    if not state then return end
                    if gui and gui.Name and type(gui.Name) == "string" and gui.Name:lower():find("blobman") then
                        task.wait()
                        pcall(function()
                            if gui and gui.Parent then
                                gui:Destroy()
                                fireGrabbingEvent()
                            end
                        end)
                    end
                end))

                storeConnection(plr.CharacterAdded:Connect(function(char)
                    if not state then return end
                    state.isRetrying = false
                    state.currentRetries = 0
                    task.wait(0.1)
                    executeSequence(char)
                end))

                if LocalPlayer:FindFirstChild("InPlot") then
                    storeConnection(LocalPlayer.InPlot.Changed:Connect(function(inPlot)
                        pcall(function()
                            if not inPlot and state and state.plotBlobman then
                                if state.plotBlobman.Parent then
                                    local rem = ReplicatedStorage:FindFirstChild("MenuToys")
                                                and ReplicatedStorage.MenuToys:FindFirstChild("DestroyToy")
                                    if rem then rem:FireServer(state.plotBlobman) end
                                end
                                state.plotBlobman = nil
                                state.currentPlot = nil
                            end
                        end)
                    end))
                end

                executeSequence(plr.Character)
                removeBlobmanGuis()
                task.spawn(function()
                    while state and state.autoGucci and state.autoGucci.active do
                        task.wait(1)
                        removeBlobmanGuis()
                        autoReset()
                    end
                end)

            else
                if state then
                    state.autoGucci.active = false
                    state.sitJump.active = false
                    state.ragdollPingActive = false

                    pcall(function()
                        if state.plotBlobman and state.plotBlobman.Parent then
                            local rem = ReplicatedStorage:FindFirstChild("MenuToys")
                            if rem then
                                rem = rem:FindFirstChild("DestroyToy")
                            end
                            if rem then
                                rem:FireServer(state.plotBlobman)
                            end
                        end

                        if state.blobmanInstance and state.blobmanInstance ~= state.plotBlobman then
                            local rem2 = ReplicatedStorage:FindFirstChild("MenuToys")
                            if rem2 then
                                rem2 = rem2:FindFirstChild("DestroyToy")
                            end
                            if rem2 then
                                rem2:FireServer(state.blobmanInstance)
                            end
                        end
                    end)

                    clearConnections()
                    pcall(function()
                        local char = LocalPlayer and LocalPlayer.Character
                        if char then
                            local hum = char:FindFirstChild("Humanoid")
                            if hum then hum.Health = 0 end
                        end
                    end)

                    state = nil
                end
            end
        end)

        if not ok then
            warn("callback error:", err)
        end
    end
})

---------------------------------------------------------------------------------
W = game:GetService("Workspace")
Lighting = game:GetService("Lighting")
Tween = game:GetService("TweenService")
uis = game:GetService("UserInputService")
RS = game:GetService("ReplicatedStorage")
RF = game:GetService("ReplicatedFirst")
CAS = game:GetService("ContextActionService")
R = game:GetService("RunService")
VU = game:GetService("VirtualUser")
SoundService = game:GetService("SoundService")
HttpService = game:GetService("HttpService")
PS = game:GetService("Players")
CE = safeWaitForChild(RS, "CharacterEvents", BOOT_WAIT_TIMEOUT)

local MenuToysFolder = safeWaitForChild(RS, "MenuToys", BOOT_WAIT_TIMEOUT)
SpawnToyRF = MenuToysFolder and (MenuToysFolder:FindFirstChild("SpawnToyRemoteFunction") or safeWaitForChild(MenuToysFolder, "SpawnToyRemoteFunction", BOOT_WAIT_TIMEOUT))
DeleteToyRE = MenuToysFolder and (MenuToysFolder:FindFirstChild("DestroyToy") or safeWaitForChild(MenuToysFolder, "DestroyToy", BOOT_WAIT_TIMEOUT))
RagdollRemote = CE and (CE:FindFirstChild("RagdollRemote") or safeWaitForChild(CE, "RagdollRemote", BOOT_WAIT_TIMEOUT))

Player = PS.LocalPlayer

PlayerToysFolder = safeGetPlayerToyFolder(Player, BOOT_WAIT_TIMEOUT)

local function refreshPlayerToysFolder(timeout)
	PlayerToysFolder = safeGetPlayerToyFolder(Player, timeout or 0)
	return PlayerToysFolder
end

function GetPlayerCharacter()
	if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") and Player.Character:FindFirstChildOfClass("Humanoid") then
		return Player.Character
	end
end

function GetPlayerCFrame()
	return _G.UniversalPlayerRoot and _G.UniversalPlayerRoot.CFrame or nil
end

_G.TP_Priority = -math.huge
cooldownThread = nil
clone_cooldownThread = nil
teleporting = false

function TeleportPlayer(cframe, p, returnPos, cooldownTime, stopVelocity)
	p = tonumber(p) or 0
	cooldownTime = tonumber(cooldownTime) or 0.5

	if stopVelocity == nil then
		stopVelocity = true
	end

	if teleporting and p < _G.TP_Priority then
		return
	end

	if cooldownThread then
		task.cancel(cooldownThread)
		cooldownThread = nil
	end

	teleporting = true
	_G.TP_Priority = p

	local char = GetPlayerCharacter()
	local humanoid, hrp;
	
	if char and typeof(cframe) == "CFrame" then
		hrp = char["HumanoidRootPart"]
		humanoid = char:FindFirstChildOfClass("Humanoid")

		hrp.CFrame = hrp.CFrame.Rotation + cframe.Position

		if not (humanoid.SeatPart ~= nil and tostring(humanoid.SeatPart.Parent) == "CreatureBlobman") then
			humanoid.Sit = false
		end

		if _G.IsCharacterInRagdoll then
			for i, part in pairs(char:GetChildren()) do
				if part.Name == "Head" or part.Name == "Right Arm" or part.Name == "Left Arm" or part.Name == "Left Leg" or part.Name == "Right Leg" or part.Name == "Torso" then
					part.CFrame = hrp.CFrame
				end
			end
		end

		if stopVelocity then
			hrp.Velocity = Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z)
		end

		cooldownThread = task.spawn(function()
			task.wait(2)
			_G.TP_Priority = -math.huge
			teleporting = false
			cooldownThread = nil
		end)
	end
end


function reconnect()
	local Character = Player.Character or Player.CharacterAdded:Wait()
	local Humanoid = Character:FindFirstChildWhichIsA("Humanoid") or Character:WaitForChild("Humanoid")
	local Animator;
	local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
	local Head = Character:WaitForChild("Head")
	local Torso = Character:WaitForChild("Torso")
	_G.IsCharacterInRagdoll = false
	GucciAttempts = 0

	_G.PianoAttachment = Attachment_Piano
	_G.UniversalPlayerRoot = HumanoidRootPart
	_G.UniversalPlayerHead = Head
	_G.UniversalPlayerHumanoid = Humanoid
	_G.UniverChar = Character
	_G.Torso = Torso
	local RagdollValue = Humanoid:WaitForChild("Ragdolled")

	RagdollValue.Changed:Connect(function(v)
		_G.IsCharacterInRagdoll = v
		GucciAttempts = 0
      _G.IsGodModeOn = false
	end)

	Humanoid.Died:Connect(function() -- Line 392
		_G.IsGodModeOn = false
		if DeleteToyRE and blobmanInstanceS then
			DeleteToyRE:FireServer(blobmanInstanceS)
		end
	end)
end

ragdollLoopF_thread = nil

function ragdollLoopF()
	local char = Player.Character
	local hrp = char:WaitForChild("HumanoidRootPart")
	local hum = char:WaitForChild("Humanoid")

	while true do
		if char and hrp and not _G.IsGucciEnabled and RagdollRemote then
			local args={[1] = _G.UniversalPlayerRoot, [2] = 0}
			RagdollRemote:FireServer(unpack(args))
			--print("Ragdoll")
		end

		task.wait()
	end
end

task.spawn(function() 
	reconnect()
end)

Player.CharacterAdded:Connect(reconnect)

local function removeBlobmanScript()
	local CreatureLocalScript = Player.Character:FindFirstChild("LocalCreatureControl")

	if CreatureLocalScript then
		local BlobmanGUI = CreatureLocalScript:FindFirstChild("BlobmanGui")

		if BlobmanGUI then
			BlobmanGUI:Destroy()
		end

		local ToggleMobileButtonVisibility = CreatureLocalScript.Parent["GrabbingScript"]["ToggleMobileButtonVisibility"]
		local ToggleControlsGuiVisibility = Player["PlayerGui"]["ControlsGui"]["ToggleControlsGuiVisibility"]

		CAS:UnbindAction("LeftGrab")
		CAS:UnbindAction("RightGrab")
		ToggleMobileButtonVisibility:Fire(true)
		ToggleControlsGuiVisibility:Fire(true)

		CreatureLocalScript:Destroy()
	end
end

blobmanInstanceS = nil

function spawnBlobmanF()
	PlayerToysFolder = PlayerToysFolder or refreshPlayerToysFolder(2)
	if not PlayerToysFolder or not SpawnToyRF or not _G.UniversalPlayerHead then return end

	local blobman = PlayerToysFolder:FindFirstChild("CreatureBlobman")
	
	if not blobman then
		local args = {
			[1] = "CreatureBlobman",
			[2] = CFrame.new(_G.UniversalPlayerHead.Position + Vector3.new(0, 5, 3)),
			[3] = Vector3.new(0, 97.69000244140625, 0)
		}

		SpawnToyRF:InvokeServer(unpack(args))
		task.wait(0.1)
	else
		blobmanInstanceS = blobman
	end
end

GucciAttempts = 0

function GucciV2()
	local hum = _G.UniversalPlayerHumanoid
	local hrp = _G.UniversalPlayerRoot
	local seat = nil
	local blobman = nil
	local oldposition = GetPlayerCFrame()

	local antigrabgucci_toggle = OrionLib.Flags["antigrabgucci_toggle"]

	if antigrabgucci_toggle and not antigrabgucci_toggle.Value then return; end

	if not _G.IsCharacterInRagdoll and hum.Health > 0 then
		_G.LastPosGucciSit = GetPlayerCFrame()

		task.spawn(function() 
			repeat
				removeBlobmanScript()
				task.wait(1)
			until not antigrabgucci_toggle.Value
		end)

		repeat
			PlayerToysFolder = PlayerToysFolder or refreshPlayerToysFolder(0)
			if not PlayerToysFolder then
				task.wait(0.1)
				continue
			end

			blobman = PlayerToysFolder:FindFirstChild("CreatureBlobman")
			blobmanInstanceS = blobman
			hum = _G.UniversalPlayerHumanoid
			hrp = _G.UniversalPlayerRoot

			if blobman and blobman.Parent and blobman:FindFirstChild("VehicleSeat") then
				seat = blobman:FindFirstChildOfClass("VehicleSeat")

				if seat and seat.Occupant ~= hum then
					if not _G.IsCharacterInRagdoll and not _G.IsGucciEnabled and hum.Health > 0 then
						if oldposition == nil then oldposition = GetPlayerCFrame(); end
						seat:Sit(_G.UniversalPlayerHumanoid);
						RagdollRemote:FireServer(_G.UniversalPlayerRoot, 0);
						hum:ChangeState(Enum.HumanoidStateType.Jumping)
						GucciAttempts = GucciAttempts + 1
					end

					wait(0.1)

					if hum.Health > 0 then
						RagdollRemote:FireServer(_G.UniversalPlayerRoot, 0.1)
						local ragdoll = false

						for i = 0, 25 do
							if _G.IsCharacterInRagdoll then
								print("Gucci não feito!")
								_G.IsGucciEnabled = false
								ragdoll = true
								attempts = 0
								wait(0.2)
								break
							end
							wait(0.01)
						end

						if not ragdoll then 
							_G.IsGucciEnabled = true
							--_G.UniversalPlayerRoot.CFrame = oldposition
							for i = 0, 10 do
								TeleportPlayer(oldposition)
								wait(0.02)
							end
							
							oldposition = nil

							if blobman and blobman.Parent and blobman:FindFirstChild("HumanoidRootPart") then
								local b_hrp = blobman["HumanoidRootPart"] 

								if not b_hrp:FindFirstChild("GucciVelocity") then
									local bv = Instance.new("BodyVelocity", b_hrp)
									bv.MaxForce = Vector3.new(1, 1, 1) * math.huge
									bv.Velocity = Vector3.new(0,0,0)
									bv.Name = "GucciVelocity"
								end
								
								blobman:PivotTo(CFrame.new(0, 10000000, 0))
							end
						end
					end
				end
			else
				spawnBlobmanF()
			end

			task.wait()
		until not antigrabgucci_toggle.Value
	end

	task.wait(Player:GetNetworkPing())
end

AntiGrabGucciV2 = nil

ITab:AddToggle({
	Name = "Auto Gucci V3",
	Default = false,
	Callback = function(Value)
		if ragdollLoopF_thread then task.cancel(ragdollLoopF_thread); ragdollLoopF_thread = nil end

		if Value then
			ragdollLoopF_thread = task.spawn(ragdollLoopF)

			task.wait(0.1)

			if not AntiGrabGucciV2 or (typeof(AntiGrabGucciV2) == "thread" and coroutine.status(AntiGrabGucciV2) == "dead") then
				AntiGrabGucciV2 = task.spawn(GucciV2)
			end

			blobmanInstanceS = nil
		else
			if typeof(AntiGrabGucciV2) == "thread" and coroutine.status(AntiGrabGucciV2) ~= "dead" then
				task.cancel(AntiGrabGucciV2)
			end

			if _G.UniversalPlayerHumanoid and _G.IsGucciEnabled then
				_G.UniversalPlayerHumanoid.Sit = true
			end
		end
	end,
	Save = true,
	Flag = "antigrabgucci_toggle"      
})

localPlayer = Players.LocalPlayer

local antiGrabConfig = {
    looptrain = true,
    invisibleAntiGrabEnabled = false,
    invisibleAntiGrabConnection = nil,
    characterAddedConnection = nil
}

_G.executeAntiGrab = function()
    if not antiGrabConfig.invisibleAntiGrabEnabled then return end

    local success, errorMessage = pcall(function()
        local currentCharacter = localPlayer.Character
        if not currentCharacter then return end
        
        local characterHumanoid = currentCharacter:FindFirstChild("Humanoid")
        local humanoidRootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
        
        local trainSeat = safeResolvePath(workspace, {
            "Map",
            "AlwaysHereTweenedObjects",
            "Train",
            "Object",
            "ObjectModel",
            "Seat"
        }, 0)
        local ragdollRemote = safeResolvePath(ReplicatedStorage, {"CharacterEvents", "RagdollRemote"}, 0)
            
        if characterHumanoid and humanoidRootPart and trainSeat and ragdollRemote then
            local proximityPrompt = trainSeat:FindFirstChild("ProximityPrompt")
            trainSeat:Sit(characterHumanoid)
            if proximityPrompt then
                fireproximityprompt(proximityPrompt, 1, characterHumanoid)
                fireproximityprompt(proximityPrompt, 0, characterHumanoid)
            end
            ragdollRemote:FireServer(humanoidRootPart, 0)
        end
    end)
end

_G.resetCharacter = function()
    local success, errorMessage = pcall(function()
        local currentCharacter = localPlayer.Character
        if currentCharacter then
            local characterHumanoid = currentCharacter:FindFirstChild("Humanoid")
            if characterHumanoid then
                characterHumanoid.Health = 0
            end
        end
    end)
end

ITab:AddToggle({
    Name = "Invisible",
    Default = false,
    Callback = function(Value)
        antiGrabConfig.invisibleAntiGrabEnabled = Value
        
        if Value then
            if not localPlayer:GetAttribute("AntiGrabActive") then
                localPlayer:SetAttribute("AntiGrabActive", true)
            end
            
            antiGrabConfig.invisibleAntiGrabConnection = RunService.Heartbeat:Connect(_G.executeAntiGrab)
            
            antiGrabConfig.characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
                if antiGrabConfig.invisibleAntiGrabEnabled then
                    task.wait(1)
                    _G.executeAntiGrab()
                end
            end)
            
        else
            if antiGrabConfig.invisibleAntiGrabConnection then
                antiGrabConfig.invisibleAntiGrabConnection:Disconnect()
                antiGrabConfig.invisibleAntiGrabConnection = nil
            end
            
            if antiGrabConfig.characterAddedConnection then
                antiGrabConfig.characterAddedConnection:Disconnect()
                antiGrabConfig.characterAddedConnection = nil
            end
            
            if localPlayer:GetAttribute("AntiGrabActive") then
                localPlayer:SetAttribute("AntiGrabActive", false)
                _G.resetCharacter()
            end
        end
    end
})

getgenv().Players           = game:GetService("Players")
getgenv().ReplicatedStorage = game:GetService("ReplicatedStorage")
getgenv().RunService        = game:GetService("RunService")
getgenv().Workspace         = game:GetService("Workspace")
getgenv().LOCAL_PLAYER      = getgenv().Players.LocalPlayer

Players = getgenv().Players
ReplicatedStorage = getgenv().ReplicatedStorage
RunService = getgenv().RunService
Workspace = getgenv().Workspace
LocalPlayer = getgenv().LOCAL_PLAYER

getgenv().MODE               = "Normal"
getgenv().state              = { model = nil, seat = nil }
getgenv().blacklist          = {}
getgenv().antiStuckActive    = false
getgenv().antiStuckHB        = nil
getgenv().antiStuckCharAdded = nil
getgenv().antiSnowLoop       = nil
getgenv().autoAttackConnection = nil

function disconnectConnection(conn)
    if conn and conn.Disconnect then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

getgenv().getCurrentToyFolder = function()
    local inPlot = LocalPlayer:FindFirstChild("InPlot")
    if inPlot and inPlot.Value then
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            for i = 1, 5 do
                local p = plots["Plot"..i]
                if p and p:FindFirstChild("PlotSign") then
                    local sign = p.PlotSign

                    for _, name in ipairs({"ThisPlotsOwners","ThisPlotsOwner","ThisPlotOwners"}) do
                        local c = sign:FindFirstChild(name)
                        if c then
                            local owner = (c:IsA("StringValue") and c)
                                          or c:FindFirstChildOfClass("StringValue")
                            if owner and owner.Value == LocalPlayer.Name then
                                return Workspace.PlotItems["Plot"..i], p
                            end
                        end
                    end
                end
            end
        end
    end
    return Workspace:FindFirstChild(LocalPlayer.Name.."SpawnedInToys"), nil
end

getgenv().spawnBlob = function()
    ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer(
        "CreatureBlobman",
        LocalPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(0,0,-5),
        Vector3.new(0,-15.716,0)
    )
end

getgenv().claimBlob = function()
    getgenv().state.model, getgenv().state.seat = nil, nil
    local folder = getgenv().getCurrentToyFolder()

    if folder then
        for _, toy in ipairs(folder:GetChildren()) do
            if toy.Name == "CreatureBlobman" and not getgenv().blacklist[toy] then
                local seat = toy:FindFirstChildWhichIsA("VehicleSeat", true)
                if seat then
                    local occ = seat.Occupant
                    if occ and occ.Parent ~= LocalPlayer.Character then
                        ReplicatedStorage.MenuToys.DestroyToy:FireServer(toy)
                        getgenv().blacklist[toy] = true
                    else
                        getgenv().state.model = toy
                        getgenv().state.seat  = seat
                        return
                    end
                end
            end
        end
    end

    getgenv().spawnBlob()

    task.wait(0.3)
    local folder2 = getgenv().getCurrentToyFolder()
    local newToy = folder2 and folder2:FindFirstChild("CreatureBlobman")
    getgenv().state.model = newToy
    getgenv().state.seat  = newToy and newToy:FindFirstChildWhichIsA("VehicleSeat", true)
end

--------------------------------------------AuraTAB INC---------------------------------------------
local ATab = Window:MakeTab({
    Name = "Aura",
    Icon = "rbxassetid://119272570124806",
    PremiumOnly = false
})


--------------------------------------------AuraTAB end---------------------------------------------
--------------------------------------------GRABTAB INC---------------------------------------------
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character
local Root = Character and (Character:FindFirstChild("HumanoidRootPart") or safeWaitForChild(Character, "HumanoidRootPart", 5))

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    Root = safeWaitForChild(char, "HumanoidRootPart", 5)
end)

local GTab = Window:MakeTab({
    Name = "Grab",
    Icon = "rbxassetid://130473583552143",
    PremiumOnly = false
})

local strength = 400
local SuperStrengthConn = nil

GTab:AddToggle({
    Name = "Super Strength",
    Default = false,
    Callback = function(state)
        if state then
            SuperStrengthConn = Workspace.ChildAdded:Connect(function(child)
                if child.Name ~= "GrabParts" then return end

                local grabPart = child:FindFirstChild("GrabPart")
                local weld = grabPart and grabPart:FindFirstChildOfClass("WeldConstraint")
                if not weld or not weld.Part1 then return end

                local bv = Instance.new("BodyVelocity")
                bv.MaxForce = Vector3.new(0,0,0)
                bv.Velocity = Vector3.zero
                bv.Parent = weld.Part1

                child.AncestryChanged:Connect(function(_, parent)
                    if parent then return end
                    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                        bv.Velocity = Workspace.CurrentCamera.CFrame.LookVector * strength
                        task.delay(1.5, function()
                            if bv then bv:Destroy() end
                        end)
                    else
                        bv:Destroy()
                    end
                end)
            end)
        else
            if SuperStrengthConn then SuperStrengthConn:Disconnect() end
        end
    end
})

GTab:AddSlider({
    Name = "Strength",
    Min = 10,
    Max = 10000,
    Default = strength,
    Callback = function(v)
        strength = v
    end
})

local BreakEnabled = false

local LimbNames = {
    "Left Leg","Right Leg","LeftLowerLeg","RightLowerLeg"
}

local function GetGrabbedPlayer()
    local folder = Workspace:FindFirstChild("GrabParts")
    if not folder then return end

    for _,v in ipairs(folder:GetDescendants()) do
        if v:IsA("WeldConstraint") and v.Part1 then
            local char = v.Part1:FindFirstAncestorOfClass("Model")
            if char and char:FindFirstChildOfClass("Humanoid") then
                return Players:GetPlayerFromCharacter(char)
            end
        end
    end
end

local function BreakLimbs(plr)
    if not plr then return end
    local char = plr.Character
    if not char then return end

    for _,name in ipairs(LimbNames) do
        local limb = char:FindFirstChild(name)
        if limb then
            limb:BreakJoints()
            limb.CFrame = CFrame.new(0, Workspace.FallenPartsDestroyHeight - 500, 0)
        end
    end
end

UserInputService.InputBegan:Connect(function(input,gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F and BreakEnabled then
        BreakLimbs(GetGrabbedPlayer())
    end
end)

GTab:AddToggle({
    Name = "Break Limb (F)",
    Default = false,
    Callback = function(v)
        BreakEnabled = v
    end
})

local RG_enabled = false
local RG_current = nil
local RG_folder = safeGetPlayerToyFolder(LocalPlayer, BOOT_WAIT_TIMEOUT)

local function refreshRGFolder(timeout)
    RG_folder = safeGetPlayerToyFolder(LocalPlayer, timeout or 0)
    return RG_folder
end

local function SpawnPallet()
    if not Root then return end
    ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer(
        "PalletLightBrown",
        Root.CFrame * CFrame.new(4,0,4),
        Vector3.new(0,30,0)
    )
end

local function HandlePallet(p)
    if RG_current then return end
    local part = safeWaitForChild(p, "SoundPart", 3)
    if not part then return end

    ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(part, part.CFrame)

    local conn
    conn = RunService.Heartbeat:Connect(function()
        local owner = part:FindFirstChild("PartOwner")
        if owner and owner.Value == LocalPlayer.Name then
            RG_current = p
            for _,v in ipairs(p:GetDescendants()) do
                if v:IsA("BasePart") then
                    local bv = Instance.new("BodyVelocity")
                    bv.MaxForce = Vector3.new(1e5,1e5,1e5)
                    bv.Velocity = Vector3.new(0,150,0)
                    bv.Parent = v
                    v.CanCollide = false
                    v.Transparency = 1
                end
            end
            conn:Disconnect()
        end
    end)
end

local function Follow(plr)
    task.spawn(function()
        while RG_enabled and RG_current and plr.Character do
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                for _,v in ipairs(RG_current:GetDescendants()) do
                    if v:IsA("BasePart") then
                        v.CFrame = hrp.CFrame
                    end
                end
            end
            task.wait()
        end
    end)
end

local function MonitorGrab(obj)
    task.spawn(function()
        while obj.Parent and RG_enabled do
            local grab = obj:FindFirstChild("GrabPart")
            local weld = grab and grab:FindFirstChildOfClass("WeldConstraint")
            if weld and weld.Part1 then
                for _,p in ipairs(Players:GetPlayers()) do
                    if p.Character and weld.Part1:IsDescendantOf(p.Character) then
                        Follow(p)
                    end
                end
            end
            task.wait(0.1)
        end
    end)
end

GTab:AddToggle({
    Name = "Ragdoll Grab",
    Default = false,
    Callback = function(v)
        RG_enabled = v
        if not v then
            RG_current = nil
            return
        end

        RG_folder = RG_folder or refreshRGFolder(2)
        if not RG_folder then
            return
        end

        RG_folder.ChildAdded:Connect(function(c)
            if c.Name == "PalletLightBrown" then
                HandlePallet(c)
            end
        end)

        Workspace.ChildAdded:Connect(function(c)
            if c.Name == "GrabParts" then
                MonitorGrab(c)
            end
        end)

        RunService.Heartbeat:Connect(function()
            if not RG_enabled then return end
            if not RG_current then
                SpawnPallet()
            end
        end)
    end
})

local MasslessConn = nil

GTab:AddToggle({
    Name = "Massless Grab",
    Default = false,
    Callback = function(v)
        if v then
            MasslessConn = Workspace.ChildAdded:Connect(function(child)
                if child.Name == "GrabParts" then
                    local drag = child:FindFirstChild("DragPart")
                    if drag then
                        drag.AlignPosition.MaxForce = math.huge
                        drag.AlignOrientation.MaxTorque = math.huge
                    end
                end
            end)
        else
            if MasslessConn then MasslessConn:Disconnect() end
        end
    end
})
---------------------------------------GRABTAB end---------------------------------------------
--------------------------------------------KeybindTAB INC---------------------------------------------
local KTab = Window:MakeTab({
    Name = "Keybinds",
    Icon = "rbxassetid://11710306232",
    PremiumOnly = false
})


KTab:AddBind({
    Name = "Teleport (Z)",
    Default = Enum.KeyCode.Z,
    Hold = false,
    Callback = function()
        local camera = Workspace.CurrentCamera
        local rayOrigin = camera.CFrame.Position
        local rayDirection = camera.CFrame.LookVector * 1000
        local ray = Ray.new(rayOrigin, rayDirection)
        
        local hit, position = Workspace:FindPartOnRay(ray, LocalPlayer.Character)
        if hit then
            local cframe = CFrame.new(position)
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = cframe + Vector3.new(0, 5, 0)
                LocalPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                LocalPlayer.Character.HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end
})

KTab:AddToggle({
    Title = "Bringplayer (G)",
    Default = false,
    Callback = function(state)

        local Players = game:GetService("Players")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local UserInputService = game:GetService("UserInputService")

        local localPlayer = Players.LocalPlayer
        local mouse = localPlayer:GetMouse()

        local targetPlayer = nil
        local grabEnabled = state

        local GrabEvents = ReplicatedStorage:WaitForChild("GrabEvents")
        local SetNetworkOwner = GrabEvents:WaitForChild("SetNetworkOwner")
        local DestroyGrabLine = GrabEvents:WaitForChild("DestroyGrabLine")

        local function updateTarget()
            local target = mouse.Target
            if target and target.Parent then
                local character = target.Parent
                local player = Players:GetPlayerFromCharacter(character)
                if player and player ~= localPlayer then
                    targetPlayer = player
                    return
                end
            end
            targetPlayer = nil
        end

        mouse.Move:Connect(updateTarget)

        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if not grabEnabled then return end

            if input.KeyCode == Enum.KeyCode.G and targetPlayer then
                local character = localPlayer.Character
                if not character then return end

                local hrp = character:FindFirstChild("HumanoidRootPart")
                if not hrp then return end

                local targetChar = targetPlayer.Character
                if not targetChar then return end

                local targetTorso = targetChar:FindFirstChild("Torso") or targetChar:FindFirstChild("UpperTorso")
                if not targetTorso then return end

                local lastPosition = hrp.CFrame

                hrp.CFrame = targetTorso.CFrame + Vector3.new(0,3,0)

                for i = 1,3 do
                    SetNetworkOwner:FireServer(targetTorso, targetTorso.CFrame)
                    task.wait(0.1)
                end

                targetTorso.CFrame = lastPosition
                hrp.CFrame = lastPosition

                task.wait(0.1)
                DestroyGrabLine:FireServer(targetTorso, targetTorso.CFrame)
            end
        end)

    end
})

--------------------------------------------KeybindTAB END---------------------------------------------
--------------------------------------------LoopTAB INC---------------------------------------------

local LoopTab = Window:MakeTab({
    Name = "Loops",
    Icon = "rbxassetid://81412724248693",
    PremiumOnly = false
})

Players = game:GetService("Players")
ReplicatedStorage = game:GetService("ReplicatedStorage")
RunService = game:GetService("RunService")
Workspace = game:GetService("Workspace")
bypassAntiKickEnabled = false

TargetDropdown = LoopTab:AddPlayersDropdown({
    Name = "Target",
    MultipleSelection = true,
    Callback = function(TargetSelected)
        TargetChutar = {}
        for _, playerName in pairs(TargetSelected) do
            player = Players:FindFirstChild(playerName)
            if player then
                table.insert(TargetChutar, player)
            end
        end
    end
})

w = Workspace
LocalPlayer = Players.LocalPlayer
me = LocalPlayer

Cons = {}
PCLDFlag = true
PCLDActive = true
PCLDTrans = 1
PCLDColor = Color3.new(1, 0, 0)

function FWC(Parent, Name, Time)
    return Parent:FindFirstChild(Name) or Parent:WaitForChild(Name, Time)
end

Cons["PCLDChild"] = w.ChildAdded:Connect(function(part)
    if part.Name == "PlayerCharacterLocationDetector" and PCLDFlag then
        if not PCLDActive then
            part.Transparency = 0
        else
            part.Transparency = PCLDTrans
            part.Color = PCLDColor
        end
    end
end)

task.spawn(function()
    while PCLDFlag and task.wait() do
        for _, prt in pairs(w:GetChildren()) do
            if prt.Name == "PlayerCharacterLocationDetector" then
                if PCLDActive then
                    prt.Transparency = PCLDTrans
                    prt.Color = PCLDColor
                else
                    prt.Transparency = 1
                end
            end
        end
        
        local char = me.Character
        if char then
            local torso = FWC(char, "Torso", 3)
            if torso then
                for _, prt in pairs(w:GetChildren()) do
                    if prt.Name == "PlayerCharacterLocationDetector" and (prt.Position - torso.Position + Vector3.new(0, 0.51, 0)).Magnitude < 0.5 then 
                        prt.Name = "MyPCLD"
                        prt.Transparency = 1
                    end
                end
            end
        end
    end
end)

getgenv().isnetworkowner = function(part)
    if part.AssemblyRootPart.ReceiveAge == 0 and not part.Anchored then
        return true
    else
        return false
    end
end

local PlotStatus = {}

function isPlayerInTarget(player)
    if typeof(player) == "Instance" and player:IsA("Player") and player:IsDescendantOf(game) then
        for _, target in ipairs(TargetChutar or {}) do
            if target == player then
                return true
            end
        end
    end
    return false
end

function sno(part)
    pcall(function()
        ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(part, part.CFrame)
    end)
end

function blob_kick(blob, hrp, rl, v)
    local detec = FWC(blob, rl.."Detector", 2)
    if detec then
        local grab = blob.BlobmanSeatAndOwnerScript.CreatureGrab
        local drop = blob.BlobmanSeatAndOwnerScript.CreatureDrop
        local rel = blob.BlobmanSeatAndOwnerScript.CreatureRelease
        if v == "Default" and detec then
            grab:FireServer(detec, hrp, detec[rl.."Weld"])
        elseif v == "DDrop" then
            drop:FireServer(detec[rl.."Weld"])
        elseif v == "Release" then
            rel:FireServer(detec[rl.."Weld"], hrp)
        end
    end
end

function findClosestPCLD(localCharacter)
    local LocalHead = localCharacter:FindFirstChild("Head")
    if not LocalHead then return nil end
    
    local closestDistance = 30
    local closestPCLD = nil
    
    for _, Child in pairs(Workspace:GetChildren()) do
        if Child:IsA("BasePart") and Child.Name == "PlayerCharacterLocationDetector" then
            if Child.Name == "MyPCLD" then 
                continue
            end
            
            local Distance = (LocalHead.Position - Child.Position).Magnitude
            if Distance <= 20 and Child.Position.Y > LocalHead.Position.Y and Distance < closestDistance then
                closestDistance = Distance
                closestPCLD = Child
            end
        end
    end
    
    return closestPCLD
end

kickLoopEnabled = false
activeBodyPositions = {}

ToggleUnified = LoopTab:AddToggle({
    Name = "Loop Kick Grab + Blob",
    Default = false,
    Save = true,
    Flag = "UnifiedKickToggle",
    Callback = function(Value)
        kickLoopEnabled = Value
        
        if kickLoopEnabled then
            task.spawn(function()
                print("Unified kick loop started")
                
                while kickLoopEnabled and RunService.Heartbeat:Wait() do
                    local char = LocalPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local head = char and char:FindFirstChild("Head")
                    local myhum = char and char:FindFirstChild("Humanoid")
                    
                    if not (char and hrp and head and myhum) then 
                        task.wait(0)
                        continue 
                    end
                    
                    local MyBlob = nil
                    if myhum.SeatPart then 
                        MyBlob = myhum.SeatPart.Parent 
                    end
                    
                    local currentPCLD = findClosestPCLD(char)

                    for _, targetplr in ipairs(Players:GetPlayers()) do
                        if not kickLoopEnabled then break end
                        
                        if targetplr ~= LocalPlayer and isPlayerInTarget(targetplr) then
                            if not targetplr.Character then 
                                continue 
                            end
                            
                            if typeof(targetplr) == "Instance" and targetplr:IsA("Player") and targetplr:IsDescendantOf(game) then
                                local InPlot = FWC(targetplr, "InPlot", 5)
                                if InPlot and InPlot.Value == true then
                                    if not PlotStatus[targetplr.UserId] then
                                        PlotStatus[targetplr.UserId] = true
                                        OrionLib:MakeNotification({
                                            Name = "InPlot",
                                            Content = "Target in inPlot",
                                            Image = "rbxassetid://4483345998",
                                            Time = 2
                                        })
                                    end
                                    continue
                                else
                                    if PlotStatus[targetplr.UserId] then
                                        PlotStatus[targetplr.UserId] = false
                                        OrionLib:MakeNotification({
                                            Name = "InPlot",
                                            Content = "Target left inPlot",
                                            Image = "rbxassetid://4483345998",
                                            Time = 2
                                        })
                                    end
                                end
                            end
                            
                            local Head = targetplr.Character:FindFirstChild("Head")
                            local Torso = targetplr.Character:FindFirstChild("Torso") or targetplr.Character:FindFirstChild("UpperTorso")
                            local HRP = targetplr.Character:FindFirstChild("HumanoidRootPart")
                            local Hum = targetplr.Character:FindFirstChild("Humanoid")
                            
                            if not (Head and Hum and HRP) or Hum.Health == 0 then
                                continue
                            end
                        
                            if currentPCLD and MyBlob and MyBlob.Parent then
                                if (hrp.Position - HRP.Position).Magnitude < 40 then
                                    blob_kick(MyBlob, HRP, "Left", "Default")
                                    blob_kick(MyBlob, HRP, "Right", "Default")
                                    task.wait(0)
                                    blob_kick(MyBlob, HRP, "Left", "DDrop")
                                    blob_kick(MyBlob, HRP, "Right", "DDrop")
                                end
                            else
                                local BodyPos = Torso:FindFirstChild("BodyPosition")
                                
                                if (Torso.Position - hrp.Position).Magnitude <= 30 then
                                    if not BodyPos then
                                        BodyPos = Instance.new("BodyPosition")
                                        BodyPos.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                                        BodyPos.Parent = Torso
                                        BodyPos.P = 45000
                                        BodyPos.D = 900
                                        activeBodyPositions[targetplr.UserId] = BodyPos
                                    end
                                    
                                    sno(Head)
                                    BodyPos.Position = head.Position + Vector3.new(0, 13, 0)
                                    
                                    pcall(function()
                                        ReplicatedStorage.GrabEvents.DestroyGrabLine:FireServer(Head)
                                    end)
                                else
                                    local oldCF = char:GetPivot()

                                    if not Head or not Hum or Hum.Health == 0 then
                                        local newChar = targetplr.CharacterAdded:Wait(0)
                                        Head = newChar:WaitForChild("Head", 2)
                                        Hum = newChar:FindFirstChild("Humanoid")
                                    end
                                    
                                    repeat
                                        if not kickLoopEnabled then break end
                                        
                                        pcall(function()
                                            char:PivotTo(Head.CFrame * CFrame.new(0, 10, 0))
                                        end)
                                        
                                        sno(Head)
                                        task.wait(0)
                                        
                                    until not Head 
                                        or (Head:FindFirstChild("PartOwner") and targetplr:FindFirstChild("IsHeld") and targetplr.IsHeld.Value) 
                                        or not kickLoopEnabled
                                        
                                    if Head and Head:FindFirstChild("PartOwner") then
                                        task.defer(function()
                                            for i = 1, 90 do
                                                if not kickLoopEnabled or not Head.Parent then break end
                                                pcall(function()
                                                    Head.CFrame = oldCF * CFrame.new(0, 15, 0)
                                                end)
                                                task.wait(0)
                                            end
                                        end)
                                    end
                                    
                                    pcall(function()
                                        char:PivotTo(oldCF)
                                    end)
                                end
                            end
                        end
                    end
                    
                    task.wait(0)
                end
    
                print("Unified kick disabled")
                
                for _, targetplr in ipairs(Players:GetPlayers()) do
                    if targetplr.Character then
                        local Head = targetplr.Character:FindFirstChild("Head")
                        local Torso = targetplr.Character:FindFirstChild("Torso") or targetplr.Character:FindFirstChild("UpperTorso")
                        
                        if Head then
                            pcall(function()
                                ReplicatedStorage.GrabEvents.DestroyGrabLine:FireServer(Head)
                            end)
                        end
                        
                        if Torso then
                            local BodyPos = Torso:FindFirstChild("BodyPosition")
                            if BodyPos then
                                BodyPos:Destroy()
                            end
                        end
                    end
                end
                
                for _, bp in pairs(activeBodyPositions) do
                    if bp and bp.Parent then
                        bp:Destroy()
                    end
                end
                activeBodyPositions = {}
                
                print("Cleanup complete")
            end)
        else
            kickLoopEnabled = false
            PlotStatus = {}
            print("Unified kick disabled by user")
        end
    end    
})

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local ToysFolder = safeGetPlayerToyFolder(player, 0)

local function getSnowball()
	ToysFolder = ToysFolder or safeGetPlayerToyFolder(player, 1)
	if not ToysFolder then return end

	for _,v in ipairs(ToysFolder:GetChildren()) do
		if v.Name == "BallSnowball" and not v:FindFirstChild("Used") then
			local tag = Instance.new("BoolValue")
			tag.Name = "Used"
			tag.Parent = v
			return v
		end
	end
end

_G.DestroyGucciActive = false

LoopTab:AddToggle({
    Name = "Destroy Gucci Sit",
    Default = false,
    Callback = function(value)
        _G.DestroyGucciActive = value
        
        if value then
            if not TargetChutar or #TargetChutar == 0 then
                OrionLib:MakeNotification({
                    Name = "Erro",
                    Content = "Selecione pelo menos um alvo no dropdown!",
                    Image = "rbxassetid://4483345998",
                    Time = 3
                })
                _G.DestroyGucciActive = false
                return
            end
            
            task.spawn(function()
                local runService = game:GetService("RunService")
                local startCFrame = nil
                
                while _G.DestroyGucciActive do
                    local character = LocalPlayer.Character
                    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                    local humanoid = character and character:FindFirstChild("Humanoid")
                    
                    if not rootPart or not humanoid then
                        task.wait(1)
                        continue
                    end
                    
                    if not startCFrame then
                        startCFrame = rootPart.CFrame
                    end
                    
                    for _, target in ipairs(TargetChutar) do
                        if not _G.DestroyGucciActive then break end
                        if not target or not target.Parent then continue end
                        
                        local spawnedToysName = target.Name .. "SpawnedInToys"
                        local spawnedToys = Workspace:FindFirstChild(spawnedToysName)
                        
                        if spawnedToys then
                            for _, toy in ipairs(spawnedToys:GetChildren()) do
                                if not _G.DestroyGucciActive then break end
                                
                                if toy.Name == "CreatureBlobman" then
                                    local seat = toy:FindFirstChild("VehicleSeat") or toy:FindFirstChildWhichIsA("VehicleSeat", true)
                                    if seat and humanoid.SeatPart ~= seat then
                                        local connection
                                        connection = runService.Stepped:Connect(function()
                                            if rootPart and seat then
                                                rootPart.CFrame = seat.CFrame
                                                rootPart.Velocity = Vector3.zero
                                                if toy.PrimaryPart then
                                                    toy.PrimaryPart.Velocity = Vector3.zero
                                                    toy.PrimaryPart.RotVelocity = Vector3.zero
                                                end
                                            end
                                        end)
                                        
                                        local startTime = tick()
                                        while tick() - startTime < 1 do
                                            if not _G.DestroyGucciActive then break end
                                            if humanoid.SeatPart == seat then break end
                                            seat:Sit(humanoid)
                                            task.wait()
                                        end
                                        
                                        if connection then
                                            connection:Disconnect()
                                        end
                                        
                                        if humanoid.SeatPart == seat then
                                            task.wait(0.3)
                                            humanoid.Sit = false
                                            humanoid.Jump = true
                                            task.wait(0.05)
                                            rootPart.CFrame = startCFrame
                                            rootPart.Velocity = Vector3.zero
                                            task.wait(0.5)
                                        else
                                            rootPart.CFrame = startCFrame
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    task.wait(1)
                end
            end)
        end
    end
})


getgenv().loopKillEnabled = false
getgenv().currentTargetIndex = 1
getgenv().heartbeatConnection = nil
getgenv().teleportConnection = nil
getgenv().originalFallenHeight = nil
getgenv().loopKillVoidAdjusted = false
getgenv().activeLoopPhysics = {}
getgenv().fallenHeightLoop = false
getgenv().exerting = false
getgenv().nextTargetPlayer = nil
getgenv().TELEPORT_OFFSET = getgenv().TELEPORT_OFFSET or Vector3.new(6, -18.5, 0)
getgenv().TELEPORT_PREDICTION = tonumber(getgenv().TELEPORT_PREDICTION) or 0.135
getgenv().HEIGHT_LIMIT = getgenv().HEIGHT_LIMIT or 100000


do
    local folder = ReplicatedStorage:FindFirstChild("LoopKillBindables")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "LoopKillBindables"
        folder.Parent = ReplicatedStorage
    end

    local under = folder:FindFirstChild("TeleportUnderBindable")
    if not under then
        under = Instance.new("BindableEvent")
        under.Name = "TeleportUnderBindable"
        under.Parent = folder
    end

    local home = folder:FindFirstChild("TeleportHomeBindable")
    if not home then
        home = Instance.new("BindableEvent")
        home.Name = "TeleportHomeBindable"
        home.Parent = folder
    end

    getgenv().TeleportUnderBindable = under
    getgenv().TeleportHomeBindable = home
    getgenv().teleportUnderFiring = false
    getgenv().teleportHomeFiring = false
end


local function initializeAttributes()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char:SetAttribute("OriginalPosition", char.HumanoidRootPart:GetPivot())
        char:SetAttribute("SavingOriginalPos", false)
    end
end

local function saveCurrentPosition()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char:SetAttribute("OriginalPosition", char.HumanoidRootPart:GetPivot())
    end
end

local function getOriginalPosition()
    local char = LocalPlayer.Character
    return char and char:GetAttribute("OriginalPosition") or nil
end

local function isPlayerTooHigh(player)
    local char = player and player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        return char.HumanoidRootPart.Position.Y > (getgenv().HEIGHT_LIMIT or 100000)
    end
    return true
end

local function setCanCollideFalse(character)
    if not character then return end
    for _, v in ipairs(character:GetDescendants()) do
        if v:IsA("BasePart") then
            v.CanCollide = false
        end
    end
end

local function destroyPlayer(character)
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = true
            part.AssemblyLinearVelocity = Vector3.new(0,-5,0)
            part.AssemblyAngularVelocity = Vector3.new(0,-5,0)
            part.Anchored = false

            local bp = Instance.new("BodyPosition")
            bp.MaxForce = Vector3.new(1e7, 1e7, 1e7)
            bp.P = 5000
            bp.Position = Vector3.new(part.Position.X, -5000, part.Position.Z)
            bp.Parent = part

            task.spawn(function()
                while character and character.Parent and part and part.Parent do
                    pcall(function()
                        part.CanCollide = false
                        part.CanTouch = false
                        part.CanQuery = true
                        if bp.Parent then
                            bp.Position = Vector3.new(part.Position.X, -5000, part.Position.Z)
                            Workspace.FallenPartsDestroyHeight = 0/0
                        end
                    end)
                    task.wait(0.1)
                end
                pcall(function() if bp and bp.Parent then bp:Destroy() end end)
            end)
        end
    end
end

local function scheduleTeleportHome()
    if getgenv().teleportConnection then
        pcall(function() getgenv().teleportConnection:Disconnect() end)
        getgenv().teleportConnection = nil
    end

    local originalPos = getOriginalPosition()
    if not originalPos then return end

    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        pcall(function()
            char.HumanoidRootPart:PivotTo(originalPos)
            if getgenv().loopKillVoidAdjusted then
                Workspace.FallenPartsDestroyHeight = getgenv().originalFallenHeight or Workspace.FallenPartsDestroyHeight
                getgenv().loopKillVoidAdjusted = false
            end
            char:SetAttribute("SavingOriginalPos", false)
        end)
    end

    getgenv().teleportHomeFiring = true
    task.spawn(function()
        while getgenv().teleportHomeFiring do
            pcall(function() getgenv().TeleportHomeBindable:Fire(originalPos) end)
            task.wait(0.01)
        end
    end)

    getgenv().teleportConnection = RunService.Heartbeat:Connect(function()
        local char2 = LocalPlayer.Character
        if char2 and char2:FindFirstChild("HumanoidRootPart") then
            char2.HumanoidRootPart:PivotTo(originalPos)
            if getgenv().loopKillVoidAdjusted then
                Workspace.FallenPartsDestroyHeight = getgenv().originalFallenHeight or Workspace.FallenPartsDestroyHeight
                getgenv().loopKillVoidAdjusted = false
            end
            char2:SetAttribute("SavingOriginalPos", false)
        end
        if getgenv().teleportConnection then
            pcall(function() getgenv().teleportConnection:Disconnect() end)
            getgenv().teleportConnection = nil
        end
        getgenv().teleportHomeFiring = false
    end)
end

local function startFallenHeightLoop()
    if getgenv().fallenHeightLoop then return end
    getgenv().fallenHeightLoop = true
    task.spawn(function()
        while getgenv().loopKillEnabled and getgenv().fallenHeightLoop do
            Workspace.FallenPartsDestroyHeight = -500
            task.wait(0.09)
            Workspace.FallenPartsDestroyHeight = 0/0
            task.wait(0.05)
        end
        if not getgenv().loopKillVoidAdjusted then
            Workspace.FallenPartsDestroyHeight = getgenv().originalFallenHeight or Workspace.FallenPartsDestroyHeight
        end
        getgenv().fallenHeightLoop = false
    end)
end

local function stopFallenHeightLoop()
    getgenv().fallenHeightLoop = false
    if not getgenv().loopKillVoidAdjusted then
        Workspace.FallenPartsDestroyHeight = getgenv().originalFallenHeight or Workspace.FallenPartsDestroyHeight
    end
end

local function isValidTarget(player)
    if not player then return false end
    if not isPlayerInTarget(player) then return false end
    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    local head = char:FindFirstChild("Head")
    if not (hrp and hum and head) then return false end
    if not hum.Health or hum.Health <= 0 then return false end
    if hum:GetState() == Enum.HumanoidStateType.Dead then return false end
    if player:FindFirstChild("InPlot") and player.InPlot.Value then return false end
    if isPlayerTooHigh(player) then return false end
    return true
end

local function performKill()
    local added = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isPlayerInTarget(p) then
            added[#added+1] = p
        end
    end
    if #added == 0 then return end

    local forcedTarget = nil
    if getgenv().nextTargetPlayer then
        if isValidTarget(getgenv().nextTargetPlayer) and isPlayerInTarget(getgenv().nextTargetPlayer) then
            forcedTarget = getgenv().nextTargetPlayer
        end
        getgenv().nextTargetPlayer = nil
    end

    local tries, maxTries = 0, #added
    while tries < maxTries do
        if getgenv().currentTargetIndex > #added then
            getgenv().currentTargetIndex = 1
        end
        local cand = added[getgenv().currentTargetIndex]
        if isValidTarget(cand) then break end
        getgenv().currentTargetIndex = getgenv().currentTargetIndex + 1
        tries = tries + 1
    end
    if tries == maxTries and not forcedTarget then return end

    local target = forcedTarget or added[getgenv().currentTargetIndex]
    if not target then
        getgenv().currentTargetIndex = getgenv().currentTargetIndex + 1
        return
    end

    local tChar = target.Character
    if not tChar then
        getgenv().currentTargetIndex = getgenv().currentTargetIndex + 1
        return
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (char and hrp) then
        getgenv().currentTargetIndex = getgenv().currentTargetIndex + 1
        return
    end

    if not char:GetAttribute("SavingOriginalPos") then
        saveCurrentPosition()
    end
    char:SetAttribute("SavingOriginalPos", true)

    getgenv().originalFallenHeight = Workspace.FallenPartsDestroyHeight
    Workspace.FallenPartsDestroyHeight = 0/0
    getgenv().loopKillVoidAdjusted = true

    local attemptCount = 6
    local attemptDelay = 0.01
    local predSeconds = tonumber(getgenv().TELEPORT_PREDICTION) or 0.135

    for i = 1, attemptCount do
        if not isValidTarget(target) then break end
        local currRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not currRoot then break end

        local ok, targetPivot = pcall(function() return currRoot:GetPivot() end)
        if ok and targetPivot then
            local vel = Vector3.new(0,0,0)
            pcall(function() vel = currRoot.AssemblyLinearVelocity or currRoot.Velocity or Vector3.new(0,0,0) end)

            local predictedCFrame = targetPivot * CFrame.new(vel.X * predSeconds, vel.Y * predSeconds, vel.Z * predSeconds)
            local desiredCFrame = predictedCFrame * CFrame.new(getgenv().TELEPORT_OFFSET)

            pcall(function()
                if getgenv().TeleportUnderBindable then
                    getgenv().TeleportUnderBindable:Fire(target, desiredCFrame)
                end
            end)

            pcall(function() hrp:PivotTo(desiredCFrame) end)
        end
        task.wait(attemptDelay)
    end

    tChar = target.Character
    if tChar then setCanCollideFalse(tChar) end

    pcall(function()
        if ReplicatedStorage.GrabEvents and ReplicatedStorage.GrabEvents.SetNetworkOwner then
            local currRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            if currRoot then
                ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(currRoot, currRoot.CFrame)
            end
        end
    end)

    task.wait(0.01)
    pcall(function()
        if ReplicatedStorage.GrabEvents and ReplicatedStorage.GrabEvents.DestroyGrabLine then
            local currRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            if currRoot then
                ReplicatedStorage.GrabEvents.DestroyGrabLine:FireServer(currRoot)
            end
        end
    end)
    task.wait(0.01)

    local tHead = target.Character and target.Character:FindFirstChild("Head")
    local partOwner = tHead and tHead:FindFirstChild("PartOwner")
    if not partOwner and tHead then
        for i = 1, 2 do
            task.wait(0.01)
            partOwner = tHead:FindFirstChild("PartOwner")
            if partOwner then break end
        end
    end

    if partOwner and partOwner.Value == LocalPlayer.Name then
        local tHum = target.Character and target.Character:FindFirstChild("Humanoid")
        if tHum and tHum.Health and tHum.Health > 0 and tHum:GetState() ~= Enum.HumanoidStateType.Dead then
            task.wait(0.01)
            pcall(function() destroyPlayer(tHum.Parent) end)
            task.wait(0.02)
            pcall(function()
                if tHum then
                    tHum.BreakJointsOnDeath = false
                    tHum:ChangeState(Enum.HumanoidStateType.Dead)
                end
            end)
            task.wait(0.1)
            for i = 1, 5 do
                pcall(function() Workspace.FallenPartsDestroyHeight = -500 end)
                task.wait(0.02)
            end
            pcall(function() Workspace.FallenPartsDestroyHeight = 0/0 end)
        end
    end

    scheduleTeleportHome()
    task.wait(0.02)
    getgenv().currentTargetIndex = getgenv().currentTargetIndex + 1
end

LoopTab:AddToggle({
    Name = "Loop Kill (Otimizado)",
    Default = false,
    Callback = function(enabled)
        getgenv().loopKillEnabled = enabled

        if getgenv().heartbeatConnection then
            pcall(function() getgenv().heartbeatConnection:Disconnect() end)
            getgenv().heartbeatConnection = nil
        end
        if getgenv().teleportConnection then
            pcall(function() getgenv().teleportConnection:Disconnect() end)
            getgenv().teleportConnection = nil
        end

        if enabled then
            getgenv().currentTargetIndex = 1
            startFallenHeightLoop()
            getgenv().exerting = true

            getgenv().teleportUnderFiring = true
            task.spawn(function()
                while getgenv().teleportUnderFiring and getgenv().loopKillEnabled do
                    pcall(function() getgenv().TeleportUnderBindable:Fire() end)
                    task.wait(0.01)
                end
            end)

            local baseGround = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("BaseGround")
            local savedParts = {}
            if baseGround then
                for _, part in ipairs(baseGround:GetChildren()) do
                    if part and part:IsA("BasePart") then
                        table.insert(savedParts, { part = part, cf = part.CFrame })
                    end
                end
            end
            getgenv().savedParts = savedParts

            getgenv().heartbeatConnection = RunService.Heartbeat:Connect(function()
                if getgenv().loopKillEnabled then
                    task.spawn(performKill)
                    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if root and root.Position.Y < -500 then
                        pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
                    end
                end
            end)

            local CHUNK_SIZE = 12
            getgenv().restoreThread = task.spawn(function()
                local idx = 1
                local total = #savedParts
                while getgenv().loopKillEnabled and total > 0 do
                    for chunk = 1, CHUNK_SIZE do
                        if not getgenv().loopKillEnabled then break end
                        local info = savedParts[idx]
                        if info and info.part and info.part:IsA("BasePart") then
                            local part = info.part
                            local targetCf = info.cf
                            local ok, posDiff = pcall(function() return (part.Position - targetCf.Position).Magnitude end)
                            if ok and posDiff and posDiff > 0.15 then
                                pcall(function()
                                    part.Anchored = false
                                    part.CFrame = targetCf
                                    part.Anchored = true
                                end)
                            end
                        end
                        idx = idx + 1
                        if idx > total then
                            idx = 1
                            break
                        end
                    end
                    task.wait()
                end
            end)

        else
            getgenv().loopKillEnabled = false
            stopFallenHeightLoop()
            getgenv().exerting = false
            getgenv().teleportUnderFiring = false
            scheduleTeleportHome()
            if getgenv().heartbeatConnection then
                pcall(function() getgenv().heartbeatConnection:Disconnect() end)
                getgenv().heartbeatConnection = nil
            end
            getgenv().restoreThread = nil
            getgenv().savedParts = nil
        end
    end
})

local blobLockEnabled = false
local lastReleaseTime = 0

function getSeatedBlob()
    local char = LocalPlayer.Character
    if not char then return nil end
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return nil end
    local seat = humanoid.SeatPart
    if seat and seat:IsA("VehicleSeat") and seat.Parent and seat.Parent.Name:match("CreatureBlobman") then
        return seat.Parent
    end
    return nil
end

function getNextTarget()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isPlayerInTarget(p) then
            local char = p.Character
            local hum = char and char:FindFirstChild("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if char and hum and hrp and hum.Health > 0 then
                return p
            end
        end
    end
    return nil
end

function cleanupDeadCharacters()
    for _, p in ipairs(Players:GetPlayers()) do
        local char = p.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if hum and hum.Health <= 0 then
            p.Character = nil
        end
    end
end

task.spawn(function()
    while true do
        if blobLockEnabled then
            local playerChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local humanoid = playerChar:FindFirstChild("Humanoid")
            local rootPart = playerChar:FindFirstChild("HumanoidRootPart")
            if not humanoid or not rootPart then
                task.wait(0.05)
                continue
            end

            local blob = getSeatedBlob()
            local blobScript = blob and blob:FindFirstChild("BlobmanSeatAndOwnerScript")
            
            if not blob or not blobScript then
                task.wait(0.05)
                continue
            end

            local blobDeleteCounter = 0
            local blobDeleteWindowStart = 0
            
            while blobLockEnabled do
                blob = getSeatedBlob()
                if not blob then
                    repeat
                        task.wait(0.05)
                        blob = getSeatedBlob()
                    until blob or not blobLockEnabled
                    
                    if not blobLockEnabled then break end
                    blobScript = blob and blob:FindFirstChild("BlobmanSeatAndOwnerScript")
                    if not blobScript then
                        task.wait(0.05)
                        continue
                    end
                else
                    blobDeleteCounter = 0
                    blobDeleteWindowStart = 0
                end

                local targetPlayer = getNextTarget()
                if targetPlayer then
                    local targetChar = targetPlayer.Character
                    local targetHum = targetChar and targetChar:FindFirstChild("Humanoid")
                    local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")

                    if targetChar and targetHum and targetHRP and targetHum.Health > 0 then
                        rootPart.CFrame = targetHRP.CFrame * CFrame.new(0, -13, 0)

                        local rightDetector = blob:FindFirstChild("RightDetector")
                        local rightWeld = rightDetector and rightDetector:FindFirstChild("RightWeld")
                        if blobScript:FindFirstChild("CreatureGrab") and rightDetector and rightWeld then
                            blobScript.CreatureGrab:FireServer(rightDetector, targetHRP, rightWeld)
                        end

                        if tick() - lastReleaseTime >= 0.1 then
                            if rightWeld and blobScript:FindFirstChild("CreatureRelease") then
                                for _, part in ipairs(targetChar:GetDescendants()) do
                                    if part:IsA("BasePart") then
                                        blobScript.CreatureRelease:FireServer(rightWeld, part)
                                    end
                                end
                            end
                            lastReleaseTime = tick()
                        end

                        targetHum.BreakJointsOnDeath = false
                        targetHum:ChangeState(Enum.HumanoidStateType.Dead)
                    end
                end

                cleanupDeadCharacters()
                task.wait(0.03)
                task.wait(0.03)
            end
        else
            task.wait(0.05)
        end
    end
end)

LoopTab:AddToggle({
    Name = "Blob Lock + Kill",
    Default = false,
    Callback = function(value)
        blobLockEnabled = value
    end
})

getgenv().AuraTick = 0
getgenv().blobInstaConnection = nil

getgenv().GrabAndKill = function(blob, targetChar, side)
    local detector = blob:FindFirstChild(side .. "Detector")
    local weld = detector and detector:FindFirstChild(side .. "Weld")
    if not (detector and weld and targetChar) then return end

    Workspace.FallenPartsDestroyHeight = 0/0

    for _, part in ipairs(targetChar:GetChildren()) do
        if part:IsA("BasePart") then
            pcall(function()
                blob.BlobmanSeatAndOwnerScript.CreatureRelease:FireServer(weld, part)
                part.AssemblyLinearVelocity = Vector3.new(0, -1e7, 0)
                local ap = Instance.new("AlignPosition")
                ap.MaxForce = 1e7
                ap.Responsiveness = 100
                ap.Position = Vector3.new(0, -1e7, 0)
                ap.Mode = Enum.PositionAlignmentMode.OneAttachment
                ap.Attachment0 = Instance.new("Attachment", part)
                ap.Parent = part
                game:GetService("Debris"):AddItem(ap, 0.5)
            end)
        end
    end

    task.delay(0.1, function()
        Workspace.FallenPartsDestroyHeight = -500
    end)
end

LoopTab:AddToggle({
    Name = "Blob Perm Death Void",
    Default = false,
    Callback = function(enabled)
        if enabled then
            getgenv().AuraTick = 0
            getgenv().blobInstaConnection = RunService.Heartbeat:Connect(function(dt)
                getgenv().AuraTick = getgenv().AuraTick + dt
                if getgenv().AuraTick < 0.15 then return end
                getgenv().AuraTick = 0

                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local seat = hum and hum.SeatPart
                local blob = seat and seat.Parent
                if not (seat and blob and blob.Name == "CreatureBlobman" and blob:FindFirstChild("BlobmanSeatAndOwnerScript")) then
                    OrionLib:MakeNotification({
                        Name = "Blobman",
                        Content = "Not sitting on Blobman, exiting..",
                        Time = 4
                    })
                    if getgenv().blobInstaConnection then
                        getgenv().blobInstaConnection:Disconnect()
                        getgenv().blobInstaConnection = nil
                    end
                    return
                end

                local grab = blob.BlobmanSeatAndOwnerScript:FindFirstChild("CreatureGrab")
                local rightDet = blob:FindFirstChild("RightDetector")
                local rightWeld = rightDet and rightDet:FindFirstChild("RightWeld")
                if not (grab and rightDet and rightWeld) then return end

                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and isPlayerInTarget(plr) then
                        local tgtChar = plr.Character
                        if tgtChar and tgtChar:FindFirstChild("HumanoidRootPart") then
                            task.delay(0.15, function()
                                pcall(function()
                                    grab:FireServer(rightDet, tgtChar.HumanoidRootPart, rightWeld)
                                    getgenv().GrabAndKill(blob, tgtChar, "Right")
                                end)
                            end)
                        end
                    end
                end
            end)
        else
            if getgenv().blobInstaConnection then
                getgenv().blobInstaConnection:Disconnect()
                getgenv().blobInstaConnection = nil
            end
        end
    end
})

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local StickyTools = {
    "NinjaKatana",
    "NinjaKunai",
    "NinjaShuriken",
    "ToolCleaver",
    "ToolDiggingForkRusty",
    "ToolPencil",
    "ToolPickaxe"
}

local function randomFarPosition()
    return Vector3.new(
        math.random(-50000,-5000),
        math.random(50,200),
        math.random(-50000,-5000)
    )
end

local function bypassCheckSticky(targetplr)

    local localChar = LocalPlayer.Character
    if not localChar then return end

    local myHRP = localChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end

    local char = targetplr.Character
    if not char then return end

    local targetHRP = char:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end

   
    if (myHRP.Position - targetHRP.Position).Magnitude > 30 then
        return
    end

    local toysFolder = Workspace:FindFirstChild(targetplr.Name.."SpawnedInToys")
    if not toysFolder then return end

    for _,tool in ipairs(toysFolder:GetChildren()) do

        if table.find(StickyTools, tool.Name) then

            local stickyPart = tool:FindFirstChild("StickyPart", true)

            if stickyPart then

                local weld = stickyPart:FindFirstChild("StickyWeld")

                local distMe = (stickyPart.Position - myHRP.Position).Magnitude
                local distTarget = (stickyPart.Position - targetHRP.Position).Magnitude

                if distMe <= 30 or distTarget <= 30 then

                    if weld and weld.Part1 and weld.Part1:IsDescendantOf(char) then

                        
                        for i = 1,8 do
                            pcall(function()
                                ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(stickyPart, stickyPart.CFrame)
                            end)
                        end

                        
                        pcall(function()
                            weld:Destroy()
                        end)

                       
                        stickyPart.CFrame = CFrame.new(randomFarPosition())

                    end
                end
            end
        end
    end
end


local bypassAntiKickEnabled = false
local bypassLoopRunning = false

LoopTab:AddToggle({
    Name = "Bypass Anti-Kick",
    Default = false,
    Save = true,
    Flag = "BypassAntiKick",
    Callback = function(Value)

        bypassAntiKickEnabled = Value

        if bypassAntiKickEnabled and not bypassLoopRunning then
            bypassLoopRunning = true

            task.spawn(function()

                while bypassAntiKickEnabled do

                    local myChar = LocalPlayer.Character
                    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")

                    if myHRP then
                        for _,plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LocalPlayer then
                                bypassCheckSticky(plr)
                            end
                        end
                    end

                    task.wait(0.08)

                end

                bypassLoopRunning = false

            end)
        end
    end
})

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local SB_enabled = false
local SB_loop = nil

local function spawnSnowball(cf)
    ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer(
        "BallSnowball",
        cf,
        Vector3.new(0,0,0)
    )
end

local function getSnowball()
    local folder = workspace:FindFirstChild(LocalPlayer.Name .. "SpawnedInToys")
    if not folder then return end
    for _,v in ipairs(folder:GetChildren()) do
        if v.Name == "BallSnowball" then
            return v
        end
    end
end

local function setOwner(obj)
    local sp = obj:FindFirstChild("SoundPart")
    if sp then
        ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(sp, sp.CFrame)
    end
end

local function applyForce(obj)
    for _,part in ipairs(obj:GetDescendants()) do
        if part:IsA("BasePart") then
            local bv = part:FindFirstChildOfClass("BodyVelocity")
            if not bv then
                bv = Instance.new("BodyVelocity")
                bv.MaxForce = Vector3.new(1e5,1e5,1e5)
                bv.P = 1e4
                bv.Velocity = Vector3.new(0,50,0)
                bv.Parent = part
            end
        end
    end
end

local function touch(obj, hrp)
    for _,part in ipairs(obj:GetDescendants()) do
        if part:IsA("BasePart") then
            firetouchinterest(part, hrp, 0)
            firetouchinterest(part, hrp, 1)
        end
    end
end

local function startLoop()
    if SB_loop then task.cancel(SB_loop) end

    SB_loop = task.spawn(function()
        while SB_enabled do
            for _,target in ipairs(TargetChutar) do
                local char = target.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")

                if hrp then
                    spawnSnowball(hrp.CFrame)

                    task.wait(0.1)

                    local snowball = getSnowball()

                    if snowball then
                        setOwner(snowball)
                        applyForce(snowball)

                        for i = 1,5 do
                            if not SB_enabled then break end

                            for _,part in ipairs(snowball:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.CFrame = hrp.CFrame
                                    part.CanCollide = false
                                end
                            end

                            touch(snowball, hrp)
                            task.wait(0.03)
                        end
                    end
                end
            end

            task.wait(0.05)
        end
    end)
end

LoopTab:AddToggle({
    Name = "Snowball Ragdoll",
    Default = false,
    Callback = function(state)
        SB_enabled = state

        if not state then
            if SB_loop then task.cancel(SB_loop) end
            SB_loop = nil
            return
        end

        startLoop()
    end
})

--------------------------------------------LoopTAB end---------------------------------------------
--------------------------------------------MachineTAB INC---------------------------------------------
local MTab = Window:MakeTab({
    Name = "Machine",
    Icon = "rbxassetid://103327125341396",
    PremiumOnly = false
})

MTab: AddButton({
    Title = "Nuke Server",
    Callback = function()
         Players = game:GetService("Players")
         ReplicatedStorage = game:GetService("ReplicatedStorage")
         LocalPlayer = Players.LocalPlayer
         GrabRemote = ReplicatedStorage:WaitForChild("GrabEvents"):WaitForChild("ExtendGrabLine")
        CONFIG = {
            PayloadKB = 690,
            Threads = 3,
            PacketsPerCycle = 20, 
            PacketDelay = 0.12,
            CycleDelay = 1
        }
        local payload = string.rep("🔥GENERALG🔥", CONFIG.PayloadKB * 1024)
        local function sendPackets()
            for i = 1, CONFIG.PacketsPerCycle do
                GrabRemote:FireServer(payload)
                task.wait(CONFIG.PacketDelay)
            end
        end
        for i = 1, CONFIG.Threads do
            task.spawn(function()
                while true do
                    sendPackets()
                    task.wait(CONFIG.CycleDelay)
                end
            end)
        end
    end
})
MTab:AddLabel("INFO: Use /nuke server for active too!! :D")

--------------------------------------MachineTAB end---------------------------------------------
--------------------------------------------Teleport TAB INC---------------------------------------------

local tpTab = Window:MakeTab({
    Name = "Teleport",
    Icon = "rbxassetid://6723742952",
    PremiumOnly = false
})

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local TargetPlayers = {}

local SavedPosition = nil
local LastPosition = nil

local function getLocalRootPart()
    local char = LocalPlayer.Character
    if not char then
        return nil
    end

    return char:FindFirstChild("HumanoidRootPart")
end

local function teleportWithBackTrack(targetCFrame)
    local hrp = getLocalRootPart()
    if not hrp or not targetCFrame then
        return false
    end

    LastPosition = hrp.CFrame
    hrp.CFrame = targetCFrame
    return true
end

tpTab:AddPlayersDropdown({
    Name = "Players",
    MultipleSelection = true,
    Callback = function(selected)
        table.clear(TargetPlayers)

        for _, name in ipairs(selected) do
            local plr = Players:FindFirstChild(name)
            if plr then
                table.insert(TargetPlayers, plr)
            end
        end
    end
})

-- TELEPORT TO PLAYER
tpTab:AddButton({
    Name = "Teleport To Player",
    Callback = function()
        if #TargetPlayers == 0 then return end

        local target = TargetPlayers[1]

        if target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            teleportWithBackTrack(target.Character.HumanoidRootPart.CFrame)
        end
    end
})

-- RANDOM PLAYER TP
tpTab:AddButton({
    Name = "Teleport To Random Player",
    Callback = function()
        local plrs = Players:GetPlayers()
        if #plrs <= 1 then return end

        local randomPlayer
        repeat
            randomPlayer = plrs[math.random(1, #plrs)]
        until randomPlayer ~= LocalPlayer

        if randomPlayer.Character and randomPlayer.Character:FindFirstChild("HumanoidRootPart") then
            teleportWithBackTrack(randomPlayer.Character.HumanoidRootPart.CFrame)
        end
    end
})

-- BRING
tpTab:AddButton({
    Name = "Bring",
    Callback = function()
        if not LocalPlayer.Character then return end
        if #TargetPlayers == 0 then return end

        local myHRP = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end

        local savedCFrame = myHRP.CFrame

        for _, target in ipairs(TargetPlayers) do
            if target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                local targetHRP = target.Character.HumanoidRootPart

                myHRP.CFrame = targetHRP.CFrame
                task.wait(0.15)

                game.ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(targetHRP, targetHRP.CFrame)
                task.wait(0.1)

                targetHRP.CFrame = savedCFrame
                task.wait(0.1)

                game.ReplicatedStorage.GrabEvents.DestroyGrabLine:FireServer(targetHRP, targetHRP.CFrame)
            end
        end

        myHRP.CFrame = savedCFrame
    end
})

-- SAVE POSITION
tpTab:AddButton({
    Name = "Save Position",
    Callback = function()
        local hrp = getLocalRootPart()
        if hrp then
            SavedPosition = hrp.CFrame
        end
    end
})

-- TELEPORT TO SAVED POSITION
tpTab:AddButton({
    Name = "Teleport To Saved Position",
    Callback = function()
        teleportWithBackTrack(SavedPosition)
    end
})

-- TELEPORT BACK
tpTab:AddButton({
    Name = "Teleport Back",
    Callback = function()
        local hrp = getLocalRootPart()
        if hrp and LastPosition then
            local currentPosition = hrp.CFrame
            hrp.CFrame = LastPosition
            LastPosition = currentPosition
        end
    end
})

-- VIEW PLAYER
tpTab:AddButton({
    Name = "View Player",
    Callback = function()
        if #TargetPlayers == 0 then return end

        local target = TargetPlayers[1]

        if target.Character and target.Character:FindFirstChild("Humanoid") then
            workspace.CurrentCamera.CameraSubject = target.Character.Humanoid
        end
    end
})

-- UNVIEW
tpTab:AddButton({
    Name = "Unview",
    Callback = function()
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            workspace.CurrentCamera.CameraSubject = LocalPlayer.Character.Humanoid
        end
    end
})

local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local FlashbackEnabled = false
local Rewinding = false
local Frames = {}

RunService.Heartbeat:Connect(function()
	if not FlashbackEnabled or Rewinding then return end
	
	local char = LocalPlayer.Character
	if not char then return end
	
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	table.insert(Frames,{
		cf = hrp.CFrame,
		cam = workspace.CurrentCamera.CFrame
	})
	
	if #Frames > 1200 then
		table.remove(Frames,1)
	end
end)

local function rewind()

	if Rewinding then
		Rewinding = false
		return
	end

	Rewinding = true

	local char = LocalPlayer.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local bp = Instance.new("BodyPosition")
	bp.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
	bp.P = 50000
	bp.D = 2000
	bp.Parent = hrp

	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(math.huge,math.huge,math.huge)
	bg.P = 50000
	bg.D = 2000
	bg.Parent = hrp

	for i = #Frames,1,-1 do
		
		if not Rewinding then break end
		
		local frame = Frames[i]
		
		bp.Position = frame.cf.Position
		bg.CFrame = frame.cf
		
		workspace.CurrentCamera.CFrame = frame.cam
		
		RunService.RenderStepped:Wait() 
	end

	bp:Destroy()
	bg:Destroy()

	Rewinding = false
	table.clear(Frames)
end

UIS.InputBegan:Connect(function(input,gpe)
	if gpe then return end
	if not FlashbackEnabled then return end
	
	if input.KeyCode == Enum.KeyCode.B then
		task.spawn(rewind)
	end
end)

tpTab:AddToggle({
	Name = "Flashback (Reverso)",
	Default = false,
	Callback = function(v)
		FlashbackEnabled = v
		
		if not v then
			Rewinding = false
			table.clear(Frames)
		end
	end
})
--------------------------------------------MoreTAB INC---------------------------------------------
OTab = Window:MakeTab({
	Name = "More",
	Icon = "rbxassetid://15567841177",
	PremiumOnly = false
})

OTab:AddButton({
    Name = "Break Barriers",
    Callback = function()
        task.spawn(function()
            local destroyed = false
            local targetPos = Vector3.new(263.4, -4.79, 466.8)
            local spawnPos = CFrame.new(263.5, -4.5, 486.9)
            
            local connection
            connection = Workspace.ChildAdded:Connect(function(child)
                if destroyed then
                    connection:Disconnect()
                    return
                end
                
                if child.Name == "Part" and (child.Position - targetPos).Magnitude <= 2 then
                    destroyed = true
                    connection:Disconnect()
                    
                    OrionLib:MakeNotification({
                        Name = "Sucesso!",
                        Content = "Barreiras destruídas!",
                        Image = "rbxassetid://4483345998",
                        Time = 3
                    })
                    
                    for _, plot in pairs(Workspace.Plots:GetChildren()) do
                        local barrier = plot:FindFirstChild("Barrier")
                        if barrier then
                            for _, part in pairs(barrier:GetChildren()) do
                                if part:IsA("BasePart") and part.CanCollide then
                                    part.CanCollide = false
                                end
                            end
                        end
                    end
                end
            end)
            
            local startTime = tick()
            repeat
                ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer("BallSnowball", spawnPos, Vector3.new(0, 0, 0))
                task.wait(1)
            until destroyed or tick() - startTime > 10
            
            if not destroyed then
                connection:Disconnect()
                OrionLib:MakeNotification({
                    Name = "Erro",
                    Content = "Falhou! Tente novamente.",
                    Image = "rbxassetid://4483345998",
                    Time = 3
                })
            end
        end)
    end
})
--------------------------------------------ConfigTAB INC---------------------------------------------
CTab = Window:MakeTab({
    Name = "Config",
    Icon = "rbxassetid://87350324375899",
    PremiumOnly = false
})

local kickNotifyActive = false
Connections = Connections or {}

CTab:AddToggle({
    Name = "Kick Notify",
    Default = false,
    Callback = function(value)
        kickNotifyActive = value
        
        if kickNotifyActive then
            Connections["KickNotify"] = Workspace.ChildAdded:Connect(function(child)
                if child.Name == "BlackHoleKick" then
                    local names = {}
                    local displayNames = {}
                    child.Name = "BlackHoleDetected"
                    
                    for _, player in pairs(Players:GetPlayers()) do
                        table.insert(names, player.Name)
                        table.insert(displayNames, player.DisplayName)
                    end
                    
                    task.wait(3.25)
                    
                    if #names - #Players:GetPlayers() > 1 then
                        OrionLib:MakeNotification({
                            Name = "Error Kicked " .. (#names - #Players:GetPlayers()),
                            Content = "Script dont understand who get kicked",
                            Image = "rbxassetid://4483362458",
                            Time = 5
                        })
                        return
                    end
                    
                    for i, player in pairs(Players:GetPlayers()) do
                        if player.Name ~= names[i] then
                            OrionLib:MakeNotification({
                                Name = "Kicked",
                                Content = displayNames[i] .. " (" .. names[i] .. ") get kicked!",
                                Image = "rbxassetid://4483362458",
                                Time = 5
                            })
                            return
                        end
                        
                        if #names - #Players:GetPlayers() == 1 and i + 1 == #names then
                            OrionLib:MakeNotification({
                                Name = "Kicked",
                                Content = displayNames[i + 1] .. " (" .. names[i + 1] .. ") get kicked!",
                                Image = "rbxassetid://4483362458",
                                Time = 5
                            })
                            return
                        end
                    end
                end
            end)
        else
            if Connections["KickNotify"] then
                Connections["KickNotify"]:Disconnect()
                Connections["KickNotify"] = nil
            end
        end
    end
})
-----------------------------------------ConfigTAB End---------------------------------------------
