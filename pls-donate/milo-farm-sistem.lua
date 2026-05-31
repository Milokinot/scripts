--[[
	Milo Farm System | Supreme
	Includes:
	- Auto claim booth on execute
	- Walk back to booth
	- Nearby player reactions
	- Donate watcher
	- Discord webhook
]]

repeat
	task.wait()
until game:IsLoaded()

local SUPPORTED_PLACE_IDS = {
	[8737602449] = true,
	[8943844393] = true,
}

if not SUPPORTED_PLACE_IDS[game.PlaceId] then
	return
end

if type(rawget(getgenv(), "MILO_MFS_CLEANUP")) == "function" then
	pcall(rawget(getgenv(), "MILO_MFS_CLEANUP"))
end

local RUN_FLAG = "MILO_MFS_SUPREME_RUNNING"
if getgenv()[RUN_FLAG] then
	return
end
getgenv()[RUN_FLAG] = true

local Services = {
	Players = game:GetService("Players"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	HttpService = game:GetService("HttpService"),
	RunService = game:GetService("RunService"),
	StarterGui = game:GetService("StarterGui"),
	TeleportService = game:GetService("TeleportService"),
	PathfindingService = game:GetService("PathfindingService"),
	VirtualUser = game:GetService("VirtualUser"),
}

local LocalPlayer = Services.Players.LocalPlayer
if not LocalPlayer then
	return
end

local RAW_SCRIPT_URL = "https://raw.githubusercontent.com/Milokinot/scripts/main/pls-donate/milo-farm-sistem.lua"
local TELEPORT_LOADSTRING = string.format('loadstring(game:HttpGet("%s", true))()', RAW_SCRIPT_URL)

local executor = {}
executor.request = (syn and syn.request)
	or (http and http.request)
	or http_request
	or (fluxus and fluxus.request)
	or (krnl and krnl.request)
	or request
executor.httpGet = httpget
executor.queueOnTeleport = (syn and syn.queue_on_teleport)
	or queue_on_teleport
	or queueonteleport
	or (fluxus and fluxus.queue_on_teleport)
	or (krnl and krnl.queue_on_teleport)

local function rawHttpGet(url)
	local ok, body = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(body) == "string" and #body > 0 then
		return body
	end

	if executor.httpGet then
		local okHttp, httpBody = pcall(executor.httpGet, url)
		if okHttp and type(httpBody) == "string" and #httpBody > 0 then
			return httpBody
		end
	end

	if executor.request then
		local okRequest, response = pcall(function()
			return executor.request({
				Url = url,
				Method = "GET",
			})
		end)
		if okRequest and response and type(response.Body) == "string" and #response.Body > 0 then
			return response.Body
		end
	end

	return nil
end

local SETTINGS_FILE = "milo_mfs_supreme_settings.json"
local PERMANENT_WEBHOOK_URL = ""
local DONATE_WEBHOOK_URL = "https://discord.com/api/webhooks/1500986351590576158/VJSH2gNHWWOHIbXpB-OqZWeSd0EKQWU5XLAoOyZwzwFLLI2yzJBR_lYgLHgAkaLWrxN0"
local DEFAULTS = {
	autoClaimBooth = true,
	boothLocality = true,
	autoReactPlayers = false,
	donateWatcher = true,
	donatePopup = true,
	donateWebhook = false,
	webhookUrl = PERMANENT_WEBHOOK_URL,
	claimRetryDelay = 2,
	autoClaimStartDelay = 5,
	autoClaimForwardStuds = 10,
	directMoveRefresh = 0.8,
	pathMoveRefresh = 0.1,
	movementLoopWait = 1,
	walkTimeoutBaseSeconds = 4,
	walkTimeoutDistanceDivisor = 9,
	walkTimeoutMinSeconds = 4,
	walkTimeoutMaxSeconds = 24,
	fastBoothReturnSpeed = 42,
	detectionDistance = 20,
	followDistance = 4,
	tooCloseDistance = 3,
	stopJumpCount = 3,
	closeJumpCount = 2,
	jumpCooldown = 2,
	emoteCooldown = 4,
	loopDelay = 0.25,
	movementThreshold = 1.35,
	returnToBoothDistance = 8,
	serverAuditEnabled = true,
	serverMinPlayers = 18,
	serverTargetMinPlayers = 20,
	serverTargetMaxPlayers = 25,
	serverAuditMinutes = 5,
	serverSampleInterval = 5,
	serverSuspiciousThreshold = 75,
	serverMinPremiums = 5,
	serverMinActivePremiums = 3,
	serverDonationStayThreshold = 80,
	serverQualityStayScore = 90,
	serverHopRetryDelay = 15,
	serverQueueSource = "",
}

local settings = {}
local refreshStatus
local runtime = {
	boothId = nil,
	boothAnchor = nil,
	currentTarget = nil,
	donationBaseline = nil,
	pendingDonations = {},
	serverDonationEvents = {},
	lastDonationText = "No donations yet",
	lastWaveAt = 0,
	lastPointAt = 0,
	lastJumpAt = 0,
	serverAuditText = "Server audit idle",
	lastServerReport = nil,
	bestServerReport = nil,
	serverHopInProgress = false,
	serverAuditInProgress = false,
	debugLines = { "Debug aguardando eventos" },
	debugText = "Debug aguardando eventos",
	lastDebugPrintAt = 0,
	lastTargetName = "None",
	lastAntiAfkAt = 0,
	boothClaimInProgress = false,
	lastBoothClaimAt = 0,
	startedAt = os.clock(),
	autoClaimPrepDone = false,
	autoClaimFinished = false,
	boothReturnSpeedActive = false,
	boothReturnOriginalSpeed = nil,
	boothReturnNoticeSent = false,
	boothReturnInProgress = false,
	lastBoothReturnAt = 0,
	boothLockId = nil,
	boothLockSince = 0,
	boothLockFailures = 0,
	loops = {},
	connections = {},
}

local function deepCopy(source)
	local target = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			target[key] = deepCopy(value)
		else
			target[key] = value
		end
	end
	return target
end

local function mergeDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = deepCopy(value)
			else
				target[key] = value
			end
		end
	end
	return target
end

local function saveSettings()
	if not writefile then
		return false
	end
	local ok = pcall(function()
		writefile(SETTINGS_FILE, Services.HttpService:JSONEncode(settings))
	end)
	return ok
end

local function loadSettings()
	settings = deepCopy(DEFAULTS)
	if not (readfile and isfile and isfile(SETTINGS_FILE)) then
		return
	end

	local ok, decoded = pcall(function()
		return Services.HttpService:JSONDecode(readfile(SETTINGS_FILE))
	end)
	if ok and type(decoded) == "table" then
		settings = mergeDefaults(decoded, DEFAULTS)
	end
end

loadSettings()
settings.autoClaimBooth = true
settings.autoReactPlayers = false
settings.directMoveRefresh = 0.8
settings.pathMoveRefresh = 0.1
settings.movementLoopWait = 1
settings.walkTimeoutBaseSeconds = 4
settings.walkTimeoutDistanceDivisor = 9
settings.walkTimeoutMinSeconds = 4
if type(settings.webhookUrl) ~= "string" then
	settings.webhookUrl = PERMANENT_WEBHOOK_URL
end

local function safeNumber(value, fallback)
	local numeric = tonumber(value)
	if numeric == nil then
		return fallback
	end
	return numeric
end

local DEBUG_PRINT_INTERVAL = 35 * 60
local DEBUG_MAX_LINES = 8
local BOOTH_UNSTUCK_JUMP_COOLDOWN = 1.2
local FAST_BOOTH_RETURN_SPEED = 42
local BOOTH_FREE_TIME = 60

local function rebuildDebugText()
	runtime.debugText = table.concat(runtime.debugLines, "\n")
end

local function pushDebug(scope, message, forcePrint)
	local text = tostring(message or "")
	local timestamp = os.date("%H:%M:%S")
	local line = string.format("[%s][%s] %s", timestamp, tostring(scope or "LOG"), text)

	table.insert(runtime.debugLines, 1, line)
	while #runtime.debugLines > DEBUG_MAX_LINES do
		table.remove(runtime.debugLines)
	end
	rebuildDebugText()

	if forcePrint or os.clock() - safeNumber(runtime.lastDebugPrintAt, 0) >= DEBUG_PRINT_INTERVAL then
		print("[Milo MFS DEBUG] " .. line)
		runtime.lastDebugPrintAt = os.clock()
	end

	if refreshStatus then
		refreshStatus()
	end
end

local function buildDebugSnapshot(reason)
	local boothText = runtime.boothId and tostring(runtime.boothId) or "None"
	local boothAnchor = runtime.boothAnchor and "READY" or "NONE"
	local targetName = runtime.currentTarget and runtime.currentTarget.Name or "None"
	return string.format(
		"%s | Booth=%s | Anchor=%s | Target=%s | Players=%d | Audit=%s | Donate=%s",
		tostring(reason or "Snapshot"),
		boothText,
		boothAnchor,
		targetName,
		#Services.Players:GetPlayers(),
		tostring(runtime.serverAuditText or "idle"),
		tostring(runtime.lastDonationText or "none")
	)
end

local function notify(title, text, duration)
	local sent = false
	pcall(function()
		Services.StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = duration or 4,
		})
		sent = true
	end)
	if not sent then
		warn(string.format("[Milo MFS] %s: %s", tostring(title), tostring(text)))
	end
end

local function sendWebhook(message, embedData)
	if type(DONATE_WEBHOOK_URL) ~= "string" or DONATE_WEBHOOK_URL:gsub("%s+", "") == "" then
		return false
	end
	if not executor.request then
		return false
	end

	local ok = pcall(function()
		local payload = {
			content = message,
		}
		if type(embedData) == "table" then
			payload.embeds = { embedData }
		end
		executor.request({
			Url = tostring(DONATE_WEBHOOK_URL),
			Method = "POST",
			Headers = {
				["content-type"] = "application/json",
			},
			Body = Services.HttpService:JSONEncode(payload),
		})
	end)
	return ok
end

local function getCharacter()
	return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHumanoid()
	local character = getCharacter()
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRootPart()
	local character = getCharacter()
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getRaisedValue()
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Raised") or nil
end

local function normalizeGuiText(value)
	local text = tostring(value or "")
	text = text:gsub("<.->", "")
	text = text:gsub("[%c]", " ")
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")
	return string.lower(text)
end

local function getPlanarDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function getPlanarVelocity(rootPart)
	if not rootPart then
		return 0
	end
	local velocity = rootPart.AssemblyLinearVelocity or rootPart.Velocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function getMapUi()
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if playerGui then
		local container = playerGui:FindFirstChild("MapUIContainer")
		local mapUi = container and container:FindFirstChild("MapUI")
		if mapUi then
			return mapUi
		end
	end
	return workspace:FindFirstChild("MapUI")
end

local function getBoothUiFolder()
	local mapUi = getMapUi()
	return mapUi and mapUi:FindFirstChild("BoothUI") or nil
end

local function waitForBoothUiFolder(timeoutSeconds)
	local deadline = os.clock() + math.max(0, safeNumber(timeoutSeconds, 0))
	repeat
		local boothFolder = getBoothUiFolder()
		if boothFolder and #boothFolder:GetChildren() > 0 then
			return boothFolder
		end
		task.wait(0.35)
	until os.clock() >= deadline
	return getBoothUiFolder()
end

local function extractBoothId(booth)
	if not booth then
		return nil
	end

	for _, attributeName in ipairs({ "BoothSlot", "BoothId", "ID", "Id", "Slot", "Number" }) do
		local value = booth:GetAttribute(attributeName)
		local boothId = tonumber(value)
		if boothId then
			return boothId
		end
	end

	local details = booth:FindFirstChild("Details")
	if details then
		for _, attributeName in ipairs({ "BoothSlot", "BoothId", "ID", "Id", "Slot", "Number" }) do
			local value = details:GetAttribute(attributeName)
			local boothId = tonumber(value)
			if boothId then
				return boothId
			end
		end
	end

	return tonumber(string.match(booth.Name, "%d+"))
end

local function getOwnerLabel(booth)
	local details = booth and booth:FindFirstChild("Details")
	return details and details:FindFirstChild("Owner") or nil
end

local function getRemotesModule()
	local direct = Services.ReplicatedStorage:FindFirstChild("Remotes")
	if direct then
		local ok, loaded = pcall(require, direct)
		if ok then
			return loaded
		end
	end

	for _, child in ipairs(Services.ReplicatedStorage:GetChildren()) do
		if child:IsA("ModuleScript") and child.Name:find("Remote") then
			local ok, loaded = pcall(require, child)
			if ok and loaded then
				return loaded
			end
		end
	end

	return nil
end

local Remotes = getRemotesModule()

local function resolveNamedRemote(name)
	local remote = Services.ReplicatedStorage:FindFirstChild(name, true)
	if remote and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
		return remote
	end
	return nil
end

local function callRemote(remote, args)
	if typeof(remote) == "Instance" then
		if remote:IsA("RemoteFunction") then
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end
		if remote:IsA("RemoteEvent") then
			remote:FireServer(table.unpack(args, 1, args.n))
			return true
		end
	end

	if type(remote) == "table" then
		if type(remote.InvokeServer) == "function" then
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end
		if type(remote.FireServer) == "function" then
			remote:FireServer(table.unpack(args, 1, args.n))
			return true
		end
		if type(remote.Fire) == "function" then
			remote:Fire(table.unpack(args, 1, args.n))
			return true
		end
	end

	return false
end

local function invokeRemoteEvent(name, ...)
	local args = table.pack(...)
	local directRemote = resolveNamedRemote(name)
	if directRemote then
		local ok, result = pcall(function()
			return callRemote(directRemote, args)
		end)
		if ok then
			return result
		end
	end

	if not Remotes or not Remotes.Event then
		return false
	end

	local ok, result = pcall(function()
		local remote = Remotes.Event(name)
		return callRemote(remote, args)
	end)
	if ok then
		return result
	end
	return false
