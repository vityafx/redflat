-----------------------------------------------------------------------------------------------------------------------
--                                           RedFlat audio player widget                                             --
-----------------------------------------------------------------------------------------------------------------------
-- Music player widget
-- Display audio track information with mpris2
-- Using dbus-send to control
-----------------------------------------------------------------------------------------------------------------------

-- Grab environment
-----------------------------------------------------------------------------------------------------------------------
local unpack = table.unpack
local math = math

local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local color = require("gears.color")
local timer = require("gears.timer")

local redutil = require("redflat.util")
local progressbar = require("redflat.gauge.graph.bar")
local dashcontrol = require("redflat.gauge.graph.dash")
local svgbox = require("redflat.gauge.svgbox")

-- Initialize and vars for module
-----------------------------------------------------------------------------------------------------------------------
local player = { box = {}, listening = false }

local dbus_mpris = "dbus-send --print-reply=literal --session --dest=org.mpris.MediaPlayer2.%s "
                  .. "/org/mpris/MediaPlayer2 "

local dbus_get = dbus_mpris
                 .. "org.freedesktop.DBus.Properties.Get "
                 .. "string:'org.mpris.MediaPlayer2.Player' %s"

local dbus_set = dbus_mpris
                 .. "org.freedesktop.DBus.Properties.Set "
                 .. "string:'org.mpris.MediaPlayer2.Player' %s"

local dbus_action = dbus_mpris
                    .. "org.mpris.MediaPlayer2.Player."


-- Generate default theme vars
-----------------------------------------------------------------------------------------------------------------------
local function default_style()
	local style = {
		geometry       = { width = 520, height = 150 },
		screen_gap     = 0,
		screen_pos     = nil,
		dashcontrol    = {},
		progressbar    = {},
		border_gap     = { 20, 20, 20, 20 },
		elements_gap   = { 20, 0, 0, 0 },
		volume_gap     = { 0, 0, 0, 3 },
		control_gap    = { 0, 0, 18, 8 },
		buttons_margin = { 0, 0, 3, 3 },
		pause_gap      = { 12, 12 },
		timeout        = 5,
		line_height    = 26,
		bar_width      = 8, -- progress bar height
		volume_width   = 50,
		titlefont      = "Sans 12",
		timefont       = "Sans 12",
		artistfont     = "Sans 12",
		border_width   = 2,
		icon           = {
			cover   = redutil.base.placeholder(),
			play    = redutil.base.placeholder({ txt = "►" }),
			pause   = redutil.base.placeholder({ txt = "[]" }),
			next_tr = redutil.base.placeholder({ txt = "→" }),
			prev_tr = redutil.base.placeholder({ txt = "←" }),
		},
		color          = { border = "#575757", main = "#b1222b",
		                   wibox = "#202020", gray = "#575757", icon = "#a0a0a0" }
	}
	return redutil.table.merge(style, redutil.table.check(beautiful, "float.player") or {})
end


