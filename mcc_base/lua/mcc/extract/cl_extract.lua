-- Everyone sees an incoming supply drop on their HUD until somebody opens it.

local X = MCC.Extract

local cvMarker = CreateClientConVar("mcc_extract_marker", "1", true, false, "Show supply drop markers on the HUD.")
local AMBER = Color(222, 182, 70)

local crates, nextCrates = {}, 0

hook.Add("HUDPaint", "MCC_ExtractMarkers", function()
    if not cvMarker:GetBool() then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local now = CurTime()
    if now >= nextCrates or now < nextCrates - 1 then
        nextCrates = now + 0.5
        crates = ents.FindByClass(X.CRATE_CLASS)
    end
    for _, crate in ipairs(crates) do
        if IsValid(crate) and crate:GetNWFloat("MCCDropMark", 0) > now then
            local pos = crate:GetPos() + Vector(0, 0, 40)
            local sp = pos:ToScreen()
            if sp.visible then
                local x, y = math.Clamp(sp.x, 40, ScrW() - 40), math.Clamp(sp.y, 40, ScrH() - 40)
                local s = 9 + math.sin(now * 5) * 1.5
                surface.SetDrawColor(AMBER)
                surface.DrawLine(x, y - s, x + s, y)
                surface.DrawLine(x + s, y, x, y + s)
                surface.DrawLine(x, y + s, x - s, y)
                surface.DrawLine(x - s, y, x, y - s)
                local meters = math.floor(lp:GetPos():Distance(crate:GetPos()) * 0.01905)
                draw.SimpleTextOutlined("SUPPLY DROP", "DermaDefaultBold", x, y - s - 4, AMBER,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
                draw.SimpleTextOutlined(meters .. " m", "DermaDefault", x, y + s + 3, color_white,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
            end
        end
    end
end)

-- Sound cue from the server (only sent with the MGSV Fulton addon installed): the plane that catches the
-- Fulton flying over.
MCC.Net.Receive("extract_fx", function(data)
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if data.k == "flyover" then
        EmitSound("mgsv/items/plane_flyover.wav", lp:GetPos() + Vector(0, 0, 2048), 1, CHAN_AUTO, 1, 40, 0, 100)
    end
end)
