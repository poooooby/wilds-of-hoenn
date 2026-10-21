-- The Battler hotkey: one controller button or keyboard key (the Battler: Pad / Battler: Key
-- options) switches the partner between Battle and Follow while the player walks around.
--
-- main.lua wraps gen1recomp's `input.key` / `input.gamepad` hooks, which see every key and
-- button press before the engine does, and hands each event to `onKey` / `onPad`. A press
-- of the chosen key / shoulder is ours only while the overworld is free (`deps.free`: no
-- script, message, menu, fade, warp, step event or battle; walking is fine): then the role
-- flips (Battle -> Follow, anything else -> Battle), a label pops over the partner and the
-- press is swallowed, so the same button does not also open FireRed / LeafGreen's Help or
-- act as A (Button Mode L=A). Any other time -- a menu (the bag pages with L / R), a battle,
-- another key -- it goes straight through untouched. Holding the key flips once: it must
-- be let go before it flips again.
local RoleHotkey = {}
RoleHotkey.__index = RoleHotkey

-- the option's value -> the gamepad button LOVE reports / the key it reports
RoleHotkey.PAD_BUTTON = { l = "leftshoulder", r = "rightshoulder" }
RoleHotkey.KEY = { q = "q", e = "e", r = "r" }

RoleHotkey.LABEL = { battle = "Battling!", follow = "Following" }

--- The role a press switches to from `role`. Pure.
function RoleHotkey.nextRole(role)
  if role == "battle" then return "follow" end
  return "battle"
end

--- deps:
---   padChoice(), keyChoice()  the options ("l" / "r" / "off", "q" / "e" / "r" / "off")
---   free()                    the overworld is free for it
---   current()                 the partner now: mon, role (nil mon: none)
---   set(mon, role)            make it so (Companion:set); true when done
---   notify(text)              the label over the partner
---   sound()                   the select sound
function RoleHotkey.new(deps)
  return setmetatable({ deps = deps or {}, held = {} }, RoleHotkey)
end

-- one press of the chosen input `id`: true when it was ours (swallow it)
function RoleHotkey:_press(id)
  if self.held[id] then return true end -- still held from the press that flipped it
  local d = self.deps
  if not (d.free and d.free()) then return false end
  local mon, role = nil, nil
  if d.current then mon, role = d.current() end
  if not mon then return false end
  local want = RoleHotkey.nextRole(role)
  if not (d.set and d.set(mon, want)) then return false end
  self.held[id] = true
  if d.notify then d.notify(RoleHotkey.LABEL[want] or want) end
  if d.sound then d.sound() end
  return true
end

-- a release of `id`: true when its press was ours (swallow the release too)
function RoleHotkey:_release(id)
  if not self.held[id] then return false end
  self.held[id] = nil
  return true
end

--- An `input.key` event ({ phase, key }): true = ours, do not pass it on.
function RoleHotkey:onKey(ev)
  if type(ev) ~= "table" then return false end
  local choice = self.deps.keyChoice and self.deps.keyChoice()
  local key = RoleHotkey.KEY[choice]
  if not key or ev.key ~= key then return false end
  local id = "key:" .. key
  if ev.phase == "pressed" then return self:_press(id) end
  if ev.phase == "released" then return self:_release(id) end
  return false
end

--- An `input.gamepad` event ({ phase, button, ... }): true = ours, do not pass it on.
function RoleHotkey:onPad(ev)
  if type(ev) ~= "table" then return false end
  local choice = self.deps.padChoice and self.deps.padChoice()
  local button = RoleHotkey.PAD_BUTTON[choice]
  if not button or ev.button ~= button then return false end
  local id = "pad:" .. button
  if ev.phase == "pressed" then return self:_press(id) end
  if ev.phase == "released" then return self:_release(id) end
  return false
end

--- Forget held keys (focus lost, a save loaded): the next press flips again.
function RoleHotkey:reset()
  self.held = {}
end

return RoleHotkey
