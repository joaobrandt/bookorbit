-- Server fonts land in a BookOrbit folder inside KOReader's fonts directory.
-- The folder is the record of what the device holds: a sync fetches missing
-- and cut-short files, removes what the server dropped, leaves files it did
-- not name alone, and stops early only on an error every later font would
-- hit too.

local directories = {}
local files = {}
local make_path_fails = false
local cwd = "/koreader"

package.loaded["libs/libkoreader-lfs"] = {
    currentdir = function() return cwd end,
    attributes = function(path, attribute)
        if directories[path] then
            if attribute == "mode" then return "directory" end
            return { mode = "directory" }
        end
        local size = files[path]
        if not size then return nil end
        if attribute == "mode" then return "file" end
        if attribute == "size" then return size end
        return { mode = "file", size = size }
    end,
    dir = function(path)
        local names = {}
        for file_path in pairs(files) do
            local name = file_path:match("^" .. path:gsub("([%.%-])", "%%%1") .. "/([^/]+)$")
            if name then table.insert(names, name) end
        end
        table.sort(names)
        local index = 0
        return function()
            index = index + 1
            return names[index]
        end
    end,
}

package.loaded["util"] = {
    makePath = function(path)
        if not make_path_fails then directories[path] = true end
    end,
}

package.loaded["fontlist"] = { fontdir = "./fonts" }

local swept = 0
local transfers = {}
package.loaded["bookorbit_download_transfer"] = {
    sweepStale = function() swept = swept + 1 end,
    run = function(opts)
        table.insert(transfers, opts)
        local ok, err = opts.perform({})
        if not ok then return nil, err end
        if opts.on_progress then opts.on_progress(opts.expected_bytes) end
        files[opts.destination] = opts.expected_bytes
        return true
    end,
}

os.remove = function(path)
    if not files[path] then return nil, "missing" end
    files[path] = nil
    return true
end

package.path = "koreader-plugin/bookorbit.koplugin/?.lua;" .. package.path

local Capabilities = require("bookorbit_capabilities")
local ServerFonts = require("bookorbit_server_fonts")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local DIR = "/koreader/fonts/bookorbit"

local function reset()
    directories, files, transfers, swept, make_path_fails = {}, {}, {}, 0, false
    Capabilities.reset()
end

local function makeClient(list_body, list_err, download_errors)
    local client = { server_url = "https://books.example", username = "reader", listed = 0, downloaded = {} }
    function client:getPluginVersion()
        return { capabilities = { "serverFonts" } }
    end
    function client:listServerFonts()
        self.listed = self.listed + 1
        return list_body, list_err
    end
    function client:downloadServerFont(font_id)
        table.insert(self.downloaded, font_id)
        local err = download_errors and download_errors[font_id]
        if err then return nil, err end
        return { temp_path = "unused" }
    end
    return client
end

local function font(id, format, size)
    return { id = id, format = format, fileSize = size }
end

-- The folder sits inside KOReader's own fonts directory, resolved against the
-- working directory when that directory is relative.
reset()
assertEqual(ServerFonts.dir(), DIR, "the folder lives under KOReader's fonts directory")

