--[[
    RoAudio - Universal Audio Logger for Matcha
    - Premium glass-morphism UI design
    - Fixed: Player/source text next to audio ID
    - All text properly contained within UI
]]

-- ==================== Safe Globals ====================
local safe_notify = notify or function(msg, title, dur)
    print("[RoAudio] " .. tostring(msg))
end
local safe_setclipboard = setclipboard or function(txt)
    print("[RoAudio] Copied: " .. tostring(txt))
end

-- ==================== Performance Optimizations ====================
local math_floor      = math.floor
local math_min        = math.min
local math_max        = math.max
local Vector2_new     = Vector2.new
local Color3_fromRGB  = Color3.fromRGB
local Drawing_new     = Drawing and Drawing.new or nil
local task_spawn      = task.spawn
local task_wait       = task.wait
local mem_read        = memory_read
local pcall           = pcall
local ismouse1pressed = ismouse1pressed
local tick            = tick

local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer

-- ==================== Drawing Constructor ====================
local function safeNewDrawing(typ, props)
    if not Drawing_new then return nil end
    local ok, obj = pcall(Drawing_new, typ)
    if not ok or not obj then return nil end
    for k, v in pairs(props) do
        pcall(function() obj[k] = v end)
    end
    return obj
end

-- ==================== Font Fallbacks ====================
local FONT_BOLD = 0
local FONT_MONO = 0
local FONT_REGULAR = 0

if Drawing and Drawing.Fonts then
    FONT_BOLD = Drawing.Fonts.SystemBold or Drawing.Fonts.System or Drawing.Fonts.UI or 0
    FONT_MONO = Drawing.Fonts.Monospace or Drawing.Fonts.System or Drawing.Fonts.UI or 0
    FONT_REGULAR = Drawing.Fonts.System or Drawing.Fonts.UI or 0
end

-- ==================== Mouse Position ====================
local function getMousePos()
    if LocalPlayer then
        local ok, mouse = pcall(function() return LocalPlayer:GetMouse() end)
        if ok and mouse then
            return mouse.X, mouse.Y
        end
    end
    return 0, 0
end

-- ==================== Memory Helpers ====================
local function readPtr(addr)
    if not addr or addr <= 4096 then return nil end
    local ok, v = pcall(mem_read, "uintptr_t", addr)
    return (ok and v and v > 4096) and v or nil
end

local function readStr(addr)
    if not addr or addr <= 4096 then return nil end
    local ok, v = pcall(mem_read, "string", addr)
    return ok and v or nil
end

-- ==================== SoundId Extraction (Offset 0xe0) ====================
local SOUNDID_OFFSET = 0xe0

local function getSoundId(soundInstance)
    local ok, addr = pcall(function() return tonumber(soundInstance.Address) end)
    if not ok or not addr or addr <= 4096 then return nil end
    
    local directStr = readStr(addr + SOUNDID_OFFSET)
    if directStr and (directStr:find("rbxassetid://") or directStr:find("^%d+$")) then
        return directStr
    end
    
    local ptr = readPtr(addr + SOUNDID_OFFSET)
    if ptr then
        local ptrStr = readStr(ptr)
        if ptrStr and (ptrStr:find("rbxassetid://") or ptrStr:find("^%d+$")) then
            return ptrStr
        end
    end
    return nil
end

-- ==================== Humanoid Sound Filter ====================
local HUMANOID_SOUND_NAMES = {
    "GettingUp", "Died", "FreeFalling", "Landing", "Splash",
    "Running", "Swimming", "Climbing", "Jumping"
}

local function isHumanoidSound(obj)
    if not obj then return true end
    
    local ok, parent = pcall(function() return obj.Parent end)
    if ok and parent then
        local okName, parentName = pcall(function() return parent.Name end)
        if okName and parentName == "HumanoidRootPart" then
            return true
        end
    end
    
    local okName, objName = pcall(function() return obj.Name end)
    if not okName then return true end
    
    for _, name in ipairs(HUMANOID_SOUND_NAMES) do
        if objName == name then
            return true
        end
    end
    return false
end

