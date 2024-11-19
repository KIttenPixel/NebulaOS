local component = require("component")
local computer = require("computer")

local function getcomponentAddress(name)
	return component.list(name)() or error("Required " .. name .. " component is missing")
end
 
local internetAddress, GPUAddress = 
	getcomponentAddress("internet"),
	getcomponentAddress("gpu")

local installerConfigs = "Installer/"

local FilesConfigs = "Installer/Files.cfg"

local repositoryURL = "https://raw.githubusercontent.com/KIttenPixel/NebulaOS/refs/heads/main/"


local screenWidth, screenHeight = component.invoke(GPUAddress, "getResolution")

local function centrize(width)
	return math.floor(screenWidth / 2 - width / 2)
end

local function centrizedText(y, color, text)
	component.invoke(GPUAddress, "fill", 1, y, screenWidth, 1, " ")
	component.invoke(GPUAddress, "setForeground", color)
	component.invoke(GPUAddress, "set", centrize(#text), y, text)
end

local function title()
	local y = math.floor(screenHeight / 2 - 1)
	centrizedText(y, 0x2D2D2D, "NebulaOS - Loading")

	return y + 2
end

local function progress(value)
	local width = 26
	local x, y, part = centrize(width), title(), math.ceil(width * value)
	
	component.invoke(GPUAddress, "setForeground", 0x121211)
	component.invoke(GPUAddress, "set", x, y, string.rep("─", part))
	component.invoke(GPUAddress, "setForeground", 0xC3C3C3)
	component.invoke(GPUAddress, "set", x + part, y, string.rep("─", width - part))
end

local function filesystemPath(path)
	return path:match("^(.+%/).") or ""
end

local function filesystemName(path)
	return path:match("%/?([^%/]+%/?)$")
end

local function filesystemHideExtension(path)
	return path:match("(.+)%..+") or path
end

local function rawRequest(url, chunkHandler)
	local internetHandle, reason = component.invoke(internetAddress, "request", repositoryURL .. url:gsub("([^%w%-%_%.%~])", function(char)
		return string.format("%%%02X", string.byte(char))
	end))

	if internetHandle then
		local chunk, reason
		while true do
			chunk, reason = internetHandle.read(math.huge)	
			
			if chunk then
				chunkHandler(chunk)
			else
				if reason then
					error("Internet request failed: " .. tostring(reason))
				end

				break
			end
		end

		internetHandle.close()
	else
		error("Connection failed: " .. url)
	end
end

local function request(url)
	local data = ""
	
	rawRequest(url, function(chunk)
		data = data .. chunk
	end)

	return data
end

local function download(url, path)
	selectedFilesystemProxy.makeDirectory(filesystemPath(path))

	local fileHandle, reason = selectedFilesystemProxy.open(path, "wb")
	if fileHandle then	
		rawRequest(url, function(chunk)
			selectedFilesystemProxy.write(fileHandle, chunk)
		end)

		selectedFilesystemProxy.close(fileHandle)
	else
		error("File opening failed: " .. tostring(reason))
	end
end

local function deserialize(text)
	local result, reason = load("return " .. text, "=string")
	if result then
		return result()
	else
		error(reason)
	end
end

component.invoke(GPUAddress, "setBackground", 0x1a1a1a)
component.invoke(GPUAddress, "fill", 1, 1, screenWidth, screenHeight, " ")

do
	local function warning(text)
		centrizedText(title(), 0x878787, text)

		local signal
		repeat
			signal = computer.pullSignal()
		until signal == "key_down" or signal == "touch"

		computer.shutdown()
	end

	if component.invoke(GPUAddress, "getDepth") ~= 8 then
		warning("Tier 3 GPU and screen are required")
	end

	if computer.totalMemory() < 1024 * 1024 * 2 then
		warning("At least 2x Tier 3.5 RAM modules are required")
	end

	-- Searching for appropriate temporary filesystem for storing libraries, images, etc
	for address in component.list("filesystem") do
		local proxy = component.proxy(address)
		if proxy.spaceTotal() >= 2 * 1024 * 1024 then
			temporaryFilesystemProxy, selectedFilesystemProxy = proxy, proxy
			break
		end
	end

	-- If there's no suitable HDDs found - then meow
	if not temporaryFilesystemProxy then
		warning("At least Tier 2 HDD is required")
	end
end
progress(0)
local files = deserialize(request(installerConfigs .. "Files.cfg"))
progress(50)
for i = 1, #files.OsFiles do
	progress(i / #files.OsFiles)
	download(files.OsFiles[i], files.OsFiles[i])
end
progress(100)

computer.shutdown(true)
--shell.run("/usr/bin/desktop.lua")