-- Initialize player widget
-----------------------------------------------------------------------------------------------------------------------
function player:init(args)

	-- Initialize vars
	--------------------------------------------------------------------------------
	local args = args or {}
	local _player = args.name or "vlc"
	local style = default_style()
	local show_album = false

	self.info = { artist = "Unknown", album = "Unknown" }
	self.style = style
	self.last = { status = "Stopped", length = 5 * 60 * 1000000, volume = 0.5 }

	-- dbus vars
	self.command = {
		get_position = string.format(dbus_get, _player, "string:'Position'"),
		set_volume   = string.format(dbus_set, _player, "string:'Volume' variant:double:"),
		action       = string.format(dbus_action, _player),
		set_position = string.format(dbus_action, _player) .. "SetPosition objpath:/not/used int64:",
	}

	self._actions = { "PlayPause", "Next", "Previous" }

	-- Construct layouts
	--------------------------------------------------------------------------------

	-- progressbar and icon
	self.bar = progressbar(style.progressbar)
	self.box.image = svgbox(style.icon.cover)
	self.box.image:set_color(style.color.gray)

	-- Text lines
	------------------------------------------------------------
	self.box.title = wibox.widget.textbox("Title")
	self.box.artist = wibox.widget.textbox("Artist")
	for _, w in ipairs({ self.box.title, self.box.artist }) do
		w:set_font(style.titlefont)
		w:set_valign("top")
	end

	local text_area = wibox.layout.fixed.vertical()
	text_area:add(wibox.container.constraint(self.box.title, "exact", nil, style.line_height))
	text_area:add(wibox.container.constraint(self.box.artist, "exact", nil, style.line_height))

	-- Control line
	------------------------------------------------------------

	-- playback buttons
	local player_buttons = wibox.layout.fixed.horizontal()
	local prev_button = svgbox(style.icon.prev_tr, nil, style.color.icon)
	player_buttons:add(prev_button)

	self.play_button = svgbox(style.icon.play, nil, style.color.icon)
	player_buttons:add(wibox.container.margin(self.play_button, unpack(style.pause_gap)))

	local next_button = svgbox(style.icon.next_tr, nil, style.color.icon)
	player_buttons:add(next_button)

	-- time indicator
	self.box.time = wibox.widget.textbox("0:00")
	self.box.time:set_font(style.timefont)

	-- volume
	self.volume = dashcontrol(style.dashcontrol)
	local volumespace = wibox.container.margin(self.volume, unpack(style.volume_gap))
	local volume_area = wibox.container.constraint(volumespace, "exact", style.volume_width, nil)

	-- full line
	local buttons_align = wibox.layout.align.horizontal()
	buttons_align:set_expand("outside")
	buttons_align:set_middle(wibox.container.margin(player_buttons, unpack(style.buttons_margin)))

	local control_align = wibox.layout.align.horizontal()
	control_align:set_middle(buttons_align)
	control_align:set_right(self.box.time)
	control_align:set_left(volume_area)

	-- Bring it all together
	------------------------------------------------------------
	local align_vertical = wibox.layout.align.vertical()
	align_vertical:set_top(text_area)
	align_vertical:set_middle(wibox.container.margin(control_align, unpack(style.control_gap)))
	align_vertical:set_bottom(wibox.container.constraint(self.bar, "exact", nil, style.bar_width))
	local area = wibox.layout.fixed.horizontal()
	area:add(self.box.image)
	area:add(wibox.container.margin(align_vertical, unpack(style.elements_gap)))

	-- Buttons
	------------------------------------------------------------

	-- playback controll
	self.play_button:buttons(awful.util.table.join(awful.button({}, 1, function() self:action("PlayPause") end)))
	next_button:buttons(awful.util.table.join(awful.button({}, 1, function() self:action("Next") end)))
	prev_button:buttons(awful.util.table.join(awful.button({}, 1, function() self:action("Previous") end)))

	-- volume
	self.volume:buttons(awful.util.table.join(
		awful.button({}, 4, function() self:change_volume( 0.05) end),
		awful.button({}, 5, function() self:change_volume(-0.05) end)
	))

	-- position
	self.bar:buttons(awful.util.table.join(
		awful.button(
			{}, 1, function()
				local coords = {
					bar   = mouse.current_widget_geometry,
					wibox = mouse.current_wibox:geometry(),
					mouse = mouse.coords(),
				}

				local position = (coords.mouse.x - coords.wibox.x - coords.bar.x) / coords.bar.width
				awful.spawn.with_shell(self.command.set_position .. math.floor(self.last.length * position))
			end
		)
	))

	-- switch between artist and album info on mouse click
	self.box.artist:buttons(awful.util.table.join(
		awful.button({}, 1,
			function()
				show_album = not show_album
				self.update_artist()
			end
		)
	))

	-- Create floating wibox for player widget
	--------------------------------------------------------------------------------
	self.wibox = wibox({
		ontop        = true,
		bg           = style.color.wibox,
		border_width = style.border_width,
		border_color = style.color.border
	})

	self.wibox:set_widget(wibox.container.margin(area, unpack(style.border_gap)))
	self.wibox:geometry(style.geometry)

	-- Update info functions
	--------------------------------------------------------------------------------

	-- Function to set play button state
	------------------------------------------------------------
	self.set_play_button = function(state)
		self.play_button:set_image(style.icon[state])
	end

	-- Function to set info for artist/album line
	------------------------------------------------------------
	self.update_artist = function()
		if show_album then
			self.box.artist:set_markup('<span color="' .. style.color.gray .. '">From </span>' .. self.info.album)
		else
			self.box.artist:set_markup('<span color="' .. style.color.gray .. '">By </span>' .. self.info.artist)
		end
	end

	-- Set defs
	------------------------------------------------------------
	self.clear_info = function(is_att)
		self.box.image:set_image(style.icon.cover)
		self.box.image:set_color(is_att and style.color.main or style.color.gray)

		self.box.time:set_text("0:00")
		self.bar:set_value(0)
		-- self.box.title:set_text("Stopped")
		self.info = { artist = "", album = "" }
		self.update_artist()
	end

	-- Main update function
	------------------------------------------------------------
	function self:update()
		if self.last.status ~= "Stopped" then
			awful.spawn.easy_async(
				self.command.get_position,
				function(output, _, _, exit_code)

					-- dirty trick to clean up if player closed
					if exit_code ~= 0 then
						self.clear_info(true)
						self.last.status = "Stopped"
						return
					end

					-- set progress bar
					local position = string.match(output, "int64%s+(%d+)")
					local progress = position / self.last.length
					self.bar:set_value(progress)

					-- set current time
					local ps = math.floor(position / 10^6)
					local ct = string.format("%d:%02d", math.floor(ps / 60), ps % 60)
					self.box.time:set_text(ct)
				end
			)
		end
	end

	-- Set update timer
	--------------------------------------------------------------------------------
	self.updatetimer = timer({ timeout = style.timeout })
	self.updatetimer:connect_signal("timeout", function() self:update() end)

	-- Run dbus servise
	--------------------------------------------------------------------------------
	if not self.listening then self:listen() end
