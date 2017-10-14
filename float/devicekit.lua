-----------------------------------------------------------------------------------------------------------------------
--                                        RedFlat devicekit launcher widget                                        --
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

-- Grab environment
-----------------------------------------------------------------------------------------------------------------------
local table = table
local unpack = unpack
local string = string
local math = math
local io = io
local os = os

local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")

local svgbox = require("redflat.gauge.svgbox")
local redutil = require("redflat.util")
local decoration = require("redflat.float.decoration")
local redtip = require("redflat.float.hotkeys")
local rednotify = require("redflat.float.notify")
local naughty = require("naughty")


local function print(text)
    rednotify:show({ text = text })
end
local function print2(text)
    naughty.notify({ title = "Echo", text = text, timeout = 0 })
end
local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"'..k..'"' end
            s = s .. '['..k..'] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function escape_html_spaces(str)
    return string.gsub(str, "\\x20", " ")
end


function round(num, numDecimalPlaces)
  local mult = 10 ^ (numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end
local dbus_interface = "redflat.devicekit"

-- Initialize tables and vars for module
-----------------------------------------------------------------------------------------------------------------------
local dkit = { actionlist = {}, command = "", keys = {} }

local actions = {}
local lastquery = nil

-- key bindings
dkit.keys.move = {
	{
		{}, "Down", function() dkit:down() end,
		{ description = "Select next item", group = "Navigation" }
	},
	{
		{}, "Up", function() dkit:up() end,
		{ description = "Select previous item", group = "Navigation" }
	},
}

dkit.keys.action = {
	{
		{ "Mod4" }, "F1", function() redtip:show() end,
		{ description = "Show hotkeys helper", group = "Action" }
	},
}

dkit.keys.all = awful.util.table.join(dkit.keys.move, dkit.keys.action)


-- Generate default theme vars
-----------------------------------------------------------------------------------------------------------------------
local function default_style()
	local style = {
		itemnum          = 8,
		geometry         = { width = 620, height = 440 },
		border_margin    = { 10, 10, 10, 10 },
		title_height     = 48,
		prompt_height    = 35,
		parser           = {},
		list_text_vgap   = 4,
		name_font        = "Sans Bold 12",
		comment_font     = "Sans 11",
		border_width     = 2,
		keytip           = { geometry = { width = 400, height = 250 } },
		dimage           = redutil.base.placeholder(),
		color            = { border = "#575757", text = "#aaaaaa", highlight = "#eeeeee", main = "#b1222b",
		                     bg = "#161616", bg_second = "#181818", wibox = "#202020", }
	}
	return redutil.table.merge(style, redutil.table.check(beautiful, "float.dkit") or {})
end

-- Support functions
-----------------------------------------------------------------------------------------------------------------------

-- Fuction to build list item
--------------------------------------------------------------------------------
local function construct_item(style)
	local item = {
		name    = wibox.widget.textbox(),
		comment = wibox.widget.textbox(),
		bg      = style.color.bg,
		cmd     = ""
	}

	item.name:set_font(style.name_font)
	item.comment:set_font(style.comment_font)

	-- Construct item layouts
	------------------------------------------------------------
	local text_vertical = wibox.layout.fixed.vertical()
	local text_horizontal = wibox.layout.align.horizontal()
	text_horizontal:set_left(text_vertical)
	text_vertical:add(wibox.container.margin(item.name, 0, 0, style.list_text_vgap))
	text_vertical:add(item.comment)

	local item_horizontal  = wibox.layout.align.horizontal()
	item_horizontal:set_middle(text_horizontal)

	item.layout = wibox.container.background(item_horizontal, item.bg)

	-- Item functions
	------------------------------------------------------------
	function item:set(args)
		local args = args or {}

		local name_text = awful.util.escape(args.title) or ""
		item.name:set_text(name_text)

		local comment_text = args.description and awful.util.escape(args.description)
		                     or args.title and "No description"
		                     or ""
		item.comment:set_text(comment_text)

		item.action = args.action
	end

	function item:set_bg(color)
		item.bg = color
		item.layout:set_bg(color)
	end

	function item:set_select()
		item.layout:set_bg(style.color.main)
		item.layout:set_fg(style.color.highlight)
	end

	function item:set_unselect()
		item.layout:set_bg(item.bg)
		item.layout:set_fg(style.color.text)
	end

	function item:run()
	    item.action()
    end

	------------------------------------------------------------
	return item
end

-- Fuction to build application list
--------------------------------------------------------------------------------
local function construct_list(num, actions, style)
	local list = { selected = 1, position = 1 }
    list.style = style
    list.items = {}

	-- Construct application list
	------------------------------------------------------------
	local list_layout = wibox.layout.flex.vertical()
	list.layout = wibox.container.background(list_layout, style.color.bg)

	-- Application list functions
	------------------------------------------------------------
	function list:set_select(index)
		list.items[list.selected]:set_unselect()
		list.selected = index
		list.items[list.selected]:set_select()
	end

	function list:update(t)
		for i = list.position, (list.position - 1 + num) do list.items[i - list.position + 1]:set(t[i]) end
		list:set_select(list.selected)
	end

    function list:change_items(items)
        for k, v in pairs(list.items) do
            list_layout:remove_widgets(v.layout)
        end

        list.items = {}

        for i = 1, num do
            list.items[i] = construct_item(style)
            list.items[i]:set_bg((i % 2) == 1 and style.color.bg or style.color.bg_second)
            list_layout:add(list.items[i].layout)
        end

        list:update(actions)
    end
	-- First run actions
	------------------------------------------------------------
    list:change_items(actions)
	list:update(actions)
	list:set_select(1)

	------------------------------------------------------------
	return list
end

-- Sort function
--------------------------------------------------------------------------------
local function sort_by_query(t, query)
	l = string.len(query)
	local function s(a, b)
		return string.lower(string.sub(a.title, 1, l)) == query and string.lower(string.sub(b.title, 1, l)) ~= query
	end
	table.sort(t, s)
end

-- Function to filter application list by quick search input
--------------------------------------------------------------------------------
local function list_filtrate(query)
	if lastquery ~= query then
		actions.current = {}

		for i, p in ipairs(actions.all) do
			if string.match(string.lower(p.title), query) then
				table.insert(actions.current, p)
			end
		end

		sort_by_query(actions.current, query)

		dkit.actionlist.position = 1
		dkit.actionlist:update(actions.current)
		dkit.actionlist:set_select(1)
		lastquery = query
	end
end

-- Functions to navigate through application list
-----------------------------------------------------------------------------------------------------------------------
function dkit:down()
	if self.actionlist.selected < math.min(self.itemnum, #actions.current) then
		self.actionlist:set_select(self.actionlist.selected + 1)
	elseif self.actionlist.selected + self.actionlist.position - 1 < #actions.current then
		self.actionlist.position = self.actionlist.position + 1
		self.actionlist:update(actions.current)
	end
end

function dkit:up()
	if self.actionlist.selected > 1 then
		self.actionlist:set_select(self.actionlist.selected - 1)
	elseif self.actionlist.position > 1 then
		self.actionlist.position = self.actionlist.position - 1
		self.actionlist:update(actions.current)
	end
end

-- Keypress handler
-----------------------------------------------------------------------------------------------------------------------
local function keypressed_callback(mod, key, comm)
	for _, k in ipairs(dkit.keys.all) do
		if redutil.key.match_prompt(k, mod, key) then k[3](); return true end
	end
	return false
end

local function drive_action_list()
    local list = {}
    return list
end

-- Initialize dkit widget
-----------------------------------------------------------------------------------------------------------------------
function dkit:init(args)

	-- Initialize vars
	--------------------------------------------------------------------------------
	local style = default_style()
    local args = args or {}
	self.itemnum = style.itemnum
	self.keytip = style.keytip
    self.prompt_text = "WOROLOL => "
    self.style = style

	actions.all = {}
	actions.current = awful.util.table.clone(actions.all)
   
    -- Default event handlers
    self.events = {
        driveAdded = args.driveAdded or function(data) self:driveAdded(data) end,
        deviceAdded = args.deviceAdded or function(data) self:deviceAdded(data) end,
        networkAdded = args.networkAdded or function(data) self:networkAdded(data) end,
        mouseAdded = args.mouseAdded or function(data) self:mouseAdded(data) end,
        usbAdded = args.usbAdded or function(data) self:usbAdded(data) end,
    }
    
	-- Set dbus signal handlers
    -- New disk connected notification
	dbus.request_name("system", "org.freedesktop.UDisks")
	dbus.add_match(
		"system",
		"path=/org/freedesktop/UDisks2, interface='org.freedesktop.DBus.ObjectManager', member='InterfacesAdded'"
	)
	dbus.connect_signal("org.freedesktop.DBus.ObjectManager",
		function (_, _, data)
            if data == nil then return end
            local props = data["org.freedesktop.UDisks2.Drive"]
            if props == nil then return end
            self.events.driveAdded(props)
        end
    )
    
    -- New network interface notification.
    -- New device connected.
    --
    -- The interface is registered by the awesome itself, and the method is called.
	dbus.request_name("session", dbus_interface)

    local need_connect = false -- true if we have anything in `self.events`
    for k, _ in pairs(self.events) do
        dbus.add_match(
            "session",
            "path=/, interface='" .. dbus_interface .. "', member='" .. k .. "'"
        )

        need_connect = true
    end

    if need_connect then
        dbus.connect_signal(dbus_interface,
            function (info, data)
                if info.member == nil then return end

                local handler = self.events[info.member]
                if handler ~= nil then
                    handler(data)
                end
            end
        )
    end


	-- Create quick search widget
	--------------------------------------------------------------------------------
	self.textbox = wibox.widget.textbox()
	self.textbox:set_ellipsize("start")

	-- Build application list
	--------------------------------------------------------------------------------
	self.actionlist = construct_list(dkit.itemnum, actions.current, style)

	-- Construct widget layouts
	--------------------------------------------------------------------------------
	local prompt_width = style.geometry.width - 2 * style.border_margin[1]
	                     - style.title_height
	local prompt_layout = wibox.container.constraint(self.textbox, "exact", prompt_width, style.prompt_height)

	local prompt_vertical = wibox.layout.align.vertical()
	prompt_vertical:set_expand("outside")
	prompt_vertical:set_middle(prompt_layout)

	local prompt_area_layout = wibox.container.constraint(prompt_vertical, "exact", nil, style.title_height)

	area_vertical = wibox.layout.align.vertical()
	area_vertical:set_top(prompt_area_layout)
	area_vertical:set_middle(wibox.container.margin(self.actionlist.layout, 0, 0, style.border_margin[3]))
	local area_layout = wibox.container.margin(area_vertical, unpack(style.border_margin))

	-- Create floating wibox for dkit widget
	--------------------------------------------------------------------------------
	self.wibox = wibox({
		ontop        = true,
		bg           = style.color.wibox,
		border_width = style.border_width,
		border_color = style.color.border
	})

	self.wibox:set_widget(area_layout)
	self.wibox:geometry(style.geometry)
end

-- Show dkit widget
-- Wibox appears on call and hides after "enter" or "esc" pressed
-----------------------------------------------------------------------------------------------------------------------
function dkit:show()
	if not self.wibox then
		self:init()
	else
		list_filtrate("")
		self.actionlist:set_select(1)
	end

	redutil.placement.centered(self.wibox, nil, mouse.screen.workarea)
	self.wibox.visible = true
	redtip:set_pack("Devicekit", self.keys.all, self.keytip.column, self.keytip.geometry)

	return awful.prompt.run({
		prompt = self.prompt_text,
		textbox = self.textbox,
		exe_callback = function () self.actionlist.items[self.actionlist.selected]:run() end,
		done_callback = function () self:hide() end,
		keypressed_callback = keypressed_callback,
		changed_callback = list_filtrate,
	})
end

function dkit:hide()
	self.wibox.visible = false
	redtip:remove_pack()
end

-- Set user hotkeys
-----------------------------------------------------------------------------------------------------------------------
function dkit:set_keys(keys, layout)
	local layout = layout or "all"
	if keys then
		self.keys[layout] = keys
		if layout ~= "all" then self.keys.all = awful.util.table.join(self.keys.move, self.keys.action) end
	end
end


-- Default handlers
function dkit:driveAdded(data)
	actions.all = {
        {
            title = "Partitions",
            description = "Show drive partitions",
            action = function(data) print("Partitions") end,
        },
        {
            title = "Info",
            description = "Show drive information",
            action = function(data) print("Info") end,
        }
    }
	actions.current = awful.util.table.clone(actions.all)
	self.actionlist:change_items(actions.current)
    self.prompt_text = data.Model .. " => "
    self:show()
end

function dkit:deviceAdded(data)
    print("Device added: " .. data) 
end

function dkit:networkAdded(data)
    print("Network added: " .. data)
end

function dkit:mouseAdded(data)
    print("Mouse added: " .. escape_html_spaces(data))
end

function dkit:usbAdded(data)
    print("USB: " .. data)
end

-- End
-----------------------------------------------------------------------------------------------------------------------
return dkit