-- ==================== Get Search Targets ====================
local function getSearchTargets()
    local targets = {}
    
    local ok, ws = pcall(function() return game:GetService("Workspace") end)
    if ok and ws then table.insert(targets, ws) end
    
    local ok, ss = pcall(function() return game:GetService("SoundService") end)
    if ok and ss then table.insert(targets, ss) end
    
    local ok, rs = pcall(function() return game:GetService("ReplicatedStorage") end)
    if ok and rs then table.insert(targets, rs) end
    
    if LocalPlayer then
        local ok, char = pcall(function() return LocalPlayer.Character end)
        if ok and char then table.insert(targets, char) end
    end
    
    local ok, players = pcall(function() return Players:GetPlayers() end)
    if ok and players then
        for _, player in ipairs(players) do
            if player ~= LocalPlayer then
                local ok, char = pcall(function() return player.Character end)
                if ok and char then table.insert(targets, char) end
            end
        end
    end
    
    return targets
end

-- ==================== Safe Instance Type Check ====================
local function safeIsA(obj, className)
    local ok, result = pcall(function() return obj:IsA(className) end)
    return (ok and result == true)
end

local function safeFindFirstChildWhichIsA(obj, className)
    local ok, result = pcall(function() return obj:FindFirstChildWhichIsA(className) end)
    return (ok and result) or nil
end

-- ==================== Player/Source Identification ====================
local function getSoundOwner(sound, fullPath)
    if not sound then return "Unknown", "Unknown" end
    
    local parent = sound
    local depth = 0
    local maxDepth = 20
    
    while parent and depth < maxDepth do
        depth = depth + 1
        
        if safeIsA(parent, "Model") then
            local humanoid = safeFindFirstChildWhichIsA(parent, "Humanoid")
            if humanoid then
                local ok, players = pcall(function() return Players:GetPlayers() end)
                if ok and players then
                    for _, player in ipairs(players) do
                        local ok, char = pcall(function() return player.Character end)
                        if ok and char == parent then
                            local okName, playerName = pcall(function() return player.Name end)
                            local okCharName, charName = pcall(function() return parent.Name end)
                            return (okName and playerName) or "Unknown", (okCharName and charName) or "Character"
                        end
                    end
                end
                local okName, parentName = pcall(function() return parent.Name end)
                return "Unknown", (okName and parentName) or "Model"
            end
            
        elseif safeIsA(parent, "Tool") then
            local ok, parentParent = pcall(function() return parent.Parent end)
            if ok and parentParent and safeIsA(parentParent, "Model") then
                local ok, players = pcall(function() return Players:GetPlayers() end)
                if ok and players then
                    for _, player in ipairs(players) do
                        local ok, char = pcall(function() return player.Character end)
                        if ok and char == parentParent then
                            local okName, playerName = pcall(function() return player.Name end)
                            local okCharName, charName = pcall(function() return parentParent.Name end)
                            return (okName and playerName) or "Unknown", ((okCharName and charName) or "Character") .. " (Tool)"
                        end
                    end
                end
            end
            
        elseif safeIsA(parent, "PlayerGui") then
            local ok, parentParent = pcall(function() return parent.Parent end)
            if ok and parentParent and safeIsA(parentParent, "Model") then
                local ok, players = pcall(function() return Players:GetPlayers() end)
                if ok and players then
                    for _, player in ipairs(players) do
                        local ok, char = pcall(function() return player.Character end)
                        if ok and char == parentParent then
                            local okName, playerName = pcall(function() return player.Name end)
                            return (okName and playerName) or "Unknown", "PlayerGui"
                        end
                    end
                end
            end
        end
        
        local ok, nextParent = pcall(function() return parent.Parent end)
        if not ok or not nextParent then break end
        parent = nextParent
    end
    
    if fullPath then
        if fullPath:find("Workspace") then return "World", "Workspace" end
        if fullPath:find("SoundService") then return "Game", "SoundService" end
        if fullPath:find("ReplicatedStorage") then return "Game", "ReplicatedStorage" end
    end
    return "World", "Unknown"
end

-- ==================== Scanner Logic ====================
local discoveredSounds = {}
local soundList = {}
local isScanning = false
local statusText = nil

