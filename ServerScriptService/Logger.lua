-- ModuleScript: Logger
-- Path: ServerScriptService/Logger.lua

local Logger = {}
Logger.__index = Logger

Logger.Levels = {
	NONE  = 0, -- No logging at all
	FATAL = 1, -- Critical errors that halt execution (uses warn + error())
	ERROR = 2, -- Significant errors, but execution might continue (uses warn)
	WARN  = 3, -- Potential issues or unexpected situations (uses warn)
	INFO  = 4, -- General information, phase starts/ends, major summaries
	DEBUG = 5, -- Detailed information for developers
	TRACE = 6  -- Extremely verbose, per-iteration/per-cell details
}

-- Internal state for the logger
local loggerSettings = {
	logLevel = Logger.Levels.INFO, -- Default level, will be overridden by Configure
	showTimestamp = true,
	showSource = true,
	defaultSource = "DefaultSrc", -- Default source if none provided in log call
}

-- Store level names for easy lookup (used in formatMessage)
local levelNames = {}
for name, value in pairs(Logger.Levels) do
	levelNames[value] = name
end

-- ---- Private Helper ----
local function formatMessage(level, source, ...)
	local messageParts = {}
	if loggerSettings.showTimestamp then
		table.insert(messageParts, string.format("[%s]", os.date("%X"))) -- HH:MM:SS
	end
	if loggerSettings.showSource and source then
		table.insert(messageParts, string.format("[%s]", source))
	end

	-- Add the level name to the message
	local currentLevelName = levelNames[level] or "UNKNOWN_LVL"
	table.insert(messageParts, string.format("[%s]", currentLevelName))

	local messageArgs = {...}
	if #messageArgs == 0 then
		table.insert(messageParts, "<No Message Provided>")
	elseif typeof(messageArgs[1]) == "string" and #messageArgs > 1 then
		-- Attempt to format if first arg is string and there are more args
		local success, result = pcall(string.format, table.unpack(messageArgs))
		if success then
			table.insert(messageParts, result)
		else
			-- Fallback to simple concatenation if string.format fails
			for i = 1, #messageArgs do
				table.insert(messageParts, tostring(messageArgs[i]))
			end
		end
	else
		-- Single argument or non-string first argument, just tostring them
		for i = 1, #messageArgs do
			table.insert(messageParts, tostring(messageArgs[i]))
		end
	end
	return table.concat(messageParts, " ")
end

-- ---- Public API ----

function Logger:Configure(userConfig)
	if userConfig then
		-- Set log level from name (e.g., "DEBUG")
		if userConfig.logLevelName and Logger.Levels[string.upper(userConfig.logLevelName)] then
			loggerSettings.logLevel = Logger.Levels[string.upper(userConfig.logLevelName)]
			-- Or set log level from numeric value (e.g., 5)
		elseif userConfig.logLevelValue and levelNames[userConfig.logLevelValue] then
			loggerSettings.logLevel = userConfig.logLevelValue
		end

		if userConfig.showTimestamp ~= nil then
			loggerSettings.showTimestamp = userConfig.showTimestamp
		end
		if userConfig.showSource ~= nil then
			loggerSettings.showSource = userConfig.showSource
		end
		if userConfig.defaultSource then
			loggerSettings.defaultSource = userConfig.defaultSource
		end
	end

	-- Log the configuration application itself, if INFO or higher is enabled
	-- This uses the print function directly to avoid a recursive loop if logging is NONE.
	if loggerSettings.logLevel >= Logger.Levels.INFO then
		local appliedLevelName = levelNames[loggerSettings.logLevel] or "UNKNOWN_LVL"
		local configMsg = string.format("[Logger] Configuration applied. Log Level: %s (%d). Timestamp: %s. Source: %s.",
			appliedLevelName,
			loggerSettings.logLevel,
			tostring(loggerSettings.showTimestamp),
			tostring(loggerSettings.showSource)
		)
		print(configMsg) -- Use raw print here to ensure it always shows for config
	end
end

function Logger:IsLevelEnabled(level)
	-- Ensures level is a number before comparison
	if typeof(level) ~= "number" then
		warn(formatMessage(Logger.Levels.WARN, "Logger", "IsLevelEnabled received non-numeric level: %s", tostring(level)))
		return false
	end
	return level <= loggerSettings.logLevel
end

-- Specific log functions
function Logger:Fatal(source, ...)
	if loggerSettings.logLevel < Logger.Levels.FATAL then return end
	local message = formatMessage(Logger.Levels.FATAL, source or loggerSettings.defaultSource, ...)
	warn(message)
	error(message, 0) -- error() with level 0 avoids adding extra script info to the message itself
end

function Logger:Error(source, ...)
	if loggerSettings.logLevel < Logger.Levels.ERROR then return end
	warn(formatMessage(Logger.Levels.ERROR, source or loggerSettings.defaultSource, ...))
end

function Logger:Warn(source, ...)
	if loggerSettings.logLevel < Logger.Levels.WARN then return end
	warn(formatMessage(Logger.Levels.WARN, source or loggerSettings.defaultSource, ...))
end

function Logger:Info(source, ...)
	if loggerSettings.logLevel < Logger.Levels.INFO then return end
	print(formatMessage(Logger.Levels.INFO, source or loggerSettings.defaultSource, ...))
end

function Logger:Debug(source, ...)
	if loggerSettings.logLevel < Logger.Levels.DEBUG then return end
	print(formatMessage(Logger.Levels.DEBUG, source or loggerSettings.defaultSource, ...))
end

function Logger:Trace(source, ...)
	if loggerSettings.logLevel < Logger.Levels.TRACE then return end
	print(formatMessage(Logger.Levels.TRACE, source or loggerSettings.defaultSource, ...))
end

-- Generic log function (less common to use directly)
function Logger:Log(level, source, ...)
	if typeof(level) ~= "number" or level > loggerSettings.logLevel then return end

	if level <= Logger.Levels.WARN then -- FATAL is handled by Logger:Fatal which calls error()
		warn(formatMessage(level, source or loggerSettings.defaultSource, ...))
	else
		print(formatMessage(level, source or loggerSettings.defaultSource, ...))
	end
end

return Logger