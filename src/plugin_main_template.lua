local PORT = "{{PORT}}"
local SERVER_ID = "{{SERVER_ID}}"

local SERVER_URL = string.format("http://localhost:%s", PORT)

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local pingSuccess, remoteServerId = pcall(function()
	return HttpService:GetAsync(SERVER_URL)
end)

-- If there was a transport error, just abort silently.
--
-- It's possible that the run-in-roblox plugin is erroneously installed, and we
-- should minimize our impact to the user.
if not pingSuccess then
	return
end

-- There is a server running on that port, but it isn't the right run-in-roblox
-- server and might be some other HTTP server.
if remoteServerId ~= SERVER_ID then
	return
end

local queuedMessages = {}
local timeSinceLastSend = 0
local messageSendRate = 0.1

local function flushMessages()
	if #queuedMessages == 0 then
		return
	end

	local encoded = HttpService:JSONEncode(queuedMessages)
	queuedMessages = {}

	timeSinceLastSend = 0
	HttpService:PostAsync(SERVER_URL .. "/messages", encoded)
end

local heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
	timeSinceLastSend = timeSinceLastSend + dt

	if timeSinceLastSend >= messageSendRate then
		flushMessages()
	end
end)

local logTypeToLevel = {
	[Enum.MessageType.MessageOutput] = "Print",
	[Enum.MessageType.MessageInfo] = "Info",
	[Enum.MessageType.MessageWarning] = "Warning",
	[Enum.MessageType.MessageError] = "Error",
}

local logConnection = LogService.MessageOut:Connect(function(body, messageType)
	table.insert(queuedMessages, {
		type = "Output",
		level = logTypeToLevel[messageType] or "Info",
		body = body,
	})
end)



local stopped = false
local function stop(exit_code)
	if stopped then
		return
	end
	stopped = true

	-- Wait for any remaining messages to be sent to LogService, then flush them
	-- explicitly.
	wait(2 * messageSendRate)
	heartbeatConnection:Disconnect()
	logConnection:Disconnect()
	flushMessages()

	local body = HttpService:JSONEncode({code = exit_code})
	HttpService:PostAsync(SERVER_URL .. "/stop", body)
end

local function reportScriptError(message, code)
	local sacrificialEvent = Instance.new("BindableEvent")
	sacrificialEvent.Event:Connect(error)
	sacrificialEvent:Fire(message, 1)

	stop(code)
end

local function runScript()
	local requireSuccess, requireResult = xpcall(require, debug.traceback, script.Main)
	if requireSuccess then
		local runSuccess, runResult = xpcall(requireResult, debug.traceback)
		if runSuccess then
			stop(0)
		else
			reportScriptError(runResult, 1)
		end
	else
		reportScriptError(requireResult, 1)
	end
end

HttpService:PostAsync(SERVER_URL .. "/start", "")
runScript()


