local event_handler = require "event_handler"
util = require "util"
require "scripts.utils"
gui = require "scripts.gui-lite"

local Dock = require "scripts.dock"
local PatrolGui = require "scripts.patrol-gui"
SpidertronControl = require "scripts.spidertron-control"
PatrolRemote = require "scripts.patrol-remote"
WaypointRendering = require "scripts.waypoint-rendering"


Control = {}

--[[
Globals:
storage.spidertron_waypoints: indexed by spidertron.unit_number:
  spidertron :: LuaEntity
  waypoints :: array of Waypoint
  Waypoint contains
    type :: string ("none", "time-passed", "inactivity", "full-inventory", "empty-inventory", "robots-inactive", "passenger-present", "passenger-not-present", "item-count", "circuit-condition")
    position :: Position (Concept)
    wait_time? :: int (in seconds, only with "time-passed" or "inactivity")
    item_count_info? :: array containing
      item_name :: string or SignalID (depending on if type is "item-count" or "circuit-condition")
      condition :: int (index of condition_dropdown_contents)
      count :: int
    render :: LuaRenderObject
  current_index :: int (index of waypoints)
  tick_arrived? :: int (only set when at a waypoint)
  tick_inactive? :: int (only used whilst at an "inactivity" waypoint)
  previous_inventories? :: table (only used whilst at an "inactivity" waypoint)
  on_patrol :: bool
  renders :: array of LuaRenderObject
]]

---@alias PlayerIndex uint
---@alias UnitNumber uint
---@alias GameTick uint
---@alias LuaRenderID uint

---@alias WaypointType "none" | "time-passed" | "inactivity" | "full-inventory" | "empty-inventory" | "robots-inactive" | "passenger-present" | "passenger-not-present" | "item-count" | "circuit-condition"
---@alias WaypointIndex uint

---@class Waypoint
---@field type WaypointType
---@field position MapPosition
---@field wait_time uint?
---@field item_condition_info {elem: ItemIDAndQualityIDPair, count: integer, condition: integer}?
---@field circuit_condition_info {elem: SignalID, count: integer, condition: integer}?
---@field render LuaRenderObject

---@class WaypointInfo
---@field spidertron LuaEntity
---@field waypoints table<WaypointIndex, Waypoint>
---@field renders LuaRenderObject[]
---@field current_index WaypointIndex
---@field on_patrol boolean
---@field tick_arrived GameTick?
---@field tick_inactive GameTick?
---@field previous_inventories table?
---@field stopped boolean?
---@field last_distance number?

---@param spidertron LuaEntity
---@return WaypointInfo
function get_waypoint_info(spidertron)
  local waypoint_info = storage.spidertron_waypoints[spidertron.unit_number]
  if not waypoint_info then
    log("No waypoint info found. Creating blank table")
    storage.spidertron_waypoints[spidertron.unit_number] = {
      spidertron = spidertron,
      waypoints = {},
      renders = {},
      current_index = 1,
      on_patrol = false
    }
    waypoint_info = storage.spidertron_waypoints[spidertron.unit_number]
  end
  return waypoint_info
end

RemoteInterface = require "scripts.remote-interface"

---@param spidertron_id LuaEntity | UnitNumber
function Control.clear_spidertron_waypoints(spidertron_id)
  -- Called on custom-input or whenever the current autopilot_destination is removed or when the spidertron is removed.
  -- Pass in either `spidertron` or `unit_number`
  local waypoint_info
  ---@type UnitNumber
  local unit_number
  if type(spidertron_id) == "number" then
    ---@cast spidertron_id UnitNumber
    waypoint_info = storage.spidertron_waypoints[unit_number]
    if not waypoint_info then return end
    unit_number = spidertron_id
  else
    ---@cast spidertron_id LuaEntity
    waypoint_info = get_waypoint_info(spidertron_id)
    spidertron_id.autopilot_destination = nil
    unit_number = spidertron_id.unit_number  ---@cast unit_number -?
  end
  log("Clearing spidertron waypoints for unit number " .. unit_number)
  for _, waypoint in pairs(waypoint_info.waypoints) do
    if waypoint.render then
      waypoint.render.destroy()
    end
  end
  waypoint_info.waypoints = {}
  PatrolGui.update_gui_schedule(waypoint_info)
  WaypointRendering.update_spidertron_render_paths(unit_number)
  storage.spidertron_waypoints[unit_number] = nil
end

script.on_event("sp-delete-all-waypoints",
  function(event)
    local player = game.get_player(event.player_index)  ---@cast player -?
    local spidertron_remote_selection = player.spidertron_remote_selection
    if spidertron_remote_selection then
      for _, spidertron in pairs(spidertron_remote_selection) do  -- TODO remove loop if enforcing only one connection to patrol remote?
        Control.clear_spidertron_waypoints(spidertron)
        spidertron.autopilot_destination = nil
      end
    end
  end
)

-- Detect when the player cancels a spidertron's autopilot_destination
script.on_event({"move-right-custom", --[["move-left-custom",]] "move-up-custom", "move-down-custom"},
  function(event --[[@as EventData.CustomInputEvent]])
    local player = game.get_player(event.player_index)  ---@cast player -?
    local vehicle = player.vehicle
    if vehicle and vehicle.type == "spider-vehicle" and player.render_mode == defines.render_mode.game then  -- Render mode means player isn't in map view...
      local waypoint_info = get_waypoint_info(vehicle)
      waypoint_info.on_patrol = false
      PatrolGui.update_gui_switch(waypoint_info)
    end
  end
)

---@param event EventData.on_object_destroyed
local function on_object_destroyed(event)
  local unit_number = event.useful_id
  Control.clear_spidertron_waypoints(unit_number)