end

local function sayMessage(message)
	local chatEvents = Services.ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
	local remote = chatEvents and chatEvents:FindFirstChild("SayMessageRequest")
	if remote then
		pcall(function()
			remote:FireServer(message, "All")
		end)
		return true
	end
	return false
end

local function getChatMessageEvent()
	local chatEvents = Services.ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
	return chatEvents and chatEvents:FindFirstChild("OnMessageDoneFiltering") or nil
end

local function isLocalPlayerName(text)
	local normalized = normalizeGuiText(text)
	return normalized:find(normalizeGuiText(LocalPlayer.DisplayName), 1, true)
		or normalized:find(normalizeGuiText(LocalPlayer.Name), 1, true)
end

local function cleanupPendingDonations()
	local now = os.clock()
	for index = #runtime.pendingDonations, 1, -1 do
		local donation = runtime.pendingDonations[index]
		if not donation or now - donation.createdAt > 15 then
			table.remove(runtime.pendingDonations, index)
		end
	end
end

local function queuePendingDonation(donor, amount, recipient)
	if not donor or not amount or not recipient then
		return
	end
	cleanupPendingDonations()
	table.insert(runtime.pendingDonations, {
		donor = tostring(donor),
		amount = tonumber(amount),
		recipient = tostring(recipient),
		createdAt = os.clock(),
	})
end

local function cleanupServerDonationEvents()
	local now = os.clock()
	for index = #runtime.serverDonationEvents, 1, -1 do
		local donation = runtime.serverDonationEvents[index]
		if not donation or now - safeNumber(donation.createdAt, 0) > 900 then
			table.remove(runtime.serverDonationEvents, index)
		end
	end
end

local function recordServerDonation(donor, amount, recipient)
	amount = safeNumber(amount, 0)
	if amount <= 0 then
		return
	end

	cleanupServerDonationEvents()
	table.insert(runtime.serverDonationEvents, {
		donor = tostring(donor or "Unknown"),
		recipient = tostring(recipient or "Unknown"),
		amount = amount,
		createdAt = os.clock(),
	})
end

local function getServerDonationsSince(startedAt)
	local total = 0
	local biggest = 0
	local count = 0
	startedAt = safeNumber(startedAt, 0)
	cleanupServerDonationEvents()
	for _, donation in ipairs(runtime.serverDonationEvents) do
		local amount = safeNumber(donation.amount, 0)
		if amount > 0 and safeNumber(donation.createdAt, 0) >= startedAt then
			total = total + amount
			count = count + 1
			if amount > biggest then
				biggest = amount
			end
		end
	end

	return total, count, biggest
end

local function consumePendingDonation(amount)
	cleanupPendingDonations()
	for index, donation in ipairs(runtime.pendingDonations) do
		if donation.amount == amount and isLocalPlayerName(donation.recipient) then
			table.remove(runtime.pendingDonations, index)
			return donation
		end
	end

	for index, donation in ipairs(runtime.pendingDonations) do
		if donation.amount == amount then
			table.remove(runtime.pendingDonations, index)
			return donation
		end
	end

	return nil
end

local function parseDonationFromMessage(messageText)
	local text = tostring(messageText or ""):gsub("\n", " "):gsub("%s+", " ")
	if text == "" then
		return nil
	end

	local patterns = {
		{
			pattern = "^(.-)%s+donated%s+(%d+)%s+to%s+(.-)[%!%.]?$",
			map = function(a, b, c)
				return { donor = a, amount = tonumber(b), recipient = c }
			end,
		},
		{
			pattern = "^(.-)%s+just%s+donated%s+(%d+)%s+to%s+(.-)[%!%.]?$",
			map = function(a, b, c)
				return { donor = a, amount = tonumber(b), recipient = c }
			end,
		},
		{
			pattern = "^(.-)%s+donated%s+to%s+(.-)%s+(%d+)[%!%.]?$",
			map = function(a, b, c)
				return { donor = a, recipient = b, amount = tonumber(c) }
			end,
		},
		{
			pattern = "^(.-)%s+bought%s+.-%s+from%s+(.-)%s+for%s+(%d+)%s+robux[%!%.]?$",
			map = function(a, b, c)
				return { donor = a, recipient = b, amount = tonumber(c) }
			end,
		},
	}

	for _, entry in ipairs(patterns) do
		local a, b, c = text:match(entry.pattern)
		if a and b and c then
			return entry.map(a, b, c)
		end
	end

	return nil
end

local function playEmote(command)
	if not command or command == "" then
		return false
	end
	return sayMessage(command)
end

local BoothLogic = {}

local BOOTH_ID_ATTRIBUTE_NAMES = { "BoothSlot", "BoothId", "ID", "Id", "Slot", "Number" }
local CLASSIC_BOOTH_SCAN_CENTER = Vector3.new(165.161, 0, 311.636)
local CLASSIC_BOOTH_SCAN_RADIUS = 92

local function extractInstanceBoothId(instance)
	if not instance then
		return nil
	end

	for _, attributeName in ipairs(BOOTH_ID_ATTRIBUTE_NAMES) do
		local value = instance:GetAttribute(attributeName)
		local boothId = tonumber(value)
		if boothId then
			return boothId
		end
	end

	for _, childName in ipairs(BOOTH_ID_ATTRIBUTE_NAMES) do
		local child = instance:FindFirstChild(childName)
		if child then
			local childValue = child.Name
			if child:IsA("ValueBase") then
				childValue = child.Value
			elseif child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
				childValue = child.Text
			end
			local boothId = tonumber(childValue)
			if boothId then
				return boothId
			end
		end
	end

	return tonumber(string.match(instance.Name, "%d+"))
end

local function getBoothOwnerText(booth)
	local owner = getOwnerLabel(booth)
	if owner and type(owner.Text) == "string" then
		return normalizeGuiText(owner.Text)
	end

	for _, attributeName in ipairs({ "Owner", "OwnerText", "OwnerName", "Username", "DisplayName", "Text" }) do
		local value = booth and booth:GetAttribute(attributeName)
		if type(value) == "string" and value:gsub("%s+", "") ~= "" then
			return normalizeGuiText(value)
		end
	end

	if booth then
		for _, descendant in ipairs(booth:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				local text = normalizeGuiText(descendant.Text)
				if text ~= "" then
					local mentionsClaim = text:find("claim", 1, true) or text:find("unclaim", 1, true)
					local mentionsPlayer = text:find(normalizeGuiText(LocalPlayer.Name), 1, true)
						or text:find(normalizeGuiText(LocalPlayer.DisplayName), 1, true)
					if mentionsClaim or mentionsPlayer then
						return text
					end
				end
			end
		end
	end

	return ""
end

local function isBoothUnclaimed(booth)
	local ownerText = getBoothOwnerText(booth)
	if ownerText == "" then
		return false
	end

	if ownerText == "unclaimed" or ownerText:find("unclaim", 1, true) ~= nil then
		return true
	end

	return ownerText:find("claim", 1, true) ~= nil
		and ownerText:find(normalizeGuiText(LocalPlayer.Name), 1, true) == nil
		and ownerText:find(normalizeGuiText(LocalPlayer.DisplayName), 1, true) == nil
end

local function isBoothOwnedByLocal(booth)
	local ownerText = getBoothOwnerText(booth)
	if ownerText == "" then
		return false
	end

	return ownerText:find(normalizeGuiText(LocalPlayer.DisplayName), 1, true) ~= nil
		or ownerText:find(normalizeGuiText(LocalPlayer.Name), 1, true) ~= nil
end

local function getInteractionPivot(interaction)
	if not interaction then
		return nil
	end

	if interaction:IsA("BasePart") then
		return interaction.CFrame
	end

	if interaction:IsA("Attachment") then
		return interaction.WorldCFrame
	end

	if interaction:IsA("Model") then
		local ok, pivot = pcall(function()
			return interaction:GetPivot()
		end)
		if ok and pivot then
			return pivot
		end
	end

	local basePart = nil
	if interaction:IsA("ProximityPrompt") and interaction.Parent and interaction.Parent:IsA("BasePart") then
		basePart = interaction.Parent
	else
		basePart = interaction:FindFirstChildWhichIsA("BasePart", true)
	end
	if basePart then
		return basePart.CFrame
	end

	local parent = interaction.Parent
	for _ = 1, 5 do
		if not parent then
			break
		end

		if parent:IsA("BasePart") then
			return parent.CFrame
		end

		if parent:IsA("Model") then
			local ok, pivot = pcall(function()
				return parent:GetPivot()
			end)
			if ok and pivot then
				return pivot
			end
		end

		parent = parent.Parent
	end

	return nil
end

local function buildStandCFrameFromInteraction(interaction, standDistance)
	local pivot = getInteractionPivot(interaction)
	if not pivot then
		return nil
	end

	local distance = math.max(2, safeNumber(standDistance, 3))
	local standPosition = (pivot * CFrame.new(0, 0, distance)).Position
	local lookTarget = Vector3.new(pivot.Position.X, standPosition.Y, pivot.Position.Z)
	return CFrame.new(standPosition, lookTarget)
end

local function buildApproachCFramesFromInteraction(interaction, standDistance)
	local pivot = getInteractionPivot(interaction)
	if not pivot then
		return {}
	end

	local distance = math.max(2, safeNumber(standDistance, 3))
	local variants = {
		pivot * CFrame.new(0, 0, distance),
		pivot * CFrame.new(distance, 0, 0),
		pivot * CFrame.new(-distance, 0, 0),
		pivot * CFrame.new(0, 0, -distance),
	}

	local result = {}
	local seen = {}
	for _, variant in ipairs(variants) do
		local key = string.format("%.1f:%.1f:%.1f", variant.Position.X, variant.Position.Y, variant.Position.Z)
		if not seen[key] then
			seen[key] = true
			table.insert(result, CFrame.new(variant.Position, Vector3.new(pivot.Position.X, variant.Position.Y, pivot.Position.Z)))
		end
	end

	return result
end

local faceTowards

local function placeCharacterAtCFrame(targetCFrame)
	if not targetCFrame then
		return false
	end
	faceTowards(targetCFrame.Position + targetCFrame.LookVector * 6)
	return true
end

local function estimateWalkTimeout(fromPosition, targetPosition, minimumSeconds)
	local distance = getPlanarDistance(fromPosition, targetPosition)
	local baseSeconds = safeNumber(settings.walkTimeoutBaseSeconds, 4)
	local distanceDivisor = math.max(1, safeNumber(settings.walkTimeoutDistanceDivisor, 9))
	local minSeconds = safeNumber(settings.walkTimeoutMinSeconds, 4)
	local maxSeconds = math.max(minSeconds, safeNumber(settings.walkTimeoutMaxSeconds, 24))
	local floorSeconds = math.max(safeNumber(minimumSeconds, minSeconds), minSeconds)
	local baseTimeout = baseSeconds + (distance / distanceDivisor)
	return math.clamp(math.max(floorSeconds, baseTimeout), minSeconds, maxSeconds)
end

local function tryUnstuckJump(targetPosition, scopeLabel)
	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart then
		return false
	end

	if runtime.boothReturnInProgress then
		return false
	end

	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
	task.wait(0.12)
	pcall(function()
		humanoid:MoveTo(targetPosition)
	end)
	pushDebug("BOOTH", string.format("%s travou; pulando para destravar", tostring(scopeLabel or "Movimento")))
	return true
end

local function walkDirectToPosition(targetPosition, timeoutSeconds, arrivalThreshold)
	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart or not targetPosition then
		return false, "Character unavailable"
	end

	local acceptedDistance = math.max(2.5, safeNumber(arrivalThreshold, 3.5))
	local timeoutBudget = estimateWalkTimeout(rootPart.Position, targetPosition, timeoutSeconds)
	local deadline = os.clock() + timeoutBudget
	local nextMoveAt = 0
	local bestDistance = math.huge
	local lastImprovementAt = os.clock()
	local lastJumpAt = 0
	local moveIssuedCount = 0
	repeat
		rootPart = getRootPart()
		humanoid = getHumanoid()
		if not humanoid or not rootPart then
			break
		end

		if os.clock() >= nextMoveAt then
			humanoid:MoveTo(targetPosition)
			nextMoveAt = os.clock() + math.max(0.02, safeNumber(settings.directMoveRefresh, 0.25))
			moveIssuedCount += 1
		end

		local distance = getPlanarDistance(rootPart.Position, targetPosition)
		if distance + 0.35 < bestDistance then
			bestDistance = distance
			lastImprovementAt = os.clock()
			deadline = math.max(deadline, os.clock() + 2.5)
		end

		if distance <= acceptedDistance then
			return true
		end

		local jumpDelay = runtime.boothReturnInProgress and 3.5 or 1.15
		if moveIssuedCount >= 2 and getPlanarVelocity(rootPart) <= 1 and os.clock() - lastImprovementAt >= jumpDelay and distance > acceptedDistance + 2 and os.clock() - lastJumpAt >= BOOTH_UNSTUCK_JUMP_COOLDOWN then
			if tryUnstuckJump(targetPosition, "Aproximacao da booth") then
				lastJumpAt = os.clock()
				lastImprovementAt = os.clock()
				deadline = math.max(deadline, os.clock() + 2)
			end
		end

		local stallDelay = runtime.boothReturnInProgress and 6 or 2.5
		if os.clock() - lastImprovementAt >= stallDelay and distance > acceptedDistance + 3 then
			return false, string.format("Walk stalled at %.1f studs", distance)
		end

		faceTowards(targetPosition)
		task.wait(math.max(0.01, safeNumber(settings.movementLoopWait, 0.05)))
	until os.clock() >= deadline

	local finalRoot = getRootPart()
	if finalRoot and getPlanarDistance(finalRoot.Position, targetPosition) <= acceptedDistance + 1.5 then
		return true
	end

	return false, string.format("Walk timeout after %.1fs", timeoutBudget)
end

local function followPathToPosition(targetPosition, timeoutSeconds, arrivalThreshold)
	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart or not targetPosition then
		return false, "Character unavailable"
	end

	local acceptedDistance = math.max(2.5, safeNumber(arrivalThreshold, 3.5))
	local path = Services.PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = true,
		WaypointSpacing = 4,
	})

	local computed = pcall(function()
		path:ComputeAsync(rootPart.Position, targetPosition)
	end)
	if not computed or path.Status ~= Enum.PathStatus.Success then
		return walkDirectToPosition(targetPosition, timeoutSeconds, arrivalThreshold)
	end

	local waypoints = path:GetWaypoints()
	if #waypoints == 0 then
		return walkDirectToPosition(targetPosition, timeoutSeconds, arrivalThreshold)
	end

	local totalDeadline = os.clock() + estimateWalkTimeout(rootPart.Position, targetPosition, timeoutSeconds)
	local lastJumpAt = 0
	for _, waypoint in ipairs(waypoints) do
		humanoid = getHumanoid()
		rootPart = getRootPart()
		if not humanoid or not rootPart then
			return false, "Character unavailable"
		end

		local waypointPosition = Vector3.new(waypoint.Position.X, rootPart.Position.Y, waypoint.Position.Z)
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end)
		end

		humanoid:MoveTo(waypointPosition)
		local segmentStart = os.clock() - 1
		local segmentDeadline = math.min(totalDeadline, os.clock() + 3.5)
		local segmentBestDistance = math.huge
		local segmentLastImprovementAt = os.clock()
		local moveIssuedCount = 1
		while os.clock() < segmentDeadline do
			humanoid = getHumanoid()
			rootPart = getRootPart()
			if not humanoid or not rootPart then
				return false, "Character unavailable"
			end

			if os.clock() - segmentStart >= math.max(0.02, safeNumber(settings.pathMoveRefresh, 0.2)) then
				humanoid:MoveTo(waypointPosition)
				segmentStart = os.clock()
				moveIssuedCount += 1
			end

			local distance = getPlanarDistance(rootPart.Position, waypointPosition)
			if distance + 0.35 < segmentBestDistance then
				segmentBestDistance = distance
				segmentLastImprovementAt = os.clock()
			end

			if distance <= math.max(acceptedDistance, 3) then
				break
			end

			local jumpDelay = runtime.boothReturnInProgress and 3 or 0.9
			if moveIssuedCount >= 2 and getPlanarVelocity(rootPart) <= 1 and os.clock() - segmentLastImprovementAt >= jumpDelay and distance > math.max(acceptedDistance, 3) + 1.5 and os.clock() - lastJumpAt >= BOOTH_UNSTUCK_JUMP_COOLDOWN then
				if tryUnstuckJump(waypointPosition, "Waypoint da booth") then
					lastJumpAt = os.clock()
					segmentLastImprovementAt = os.clock()
					segmentDeadline = math.min(totalDeadline, math.max(segmentDeadline, os.clock() + 2))
				end
			end

			faceTowards(waypointPosition)
			task.wait(math.max(0.01, safeNumber(settings.movementLoopWait, 0.05)))
		end
	end

	rootPart = getRootPart()
	if rootPart and getPlanarDistance(rootPart.Position, targetPosition) <= acceptedDistance + 1.5 then
		return true
	end

	return walkDirectToPosition(targetPosition, math.max(2.5, safeNumber(timeoutSeconds, 6) / 2), arrivalThreshold)
