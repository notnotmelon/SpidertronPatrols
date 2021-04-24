local circuit_connections = require "circuit-connections"

local dock_item = {
  type = "item",
  name = "sp-spidertron-dock",
  icon = "__SpidertronWaypoints__/graphics/icon/spidertron-dock.png",
  icon_size = 64,
  stack_size = 50,
  place_result = "sp-spidertron-dock-0",
  order = "b[personal-transport]-c[spidertron]-d[dock]",
  subgroup = "transport",
}

local dock_recipe = {
  type = 'recipe',
  name = 'sp-spidertron-dock',
  ingredients = {
    {'steel-chest', 4},
    {'spidertron-remote', 1}
  },
  energy_required = 4,
  results = {{'sp-spidertron-dock', 1}},
  enabled = false
}


--[[
-- "container" definition doesn't support filters, but does support circuit connections
local function create_spidertron_dock(inventory_size)
  return {
    type = "container",
    name = "sp-spidertron-dock-" .. inventory_size,
    icon = "__SpidertronWaypoints__/graphics/icon/spidertron-chest.png",
    icon_size = 64,
    inventory_size = inventory_size,
    picture = {
      layers = {
        {
          filename = "__SpidertronWaypoints__/graphics/entity/spidertron-chest.png",
          height = 100,
          hr_version = {
            filename = "__SpidertronWaypoints__/graphics/entity/hr-spidertron-chest.png",
            height = 199,
            priority = "high",
            scale = 0.5,
            width = 207
          },
          priority = "high",
          width = 104,
        },
        {
          draw_as_shadow = true,
          filename = "__SpidertronWaypoints__/graphics/entity/shadow.png",
          height = 75,
          hr_version = {
            draw_as_shadow = true,
            filename = "__SpidertronWaypoints__/graphics/entity/hr-shadow.png",
            height = 149,
            priority = "high",
            scale = 0.5,
            shift = {0.5625, 0.5},
            width = 277,
          },
          priority = "high",
          shift = {0.5625, 0.5},
          width = 138,
        },
      }
    },
    circuit_connector_sprites = circuit_connections.circuit_connector_sprites,
    circuit_wire_connection_point = circuit_connections.circuit_wire_connection_point,
    circuit_wire_max_distance = circuit_connections.circuit_wire_max_distance,
    max_health = 600,
    minable = {mining_time = 1, result = "sp-spidertron-dock"},
    corpse = "artillery-turret-remnants",
    fast_replaceable_group = "sp-spidertron-container",
    close_sound = {
      filename = "__base__/sound/metallic-chest-close.ogg",
      volume = 0.6
    },
    open_sound = {
      filename = "__base__/sound/metallic-chest-open.ogg",
      volume = 0.6
    },
    collision_box = {{-1.4, -1.4}, {1.4, 1.4}},
    selection_box = {{-1.5, -1.5}, {1.5, 1.5}},
    flags = {"placeable-neutral", "player-creation"},
  }
end
]]

local function create_spidertron_dock(inventory_size)
  -- TODO Fix map colors and collision masks
  return {
    type = "car",
    name = "sp-spidertron-dock-" .. inventory_size,
    localised_name = {"entity-name.sp-spidertron-dock"},
    icon = "__SpidertronWaypoints__/graphics/icon/spidertron-dock.png",
    icon_size = 64,
    inventory_size = inventory_size,
    rotation_speed = 0,
    effectivity = 1,
    consumption = "0MW",
    energy_source = {type = "void"},
    braking_force = 1,
    energy_per_hit_point = 0,
    friction = 1,
    weight = 1,
    minimap_representation = util.empty_sprite(),
    selected_minimap_representation = util.empty_sprite(),
    allow_passengers = false,
    animation = {
      direction_count = 1,
      layers = {
        {
          direction_count = 1,
          filename = "__base__/graphics/entity/artillery-turret/artillery-turret-base.png",
          height = 100,
          width = 104,
          priority = "high",
          hr_version = {
            direction_count = 1,
            filename = "__base__/graphics/entity/artillery-turret/hr-artillery-turret-base.png",
            height = 199,
            width = 207,
            priority = "high",
            scale = 0.5,
          },
        },
        {
          direction_count = 1,
          draw_as_shadow = true,
          filename = "__base__/graphics/entity/artillery-turret/artillery-turret-base-shadow.png",
          height = 75,
          width = 138,
          shift = {0.5625, 0.5},
          priority = "high",
          hr_version = {
            direction_count = 1,
            draw_as_shadow = true,
            filename = "__base__/graphics/entity/artillery-turret/hr-artillery-turret-base-shadow.png",
            height = 149,
            width = 277,
            shift = {0.5625, 0.5},
            priority = "high",
            scale = 0.5,
          },
        },
      }
    },
    --circuit_connector_sprites = circuit_connections.circuit_connector_sprites,
    --circuit_wire_connection_point = circuit_connections.circuit_wire_connection_point,
    --circuit_wire_max_distance = circuit_connections.circuit_wire_max_distance,
    max_health = 600,
    minable = {mining_time = 1, result = "sp-spidertron-dock"},
    placeable_by = {item = "sp-spidertron-dock", count = 1},
    corpse = "artillery-turret-remnants",
    --fast_replaceable_group = "sp-spidertron-container",
    close_sound = {
      filename = "__base__/sound/metallic-chest-close.ogg",
      volume = 0.6
    },
    open_sound = {
      filename = "__base__/sound/metallic-chest-open.ogg",
      volume = 0.6
    },
    collision_box = {{-1.4, -1.4}, {1.4, 1.4}},
    selection_box = {{-1.5, -1.5}, {1.5, 1.5}},
    flags = {"placeable-neutral", "player-creation"},
  }
end


local sizes_created = {0}
data:extend{create_spidertron_dock(0)}
for _, spider_prototype in pairs(data.raw["spider-vehicle"]) do
  local inventory_size = spider_prototype.inventory_size
  if not contains(sizes_created, inventory_size) then
    data:extend{create_spidertron_dock(inventory_size)}
    table.insert(sizes_created, inventory_size)
  end
end

data:extend{dock_item, dock_recipe}