--[[--
Server fonts: the administrator's font collection, copied into a folder of
KOReader's own fonts directory so the reader engine registers them the next
time KOReader starts.

The folder belongs to BookOrbit alone. Each file is named after its server
font id, and a server font file never changes under its id, so the folder is
its own record of what this device holds: a sync fetches what is missing or
cut short, removes what the server no longer offers, and an interrupted sync
picks up where it stopped.
]]

local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local Capabilities = require("bookorbit_capabilities")
local Transfer = require("bookorbit_download_transfer")

local CAPABILITY = "serverFonts"
local FOLDER_NAME = "bookorbit"
local FORMATS = { ttf = true, otf = true, woff = true, woff2 = true }

local ServerFonts = {}

local function fileName(font)
    return string.format("%d.%s", font.id, font.format)
end

local function isManagedName(name)
    local id, ext = tostring(name):match("^(%d+)%.(%w+)$")
    return id ~= nil and FORMATS[ext] == true
end

-- KOReader always scans its built-in fonts directory, on every platform, and
-- descends into folders inside it.
function ServerFonts.dir()
    local ok, FontList = pcall(require, "fontlist")
    local base = tostring(ok and type(FontList) == "table" and FontList.fontdir or "./fonts")
    base = base:gsub("^%./", "")
    if base:sub(1, 1) ~= "/" then
        local cwd = lfs.currentdir()
        if cwd then base = cwd .. "/" .. base end
    end
    return base:gsub("/+$", "") .. "/" .. FOLDER_NAME
end

-- The well-formed entries of a server list, ordered by id.
function ServerFonts.fonts(body)
    local list = type(body) == "table" and type(body.fonts) == "table" and body.fonts or {}
    local fonts = {}
    for _i, font in ipairs(list) do
        if type(font) == "table" then
            local id, size = tonumber(font.id), tonumber(font.fileSize)
            if id and id > 0 and id == math.floor(id) and FORMATS[font.format] and size and size > 0 then
                table.insert(fonts, { id = id, format = font.format, size = size })
            end
        end
    end
    table.sort(fonts, function(a, b) return a.id < b.id end)
    return fonts
end

-- Size of each BookOrbit font file in the folder, by file name.
function ServerFonts.localFiles(dir)
    local files = {}
    if lfs.attributes(dir, "mode") ~= "directory" then return files end
    local ok, iterator, dir_obj = pcall(lfs.dir, dir)
    if not ok or not iterator then return files end
    for name in iterator, dir_obj do
        if isManagedName(name) then
            local path = dir .. "/" .. name
            if lfs.attributes(path, "mode") == "file" then
                files[name] = lfs.attributes(path, "size")
            end
        end
    end
    return files
end

function ServerFonts.countLocal()
    local count = 0
    for _name in pairs(ServerFonts.localFiles(ServerFonts.dir())) do count = count + 1 end
    return count
end

-- Splits the server list against the folder: fonts to fetch (missing, or a
-- size that says the copy is not the whole file) and files to remove.
function ServerFonts.plan(fonts, files)
    local fetch, remove, wanted = {}, {}, {}
    for _i, font in ipairs(fonts) do
        local name = fileName(font)
        wanted[name] = true
        if files[name] ~= font.size then table.insert(fetch, font) end
    end
    for name in pairs(files) do
        if not wanted[name] then table.insert(remove, name) end
    end
    table.sort(remove)
    return { fetch = fetch, remove = remove }
end

-- Must run inside a Trapper coroutine: each transfer owns a background
-- subprocess. opts.on_progress(index, count, received, size) reports the
-- font being fetched.
--
-- Returns { total, added, removed, err } where err is set when a transfer
-- stopped the run early, or nil and an error when nothing could be done.
function ServerFonts.sync(client, opts)
    opts = opts or {}
    if Capabilities.supports(client, CAPABILITY) == false then return nil, "unsupported_server" end

    local body, err = client:listServerFonts()
    if not body then
        if err == 404 then
            Capabilities.markUnsupported(client, CAPABILITY)
            return nil, "unsupported_server"
        end
        return nil, err
    end

    local dir = ServerFonts.dir()
    if lfs.attributes(dir, "mode") ~= "directory" then util.makePath(dir) end
    if lfs.attributes(dir, "mode") ~= "directory" then return nil, "folder_failed" end
    Transfer.sweepStale(dir)

    local fonts = ServerFonts.fonts(body)
    local plan = ServerFonts.plan(fonts, ServerFonts.localFiles(dir))
    local summary = { total = #fonts, added = 0, removed = 0 }

    for _i, name in ipairs(plan.remove) do
        if os.remove(dir .. "/" .. name) then summary.removed = summary.removed + 1 end
    end

    local count = #plan.fetch
    for index, font in ipairs(plan.fetch) do
        local destination = dir .. "/" .. fileName(font)
        if opts.on_progress then opts.on_progress(index, count, 0, font.size) end
        local ok, transfer_err = Transfer.run({
            root = dir,
            destination = destination,
            generation = font.id,
            expected_bytes = font.size,
            on_progress = opts.on_progress and function(received)
                opts.on_progress(index, count, received, font.size)
            end or nil,
            perform = function(download_opts)
                return client:downloadServerFont(font.id, destination, download_opts)
            end,
        })
        if ok then
            summary.added = summary.added + 1
        elseif transfer_err ~= 404 then
            -- A font removed since the list was read is skipped; anything else
            -- (offline, a full disk) would fail every font after it the same way.
            summary.err = transfer_err
            break
        end
    end
    return summary
end

return ServerFonts