end

local function walkCharacterToCFrame(targetCFrame, timeoutSeconds, arrivalThreshold)
	if not targetCFrame then
		return false, "Target missing"
	end

	local rootPart = getRootPart()
	if not rootPart then
		return false, "Character unavailable"
	end

	local targetPosition = Vector3.new(targetCFrame.Position.X, rootPart.Position.Y, targetCFrame.Position.Z)
	local walked, walkErr = followPathToPosition(targetPosition, timeoutSeconds, arrivalThreshold)
	if walked then
		placeCharacterAtCFrame(targetCFrame)
		return true
	end

	placeCharacterAtCFrame(targetCFrame)
	return false, walkErr
end

local function doAutoClaimForwardJump()
	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart then
		return false, "Character unavailable"
	end

	local forwardStuds = math.max(4, safeNumber(settings.autoClaimForwardStuds, 10))
	local forward = rootPart.CFrame.LookVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	if flatForward.Magnitude <= 0.01 then
		flatForward = Vector3.new(0, 0, -1)
	end
	local target = rootPart.Position + flatForward.Unit * forwardStuds

	pcall(function()
		humanoid:MoveTo(Vector3.new(target.X, rootPart.Position.Y, target.Z))
	end)
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
	task.wait(0.2)
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
	return true
end

function BoothLogic.prepareAutoClaimSequence()
	if not runtime.autoClaimPrepDone then
		local startDelay = math.max(0, safeNumber(settings.autoClaimStartDelay, 5))
		local remaining = startDelay - (os.clock() - safeNumber(runtime.startedAt, os.clock()))
		if remaining > 0 then
			pushDebug("BOOTH", string.format("Aguardando %.1fs antes do auto claim", remaining), true)
			task.wait(remaining)
		end
		runtime.autoClaimPrepDone = true
	end

	local moved, moveErr = doAutoClaimForwardJump()
	if moved == false and moveErr then
		pushDebug("BOOTH", "Preparacao do auto claim falhou no movimento: " .. tostring(moveErr))
	else
		pushDebug("BOOTH", "Preparacao do auto claim: andando e pulando para frente")
	end
	return true
end

function BoothLogic.getInteractionBoothId(interaction)
	return extractInstanceBoothId(interaction)
end

function BoothLogic.resolveInteractionBoothId(interaction)
	local current = interaction
	for _ = 1, 6 do
		if not current then
			break
		end

		local boothId = extractInstanceBoothId(current)
		if boothId then
			return boothId
		end

		current = current.Parent
	end

	return nil
end

function BoothLogic.scoreInteractionCandidate(interaction)
	if not interaction then
		return -1
	end

	if interaction:IsA("ProximityPrompt") then
		return 400
	end
	if interaction:IsA("ClickDetector") then
		return 350
	end
	if interaction:IsA("BasePart") then
		return 300
	end
	if interaction:IsA("Attachment") then
		return 250
	end
	if interaction:IsA("Model") then
		return 200
	end
	if interaction:FindFirstChildWhichIsA("ProximityPrompt", true) then
		return 180
	end
	if interaction:FindFirstChildWhichIsA("BasePart", true) then
		return 140
	end

	return 50
end

function BoothLogic.pickBetterInteraction(currentBest, candidate)
	if not candidate then
		return currentBest
	end
	if not currentBest then
		return candidate
	end

	local currentScore = BoothLogic.scoreInteractionCandidate(currentBest)
	local candidateScore = BoothLogic.scoreInteractionCandidate(candidate)
	if candidateScore > currentScore then
		return candidate
	end

	return currentBest
end

function BoothLogic.findBoothById(boothId)
	for _, record in ipairs(BoothLogic.getAllRecords()) do
		if record.boothId == boothId then
			return record.booth
		end
	end

	return nil
end

function BoothLogic.getAllRecords()
	local records = {}
	local boothFolder = getBoothUiFolder()
	local interactions = workspace:FindFirstChild("BoothInteractions")
	if not boothFolder then
		return records
	end

	local interactionById = {}
	if interactions then
		for _, interaction in ipairs(interactions:GetDescendants()) do
			local interactionId = BoothLogic.resolveInteractionBoothId(interaction)
			if interactionId then
				interactionById[interactionId] = BoothLogic.pickBetterInteraction(interactionById[interactionId], interaction)
			end
		end
	end

	local seenBoothIds = {}
	for _, booth in ipairs(boothFolder:GetDescendants()) do
		local boothId = extractBoothId(booth)
		if boothId and not seenBoothIds[boothId] and (getOwnerLabel(booth) or booth:FindFirstChild("Details") or booth.Name:lower():find("booth", 1, true)) then
			seenBoothIds[boothId] = true
			table.insert(records, {
				boothId = boothId,
				booth = booth,
				ownerText = getBoothOwnerText(booth),
				interaction = interactionById[boothId],
			})
		end
	end

	return records
end

function BoothLogic.findOwnedBooth()
	local displayName = normalizeGuiText(LocalPlayer.DisplayName)
	local userName = normalizeGuiText(LocalPlayer.Name)
	for _, record in ipairs(BoothLogic.getAllRecords()) do
		if record.ownerText:find(displayName, 1, true) or record.ownerText:find(userName, 1, true) then
			return record.boothId, record.booth
		end
	end

	return nil, nil
end

function BoothLogic.findUnclaimedBooths()
	local result = {}
	for _, record in ipairs(BoothLogic.getAllRecords()) do
		if isBoothUnclaimed(record.booth) then
			table.insert(result, record.boothId)
		end
	end

	table.sort(result)
	return result
end

function BoothLogic.getInteractionById(boothId)
	local interactions = workspace:FindFirstChild("BoothInteractions")
	if not interactions then
		return nil
	end

	local bestInteraction = nil
	for _, interaction in ipairs(interactions:GetDescendants()) do
		local slot = BoothLogic.resolveInteractionBoothId(interaction)
		if slot == boothId or tostring(slot) == tostring(boothId) then
			bestInteraction = BoothLogic.pickBetterInteraction(bestInteraction, interaction)
		end
	end

	return bestInteraction
end

function BoothLogic.waitUntilReady(timeoutSeconds)
	local deadline = os.clock() + math.max(1, safeNumber(timeoutSeconds, 8))
	repeat
		local boothFolder = getBoothUiFolder()
		local interactions = workspace:FindFirstChild("BoothInteractions")
		if boothFolder and #boothFolder:GetDescendants() > 0 and interactions and #interactions:GetDescendants() > 0 then
			return true
		end
		task.wait(0.35)
	until os.clock() >= deadline
	return false
end

