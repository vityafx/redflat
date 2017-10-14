-----------------------------------------------------------------------------------------------------------------------
--                                           RedFlat devicekit widget                                                --
-----------------------------------------------------------------------------------------------------------------------
-- Device kit quick menu
-----------------------------------------------------------------------------------------------------------------------

-- Grab environment
-----------------------------------------------------------------------------------------------------------------------
local table = table
local unpack = unpack
local string = string
local math = math
local io = io
local os = os

local wibox = require("wibox")
local awful = require("awful")
local beautiful = require("beautiful")
local color = require("gears.color")

local redflat = require("redflat")
local redutil = require("redflat.util")
local redtip = require("redflat.float.hotkeys")

-- Initialize tables and vars for module
-----------------------------------------------------------------------------------------------------------------------
local dkit = { objects = {}, mt = {} }

function dkit.new(args, style)

	-- Initialize vars
	--------------------------------------------------------------------------------
	-- local args = args or {}
	-- local count
	-- local object = {}
	-- local update_timeout = args.update_timeout or 3600
    --
	-- local style = redutil.table.merge(default_style(), style or {})
    --
	-- -- Create widget
	-- --------------------------------------------------------------------------------
	-- object.widget = svgbox(style.icon)
	-- object.widget:set_color(style.color.icon)
	-- table.insert(mail.objects, object)
    --
	-- -- Set tooltip
	-- --------------------------------------------------------------------------------
	-- object.tp = tooltip({ objects = { object.widget } }, style.tooltip)
	-- object.tp:set_text("0 new messages")
    --
	-- -- Update info function
	-- --------------------------------------------------------------------------------
	-- local function mail_count(output)
	-- 	local c = tonumber(string.match(output, "%d+"))
    --
	-- 	if c then
	-- 		count = count + c
	-- 		if style.need_notify and count > 0 then
	-- 			rednotify:show(redutil.table.merge({ text = count .. " new messages" }, style.notify))
	-- 		end
	-- 	end
    --
	-- 	local color = count > 0 and style.color.main or style.color.icon
	-- 	object.widget:set_color(color)
	-- 	object.tp:set_text(count .. " new messages")
	-- end
    --
	-- function object.update()
	-- 	count = 0
	-- 	for _, cmail in ipairs(maillist) do
	-- 		awful.spawn.easy_async(mail.check_function[cmail.checker](cmail), mail_count)
	-- 	end
	-- end

	-- Set update timer
	--------------------------------------------------------------------------------
	local t = timer({ timeout = update_timeout })
	t:connect_signal("timeout", object.update)
	t:start()

	if style.firstrun then t:emit_signal("timeout") end

	--------------------------------------------------------------------------------
	return object.widget
end

-- Update mail info for every widget
-----------------------------------------------------------------------------------------------------------------------
function dkit:update()
	for _, o in ipairs(mail.objects) do o.update() end
end

-- Config metatable to call mail module as function
-----------------------------------------------------------------------------------------------------------------------
function mail.mt:__call(...)
	return mail.new(...)
end

return dkit