end

-- Player playback control
-----------------------------------------------------------------------------------------------------------------------
function player:action(args)
	if not awful.util.table.hasitem(self._actions, args) then return end
	if not self.wibox then self:init() end

	awful.spawn.with_shell(self.command.action .. args)
	self:update()
end

-- Player volume control
-----------------------------------------------------------------------------------------------------------------------
function player:change_volume(step)
	local v = self.last.volume + step
	if     v > 1 then v = 1
	elseif v < 0 then v = 0 end
	awful.spawn.with_shell(self.command.set_volume .. v)
end

-- Hide player widget
-----------------------------------------------------------------------------------------------------------------------
function player:hide()
	self.wibox.visible = false
	if self.updatetimer.started then self.updatetimer:stop() end
end

-- Show player widget
-----------------------------------------------------------------------------------------------------------------------
function player:show(geometry)
	if not self.wibox then self:init() end

	if not self.wibox.visible then
		self:update()

		if geometry then
			self.wibox:geometry(geometry)
		elseif self.style.set_position then
			self.wibox:geometry(self.style.set_position())
		else
			awful.placement.under_mouse(self.wibox)
		end
		redutil.placement.no_offscreen(self.wibox, self.style.screen_gap, screen[mouse.screen].workarea)

		self.wibox.visible = true
		if self.last.status == "Playing" then self.updatetimer:start() end
	else
		self:hide()
	end
end

-- Dbus signal setup
-- update some info which avaliable from dbus signal
-----------------------------------------------------------------------------------------------------------------------
function player:listen()
	dbus.request_name("session", "org.freedesktop.DBus.Properties")
	dbus.add_match(
		"session",
		"path=/org/mpris/MediaPlayer2, interface='org.freedesktop.DBus.Properties', member='PropertiesChanged'"
	)
	dbus.connect_signal("org.freedesktop.DBus.Properties",
		function (_, _, data)

			-- empty call
			if not data then return end

			-- set track info if playing
			if data.Metadata then
				-- set song title
				self.box.title:set_text(data.Metadata["xesam:title"] or "Unknown")

				-- set album or artist info
				self.info.artist = data.Metadata["xesam:artist"] and data.Metadata["xesam:artist"][1] or "Unknown"
				self.info.album  = data.Metadata["xesam:album"] or "Unknown"
				self.update_artist()

				-- set cover art
				if data.Metadata["mpris:artUrl"] then
					local image = string.match(data.Metadata["mpris:artUrl"], "file://(.+)")
					self.box.image:set_color(nil)
					self.box.image:set_image(image)
				end

				-- track length
				if data.Metadata["mpris:length"] then self.last.length = data.Metadata["mpris:length"] end
			end

			if data.PlaybackStatus then

				-- check player status and set suitable play/pause button image
				local state = data.PlaybackStatus == "Playing" and "pause" or "play"
				self.set_play_button(state)
				self.last.status = data.PlaybackStatus

				-- stop/start update timer
				if data.PlaybackStatus == "Playing" then
					if self.wibox.visible then self.updatetimer:start() end
				else
					if self.updatetimer.started then self.updatetimer:stop() end
					self:update()
				end

				-- clear track info if stoppped
				if data.PlaybackStatus == "Stopped" then
					self.clear_info()
				end
			end

			-- volume
			if data.Volume then
				self.volume:set_value(data.Volume)
				self.last.volume = data.Volume
			end
		end
	)

	self.listening = true
end

-- End
-----------------------------------------------------------------------------------------------------------------------
return player
