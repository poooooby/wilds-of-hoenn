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

--- Whether a PMDCollab sprite with this presentation is drawn swimming (cut at its
--- waterline with foam): any water presentation, unless the species is a true flyer
--- (SpriteSource.pmdFlies, lib/pmd_water.lua).
function RendererFactory.pmdSwims(dex, presentation)
  local water = presentation == SpriteSource.PRESENTATION_SWIMMING
    or presentation == SpriteSource.PRESENTATION_LEVITATES
  return water and not SpriteSource.pmdFlies(dex) or false
end

--- `dex` = an art key (a national dex number, or "%03d-<form>" for an
--- alternate form; see lib/sprite_source.lua); `presentation` is only used by the
--- ActorRenderer styles (see lib/sprite_source.lua).
function RendererFactory.new(mod, dex, shiny, style, presentation)
  if style == SpriteSource.STYLE_PMD then
    local info = SpriteSource.pmdInfo(mod, dex)
    local renderer
    if info then
      renderer = PmdRenderer.new(mod, dex, shiny, info)
    elseif SpriteSource.isForm(dex) and not SpriteSource.hasOwnArt(mod, dex) then
      -- a form with no PMD art and no HGSS art either: its base species' PMD sheet
      local base = SpriteSource.baseOf(dex)
      local baseInfo = SpriteSource.pmdInfo(mod, base)
      if baseInfo then renderer = PmdRenderer.new(mod, base, shiny, baseInfo) end
    end
    if renderer then
      renderer.swimming = RendererFactory.pmdSwims(dex, presentation)
      return renderer
    end
    style = SpriteSource.PMD_FALLBACK_STYLE
  end
  return ActorRenderer.new(mod, dex, shiny, style, presentation)
end

return RendererFactory
