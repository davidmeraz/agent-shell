-- Integración nativa de Agent Shell con Hyprland y el tema Gema.
-- Reglas aisladas por app_id Wayland ("agent-shell"): vidrio translúcido con blur nativo y esquinas a juego.
local agent_bin = (os.getenv("HOME") or "") .. "/.local/bin/agent-shell"
local f = io.open(agent_bin, "r")
if f then
    f:close()
    agent_bin = string.format('%q', agent_bin)
else
    agent_bin = "agent-shell"
end

hl.window_rule({
    match = { class = "agent-shell" },
    float = true,
    opaque = false,
    opacity = "1.0 override",
    border_size = 0,
    no_shadow = true,
    rounding = 20,
})

hl.unbind("SUPER + A")
hl.bind("SUPER + A", hl.dsp.exec_cmd(agent_bin .. " --toggle"))
