-- Milo UI + Doomsday loader
-- Troque as URLs abaixo pelos raws hospedados dos arquivos desta pasta.

getgenv().DOOMSDAY_SCRIPT_URL = getgenv().DOOMSDAY_SCRIPT_URL or "https://raw.githubusercontent.com/Milokinot/scripts/main/DOOMSDAY%20SCRIPT/DOOMSDAY.lua"
getgenv().MILO_UI_URL = getgenv().MILO_UI_URL or "https://raw.githubusercontent.com/Milokinot/scripts/main/DOOMSDAY%20SCRIPT/DOOMSDAY_OBSIDIAN_UNIVERSAL.lua"
getgenv().FIGURE_GRAB_OATS_URL = getgenv().FIGURE_GRAB_OATS_URL or "https://raw.githubusercontent.com/Milokinot/scripts/main/DOOMSDAY%20SCRIPT/modules/FIGURE_GRAB_OATS.lua"

local function configured(url)
    return type(url) == "string" and url:match("^https?://") and not url:find("COLE_AQUI", 1, true)
end

local function runRemote(url)
    if configured(url) then
        return loadstring(game:HttpGet(url))()
    end

    warn("[Milo UI Loader] URL nao configurada: " .. tostring(url))
end

local function queueOnTeleport(scriptText)
    local queueFunction = queue_on_teleport
        or queueonteleport
        or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)

    if type(queueFunction) == "function" then
        queueFunction(scriptText)
        return true
    end

    warn("[Milo UI Loader] queue_on_teleport nao esta disponivel neste executor.")
    return false
end

getgenv().QueueDoomsdayOnTeleport = function()
    if not configured(getgenv().DOOMSDAY_SCRIPT_URL) then
        warn("[Milo UI Loader] Configure DOOMSDAY_SCRIPT_URL antes de usar o rejoin.")
        return false
    end

    local payload = ('loadstring(game:HttpGet("%s"))()'):format(getgenv().DOOMSDAY_SCRIPT_URL)
    if configured(getgenv().MILO_UI_URL) then
        payload = payload .. "\n" .. ('loadstring(game:HttpGet("%s"))()'):format(getgenv().MILO_UI_URL)
    end

    return queueOnTeleport(payload)
end

runRemote(getgenv().DOOMSDAY_SCRIPT_URL)
runRemote(getgenv().MILO_UI_URL)
