-- The one place that decides which renderer class draws a Pokemon for the
-- current Sprite Style, so lib/spawn_manager.lua and lib/follower_adapter.lua
-- never branch on style themselves.
--
-- STYLE_PMD returns a lib/pmd_renderer.lua when the species has PMDCollab
-- art; a species without any (about 50 of them, and a checkout that never
-- ran tools/generate_pmd_sprites.py) quietly draws in
-- SpriteSource.PMD_FALLBACK_STYLE through lib/actor_renderer.lua instead.
local V = ...
local SpriteSource = V.require("sprite_source")
local ActorRenderer = V.require("actor_renderer")
local PmdRenderer = V.require("pmd_renderer")

local RendererFactory = {}

--- `dex` = an art key (a national dex number, or "%03d-<form>" for an
--- alternate form; see lib/sprite_source.lua); `presentation` is only used by the
--- ActorRenderer styles (see lib/sprite_source.lua).
function RendererFactory.new(mod, dex, shiny, style, presentation)
  if style == SpriteSource.STYLE_PMD then
    local info = SpriteSource.pmdInfo(mod, dex)
    if info then return PmdRenderer.new(mod, dex, shiny, info) end
    if SpriteSource.isForm(dex) and not SpriteSource.hasOwnArt(mod, dex) then
      -- a form with no PMD art and no HGSS art either: its base species' PMD sheet
      local base = SpriteSource.baseOf(dex)
      local baseInfo = SpriteSource.pmdInfo(mod, base)
      if baseInfo then return PmdRenderer.new(mod, base, shiny, baseInfo) end
    end
    style = SpriteSource.PMD_FALLBACK_STYLE
  end
  return ActorRenderer.new(mod, dex, shiny, style, presentation)
end

return RendererFactory