function scanForSounds()
    if isScanning then 
        return 
    end
    isScanning = true
    if statusText then 
        pcall(function() statusText.Text = "Scanning..." end)
    end
    
    local targets = getSearchTargets()
    local newFound = false
    
    for _, target in ipairs(targets) do
        if not target then continue end
        
        local ok, descendants = pcall(function() return target:GetDescendants() end)
        if not ok or not descendants then descendants = {} end
        
        local allObjects = {target}
        for _, d in ipairs(descendants) do
            table.insert(allObjects, d)
        end
        
        for _, obj in ipairs(allObjects) do
            if not obj then continue end
            
            local okClass, className = pcall(function() return obj.ClassName end)
            if not okClass or className ~= "Sound" then continue end
            
            if isHumanoidSound(obj) then continue end
            
            local okPath, fullPath = pcall(function() return obj:GetFullName() end)
            if not okPath or not fullPath or not fullPath:find("%.") then continue end
            if discoveredSounds[fullPath] then continue end
            
            local soundId = getSoundId(obj)
            if soundId then
                discoveredSounds[fullPath] = true
                local idNumber = soundId:match("%d+") or soundId
                local playerName, sourceDesc = getSoundOwner(obj, fullPath)
                
                local okName, objName = pcall(function() return obj.Name end)
                if not okName then objName = "Sound" end
                
                table.insert(soundList, {
                    name = objName,
                    id = idNumber,
                    player = playerName,
                    source = sourceDesc
                })
                newFound = true
            end
        end
    end
    
    rebuildListDisplay()
    
    if newFound and #soundList > 0 then
        safe_notify("Found " .. #soundList .. " sounds", "RoAudio", 2)
    end
    isScanning = false
end

-- ==================== Premium UI Layout Constants ====================
local UI = {
    x = 100, y = 100,
    width = 500, height = 560,
    titleBarHeight = 40,
    itemHeight = 28,
    visibleItems = 12,
    cornerRadius = 12
}

-- Premium Color Scheme
local C = {
    bg = Color3_fromRGB(12, 16, 24),
    titleBg = Color3_fromRGB(20, 26, 36),
    titleText = Color3_fromRGB(245, 250, 255),
    text = Color3_fromRGB(220, 228, 240),
    textSecondary = Color3_fromRGB(170, 180, 195),
    textMuted = Color3_fromRGB(120, 130, 148),
    itemBg1 = Color3_fromRGB(18, 24, 34),
    itemBg2 = Color3_fromRGB(22, 28, 40),
    selected = Color3_fromRGB(50, 90, 150),
    selectedBorder = Color3_fromRGB(100, 160, 240),
    primary = Color3_fromRGB(60, 140, 100),
    primaryHover = Color3_fromRGB(80, 170, 125),
    secondary = Color3_fromRGB(65, 70, 85),
    secondaryHover = Color3_fromRGB(85, 90, 110),
    scrollTrack = Color3_fromRGB(25, 32, 42),
    scrollHandle = Color3_fromRGB(80, 90, 110),
    scrollHandleHover = Color3_fromRGB(110, 120, 145),
    accent = Color3_fromRGB(80, 150, 220),
    accentLight = Color3_fromRGB(120, 180, 240),
    divider = Color3_fromRGB(45, 52, 65),
    shadow = Color3_fromRGB(0, 0, 0)
}

-- ==================== Drawing Objects Pool ====================
local drawings = {}
local function newDrawing(typ, props)
    local obj = safeNewDrawing(typ, props)
    if obj then table.insert(drawings, obj) end
    return obj
end

local function cleanupDrawings()
    for _, obj in ipairs(drawings) do
        pcall(function() obj:Remove() end)
    end
    drawings = {}
end

-- ==================== Rounded Rectangle Helpers ====================
local function createRoundedRect(x, y, w, h, r, color, filled, zIndex)
    zIndex = zIndex or 50
    r = math_min(r, math_floor(math_min(w, h) / 2))
    local elements = {}
    elements[#elements+1] = newDrawing("Square", { Position = Vector2_new(x + r, y), Size = Vector2_new(w - r*2, h), Color = color, Filled = filled, Visible = true, ZIndex = zIndex })
    elements[#elements+1] = newDrawing("Square", { Position = Vector2_new(x, y + r), Size = Vector2_new(w, h - r*2), Color = color, Filled = filled, Visible = true, ZIndex = zIndex })
    elements[#elements+1] = newDrawing("Circle", { Position = Vector2_new(x + r, y + r), Radius = r, Color = color, Filled = filled, Visible = true, ZIndex = zIndex })
    elements[#elements+1] = newDrawing("Circle", { Position = Vector2_new(x + w - r, y + r), Radius = r, Color = color, Filled = filled, Visible = true, ZIndex = zIndex })
    elements[#elements+1] = newDrawing("Circle", { Position = Vector2_new(x + r, y + h - r), Radius = r, Color = color, Filled = filled, Visible = true, ZIndex = zIndex })
    elements[#elements+1] = newDrawing("Circle", { Position = Vector2_new(x + w - r, y + h - r), Radius = r, Color = color, Filled = filled, Visible = true, ZIndex = zIndex })
    return elements
end

-- ==================== UI Elements ====================
local bgElements, titleBarElements = {}, {}
local titleText, statusText, headerLine, titleIcon
local copyButton, refreshButton = {}, {}
local copyButtonText, refreshButtonText
local scrollBarBg, scrollBarHandle
local itemTexts = {}
local itemBgSquares = {}
local itemBorders = {}

local selectedIndex = 0
local scrollOffset = 0
local lastCopyTime = 0
local COPY_COOLDOWN = 0.3

local function createStaticUI()
    cleanupDrawings()
    bgElements = {}
    titleBarElements = {}
    itemBgSquares = {}
    itemTexts = {}
    itemBorders = {}
    
    -- Shadow effect
    bgElements = createRoundedRect(UI.x + 2, UI.y + 2, UI.width, UI.height, UI.cornerRadius, C.shadow, true, 49)
    
    -- Main background
    bgElements = createRoundedRect(UI.x, UI.y, UI.width, UI.height, UI.cornerRadius, C.bg, true, 50)
    
    -- Title bar
    local titleR = UI.cornerRadius
    titleBarElements[#titleBarElements+1] = newDrawing("Square", { Position = Vector2_new(UI.x + titleR, UI.y), Size = Vector2_new(UI.width - titleR*2, UI.titleBarHeight), Color = C.titleBg, Filled = true, Visible = true, ZIndex = 51 })
    titleBarElements[#titleBarElements+1] = newDrawing("Square", { Position = Vector2_new(UI.x, UI.y + titleR), Size = Vector2_new(UI.width, UI.titleBarHeight - titleR), Color = C.titleBg, Filled = true, Visible = true, ZIndex = 51 })
    titleBarElements[#titleBarElements+1] = newDrawing("Circle", { Position = Vector2_new(UI.x + titleR, UI.y + titleR), Radius = titleR, Color = C.titleBg, Filled = true, Visible = true, ZIndex = 51 })
    titleBarElements[#titleBarElements+1] = newDrawing("Circle", { Position = Vector2_new(UI.x + UI.width - titleR, UI.y + titleR), Radius = titleR, Color = C.titleBg, Filled = true, Visible = true, ZIndex = 51 })
    
    -- Title icon
    titleIcon = newDrawing("Circle", { 
        Position = Vector2_new(UI.x + 16, UI.y + 20), 
        Radius = 4, 
        Color = C.accent, 
        Filled = true, 
        Visible = true, 
        ZIndex = 52 
    })
    
    -- Title text
    titleText = newDrawing("Text", { Text = "RoAudio", Position = Vector2_new(UI.x + 28, UI.y + 10), Size = 17, Color = C.titleText, Font = FONT_BOLD, Outline = false, Visible = true, ZIndex = 52 })
    
    -- Header divider
    headerLine = newDrawing("Line", { 
        From = Vector2_new(UI.x + 12, UI.y + UI.titleBarHeight), 
        To = Vector2_new(UI.x + UI.width - 12, UI.y + UI.titleBarHeight),
        Color = C.divider, 
        Thickness = 1, 
        Visible = true, 
        ZIndex = 51 
    })
    
    -- Buttons
    local btnY = UI.y + UI.height - 50
    local btnH = 32
    
    local refreshX = UI.x + 16
    local refreshW = 80
    refreshButton = createRoundedRect(refreshX, btnY, refreshW, btnH, 6, C.secondary, true, 50)
    refreshButtonText = newDrawing("Text", { Text = "Refresh", Position = Vector2_new(refreshX + refreshW/2, btnY + 8), Size = 13, Color = Color3_fromRGB(255,255,255), Font = FONT_BOLD, Center = true, Outline = false, Visible = true, ZIndex = 54 })
    
    local copyX = UI.x + UI.width - 110
    local copyW = 92
    copyButton = createRoundedRect(copyX, btnY, copyW, btnH, 6, C.primary, true, 50)
    copyButtonText = newDrawing("Text", { Text = "Copy ID", Position = Vector2_new(copyX + copyW/2, btnY + 8), Size = 13, Color = Color3_fromRGB(255,255,255), Font = FONT_BOLD, Center = true, Outline = false, Visible = true, ZIndex = 54 })
    
    -- Scrollbar
    local scrollX = UI.x + UI.width - 14
    local scrollY = UI.y + UI.titleBarHeight + 10
    local scrollH = UI.height - UI.titleBarHeight - 70
    scrollBarBg = newDrawing("Square", { Position = Vector2_new(scrollX, scrollY), Size = Vector2_new(4, scrollH), Color = C.scrollTrack, Filled = true, Visible = true, ZIndex = 51 })
    scrollBarHandle = newDrawing("Square", { Position = Vector2_new(scrollX, scrollY), Size = Vector2_new(4, 30), Color = C.scrollHandle, Filled = true, Visible = true, ZIndex = 52 })
    
    -- Status text
    statusText = newDrawing("Text", { Text = "Ready", Position = Vector2_new(UI.x + 16, UI.y + UI.height - 24), Size = 11, Color = C.textMuted, Font = FONT_REGULAR, Center = false, Outline = false, Visible = true, ZIndex = 53 })
end

function rebuildListDisplay()
    for _, bg in ipairs(itemBgSquares) do pcall(function() bg:Remove() end) end
    for _, t in ipairs(itemTexts) do pcall(function() t:Remove() end) end
    for _, b in ipairs(itemBorders) do pcall(function() b:Remove() end) end
    itemBgSquares = {}
    itemTexts = {}
    itemBorders = {}
    
    local listX = UI.x + 12
    local listY = UI.y + UI.titleBarHeight + 10
    local listW = UI.width - 32
    local maxItems = math_min(#soundList, UI.visibleItems)
    
    for i = 1, maxItems do
        local idx = i + scrollOffset
        if idx <= #soundList then
            local item = soundList[idx]
            local yPos = listY + (i-1) * UI.itemHeight
            local isSelected = (idx == selectedIndex)
            
            -- Item background
            local bgColor = (i % 2 == 0) and C.itemBg1 or C.itemBg2
            if isSelected then bgColor = C.selected end
            local bg = newDrawing("Square", { 
                Position = Vector2_new(listX, yPos), 
                Size = Vector2_new(listW, UI.itemHeight - 2), 
                Color = bgColor, 
                Filled = true, 
                Visible = true, 
                ZIndex = 50 
            })
            table.insert(itemBgSquares, bg)
            
            -- Selected border
            if isSelected then
                local border = newDrawing("Line", {
                    From = Vector2_new(listX, yPos),
                    To = Vector2_new(listX, yPos + UI.itemHeight - 2),
                    Color = C.selectedBorder,
                    Thickness = 3,
                    Visible = true,
                    ZIndex = 51
                })
                table.insert(itemBorders, border)
            end
            
            -- Music note icon
            local icon = newDrawing("Text", { 
                Text = "♪", 
                Position = Vector2_new(listX + 8, yPos + 5), 
                Size = 12, 
                Color = C.accent, 
                Font = FONT_REGULAR, 
                Outline = false, 
                Visible = true, 
                ZIndex = 52 
            })
            table.insert(itemTexts, icon)
            
            -- Sound name
            local nameText = item.name or "Sound"
            if #nameText > 14 then
                nameText = nameText:sub(1, 11) .. "..."
            end
            local txt1 = newDrawing("Text", { 
                Text = nameText, 
                Position = Vector2_new(listX + 26, yPos + 5), 
                Size = 12, 
                Color = C.text, 
                Font = FONT_BOLD, 
                Outline = false, 
                Visible = true, 
                ZIndex = 52 
            })
            table.insert(itemTexts, txt1)
            
            -- Audio ID
            local idText = item.id or "?"
            local txt2 = newDrawing("Text", { 
                Text = idText, 
                Position = Vector2_new(listX + 135, yPos + 5), 
                Size = 10, 
                Color = C.accentLight, 
                Font = FONT_MONO, 
                Outline = false, 
                Visible = true, 
                ZIndex = 52 
            })
            table.insert(itemTexts, txt2)
            
            -- Player/source NEXT TO audio ID (not at far right)
            local subText = "@" .. (item.player or "?")
            if #subText > 14 then
                subText = subText:sub(1, 11) .. "..."
            end
            -- Position right after the ID
            local txt3 = newDrawing("Text", { 
                Text = subText, 
                Position = Vector2_new(listX + 210, yPos + 5), 
                Size = 10, 
                Color = C.textMuted, 
                Font = FONT_REGULAR, 
                Outline = false, 
                Visible = true, 
                ZIndex = 52 
            })
            table.insert(itemTexts, txt3)
        end
    end
    
    -- Update scrollbar
    local totalItems = #soundList
    if totalItems > UI.visibleItems then
        local trackH = UI.height - UI.titleBarHeight - 70
        local handleH = math_max(30, math_floor(trackH * (UI.visibleItems / totalItems)))
        local maxScroll = totalItems - UI.visibleItems
        local scrollProgress = maxScroll > 0 and (scrollOffset / maxScroll) or 0
        local handleY = UI.y + UI.titleBarHeight + 10 + math_floor(scrollProgress * (trackH - handleH))
        scrollBarHandle.Size = Vector2_new(4, handleH)
        scrollBarHandle.Position = Vector2_new(UI.x + UI.width - 14, handleY)
        scrollBarHandle.Visible = true
        scrollBarBg.Visible = true
    else
        scrollBarHandle.Visible = false
        scrollBarBg.Visible = false
    end
    
    if statusText then
        if isScanning then
            pcall(function() statusText.Text = "Scanning... " .. #soundList .. " found" end)
        elseif #soundList == 0 then
            pcall(function() statusText.Text = "No sounds - Click Refresh" end)
        else
            pcall(function() statusText.Text = #soundList .. " audio source" .. (#soundList == 1 and "" or "s") end)
        end
    end
end

-- ==================== Interaction ====================
local draggingWindow = false
local dragStartMouseX, dragStartMouseY = 0, 0
local dragStartUIX, dragStartUIY = 0, 0

local function pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

local draggingScroll = false
local dragStartY = 0
local dragStartOffset = 0

local mousePressX, mousePressY = 0, 0
local mouseWasDown = false

function updateButtonColors(mx, my)
    if not ismouse1pressed() then
        local copyX = UI.x + UI.width - 110
        local copyY = UI.y + UI.height - 50
        if pointInRect(mx, my, copyX, copyY, 92, 32) then
            for _, obj in ipairs(copyButton) do obj.Color = C.primaryHover end
        else
            for _, obj in ipairs(copyButton) do obj.Color = C.primary end
        end
        
        local refreshX = UI.x + 16
        local refreshY = UI.y + UI.height - 50
        if pointInRect(mx, my, refreshX, refreshY, 80, 32) then
            for _, obj in ipairs(refreshButton) do obj.Color = C.secondaryHover end
        else
            for _, obj in ipairs(refreshButton) do obj.Color = C.secondary end
        end
        
        if scrollBarBg.Visible then
            local scrollX = UI.x + UI.width - 14
            local scrollY = UI.y + UI.titleBarHeight + 10
            local scrollH = UI.height - UI.titleBarHeight - 70
            if pointInRect(mx, my, scrollX, scrollY, 4, scrollH) then
                scrollBarHandle.Color = C.scrollHandleHover
            else
                scrollBarHandle.Color = C.scrollHandle
            end
        end
    end
end

local function handleInput()
    local mx, my = getMousePos()
    local mouseDown = ismouse1pressed()
    
    updateButtonColors(mx, my)
    
    if mouseDown and not mouseWasDown then
        mousePressX = mx
        mousePressY = my
        
        if pointInRect(mx, my, UI.x, UI.y, UI.width, UI.titleBarHeight) then
            draggingWindow = true
            dragStartMouseX = mx
            dragStartMouseY = my
            dragStartUIX = UI.x
            dragStartUIY = UI.y
        end
        
        if scrollBarHandle.Visible then
            local handleX = UI.x + UI.width - 14
            local handleY = scrollBarHandle.Position.Y
            local handleH = scrollBarHandle.Size.Y
            if pointInRect(mx, my, handleX, handleY, 4, handleH) then
                draggingScroll = true
                dragStartY = my
                dragStartOffset = scrollOffset
            end
        end
    end
    
    if not mouseDown then
        draggingWindow = false
        draggingScroll = false
    end
    
    if draggingWindow and mouseDown then
        local dx = mx - dragStartMouseX
        local dy = my - dragStartMouseY
        if dx ~= 0 or dy ~= 0 then
            UI.x = dragStartUIX + dx
            UI.y = dragStartUIY + dy
            createStaticUI()
            rebuildListDisplay()
        end
        mouseWasDown = mouseDown
        return
    end
    
    if draggingScroll and mouseDown then
        local totalItems = #soundList
        if totalItems > UI.visibleItems then
            local maxScroll = totalItems - UI.visibleItems
            local trackH = UI.height - UI.titleBarHeight - 70
            local handleH = scrollBarHandle.Size.Y
            local deltaY = my - dragStartY
            local scrollDelta = math_floor((deltaY / (trackH - handleH)) * maxScroll + 0.5)
            local newOffset = math_max(0, math_min(maxScroll, dragStartOffset + scrollDelta))
            if newOffset ~= scrollOffset then
                scrollOffset = newOffset
                rebuildListDisplay()
            end
        end
    end
    
    if not mouseDown and mouseWasDown then
        if not draggingWindow and not draggingScroll then
            -- Refresh button
            local refreshX = UI.x + 16
            local refreshY = UI.y + UI.height - 50
            if pointInRect(mousePressX, mousePressY, refreshX, refreshY, 80, 32) and
               pointInRect(mx, my, refreshX, refreshY, 80, 32) then
                scanForSounds()
                mouseWasDown = mouseDown
                return
            end
            
            -- Copy button
            local copyX = UI.x + UI.width - 110
            local copyY = UI.y + UI.height - 50
            if pointInRect(mousePressX, mousePressY, copyX, copyY, 92, 32) and
               pointInRect(mx, my, copyX, copyY, 92, 32) then
                local now = tick()
                if now - lastCopyTime >= COPY_COOLDOWN then
                    lastCopyTime = now
                    if selectedIndex > 0 and selectedIndex <= #soundList then
                        local id = soundList[selectedIndex].id
                        if id then
                            safe_setclipboard(id)
                            safe_notify("Copied: " .. id, "RoAudio", 1.5)
                        end
                    else
                        safe_notify("Select a sound first", "RoAudio", 1)
                    end
                end
                mouseWasDown = mouseDown
                return
            end
            
            -- Scrollbar track click
            if scrollBarBg.Visible then
                local scrollX = UI.x + UI.width - 14
                local scrollY = UI.y + UI.titleBarHeight + 10
                local scrollH = UI.height - UI.titleBarHeight - 70
                if pointInRect(mousePressX, mousePressY, scrollX, scrollY, 4, scrollH) and
                   pointInRect(mx, my, scrollX, scrollY, 4, scrollH) then
                    local totalItems = #soundList
                    if totalItems > UI.visibleItems then
                        local handleY = scrollBarHandle.Position.Y
                        if my < handleY then
                            scrollOffset = math_max(0, scrollOffset - UI.visibleItems)
                        else
                            scrollOffset = math_min(totalItems - UI.visibleItems, scrollOffset + UI.visibleItems)
                        end
                        rebuildListDisplay()
                    end
                    mouseWasDown = mouseDown
                    return
                end
            end
            
            -- List selection
            local listX = UI.x + 12
            local listY = UI.y + UI.titleBarHeight + 10
            local listW = UI.width - 32
            local listH = UI.visibleItems * UI.itemHeight
            if pointInRect(mousePressX, mousePressY, listX, listY, listW, listH) and
               pointInRect(mx, my, listX, listY, listW, listH) then
                local relY = my - listY
                local clickedIdx = math_floor(relY / UI.itemHeight) + 1 + scrollOffset
                if clickedIdx >= 1 and clickedIdx <= #soundList then
                    selectedIndex = clickedIdx
                    rebuildListDisplay()
                end
            end
        end
    end
    
    mouseWasDown = mouseDown
end

-- ==================== Main Loop ====================
local running = true

print("[RoAudio] Starting...")

pcall(createStaticUI)
pcall(rebuildListDisplay)

task_spawn(function()
    task_wait(0.5)
    pcall(scanForSounds)
end)

task_spawn(function()
    while running do
        task_wait(5.0)
        pcall(scanForSounds)
    end
end)

while running do
    pcall(handleInput)
    task_wait(0.03)
end