function BoothLogic.getUnclaimedCandidates()
	local candidates = {}
	local rootPart = getRootPart()
	for _, record in ipairs(BoothLogic.getAllRecords()) do
		if isBoothUnclaimed(record.booth) then
			local interaction = record.interaction or BoothLogic.getInteractionById(record.boothId)
			local standCFrames = buildApproachCFramesFromInteraction(interaction, 3)
			local approachCFrames = buildApproachCFramesFromInteraction(interaction, 5)
			local standCFrame = standCFrames[1] or buildStandCFrameFromInteraction(interaction, 3)
			local distanceTarget = approachCFrames[1] or standCFrame
			local distance = math.huge
			if rootPart and distanceTarget then
				distance = getPlanarDistance(rootPart.Position, distanceTarget.Position)
			end
			table.insert(candidates, {
				boothId = record.boothId,
				booth = record.booth,
				interaction = interaction,
				standCFrame = standCFrame,
				standCFrames = standCFrames,
				approachCFrames = approachCFrames,
				distance = distance,
			})
		end
	end

	table.sort(candidates, function(a, b)
		if a.distance == b.distance then
			return a.boothId < b.boothId
		end
		return a.distance < b.distance
	end)

	pushDebug("BOOTH", string.format("Scan encontrou %d booth(s) livres", #candidates))
	return candidates
end

function BoothLogic.getClassicUnclaimedCandidates()
	local candidates = {}
	local boothFolder = getBoothUiFolder()
	local interactions = workspace:FindFirstChild("BoothInteractions")
	if not boothFolder or not interactions then
		return candidates
	end

	local rootPart = getRootPart()
	for _, booth in ipairs(boothFolder:GetChildren()) do
		local owner = booth:FindFirstChild("Details") and booth.Details:FindFirstChild("Owner")
		local boothId = extractBoothId(booth)
		if boothId and owner and normalizeGuiText(owner.Text) == "unclaimed" then
			local interaction = nil
			for _, candidateInteraction in ipairs(interactions:GetChildren()) do
				local slot = candidateInteraction:GetAttribute("BoothSlot")
				local slotMatches = slot == boothId or tostring(slot) == tostring(boothId)
				if slotMatches and candidateInteraction:IsA("BasePart") then
					local pos2D = Vector3.new(candidateInteraction.Position.X, 0, candidateInteraction.Position.Z)
					if getPlanarDistance(pos2D, CLASSIC_BOOTH_SCAN_CENTER) < CLASSIC_BOOTH_SCAN_RADIUS then
						interaction = candidateInteraction
						break
					end
				end
			end
			if not interaction then
				continue
			end

			local standCFrames = buildApproachCFramesFromInteraction(interaction, 3)
			local approachCFrames = buildApproachCFramesFromInteraction(interaction, 5)
			local standCFrame = standCFrames[1] or buildStandCFrameFromInteraction(interaction, 3)
			local distanceTarget = approachCFrames[1] or standCFrame
			local distance = math.huge
			if rootPart and distanceTarget then
				distance = getPlanarDistance(rootPart.Position, distanceTarget.Position)
			end
			table.insert(candidates, {
				boothId = boothId,
				booth = booth,
				interaction = interaction,
				standCFrame = standCFrame,
				standCFrames = standCFrames,
				approachCFrames = approachCFrames,
				distance = distance,
				classic = true,
				classicPriority = #candidates + 1,
			})
		end
	end

	table.sort(candidates, function(a, b)
		local aPriority = safeNumber(a.classicPriority, math.huge)
		local bPriority = safeNumber(b.classicPriority, math.huge)
		if aPriority == bPriority then
			return a.boothId < b.boothId
		end
		return aPriority < bPriority
	end)

	if #candidates >= 2 then
		local preferred = table.remove(candidates, 2)
		table.insert(candidates, 1, preferred)
	end

	pushDebug("BOOTH", string.format("Classic scan encontrou %d booth(s) livres", #candidates))
	return candidates
end

function BoothLogic.isStillUnclaimed(boothId)
	local booth = BoothLogic.findBoothById(boothId)
	return booth ~= nil and isBoothUnclaimed(booth)
end

function BoothLogic.clearCurrentBooth()
	runtime.boothId = nil
	runtime.boothAnchor = nil
end

function BoothLogic.clearBoothLock(reason)
	if runtime.boothLockId then
		pushDebug(
			"BOOTH",
			string.format("Lock da booth %s liberado%s", tostring(runtime.boothLockId), reason and (" | " .. tostring(reason)) or "")
		)
	end
	runtime.boothLockId = nil
	runtime.boothLockSince = 0
	runtime.boothLockFailures = 0
end

function BoothLogic.setBoothLock(boothId, reason)
	if runtime.boothLockId ~= boothId then
		runtime.boothLockId = boothId
		runtime.boothLockSince = os.clock()
		runtime.boothLockFailures = 0
		pushDebug(
			"BOOTH",
			string.format("Lock na booth %s%s", tostring(boothId), reason and (" | " .. tostring(reason)) or "")
		)
	elseif runtime.boothLockSince <= 0 then
		runtime.boothLockSince = os.clock()
	end
end

function BoothLogic.bumpBoothLockFailure(reason)
	runtime.boothLockFailures = safeNumber(runtime.boothLockFailures, 0) + 1
	pushDebug(
		"BOOTH",
		string.format(
			"Falha na booth travada %s | tentativa %d%s",
			tostring(runtime.boothLockId),
			runtime.boothLockFailures,
			reason and (" | " .. tostring(reason)) or ""
		)
	)
end

function BoothLogic.findCandidateById(candidates, boothId)
	for _, candidate in ipairs(candidates or {}) do
		if candidate.boothId == boothId then
			return candidate
		end
	end
	return nil
end

function BoothLogic.buildCandidateQueue(candidates)
	local queue = {}
	local seen = {}

	if runtime.boothLockId then
		local lockedCandidate = BoothLogic.findCandidateById(candidates, runtime.boothLockId)
		if lockedCandidate then
			table.insert(queue, lockedCandidate)
			seen[lockedCandidate.boothId] = true
			pushDebug("BOOTH", "Tentando novamente a booth travada " .. tostring(lockedCandidate.boothId))
		else
			BoothLogic.clearBoothLock("booth travada nao esta mais livre")
		end
	end

	for _, candidate in ipairs(candidates or {}) do
		if not seen[candidate.boothId] then
			table.insert(queue, candidate)
			seen[candidate.boothId] = true
		end
	end

	return queue
end

function BoothLogic.moveToCandidate(candidate)
	if not candidate then
		return false, "Booth candidate missing"
	end

	local rootPart = getRootPart()
	local targetCFrames = {}
	for _, cframe in ipairs(candidate.approachCFrames or {}) do
		table.insert(targetCFrames, cframe)
	end
	for _, cframe in ipairs(candidate.standCFrames or {}) do
		table.insert(targetCFrames, cframe)
	end
	if #targetCFrames == 0 and candidate.standCFrame then
		table.insert(targetCFrames, candidate.standCFrame)
	end
	if #targetCFrames == 0 then
		return false, "Booth approach missing"
	end

	table.sort(targetCFrames, function(a, b)
		if not rootPart then
			return tostring(a) < tostring(b)
		end
		return getPlanarDistance(rootPart.Position, a.Position) < getPlanarDistance(rootPart.Position, b.Position)
	end)

	local lastErr = "Booth approach missing"
	for index, targetCFrame in ipairs(targetCFrames) do
		local currentRoot = getRootPart() or rootPart
		if not currentRoot then
			return false, "Character unavailable"
		end

		local targetDistance = getPlanarDistance(currentRoot.Position, targetCFrame.Position)
		local walkTimeout = math.max(8, targetDistance / 7 + 6)
		pushDebug(
			"BOOTH",
			string.format(
				"Indo andando para booth %s | ponto %d/%d | distancia %.1f | timeout %.1fs",
				tostring(candidate.boothId),
				index,
				#targetCFrames,
				targetDistance,
				walkTimeout
			)
		)

		local walked, walkErr = walkCharacterToCFrame(targetCFrame, walkTimeout, 4)
		if walked then
			return true
		end
		lastErr = walkErr or lastErr
	end

	return false, lastErr
end

function BoothLogic.getPromptFromInteraction(interaction)
	if not interaction then
		return nil
	end

	if interaction:IsA("ProximityPrompt") then
		return interaction
	end

	local prompt = interaction:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		return prompt
	end

	local parent = interaction.Parent
	if parent then
		return parent:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	return nil
end

function BoothLogic.getPromptForCandidate(candidate)
	if not candidate then
		return nil
	end

	local directPrompt = BoothLogic.getPromptFromInteraction(candidate.interaction)
	if directPrompt then
		return directPrompt
	end

	local roots = {}
	local seen = {}
	local function push(instance)
		if instance and not seen[instance] then
			seen[instance] = true
			table.insert(roots, instance)
		end
	end

	push(candidate.interaction)
	push(candidate.booth)
	local parent = candidate.interaction and candidate.interaction.Parent or nil
	for _ = 1, 4 do
		if not parent then
			break
		end
		push(parent)
		parent = parent.Parent
	end

	for _, root in ipairs(roots) do
		local prompt = root:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			return prompt
		end
	end

	return nil
end

function BoothLogic.getClickDetectorFromInteraction(interaction)
	if not interaction then
		return nil
	end

	if interaction:IsA("ClickDetector") then
		return interaction
	end

	local detector = interaction:FindFirstChildWhichIsA("ClickDetector", true)
	if detector then
		return detector
	end

	local parent = interaction.Parent
	if parent then
		return parent:FindFirstChildWhichIsA("ClickDetector", true)
	end

	return nil
end

function BoothLogic.getTouchPartFromInteraction(interaction)
	if not interaction then
		return nil
	end

	if interaction:IsA("BasePart") then
		return interaction
	end

	local parent = interaction.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end

	return interaction:FindFirstChildWhichIsA("BasePart", true)
end

function BoothLogic.attemptPromptClaim(candidate)
	local prompt = BoothLogic.getPromptForCandidate(candidate)
	if not prompt then
		return false
	end

	local holdDuration = math.max(0.35, safeNumber(prompt.HoldDuration, 0) + 0.15)
	local okHold = pcall(function()
		prompt:InputHoldBegin()
		task.wait(holdDuration)
		prompt:InputHoldEnd()
		task.wait(0.2)
	end)
	if okHold then
		pushDebug(
			"BOOTH",
			string.format("Claim por Prompt hold em booth %s | hold %.2fs", tostring(candidate.boothId), holdDuration)
		)
		return true
	end

	if fireproximityprompt then
		local okFire = pcall(function()
			fireproximityprompt(prompt)
		end)
		if okFire then
			pushDebug("BOOTH", "Claim por fireproximityprompt em booth " .. tostring(candidate.boothId))
			return true
		end
	end

	local okFallback = pcall(function()
		prompt:InputHoldBegin()
		task.wait(0.75)
		prompt:InputHoldEnd()
		task.wait(0.2)
	end)
	if okFallback then
		pushDebug("BOOTH", "Claim por Prompt fallback em booth " .. tostring(candidate.boothId))
	end
	return okFallback
end

function BoothLogic.attemptClickDetectorClaim(candidate)
	local detector = BoothLogic.getClickDetectorFromInteraction(candidate and candidate.interaction or nil)
	if not detector or not fireclickdetector then
		return false
	end

	local ok = pcall(function()
		fireclickdetector(detector)
	end)
	if ok then
		pushDebug("BOOTH", "Claim por ClickDetector em booth " .. tostring(candidate.boothId))
	end
	return ok
end

function BoothLogic.attemptTouchClaim(candidate)
	local rootPart = getRootPart()
	local touchPart = BoothLogic.getTouchPartFromInteraction(candidate and candidate.interaction or nil)
	if not rootPart or not touchPart or not firetouchinterest then
		return false
	end

	local ok = pcall(function()
		firetouchinterest(rootPart, touchPart, 0)
		task.wait(0.1)
		firetouchinterest(rootPart, touchPart, 1)
	end)
	if ok then
		pushDebug("BOOTH", "Claim por TouchInterest em booth " .. tostring(candidate.boothId))
	end
	return ok
end

function BoothLogic.attemptRemoteClaim(candidate)
	local boothId = candidate and candidate.boothId or nil
	local remoteNames = { "ClaimBooth", "ClaimStand", "TakeBooth", "InteractBooth" }
	for _, remoteName in ipairs(remoteNames) do
		local claimed = invokeRemoteEvent(remoteName, boothId)
		if claimed ~= false then
			pushDebug("BOOTH", string.format("Claim remoto %s em booth %s", tostring(remoteName), tostring(boothId)))
			return true
		end
	end
	return false
end

function BoothLogic.attemptClassicRemoteClaim(candidate)
	if not candidate or not candidate.boothId then
		return false
	end

	local claimed = invokeRemoteEvent("ClaimBooth", candidate.boothId)
	if claimed ~= false then
		pushDebug("BOOTH", "Classic ClaimBooth remoto em booth " .. tostring(candidate.boothId), true)
		return true
	end

	return false
end

function BoothLogic.waitForClaimConfirmation(boothId, timeoutSeconds, booth)
	local deadline = os.clock() + math.max(1, safeNumber(timeoutSeconds, 5))
	repeat
		task.wait(0.25)
		if booth and isBoothOwnedByLocal(booth) then
			runtime.boothId = boothId
			BoothLogic.refreshAnchor()
			BoothLogic.clearBoothLock("claim confirmado pelo owner direto")
			pushDebug("BOOTH", "Booth capturada com sucesso: " .. tostring(boothId), true)
			return true
		end

		local ownedId = BoothLogic.findOwnedBooth()
		if ownedId == boothId then
			runtime.boothId = ownedId
			BoothLogic.refreshAnchor()
			BoothLogic.clearBoothLock("claim confirmado")
			pushDebug("BOOTH", "Booth capturada com sucesso: " .. tostring(boothId), true)
			return true
		end

		if booth and not isBoothUnclaimed(booth) then
			BoothLogic.clearBoothLock("booth classica foi ocupada durante confirmacao")
			pushDebug("BOOTH", "Booth " .. tostring(boothId) .. " foi ocupada durante a confirmacao")
			return false
		end

		if not booth and not BoothLogic.isStillUnclaimed(boothId) then
			BoothLogic.clearBoothLock("booth foi ocupada durante confirmacao")
			pushDebug("BOOTH", "Booth " .. tostring(boothId) .. " foi ocupada durante a confirmacao")
			return false
		end
	until os.clock() >= deadline

	return false
end

function BoothLogic.attemptClaimMethods(candidate)
	local prompt = BoothLogic.getPromptForCandidate(candidate)
	if prompt then
		pushDebug("BOOTH", "Booth " .. tostring(candidate.boothId) .. " tem ProximityPrompt; priorizando hold do E")
		return BoothLogic.attemptPromptClaim(candidate)
	end

	local attemptedAny = false

	if BoothLogic.attemptRemoteClaim(candidate) then
		attemptedAny = true
	end
	if BoothLogic.attemptClickDetectorClaim(candidate) then
		attemptedAny = true
	end
	if BoothLogic.attemptTouchClaim(candidate) then
		attemptedAny = true
	end

	return attemptedAny
end

function BoothLogic.positionAtBooth(interaction)
	local standCFrames = buildApproachCFramesFromInteraction(interaction, 3)
	local standCFrame = standCFrames[1] or buildStandCFrameFromInteraction(interaction, 3)
	if not standCFrame then
		return false, "Booth stand position missing"
	end

	placeCharacterAtCFrame(standCFrame)
	return true
end

function BoothLogic.walkClassicToCandidate(candidate)
	if not candidate or not candidate.interaction then
		return false, "Classic booth interaction missing"
	end

	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart then
		return false, "Character unavailable"
	end

	local standCFrame = candidate.standCFrame or (candidate.standCFrames and candidate.standCFrames[1])
		or buildStandCFrameFromInteraction(candidate.interaction, 3)
	if not standCFrame then
		return false, "Classic stand position missing"
	end

	local targetPosition = Vector3.new(standCFrame.Position.X, rootPart.Position.Y, standCFrame.Position.Z)
	local reached = false
	local originalWalkSpeed = humanoid.WalkSpeed
	local connection
	connection = humanoid.MoveToFinished:Connect(function()
		reached = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end)

	humanoid.WalkSpeed = math.max(humanoid.WalkSpeed, 20)
	humanoid:MoveTo(targetPosition)

	local deadline = os.clock() + estimateWalkTimeout(rootPart.Position, targetPosition, 8)
	repeat
		rootPart = getRootPart()
		if rootPart and getPlanarDistance(rootPart.Position, targetPosition) <= 4 then
			reached = true
			break
		end
		task.wait(0.1)
	until reached or os.clock() >= deadline

	if connection then
		connection:Disconnect()
	end

	pcall(function()
		humanoid.WalkSpeed = originalWalkSpeed
	end)

	if reached then
		placeCharacterAtCFrame(standCFrame)
		return true
	end

	return false, "Classic walk timeout"
end

function BoothLogic.refreshAnchor()
	if not runtime.boothId then
		local ownedId = BoothLogic.findOwnedBooth()
		runtime.boothId = ownedId
	end
	if not runtime.boothId then
		runtime.boothAnchor = nil
		return nil
	end

	local interaction = BoothLogic.getInteractionById(runtime.boothId)
	local standCFrame = (buildApproachCFramesFromInteraction(interaction, 3))[1] or buildStandCFrameFromInteraction(interaction, 3)
	if not standCFrame then
		runtime.boothAnchor = nil
		return nil
	end

runtime.boothAnchor = standCFrame
	return runtime.boothAnchor
end

local faceBooth

function BoothLogic.walkToBooth()
	local anchor = runtime.boothAnchor or BoothLogic.refreshAnchor()
	if not anchor then
		pushDebug("BOOTH", "Anchor da booth nao encontrada")
		return false, "Booth anchor missing"
	end

	local walked, walkErr = walkCharacterToCFrame(anchor, 10, 4)
	if walked == false then
		pushDebug("BOOTH", "Nao consegui reposicionar na booth: " .. tostring(walkErr))
		return false, "Failed to reach booth"
	end

	local interaction = runtime.boothId and BoothLogic.getInteractionById(runtime.boothId) or nil
	if interaction then
		BoothLogic.positionAtBooth(interaction)
		faceBooth()
	end
	runtime.lastBoothReturnAt = os.clock()
	return true
end

function BoothLogic.randomizePositionAtBooth()
	local interaction = runtime.boothId and BoothLogic.getInteractionById(runtime.boothId) or nil
	if not interaction then
		return false, "Booth interaction missing"
	end

	local standCFrames = buildApproachCFramesFromInteraction(interaction, 3)
	if #standCFrames == 0 then
		return false, "Booth positions missing"
	end

	local targetCFrame = standCFrames[math.random(1, #standCFrames)]
	local walked = walkCharacterToCFrame(targetCFrame, 4, 3)
	placeCharacterAtCFrame(targetCFrame)
	faceBooth()
	return walked ~= false
end

local function disableAutoClaimBooth()
	if runtime.autoClaimFinished then
		return
	end

	settings.autoClaimBooth = false
	runtime.autoClaimFinished = true
	runtime.lastBoothReturnAt = os.clock()
	pushDebug("BOOTH", "Auto claim desligado apos claim completo e posicionamento na booth", true)
	notify("Milo MFS", "Auto claim booth disabled", 4)
end

function BoothLogic.claimBooth()
	if runtime.boothClaimInProgress and os.clock() - safeNumber(runtime.lastBoothClaimAt, 0) > 20 then
		runtime.boothClaimInProgress = false
		pushDebug("BOOTH", "Claim lock antigo liberado automaticamente")
	end

	if runtime.boothClaimInProgress then
		pushDebug("BOOTH", "Claim ignorado porque ja existe uma tentativa em andamento")
		return false, "Claim already in progress"
	end

	runtime.boothClaimInProgress = true
	runtime.lastBoothClaimAt = os.clock()
	BoothLogic.waitUntilReady(10)
	pushDebug("BOOTH", "Busca manual por booth iniciada", true)

	local ownedId = BoothLogic.findOwnedBooth()
	if ownedId then
		runtime.boothId = ownedId
		BoothLogic.refreshAnchor()
		BoothLogic.clearBoothLock("booth ja esta propria")
		runtime.lastBoothReturnAt = os.clock()
		pushDebug("BOOTH", "Ja existe uma booth propria: " .. tostring(ownedId), true)
		runtime.boothClaimInProgress = false
		return true
	end

	BoothLogic.clearCurrentBooth()

	local boothFolder = waitForBoothUiFolder(12)
	if not boothFolder then
		pushDebug("BOOTH", "Booth UI nao encontrada", true)
		runtime.boothClaimInProgress = false
		return false, "Booth UI not found"
	end

	local candidates = BoothLogic.getClassicUnclaimedCandidates()
	if #candidates == 0 then
		BoothLogic.clearBoothLock("nenhuma booth livre no scan")
		pushDebug("BOOTH", "Nenhuma booth livre acessivel encontrada no scan classico", true)
		runtime.boothClaimInProgress = false
		return false, "No accessible unclaimed booth found"
	end

	local queue = BoothLogic.buildCandidateQueue(candidates)

	for _, candidate in ipairs(queue) do
		if isBoothUnclaimed(candidate.booth) then
			BoothLogic.setBoothLock(candidate.boothId, "classic claim antes de andar")
			pushDebug("BOOTH", "Classic claim direto na booth acessivel " .. tostring(candidate.boothId), true)
			local claimed = BoothLogic.attemptClassicRemoteClaim(candidate)
			if claimed and BoothLogic.waitForClaimConfirmation(candidate.boothId, 3.5, candidate.booth) then
				runtime.boothClaimInProgress = false
				return true
			end
			BoothLogic.bumpBoothLockFailure("classic claim nao confirmou")
			BoothLogic.clearBoothLock("classic claim falhou, tentando proxima booth acessivel")
		end
	end

	local fallbackOwnedId = BoothLogic.findOwnedBooth()
	if fallbackOwnedId then
		runtime.boothId = fallbackOwnedId
		BoothLogic.refreshAnchor()
		runtime.lastBoothReturnAt = os.clock()
		BoothLogic.walkToBooth()
		BoothLogic.clearBoothLock("fallback encontrou booth propria")
		pushDebug("BOOTH", "Encontrada booth ja atribuida no fallback: " .. tostring(fallbackOwnedId), true)
		runtime.boothClaimInProgress = false
		return true
	end

	BoothLogic.clearBoothLock("todas as booths da fila falharam")
	pushDebug("BOOTH", "Claim manual falhou em todas as booths livres", true)
	runtime.boothClaimInProgress = false
	return false, "Failed to claim booth"
end

faceTowards = function(targetPosition)
	local rootPart = getRootPart()
	if not rootPart then
		return
	end
	local lookPosition = Vector3.new(targetPosition.X, rootPart.Position.Y, targetPosition.Z)
	rootPart.CFrame = CFrame.new(rootPart.Position, lookPosition)
end

local function getBoothLookTarget()
	local interaction = runtime.boothId and BoothLogic.getInteractionById(runtime.boothId) or nil
	local pivot = interaction and getInteractionPivot(interaction) or runtime.boothAnchor
	return pivot and pivot.Position or nil
end

faceBooth = function()
	local lookTarget = getBoothLookTarget()
	if lookTarget then
		faceTowards(lookTarget)
	end
end

local function moveNearPosition(targetPosition, followDistance)
	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart then
		return false
	end

	local currentPosition = rootPart.Position
	local flatDelta = Vector3.new(targetPosition.X - currentPosition.X, 0, targetPosition.Z - currentPosition.Z)
	local magnitude = flatDelta.Magnitude
	if magnitude < 0.15 then
		faceTowards(targetPosition)
		return true
	end

	local direction = flatDelta.Unit
	local desired = targetPosition - direction * followDistance
	humanoid:MoveTo(Vector3.new(desired.X, currentPosition.Y, desired.Z))
	faceTowards(targetPosition)
	return true
end

local function getDonateWebhookMood(amount)
	local donateAmount = safeNumber(amount, 0)
	if donateAmount >= 2500 then
		return "FELICIDADE MAXIMAAAAA 2.5K", 0xFFD700
	end
	if donateAmount >= 1500 then
		return "ABSURDAMENTE FELIZZZZZ", 0xF1C40F
	end
	if donateAmount >= 1000 then
		return "EXTREMAMENTE FELIZZZZ", 0xE67E22
	end
	if donateAmount >= 750 then
		return "MEGA FELIZZZZ", 0xE74C3C
	end
	if donateAmount >= 500 then
		return "ULTRA FELIZZZ", 0x9B59B6
	end
	if donateAmount >= 250 then
		return "SUPER HIPER FELIZZZ", 0x8E44AD
	end
	if donateAmount >= 126 then
		return "SUPER FELIZZZZZ", 0x57F287
	end
	if donateAmount >= 51 then
		return "MUITO FELIZZZ", 0x2ECC71
	end
	if donateAmount >= 26 then
		return "FELIZZZ", 0x5865F2
	end
	return "OK", 0x3498DB
end

local function buildDonateWebhookMessage(donorText, recipientText, amount)
	local mood = getDonateWebhookMood(amount)
	return string.format(
		"@Milokinot %s | de %s para %s | doou %s R$",
		tostring(mood),
		tostring(donorText),
		tostring(recipientText),
		tostring(amount)
	)
end

local function handleDonation(amount, newTotal)
	if amount <= 0 then
		return
	end

	local donationMeta = consumePendingDonation(amount)
	local donorText = donationMeta and donationMeta.donor or "Unknown"
	local recipientText = donationMeta and donationMeta.recipient
		or string.format("%s (@%s)", tostring(LocalPlayer.DisplayName), tostring(LocalPlayer.Name))

	local message = string.format(
		"Donate recebido | De: %s | Para: %s | Quantia: %s R$ | Total: %s R$",
		tostring(donorText),
		tostring(recipientText),
		tostring(amount),
		tostring(newTotal)
	)

	runtime.lastDonationText = message
	if refreshStatus then
		refreshStatus()
	end

	if settings.donatePopup then
		notify("Milo MFS", message, 6)
	end

	pushDebug("DONATE", message, true)

	local webhookMood, webhookColor = getDonateWebhookMood(amount)
	local webhookMessage = buildDonateWebhookMessage(donorText, recipientText, amount)

	sendWebhook(webhookMessage, {
		title = webhookMood,
		description = string.format("%s doou para %s", tostring(donorText), tostring(recipientText)),
		color = webhookColor,
		fields = {
			{ name = "De", value = tostring(donorText), inline = true },
			{ name = "Para", value = tostring(recipientText), inline = true },
			{ name = "Quantia", value = tostring(amount) .. " R$", inline = true },
			{ name = "Total Atual", value = tostring(newTotal) .. " R$", inline = true },
			{ name = "PlaceId", value = tostring(game.PlaceId), inline = true },
			{
				name = "Player",
				value = string.format("%s (@%s)", tostring(LocalPlayer.DisplayName), tostring(LocalPlayer.Name)),
				inline = true,
			},
		},
	})
end

local function returnToBooth()
	if not settings.boothLocality then
		return
	end
	if not runtime.boothId or runtime.boothReturnInProgress then
		return
	end
	local anchor = runtime.boothAnchor or BoothLogic.refreshAnchor()
	local rootPart = getRootPart()
	local humanoid = getHumanoid()
	if not anchor or not rootPart or not humanoid then
		return
	end

	local lastReturnAt = safeNumber(runtime.lastBoothReturnAt, 0)
	if lastReturnAt <= 0 then
		runtime.lastBoothReturnAt = os.clock()
		return
	end

	if os.clock() - lastReturnAt < BOOTH_FREE_TIME then
		return
	end

	runtime.boothReturnInProgress = true
	runtime.lastBoothReturnAt = os.clock()

	if not runtime.boothReturnSpeedActive then
		runtime.boothReturnOriginalSpeed = humanoid.WalkSpeed
		runtime.boothReturnSpeedActive = true
	end
	humanoid.WalkSpeed = math.max(humanoid.WalkSpeed, safeNumber(settings.fastBoothReturnSpeed, FAST_BOOTH_RETURN_SPEED))

	if not runtime.boothReturnNoticeSent then
		runtime.boothReturnNoticeSent = true
		pushDebug("BOOTH", string.format("Retorno para booth acionado apos %d segundos", BOOTH_FREE_TIME))
	end

	local walked = walkCharacterToCFrame(anchor, 18, 5)
	if walked ~= false then
		local interaction = runtime.boothId and BoothLogic.getInteractionById(runtime.boothId) or nil
		if interaction then
			BoothLogic.positionAtBooth(interaction)
		end
		faceBooth()
	else
		pushDebug("BOOTH", "Retorno para booth falhou na caminhada longa; tentando walkToBooth padrao")
		BoothLogic.walkToBooth()
	end

	humanoid = getHumanoid()
	if humanoid and runtime.boothReturnSpeedActive then
		humanoid.WalkSpeed = runtime.boothReturnOriginalSpeed or 16
	end
	runtime.boothReturnOriginalSpeed = nil
	runtime.boothReturnSpeedActive = false
	runtime.boothReturnNoticeSent = false
	runtime.boothReturnInProgress = false
end

local function stopLoop(name)
	local thread = runtime.loops[name]
	if thread then
		task.cancel(thread)
		runtime.loops[name] = nil
	end
end

local function startLoop(name, callback)
	stopLoop(name)
	runtime.loops[name] = task.spawn(callback)
end

local function stopAllLoops()
	for name in pairs(runtime.loops) do
		stopLoop(name)
	end
end

local function getCurrentPopulation()
	return #Services.Players:GetPlayers()
end

local function formatPercent(value)
	return string.format("%.0f%%", math.clamp(safeNumber(value, 0), 0, 100))
end

local function updateServerAuditText(text)
	runtime.serverAuditText = tostring(text or "Server audit idle")
	pushDebug("SERVER", runtime.serverAuditText)
	if refreshStatus then
		refreshStatus()
	end
end

local function decodeJson(raw)
	local ok, decoded = pcall(function()
		return Services.HttpService:JSONDecode(raw)
	end)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

local function queueScriptOnTeleport()
	if type(executor.queueOnTeleport) ~= "function" then
		return false, "queue_on_teleport unavailable"
	end

	local ok, err = pcall(function()
		executor.queueOnTeleport(TELEPORT_LOADSTRING)
	end)
	if not ok then
		return false, tostring(err or "queue_on_teleport failed")
	end

	return true
end

local function fetchPublicServers(cursor)
	local url = string.format(
		"https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Desc&limit=100",
		tostring(game.PlaceId)
	)
	if type(cursor) == "string" and cursor ~= "" then
		url = url .. "&cursor=" .. Services.HttpService:UrlEncode(cursor)
	end

	local body = rawHttpGet(url)
	if type(body) ~= "string" or body == "" then
		return nil
	end

	return decodeJson(body)
end

local function findPreferredServer()
	local targetMin = safeNumber(settings.serverTargetMinPlayers, 20)
	local targetMax = safeNumber(settings.serverTargetMaxPlayers, 25)
	if targetMin > targetMax then
		targetMin, targetMax = targetMax, targetMin
	end

	local bestExact = {}
	local bestFallback = {}
	local cursor = nil
	for _ = 1, 5 do
		local page = fetchPublicServers(cursor)
		if not page or type(page.data) ~= "table" then
			break
		end

		for _, server in ipairs(page.data) do
			local serverId = tostring(server.id or "")
			local playing = safeNumber(server.playing, 0)
			local maxPlayers = safeNumber(server.maxPlayers, 0)
			if serverId ~= "" and serverId ~= tostring(game.JobId) and playing < maxPlayers then
				local entry = {
					id = serverId,
					playing = playing,
					maxPlayers = maxPlayers,
					ping = safeNumber(server.ping, 9999),
				}
				if playing >= targetMin and playing <= targetMax then
					table.insert(bestExact, entry)
				elseif playing >= safeNumber(settings.serverMinPlayers, 18) then
					table.insert(bestFallback, entry)
				end
			end
		end

		cursor = page.nextPageCursor
		if #bestExact > 0 or type(cursor) ~= "string" or cursor == "" then
			break
		end
	end

	local pool = #bestExact > 0 and bestExact or bestFallback
	table.sort(pool, function(a, b)
		if a.playing == b.playing then
			return a.ping < b.ping
		end
		return a.playing > b.playing
	end)

	return pool[1] or nil
end

local function hopToPreferredServer(reason)
	if runtime.serverHopInProgress then
		return false, "Teleport already in progress"
	end

	local target = findPreferredServer()
	if not target then
		updateServerAuditText("No public server 20-25 found")
		return false, "No preferred server found"
	end

	runtime.serverHopInProgress = true
	updateServerAuditText(string.format("Teleporting to %d/%d players...", target.playing, target.maxPlayers))

	local queueOk, queueErr = queueScriptOnTeleport()
	if not queueOk and queueErr then
		warn("[Milo MFS] Teleport queue skipped: " .. tostring(queueErr))
	end

	notify("Milo MFS", reason or string.format("Switching to %d player server", target.playing), 5)

	local ok, err = pcall(function()
		Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LocalPlayer)
	end)
	if not ok then
		runtime.serverHopInProgress = false
		updateServerAuditText("Teleport failed")
		return false, err
	end

	return true
end

local function joinMilokinotExperience()
	local okUser, targetUserId = pcall(function()
		return Services.Players:GetUserIdFromNameAsync("Milokinot")
	end)
	if not okUser or not targetUserId then
		return false, "Nao consegui localizar Milokinot"
	end

	local okPlace, currentInstance, _, placeId, jobId = pcall(function()
		return Services.TeleportService:GetPlayerPlaceInstanceAsync(targetUserId)
	end)
	if not okPlace then
		return false, "Nao consegui verificar onde Milokinot esta"
	end

	if not currentInstance or not placeId or not jobId or tostring(jobId) == "" then
		return false, "Milokinot nao esta em uma experiencia acessivel agora"
	end

	if tonumber(placeId) == tonumber(game.PlaceId) and tostring(jobId) == tostring(game.JobId) then
		return false, "Voce ja esta na mesma instancia do Milokinot"
	end

	local queueOk, queueErr = queueScriptOnTeleport()
	if not queueOk and queueErr then
		warn("[Milo MFS] Teleport queue skipped: " .. tostring(queueErr))
	end

	local okTeleport, teleportErr = pcall(function()
		Services.TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
	end)
	if not okTeleport then
		return false, tostring(teleportErr or "Teleport falhou")
	end

	return true
end

local function collectPlayerMotionStats(trackers)
	for _, player in ipairs(Services.Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and rootPart and humanoid.Health > 0 then
				local flatPosition = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
				local tracker = trackers[player.UserId]
				if not tracker then
					tracker = {
						name = tostring(player.Name),
						isPremium = player.MembershipType == Enum.MembershipType.Premium,
						samples = 0,
						activeSamples = 0,
						totalDistance = 0,
						directionChanges = 0,
						startPosition = flatPosition,
						lastPosition = flatPosition,
						lastDirection = nil,
					}
					trackers[player.UserId] = tracker
				end
				tracker.isPremium = player.MembershipType == Enum.MembershipType.Premium

				tracker.samples = tracker.samples + 1
				local delta = flatPosition - tracker.lastPosition
				local distance = delta.Magnitude
				if distance >= 1 then
					tracker.activeSamples = tracker.activeSamples + 1
					tracker.totalDistance = tracker.totalDistance + distance
					local direction = delta.Unit
					if tracker.lastDirection and direction:Dot(tracker.lastDirection) < 0.1 then
						tracker.directionChanges = tracker.directionChanges + 1
					end
					tracker.lastDirection = direction
				end
				tracker.lastPosition = flatPosition
			end
		end
	end
end

local function countPremiumPlayers()
	local premiumCount = 0
	for _, player in ipairs(Services.Players:GetPlayers()) do
		if player ~= LocalPlayer and player.MembershipType == Enum.MembershipType.Premium then
			premiumCount = premiumCount + 1
		end
	end
	return premiumCount
end

local function getPremiumPlayerNames()
	local names = {}
	for _, player in ipairs(Services.Players:GetPlayers()) do
		if player ~= LocalPlayer and player.MembershipType == Enum.MembershipType.Premium then
			table.insert(names, string.format("%s (@%s)", tostring(player.DisplayName), tostring(player.Name)))
		end
	end
	table.sort(names)
	return names
end

local function getServerQualityScore(activePremiums, premiumAfkCount, donationPower)
	local score = 0
	score = score + safeNumber(activePremiums, 0) * 25
	score = score + safeNumber(premiumAfkCount, 0) * 5
	score = score + math.min(safeNumber(donationPower, 0) * 1.5, 150)
	return math.floor(score + 0.5)
end

local function isBetterServerReport(candidate, currentBest)
	if not candidate then
		return false
	end
	if not currentBest then
		return true
	end

	local candidatePremiums = safeNumber(candidate.premiumCount, 0)
	local bestPremiums = safeNumber(currentBest.premiumCount, 0)
	if candidatePremiums ~= bestPremiums then
		return candidatePremiums > bestPremiums
	end

	local candidateActivePremiums = safeNumber(candidate.activePremiums, 0)
	local bestActivePremiums = safeNumber(currentBest.activePremiums, 0)
	if candidateActivePremiums ~= bestActivePremiums then
		return candidateActivePremiums > bestActivePremiums
	end

	return safeNumber(candidate.serverQualityScore, 0) > safeNumber(currentBest.serverQualityScore, 0)
end

local function summarizeServerAudit(trackers, baselinePopulation, peakPopulation, auditStartedAt)
	local observedCount = 0
	local suspiciousCount = 0
	local afkCount = 0
	local botCount = 0
	local premiumCount = countPremiumPlayers()
	local observedPremiums = 0
	local premiumAfkCount = 0
	local activePremiums = 0

	for _, tracker in pairs(trackers) do
		if safeNumber(tracker.samples, 0) >= 3 then
			observedCount = observedCount + 1

			local activeRatio = tracker.activeSamples / math.max(1, tracker.samples)
			local netDistance = getPlanarDistance(tracker.startPosition, tracker.lastPosition)
			local isAfk = tracker.totalDistance < 6 or activeRatio < 0.15
			local isBot = activeRatio >= 0.75
				and tracker.directionChanges >= math.max(3, math.floor(tracker.samples * 0.25))
				and netDistance <= (tracker.totalDistance * 0.55)

			if isAfk then
				afkCount = afkCount + 1
			end
			if tracker.isPremium then
				observedPremiums = observedPremiums + 1
				if isAfk then
					premiumAfkCount = premiumAfkCount + 1
				else
					activePremiums = activePremiums + 1
				end
			end
			if isBot then
				botCount = botCount + 1
			end
			if isAfk or isBot then
				suspiciousCount = suspiciousCount + 1
			end
		end
	end

	local finalPopulation = getCurrentPopulation()
	local suspiciousRatio = observedCount > 0 and (suspiciousCount / observedCount) or 0
	local robuxDonatedDuringAudit, donationCount, biggestDonation = getServerDonationsSince(auditStartedAt)
	local serverQualityScore = getServerQualityScore(activePremiums, premiumAfkCount, robuxDonatedDuringAudit)
	local minPremiums = safeNumber(settings.serverMinPremiums, 5)
	local minActivePremiums = safeNumber(settings.serverMinActivePremiums, 3)
	local donationStayThreshold = safeNumber(settings.serverDonationStayThreshold, 80)
	local qualityStayScore = safeNumber(settings.serverQualityStayScore, 90)
	local shouldStay = (premiumCount >= minPremiums and activePremiums >= minActivePremiums)
		or (premiumCount < minPremiums and robuxDonatedDuringAudit >= donationStayThreshold)
		or serverQualityScore >= qualityStayScore
	local summary = string.format(
		"Players %d->%d (peak %d) | Premium %d (%d active/%d AFK) | Donate %d R$ | Score %d | %s",
		baselinePopulation,
		finalPopulation,
		peakPopulation,
		premiumCount,
		activePremiums,
		premiumAfkCount,
		robuxDonatedDuringAudit,
		serverQualityScore,
		shouldStay and "STAY" or "HOP"
	)

	return {
		baselinePopulation = baselinePopulation,
		finalPopulation = finalPopulation,
		peakPopulation = peakPopulation,
		observedCount = observedCount,
		suspiciousCount = suspiciousCount,
		suspiciousRatio = suspiciousRatio,
		afkCount = afkCount,
		botCount = botCount,
		premiumCount = premiumCount,
		observedPremiums = observedPremiums,
		activePremiums = activePremiums,
		premiumAfkCount = premiumAfkCount,
		robuxDonatedDuringAudit = robuxDonatedDuringAudit,
		donationCount = donationCount,
		biggestDonation = biggestDonation,
		serverQualityScore = serverQualityScore,
		shouldStay = shouldStay,
		jobId = tostring(game.JobId),
		summary = summary,
	}
end

local function performServerAudit()
	if runtime.serverAuditInProgress then
		return nil, "Server audit already running"
	end

	runtime.serverAuditInProgress = true
	local ok, result = pcall(function()
		local baselinePopulation = getCurrentPopulation()
		local peakPopulation = baselinePopulation
		local trackers = {}
		local auditStartedAt = os.clock()
		local durationSeconds = math.max(60, safeNumber(settings.serverAuditMinutes, 5) * 60)
		local sampleInterval = math.max(2, safeNumber(settings.serverSampleInterval, 5))
		local deadline = os.clock() + durationSeconds

		repeat
			local population = getCurrentPopulation()
			if population > peakPopulation then
				peakPopulation = population
			end

			collectPlayerMotionStats(trackers)
			updateServerAuditText(string.format(
				"Auditing server... %ds left | Players %d | Premium %d",
				math.max(0, math.ceil(deadline - os.clock())),
				population,
				countPremiumPlayers()
			))
			task.wait(sampleInterval)
		until os.clock() >= deadline or runtime.serverHopInProgress

		return summarizeServerAudit(trackers, baselinePopulation, peakPopulation, auditStartedAt)
	end)
	runtime.serverAuditInProgress = false

	if not ok then
		updateServerAuditText("Server audit error")
		return nil, result
	end

	runtime.lastServerReport = result
	if isBetterServerReport(result, runtime.bestServerReport) then
		runtime.bestServerReport = result
		pushDebug("SERVER", "Best server atualizado: " .. tostring(result.summary), true)
	end
	updateServerAuditText(result.summary)
	return result
end

local function serverAuditLoop()
	while true do
		if settings.serverAuditEnabled and not runtime.serverHopInProgress then
			local minPlayers = safeNumber(settings.serverMinPlayers, 18)
			local currentPopulation = getCurrentPopulation()

			if currentPopulation < minPlayers then
				updateServerAuditText(string.format(
					"Low population: %d/%d. Looking for %d-%d...",
					currentPopulation,
					minPlayers,
					safeNumber(settings.serverTargetMinPlayers, 20),
					safeNumber(settings.serverTargetMaxPlayers, 25)
				))
				local _, hopErr = hopToPreferredServer(
					string.format("Server below %d players (%d online)", minPlayers, currentPopulation)
				)
				if hopErr then
					warn("[Milo MFS] " .. tostring(hopErr))
				end
				task.wait(math.max(10, safeNumber(settings.serverHopRetryDelay, 15)))
			else
				local baselinePopulation = currentPopulation
				local report, auditErr = performServerAudit()
				if not report then
					if auditErr then
						warn("[Milo MFS] " .. tostring(auditErr))
					end
					task.wait(5)
				else
					local targetMin = safeNumber(settings.serverTargetMinPlayers, 20)
					local minPlayers = safeNumber(settings.serverMinPlayers, 18)
					local shouldGrow = baselinePopulation < targetMin
					local populationTooWeak = report.finalPopulation < minPlayers
					local populationStagnated = shouldGrow
						and (report.peakPopulation <= baselinePopulation or report.finalPopulation < baselinePopulation)

					if populationTooWeak or populationStagnated then
						local _, hopErr = hopToPreferredServer("Population stagnated or dropped after 5 min")
						if hopErr then
							warn("[Milo MFS] " .. tostring(hopErr))
						end
						task.wait(math.max(10, safeNumber(settings.serverHopRetryDelay, 15)))
					else
						if not report.shouldStay then
							local _, hopErr = hopToPreferredServer(string.format(
								"Server fraco: %d premium (%d active) | Donate %d R$ | Score %d",
								safeNumber(report.premiumCount, 0),
								safeNumber(report.activePremiums, 0),
								safeNumber(report.robuxDonatedDuringAudit, 0),
								safeNumber(report.serverQualityScore, 0)
							))
							if hopErr then
								warn("[Milo MFS] " .. tostring(hopErr))
							end
							task.wait(math.max(10, safeNumber(settings.serverHopRetryDelay, 15)))
						else
							notify("Milo MFS", "Server vale ficar: " .. report.summary, 6)
							task.wait(10)
						end
					end
				end
			end
		else
			updateServerAuditText("Server audit OFF")
			task.wait(5)
		end
	end
end

local function refreshStatusText()
	local boothText = runtime.boothId and tostring(runtime.boothId) or "None"
	return string.format(
		"BoothMode: %s | Booth: %s | Players: %d",
		settings.autoClaimBooth and "AUTO" or "MANUAL",
		boothText,
		getCurrentPopulation()
	)
end

local function createSimpleObsidian()
	local CoreGui = game:GetService("CoreGui")
	local UserInputService = game:GetService("UserInputService")

	local oldGui = CoreGui:FindFirstChild("MiloMfsSimpleObsidian")
	if oldGui then
		oldGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MiloMfsSimpleObsidian"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = CoreGui

	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	frame.BorderColor3 = Color3.fromRGB(68, 72, 82)
	frame.BorderSizePixel = 1
	frame.Position = UDim2.fromOffset(24, 96)
	frame.Size = UDim2.fromOffset(430, 430)
	frame.Parent = screenGui

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundColor3 = Color3.fromRGB(28, 29, 35)
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, 34)
	titleBar.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamSemibold
	title.TextColor3 = Color3.fromRGB(232, 234, 240)
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(12, 0)
	title.Size = UDim2.new(1, -92, 1, 0)
	title.Parent = titleBar

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Color3.fromRGB(232, 234, 240)
	close.TextSize = 13
	close.Position = UDim2.new(1, -32, 0, 6)
	close.Size = UDim2.fromOffset(22, 22)
	close.Parent = titleBar

	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundColor3 = Color3.fromRGB(22, 23, 28)
	tabBar.BorderSizePixel = 0
	tabBar.Position = UDim2.fromOffset(0, 34)
	tabBar.Size = UDim2.new(1, 0, 0, 36)
	tabBar.Parent = frame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(8, 78)
	content.Size = UDim2.new(1, -16, 1, -86)
	content.Parent = frame

	local pages = {}
	local buttons = {}
	local selectedPage = nil

	local function styleText(object, size)
		object.Font = Enum.Font.Gotham
		object.TextColor3 = Color3.fromRGB(224, 226, 232)
		object.TextSize = size or 13
	end

	local function updateTabs(page)
		selectedPage = page
		for tabPage, button in pairs(buttons) do
			tabPage.Visible = tabPage == page
			button.BackgroundColor3 = tabPage == page and Color3.fromRGB(55, 60, 72) or Color3.fromRGB(32, 34, 40)
		end
	end

	local dragging = false
	local dragStart = nil
	local frameStart = nil
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			frameStart = frame.Position
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement and dragStart and frameStart then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				frameStart.X.Scale,
				frameStart.X.Offset + delta.X,
				frameStart.Y.Scale,
				frameStart.Y.Offset + delta.Y
			)
		end
	end)

	close.MouseButton1Click:Connect(function()
		screenGui.Enabled = not screenGui.Enabled
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
			screenGui.Enabled = not screenGui.Enabled
		end
	end)

	local library = {}
	function library:MakeWindow(options)
		title.Text = tostring(options and options.Name or "Milo MFS")
		local window = {}
		function window:MakeTab(tabOptions)
			local page = Instance.new("ScrollingFrame")
			page.Name = tostring(tabOptions and tabOptions.Name or "Tab")
			page.BackgroundTransparency = 1
			page.BorderSizePixel = 0
			page.CanvasSize = UDim2.fromOffset(0, 0)
			page.ScrollBarThickness = 4
			page.Size = UDim2.new(1, 0, 1, 0)
			page.Visible = false
			page.Parent = content

			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 7)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = page
			layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				page.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
			end)

			local tabButton = Instance.new("TextButton")
			tabButton.Name = page.Name .. "Button"
			tabButton.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
			tabButton.BorderSizePixel = 0
			styleText(tabButton, 12)
			tabButton.Text = page.Name
			tabButton.Size = UDim2.fromOffset(math.max(78, #page.Name * 8 + 20), 28)
			tabButton.Parent = tabBar
			tabButton.MouseButton1Click:Connect(function()
				updateTabs(page)
			end)

			pages[#pages + 1] = page
			buttons[page] = tabButton
			if not selectedPage then
				updateTabs(page)
			end

			local tab = {}
			local function addBase(height)
				local holder = Instance.new("Frame")
				holder.BackgroundColor3 = Color3.fromRGB(25, 26, 32)
				holder.BorderColor3 = Color3.fromRGB(48, 51, 60)
				holder.BorderSizePixel = 1
				holder.Size = UDim2.new(1, -6, 0, height)
				holder.Parent = page
				return holder
			end

			function tab:AddParagraph(name, text)
				local holder = addBase(58)
				local header = Instance.new("TextLabel")
				header.BackgroundTransparency = 1
				header.Font = Enum.Font.GothamSemibold
				header.TextColor3 = Color3.fromRGB(236, 238, 244)
				header.TextSize = 13
				header.TextXAlignment = Enum.TextXAlignment.Left
				header.Position = UDim2.fromOffset(10, 5)
				header.Size = UDim2.new(1, -20, 0, 18)
				header.Text = tostring(name or "Info")
				header.Parent = holder

				local body = Instance.new("TextLabel")
				body.BackgroundTransparency = 1
				styleText(body, 12)
				body.TextColor3 = Color3.fromRGB(178, 184, 196)
				body.TextWrapped = true
				body.TextXAlignment = Enum.TextXAlignment.Left
				body.TextYAlignment = Enum.TextYAlignment.Top
				body.Position = UDim2.fromOffset(10, 25)
				body.Size = UDim2.new(1, -20, 1, -30)
				body.Text = tostring(text or "")
				body.Parent = holder

				local paragraph = {}
				function paragraph:Set(a, b)
					if b ~= nil then
						header.Text = tostring(a or "")
						body.Text = tostring(b or "")
					else
						body.Text = tostring(a or "")
					end
				end
				return paragraph
			end

			function tab:AddToggle(options)
				local holder = addBase(34)
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				styleText(label, 13)
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.Position = UDim2.fromOffset(10, 0)
				label.Size = UDim2.new(1, -72, 1, 0)
				label.Text = tostring(options and options.Name or "Toggle")
				label.Parent = holder

				local button = Instance.new("TextButton")
				button.BorderSizePixel = 0
				styleText(button, 12)
				button.Position = UDim2.new(1, -58, 0, 6)
				button.Size = UDim2.fromOffset(48, 22)
				button.Parent = holder

				local value = options and options.Default == true
				local function paint()
					button.Text = value and "ON" or "OFF"
					button.BackgroundColor3 = value and Color3.fromRGB(68, 118, 93) or Color3.fromRGB(58, 61, 70)
				end
				paint()
				button.MouseButton1Click:Connect(function()
					value = not value
					paint()
					if options and type(options.Callback) == "function" then
						pcall(options.Callback, value)
					end
				end)
			end

			function tab:AddSlider(options)
				local holder = addBase(46)
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				styleText(label, 13)
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.Position = UDim2.fromOffset(10, 0)
				label.Size = UDim2.new(1, -20, 0, 22)
				label.Parent = holder

				local input = Instance.new("TextBox")
				input.BackgroundColor3 = Color3.fromRGB(35, 37, 44)
				input.BorderColor3 = Color3.fromRGB(58, 62, 72)
				input.ClearTextOnFocus = false
				styleText(input, 12)
				input.Position = UDim2.fromOffset(10, 23)
				input.Size = UDim2.new(1, -20, 0, 18)
				input.Parent = holder

				local min = tonumber(options and options.Min) or 0
				local max = tonumber(options and options.Max) or 100
				local valueName = tostring(options and options.ValueName or "")
				local current = math.clamp(tonumber(options and options.Default) or min, min, max)
				local function setText()
					label.Text = tostring(options and options.Name or "Value") .. ": " .. tostring(current) .. (valueName ~= "" and (" " .. valueName) or "")
					input.Text = tostring(current)
				end
				setText()
				input.FocusLost:Connect(function(enterPressed)
					if not enterPressed then
						setText()
						return
					end
					local nextValue = tonumber(input.Text)
					if nextValue then
						current = math.clamp(nextValue, min, max)
						if options and type(options.Callback) == "function" then
							pcall(options.Callback, current)
						end
					end
					setText()
				end)
			end

			function tab:AddTextbox(options)
				local holder = addBase(48)
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				styleText(label, 13)
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.Position = UDim2.fromOffset(10, 0)
				label.Size = UDim2.new(1, -20, 0, 20)
				label.Text = tostring(options and options.Name or "Text")
				label.Parent = holder

				local input = Instance.new("TextBox")
				input.BackgroundColor3 = Color3.fromRGB(35, 37, 44)
				input.BorderColor3 = Color3.fromRGB(58, 62, 72)
				input.ClearTextOnFocus = false
				styleText(input, 12)
				input.TextXAlignment = Enum.TextXAlignment.Left
				input.Position = UDim2.fromOffset(10, 23)
				input.Size = UDim2.new(1, -20, 0, 19)
				input.Text = tostring(options and options.Default or "")
				input.Parent = holder
				input.FocusLost:Connect(function(enterPressed)
					if enterPressed and options and type(options.Callback) == "function" then
						pcall(options.Callback, input.Text)
					end
				end)
			end

			function tab:AddButton(options)
				local button = Instance.new("TextButton")
				button.BackgroundColor3 = Color3.fromRGB(42, 46, 56)
				button.BorderColor3 = Color3.fromRGB(66, 72, 84)
				button.BorderSizePixel = 1
				styleText(button, 13)
				button.Text = tostring(options and options.Name or "Button")
				button.Size = UDim2.new(1, -6, 0, 32)
				button.Parent = page
				button.MouseButton1Click:Connect(function()
					if options and type(options.Callback) == "function" then
						pcall(options.Callback)
					end
				end)
			end

			return tab
		end
		return window
	end

	return library
end

local ObsidianLib = createSimpleObsidian()

local Window = ObsidianLib:MakeWindow({
	Name = "Milo MFS | Supreme",
	HidePremium = false,
	SaveConfig = false,
	IntroEnabled = false,
	ConfigFolder = "MiloFarm",
})

local MainTab = Window:MakeTab({
	Name = "Main",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false,
})

local BoothTab = Window:MakeTab({
	Name = "Booth",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false,
})

local ServerTab = Window:MakeTab({
	Name = "Server",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false,
})

local DonateTab = Window:MakeTab({
	Name = "Donate",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false,
})

local StatusParagraph = MainTab:AddParagraph("Status", refreshStatusText())
local ServerParagraph = ServerTab:AddParagraph("Audit", runtime.serverAuditText)
local DonateParagraph = DonateTab:AddParagraph("Last Donate", runtime.lastDonationText)
local DebugParagraph = MainTab:AddParagraph("Debug", runtime.debugText)

refreshStatus = function()
	local text = refreshStatusText()
	pcall(function()
		StatusParagraph:Set("Status", text)
	end)
	pcall(function()
		StatusParagraph:Set(text)
	end)
	pcall(function()
		ServerParagraph:Set("Audit", runtime.serverAuditText)
	end)
	pcall(function()
		ServerParagraph:Set(runtime.serverAuditText)
	end)
	pcall(function()
		DonateParagraph:Set("Last Donate", runtime.lastDonationText)
	end)
	pcall(function()
		DonateParagraph:Set(runtime.lastDonationText)
	end)
	pcall(function()
		DebugParagraph:Set("Debug", runtime.debugText)
	end)
	pcall(function()
		DebugParagraph:Set(runtime.debugText)
	end)
end

local function debugLoop()
	pushDebug("DEBUG", "Debug online no HUD e com resumo automatico a cada 35 minutos", true)
	while true do
		task.wait(DEBUG_PRINT_INTERVAL)
		pushDebug("DEBUG", buildDebugSnapshot("Resumo periodico"), true)
	end
end

local function premiumPrintLoop()
	while true do
		local premiumNames = getPremiumPlayerNames()
		local message = #premiumNames > 0
			and string.format("Premiums no server (%d): %s", #premiumNames, table.concat(premiumNames, ", "))
			or "Premiums no server (0): nenhum"
		print("[Milo MFS] " .. message)
		pushDebug("PREMIUM", message, true)
		task.wait(10)
	end
end

local function runAntiAfkPulse(reason, forcePrint)
	runtime.lastAntiAfkAt = os.clock()

	local clicked = false
	if Services.VirtualUser then
		pcall(function()
			Services.VirtualUser:CaptureController()
			Services.VirtualUser:ClickButton2(Vector2.new(0, 0))
			clicked = true
		end)
	end

	local humanoid = getHumanoid()
	if humanoid then
		pcall(function()
			humanoid:Move(Vector3.new(0, 0, 0), true)
		end)
	end

	pushDebug(
		"AFK",
		string.format("Anti AFK pulso (%s) | VirtualUser=%s", tostring(reason or "manual"), clicked and "OK" or "FAIL"),
		forcePrint == true
	)
end

local function antiAfkLoop()
	pushDebug("AFK", "Anti AFK online", true)
	while true do
		task.wait(300)
		runAntiAfkPulse("heartbeat", false)
	end
end

local function ensureBoothClaimedAndReached()
	if not settings.autoClaimBooth then
		pushDebug("BOOTH", "Auto claim desativado; fluxo automatico ignorado")
		return false
	end

	BoothLogic.prepareAutoClaimSequence()
	local success = false

	for _ = 1, 3 do
		local claimed, err = BoothLogic.claimBooth()
		if claimed then
			local walked = BoothLogic.walkToBooth()
			if walked ~= false then
				BoothLogic.randomizePositionAtBooth()
				disableAutoClaimBooth()
				notify("Milo MFS", "Booth claimed and reached", 4)
				success = true
				break
			end
		end

		if err then
			warn("[Milo MFS] " .. tostring(err))
		end
		task.wait(0.2)
	end
	return success
end

local function claimLoop()
	while true do
		local ownedId = BoothLogic.findOwnedBooth()
		if ownedId then
			runtime.boothId = ownedId
			BoothLogic.refreshAnchor()
		else
			if runtime.boothId then
				pushDebug("BOOTH", "Booth perdida ou nao localizada mais")
			end
			BoothLogic.clearCurrentBooth()
		end

		if settings.autoClaimBooth and not ownedId then
			ensureBoothClaimedAndReached()
		end

		refreshStatus()
		task.wait(math.max(1, safeNumber(settings.claimRetryDelay, 5)))
	end
end

local function behaviorLoop()
	while true do
		runtime.currentTarget = nil
		returnToBooth()
		refreshStatus()
		task.wait(math.max(0.1, safeNumber(settings.loopDelay, 0.25)))
	end
end

startLoop("claim", claimLoop)
startLoop("behavior", behaviorLoop)
startLoop("serverAudit", serverAuditLoop)
startLoop("debug", debugLoop)
startLoop("premiumPrint", premiumPrintLoop)
startLoop("antiAfk", antiAfkLoop)

task.spawn(function()
	task.wait(1)
	local ownedId = BoothLogic.findOwnedBooth()
	if ownedId then
		runtime.boothId = ownedId
		BoothLogic.refreshAnchor()
		BoothLogic.walkToBooth()
		pushDebug("BOOTH", "Booth propria detectada no carregamento: " .. tostring(ownedId), true)
	else
		pushDebug("BOOTH", "Nenhuma booth propria detectada no carregamento")
		ensureBoothClaimedAndReached()
	end
end)

table.insert(runtime.connections, LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1.5)
	local ownedId = BoothLogic.findOwnedBooth()
	if ownedId then
		runtime.boothId = ownedId
		BoothLogic.refreshAnchor()
		BoothLogic.walkToBooth()
		pushDebug("BOOTH", "Booth propria restaurada apos respawn: " .. tostring(ownedId), true)
	else
		BoothLogic.clearCurrentBooth()
		pushDebug("BOOTH", "Respawn sem booth propria detectada")
		ensureBoothClaimedAndReached()
	end
	runAntiAfkPulse("character_added", false)
	refreshStatus()
end))

table.insert(runtime.connections, LocalPlayer.Idled:Connect(function()
	runAntiAfkPulse("idled_event", true)
end))

table.insert(runtime.connections, Services.TeleportService.TeleportInitFailed:Connect(function(player, teleportResult)
	if player == LocalPlayer then
		runtime.serverHopInProgress = false
		updateServerAuditText("Teleport failed: " .. tostring(teleportResult))
	end
end))

task.spawn(function()
	local chatEvent = getChatMessageEvent()
	while not chatEvent do
		task.wait(1)
		chatEvent = getChatMessageEvent()
	end

	table.insert(runtime.connections, chatEvent.OnClientEvent:Connect(function(messageData)
		local messageText = nil
		if type(messageData) == "table" then
			messageText = messageData.Message or messageData.message or messageData.Text or messageData.text
		elseif type(messageData) == "string" then
			messageText = messageData
		end

		local parsed = parseDonationFromMessage(messageText)
		if parsed and parsed.amount and parsed.amount > 0 then
			recordServerDonation(parsed.donor, parsed.amount, parsed.recipient)
			queuePendingDonation(parsed.donor, parsed.amount, parsed.recipient)
		end
	end))
end)

task.spawn(function()
	local raisedValue = getRaisedValue()
	while not raisedValue do
		task.wait(1)
		raisedValue = getRaisedValue()
	end

	runtime.donationBaseline = safeNumber(raisedValue.Value, 0)
	table.insert(runtime.connections, raisedValue.Changed:Connect(function()
		if not settings.donateWatcher then
			runtime.donationBaseline = safeNumber(raisedValue.Value, 0)
			return
		end

		local currentValue = safeNumber(raisedValue.Value, 0)
		local previousValue = safeNumber(runtime.donationBaseline, currentValue)
		local delta = currentValue - previousValue
		if delta > 0 then
			handleDonation(delta, currentValue)
		end
		runtime.donationBaseline = currentValue
	end))
end)

MainTab:AddParagraph("Simplified", "Build enxuta com foco em booth, donate watcher, audit e webhook opcional.")

BoothTab:AddButton({
	Name = "Andar e Pegar Booth Mais Perta",
	Callback = function()
		pushDebug("HUD", "Botao manual de booth acionado", true)
		local ok, err = BoothLogic.claimBooth()
		if not ok then
			pushDebug("BOOTH", "Botao manual falhou: " .. tostring(err or "erro desconhecido"), true)
			notify("Milo MFS", "Nao consegui pegar uma booth livre", 4)
		else
			notify("Milo MFS", "Booth mais perto capturada andando", 4)
		end
		refreshStatus()
	end,
})

BoothTab:AddSlider({
	Name = "MoveTo Refresh",
	Min = 0,
	Max = 2,
	Default = safeNumber(settings.directMoveRefresh, 0.25),
	ValueName = "s",
	Callback = function(value)
		settings.directMoveRefresh = value
		saveSettings()
	end,
})

BoothTab:AddSlider({
	Name = "Path Refresh",
	Min = 0,
	Max = 2,
	Default = safeNumber(settings.pathMoveRefresh, 0.2),
	ValueName = "s",
	Callback = function(value)
		settings.pathMoveRefresh = value
		saveSettings()
	end,
})

BoothTab:AddSlider({
	Name = "Movement Loop Wait",
	Min = 0,
	Max = 1,
	Default = safeNumber(settings.movementLoopWait, 0.05),
	ValueName = "s",
	Callback = function(value)
		settings.movementLoopWait = value
		saveSettings()
	end,
})

BoothTab:AddSlider({
	Name = "Walk Timeout Base",
	Min = 1,
	Max = 15,
	Default = safeNumber(settings.walkTimeoutBaseSeconds, 4),
	ValueName = "s",
	Callback = function(value)
		settings.walkTimeoutBaseSeconds = value
		saveSettings()
	end,
})

BoothTab:AddSlider({
	Name = "Walk Timeout Divisor",
	Min = 1,
	Max = 30,
	Default = safeNumber(settings.walkTimeoutDistanceDivisor, 9),
	ValueName = "dist",
	Callback = function(value)
		settings.walkTimeoutDistanceDivisor = value
		saveSettings()
	end,
})

BoothTab:AddSlider({
	Name = "Walk Timeout Min",
	Min = 1,
	Max = 20,
	Default = safeNumber(settings.walkTimeoutMinSeconds, 4),
	ValueName = "s",
	Callback = function(value)
		settings.walkTimeoutMinSeconds = value
		if settings.walkTimeoutMaxSeconds < value then
			settings.walkTimeoutMaxSeconds = value
		end
		saveSettings()
	end,
})

BoothTab:AddSlider({
	Name = "Walk Timeout Max",
	Min = 1,
	Max = 40,
	Default = safeNumber(settings.walkTimeoutMaxSeconds, 24),
	ValueName = "s",
	Callback = function(value)
		settings.walkTimeoutMaxSeconds = value
		if settings.walkTimeoutMinSeconds > value then
			settings.walkTimeoutMinSeconds = value
		end
		saveSettings()
	end,
})

BoothTab:AddSlider({
	Name = "Fast Return Speed",
	Min = 16,
	Max = 100,
	Default = safeNumber(settings.fastBoothReturnSpeed, 42),
	ValueName = "ws",
	Callback = function(value)
		settings.fastBoothReturnSpeed = value
		saveSettings()
	end,
})

ServerTab:AddParagraph(
	"Rules",
	"Busca premiums: 5+ premium/3 active = stay | <5 premium precisa donation forte | score fraco = hop"
)

ServerTab:AddToggle({
	Name = "Auto Server Audit",
	Default = settings.serverAuditEnabled,
	Callback = function(value)
		settings.serverAuditEnabled = value
		saveSettings()
		updateServerAuditText(value and "Server audit armed" or "Server audit OFF")
	end,
})

ServerTab:AddSlider({
	Name = "Min Players",
	Min = 10,
	Max = 25,
	Default = safeNumber(settings.serverMinPlayers, 18),
	Color = Color3.fromRGB(0, 170, 127),
	Increment = 1,
	ValueName = "players",
	Callback = function(value)
		settings.serverMinPlayers = value
		saveSettings()
		refreshStatus()
	end,
})

ServerTab:AddSlider({
	Name = "Target Min",
	Min = 15,
	Max = 25,
	Default = safeNumber(settings.serverTargetMinPlayers, 20),
	Color = Color3.fromRGB(0, 170, 127),
	Increment = 1,
	ValueName = "players",
	Callback = function(value)
		settings.serverTargetMinPlayers = value
		if settings.serverTargetMaxPlayers < value then
			settings.serverTargetMaxPlayers = value
		end
		saveSettings()
	end,
})

ServerTab:AddSlider({
	Name = "Target Max",
	Min = 18,
	Max = 30,
	Default = safeNumber(settings.serverTargetMaxPlayers, 25),
	Color = Color3.fromRGB(0, 170, 127),
	Increment = 1,
	ValueName = "players",
	Callback = function(value)
		settings.serverTargetMaxPlayers = value
		if settings.serverTargetMinPlayers > value then
			settings.serverTargetMinPlayers = value
		end
		saveSettings()
	end,
})

ServerTab:AddSlider({
	Name = "Audit Minutes",
	Min = 1,
	Max = 10,
	Default = safeNumber(settings.serverAuditMinutes, 5),
	Color = Color3.fromRGB(0, 170, 127),
	Increment = 1,
	ValueName = "min",
	Callback = function(value)
		settings.serverAuditMinutes = value
		saveSettings()
	end,
})

ServerTab:AddSlider({
	Name = "Min Premiums",
	Min = 1,
	Max = 15,
	Default = safeNumber(settings.serverMinPremiums, 5),
	Color = Color3.fromRGB(0, 170, 127),
	Increment = 1,
	ValueName = "premium",
	Callback = function(value)
		settings.serverMinPremiums = value
		saveSettings()
	end,
})

ServerTab:AddSlider({
	Name = "Min Active Premiums",
	Min = 1,
	Max = 10,
	Default = safeNumber(settings.serverMinActivePremiums, 3),
	Color = Color3.fromRGB(0, 170, 127),
	Increment = 1,
	ValueName = "active",
	Callback = function(value)
		settings.serverMinActivePremiums = value
		saveSettings()
	end,
})

ServerTab:AddSlider({
	Name = "Donation Stay",
	Min = 0,
	Max = 500,
	Default = safeNumber(settings.serverDonationStayThreshold, 80),
	Color = Color3.fromRGB(0, 170, 127),
	Increment = 10,
	ValueName = "R$",
	Callback = function(value)
		settings.serverDonationStayThreshold = value
		saveSettings()
	end,
})

ServerTab:AddSlider({
	Name = "Stay Score",
	Min = 0,
	Max = 300,
	Default = safeNumber(settings.serverQualityStayScore, 90),
	Color = Color3.fromRGB(0, 170, 127),
	Increment = 5,
	ValueName = "score",
	Callback = function(value)
		settings.serverQualityStayScore = value
		saveSettings()
	end,
})

ServerTab:AddButton({
	Name = "Run Audit Now",
	Callback = function()
		task.spawn(function()
			local report, err = performServerAudit()
			if report then
				notify("Milo MFS", report.summary, 8)
			elseif err then
				notify("Milo MFS", tostring(err), 6)
			end
		end)
	end,
})

ServerTab:AddButton({
	Name = "Hop 20-25 Players",
	Callback = function()
		local ok, err = hopToPreferredServer("Manual server hop requested")
		if not ok and err then
			notify("Milo MFS", tostring(err), 6)
		end
	end,
})

ServerTab:AddButton({
	Name = "Join Milokinot",
	Callback = function()
		local ok, err = joinMilokinotExperience()
		if ok then
			notify("Milo MFS", "Entrando na experiencia do Milokinot", 5)
		elseif err then
			notify("Milo MFS", tostring(err), 6)
		end
	end,
})

DonateTab:AddToggle({
	Name = "Donate Watcher",
	Default = settings.donateWatcher,
	Callback = function(value)
		settings.donateWatcher = value
		saveSettings()
	end,
})

DonateTab:AddToggle({
	Name = "Donate Popup",
	Default = settings.donatePopup,
	Callback = function(value)
		settings.donatePopup = value
		saveSettings()
	end,
})

DonateTab:AddButton({
	Name = "Test Discord Alert",
	Callback = function()
		local testMessage = buildDonateWebhookMessage(
			string.format("%s (@%s)", tostring(LocalPlayer.DisplayName), tostring(LocalPlayer.Name)),
			"Milokinot",
			126
		)
		local ok = sendWebhook(
			testMessage,
			{
				title = "SUPER FELIZZZZZ",
				description = "Teste manual do webhook fixo de donate",
				color = 0xFFD700,
				fields = {
					{
						name = "Player",
						value = string.format("%s (@%s)", tostring(LocalPlayer.DisplayName), tostring(LocalPlayer.Name)),
						inline = true,
					},
					{
						name = "PlaceId",
						value = tostring(game.PlaceId),
						inline = true,
					},
				},
			}
		)
		notify("Milo MFS", ok and "Webhook enviado" or "Webhook falhou", 4)
	end,
})

refreshStatus()
notify("Milo MFS", "Supreme loaded", 4)

getgenv().MILO_MFS_CLEANUP = function()
	stopAllLoops()
	for _, connection in ipairs(runtime.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	runtime.connections = {}
	getgenv()[RUN_FLAG] = nil
end