end


local function process_active_mods()
  local version_string = script.active_mods["base"]
  local version_strings = util.split(version_string, ".")
  local version = {}  ---@type uint[]
  for i=1, #version_strings do
    version[i] = tonumber(version_strings[i])
  end
  storage.base_version = version

  storage.freight_forwarding_enabled = script.active_mods["FreightForwarding"] ~= nil
  storage.freight_forwarding_container_items = {}
  if storage.freight_forwarding_enabled then
    for name, _ in pairs(prototypes.item) do
      if name:sub(1, 15) == "deadlock-crate-" or name:sub(1, 13) == "ic-container-" then
        -- Old versions of FF use DCM, newer versions use IC
        storage.freight_forwarding_container_items[name] = true
      end
    end
  end
end

local function setup()
  process_active_mods()
  ---@type table<UnitNumber, WaypointInfo>
  storage.spidertron_waypoints = {}
  ---@type table<PlayerIndex, table<UnitNumber, table<WaypointIndex, LuaRenderObject>>>
  storage.path_renders = {}
  ---@type table<LuaRenderID, LuaCustomChartTag[]>
  storage.chart_tags = {}
  ---@type table<PlayerIndex, WaypointIndex>
  storage.remotes_in_cursor = {}
  ---@type table<PlayerIndex, table<LuaRenderID, table<LuaRenderObject, GameTick>>>
  storage.blinking_renders = {}

  ---@type table<UnitNumber, DockData>
  storage.spidertron_docks = {}
  ---@type table<UnitNumber, UnitNumber>
  storage.spidertrons_docked = {}
  ---@type table<GameTick, LuaEntity[]>
  storage.scheduled_dock_replacements = {}

  ---@type table<PlayerIndex, GuiElements>
  storage.open_gui_elements = {}
  ---@type table<PlayerIndex, {button: LuaGuiElement, tick_started: GameTick}>
  storage.player_highlights = {}  -- Indexed by player.index

  RemoteInterface.connect_to_remote_interfaces()
  WaypointRendering.update_render_players()
  --settings_changed()
end

local function config_changed_setup(changed_data)
  process_active_mods()
  -- Only run when this mod was present in the previous save as well. Otherwise, on_init will run.
  local mod_changes = changed_data.mod_changes
  local old_version_string
  if mod_changes and mod_changes["SpidertronPatrols"] and mod_changes["SpidertronPatrols"]["old_version"] then
    old_version_string = mod_changes["SpidertronPatrols"]["old_version"]
  else
    return
  end

  -- Close all spidertron GUIs
  for _, player in pairs(game.players) do
    if player.opened_gui_type == defines.gui_type.entity then
      local entity = player.opened  --[[@as LuaEntity]]
      if entity and entity.object_name == "LuaEntity" and entity.type == "spider-vehicle" then
        player.opened = nil
      end
    end
  end

  storage.wait_time_defaults = nil

  log("Coming from old version: " .. old_version_string)
  local version_strings = util.split(old_version_string, ".")
  local old_version = {}
  for i=1, #version_strings do
    old_version[i] = tonumber(version_strings[i])
  end

  if old_version[1] == 2 then
    if old_version[2] < 1 then
      -- Pre 2.1
      storage.path_renders = {}
      storage.player_highlights = {}
    end
    if old_version[2] < 3 then
      -- Pre 2.3
      storage.scheduled_dock_replacements = {}
    end
    if old_version[2] < 3 or (old_version[2] == 3 and old_version[3] < 2) then
      -- Pre 2.3.2
      storage.chart_tags = {}
    end
    if old_version[2] < 4 then
      -- Pre 2.4
      storage.remotes_in_cursor = {}
      storage.blinking_renders = {}
    end
    if old_version[2] < 5 then
      -- Pre 2.5. Has to go at end so that globals can be initialized first.
      reset_render_objects()
      -- Disconnect all spidertrons from docks, since previous_items format has changed
      for _, dock_data in pairs(storage.spidertron_docks) do
        local spidertron = dock_data.connected_spidertron
        local dock = dock_data.dock

        if dock and dock.valid and dock.name ~= "sp-spidertron-dock-closing" and spidertron and spidertron.valid then
          storage.spidertrons_docked[spidertron.unit_number] = nil
          dock = replace_dock(dock, "sp-spidertron-dock")
          storage.spidertron_docks[dock.unit_number] = {dock = dock}
        end
      end
    end
  end
end

Control.on_init = setup
Control.on_configuration_changed = config_changed_setup
Control.events = {
  [defines.events.on_object_destroyed] = on_object_destroyed,
}

function reset_render_objects()
  rendering.clear("SpidertronPatrols")
  storage.path_renders = {}
  storage.blinking_renders = {}
  WaypointRendering.update_render_players()
  for _, waypoint_info in pairs(storage.spidertron_waypoints) do
    local spidertron = waypoint_info.spidertron
    if spidertron and spidertron.valid then
      WaypointRendering.update_render_text(waypoint_info.spidertron)
    end
  end
  for _, player in pairs(game.players) do
    WaypointRendering.update_player_render_paths(player)
  end
end

commands.add_command("reset-sp-render-objects",
  "Clears all render objects (numbers and lines on the ground) created by Spidertron Patrols and recreates only the objects that are supposed to exist. Use whenever render objects are behaving unexpectedly or have been permanently left behind due to a mod bug or incompatibility.",
  function()
    reset_render_objects()
    game.print("Render objects reset")
  end
)

event_handler.add_libraries{
  gui,
  Control,
  RemoteInterface,
  Dock,
  PatrolGui,
  PatrolRemote,
  SpidertronControl,
  WaypointRendering
}