-- Malformed entries are dropped and the rest come back in id order.
local parsed = ServerFonts.fonts({ fonts = {
    font(9, "otf", 300),
    font(2, "ttf", 100),
    font(3, "exe", 100),
    font(4, "ttf", 0),
    font(-1, "ttf", 100),
    font(5.5, "woff", 100),
    "not a font",
} })
assertEqual(#parsed, 2, "only well-formed fonts are kept")
assertEqual(parsed[1].id, 2, "fonts are ordered by id")
assertEqual(parsed[2].id, 9, "the second font follows")

-- A first sync fetches everything and reports each font as it goes.
reset()
local progress = {}
local client = makeClient({ fonts = { font(1, "ttf", 100), font(2, "woff2", 200) } })
local summary = ServerFonts.sync(client, {
    on_progress = function(index, count, received) table.insert(progress, index .. "/" .. count .. ":" .. received) end,
})
assertEqual(directories[DIR], true, "the folder is created")
assertEqual(swept, 1, "leftovers of a killed run are swept first")
assertEqual(summary.total, 2, "the server offered two fonts")
assertEqual(summary.added, 2, "both fonts are fetched")
assertEqual(summary.removed, 0, "nothing is removed")
assertEqual(summary.err, nil, "the run finished")
assertEqual(files[DIR .. "/1.ttf"], 100, "the first font is named after its id")
assertEqual(files[DIR .. "/2.woff2"], 200, "the second keeps its own format")
assertEqual(transfers[1].expected_bytes, 100, "the transfer knows the size to expect")
assertEqual(transfers[1].root, DIR, "transfers are confined to the folder")
assertEqual(table.concat(progress, ","), "1/2:0,1/2:100,2/2:0,2/2:200", "progress names the font and its bytes")

-- Later syncs fetch only what is missing or cut short, remove what the server
-- dropped, and leave files BookOrbit did not name alone.
reset()
directories[DIR] = true
files[DIR .. "/1.ttf"] = 100
files[DIR .. "/2.woff2"] = 50
files[DIR .. "/7.otf"] = 70
files[DIR .. "/MyOwnFont.ttf"] = 10
client = makeClient({ fonts = { font(1, "ttf", 100), font(2, "woff2", 200), font(3, "otf", 300) } })
summary = ServerFonts.sync(client)
assertEqual(table.concat(client.downloaded, ","), "2,3", "the complete copy is kept, the short one and the new one are fetched")
assertEqual(summary.added, 2, "two fonts are added")
assertEqual(summary.removed, 1, "the font the server dropped is removed")
assertEqual(files[DIR .. "/7.otf"], nil, "the dropped font is gone")
assertEqual(files[DIR .. "/MyOwnFont.ttf"], 10, "a file BookOrbit did not name stays")
assertEqual(files[DIR .. "/2.woff2"], 200, "the short copy is replaced by the whole file")

-- Nothing to do is a successful, empty run.
summary = ServerFonts.sync(client)
assertEqual(summary.added + summary.removed, 0, "an up-to-date folder changes nothing")
assertEqual(summary.total, 3, "the total still counts the server's fonts")

-- A font deleted since the list was read is skipped; any other failure stops
-- the run, since every later font would fail the same way.
reset()
client = makeClient({ fonts = { font(1, "ttf", 100), font(2, "ttf", 100), font(3, "ttf", 100), font(4, "ttf", 100) } }, nil,
    { [1] = 404, [3] = "timeout" })
summary = ServerFonts.sync(client)
assertEqual(table.concat(client.downloaded, ","), "1,2,3", "the run stops after the failing font")
assertEqual(summary.added, 1, "the font before the failure is kept")
assertEqual(summary.err, "timeout", "the failure is reported")

-- An older server is detected from its capabilities or its 404, and the
-- answer sticks for the session.
reset()
client = makeClient(nil, 404)
local result, err = ServerFonts.sync(client)
assertEqual(result, nil, "an older server gives no summary")
assertEqual(err, "unsupported_server", "an older server is named as such")
result, err = ServerFonts.sync(client)
assertEqual(err, "unsupported_server", "the second run is answered from the capability cache")
assertEqual(client.listed, 1, "the list is not requested again")

reset()
client = makeClient({ fonts = {} })
client.getPluginVersion = function() return { capabilities = { "bookmarkSync" } } end
result, err = ServerFonts.sync(client)
assertEqual(err, "unsupported_server", "a server that does not advertise fonts is not asked for them")
assertEqual(client.listed, 0, "the list route is never called")

-- Transport errors pass through untouched.
reset()
result, err = ServerFonts.sync(makeClient(nil, "connection refused"))
assertEqual(err, "connection refused", "a transport error is returned as is")

-- A folder that cannot be created stops before any transfer.
reset()
make_path_fails = true
client = makeClient({ fonts = { font(1, "ttf", 100) } })
result, err = ServerFonts.sync(client)
assertEqual(err, "folder_failed", "a missing folder is reported")
assertEqual(#client.downloaded, 0, "nothing is downloaded")

-- The settings summary counts only BookOrbit's own files.
reset()
directories[DIR] = true
files[DIR .. "/1.ttf"] = 100
files[DIR .. "/2.otf"] = 100
files[DIR .. "/notes.txt"] = 5
assertEqual(ServerFonts.countLocal(), 2, "only managed fonts are counted")

print("bookorbit_server_fonts_test.lua: ok")
