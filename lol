-- ============================================
-- LOGIC (Nova Silent Aim Enhanced)
-- ============================================

print("Loading Nova Silent Aim...")

local Config = shared.Glory

-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
repeat task.wait() until LocalPlayer.Character
local Mouse = LocalPlayer:GetMouse()

-- Performance Optimizations
local math_sqrt = math.sqrt
local math_huge = math.huge
local math_min = math.min
local math_max = math.max
local math_clamp = math.clamp
local math_floor = math.floor
local math_abs = math.abs
local Vector2_new = Vector2.new
local Vector3_new = Vector3.new
local CFrame_new = CFrame.new

-- State Variables
local CurrentTarget = nil
local CachedTarget = nil
local SilentAimActive = false
local TriggerBotEnabled = false
local FoundTarget = false
local ESPLabels = {}
local SpeedEnabled = false
local LastTriggerClick = 0
local LastTargetScan = 0
local ScanRate = 1 / 60
local isLocking = false
local lastVisibleTarget = nil

-- Drawing Objects
local TargetLine = Drawing.new("Line")
TargetLine.Visible = false
TargetLine.Thickness = Config['Target Line']['Thickness']
TargetLine.Transparency = Config['Target Line']['Transparency']
TargetLine.Color = Config['Target Line']['Vulnerable']
TargetLine.ZIndex = 999

local outlinePart = Instance.new("Part")
outlinePart.Anchored = true
outlinePart.CanCollide = false
outlinePart.Transparency = 0.85
outlinePart.BrickColor = BrickColor.new("Grey")
outlinePart.Material = Enum.Material.Neon
outlinePart.Name = "FOVOutline3D"
outlinePart.Parent = Workspace

-- Raycast Parameters
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

print("Drawing objects created!")

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function FastDistance2D(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    return math_sqrt(dx * dx + dy * dy)
end

local function FastDistanceSquared3D(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return dx * dx + dy * dy + dz * dz
end

local function IsValidAddress(obj)
    return obj ~= nil and typeof(obj) == "Instance" and obj.Parent ~= nil
end

local function PlayerKnocked(player)
    if not Config['Settings']['Knock Check'] then return false end
    if not player.Character then return false end
    local bodyeffects = player.Character:FindFirstChild("BodyEffects")
    if bodyeffects then
        local ko = bodyeffects:FindFirstChild("K.O")
        if ko and ko.Value == true then return true end
        local knocked = bodyeffects:FindFirstChild("Knocked")
        if knocked and knocked.Value == true then return true end
    end
    return false
end

local function PlayerDead(player)
    if not player.Character then return true end
    local bodyeffects = player.Character:FindFirstChild("BodyEffects")
    if bodyeffects then
        local dead = bodyeffects:FindFirstChild("Dead")
        if dead and dead.Value == true then return true end
        local ko = bodyeffects:FindFirstChild("K.O")
        if ko and ko.Value == true then return true end
    end
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then return true end
    return false
end

local function SelfKnocked()
    if not Config['Settings']['Self Knock Check'] then return false end
    if LocalPlayer.Character then
        local bodyeffects = LocalPlayer.Character:FindFirstChild("BodyEffects")
        if bodyeffects then
            local ko = bodyeffects:FindFirstChild("K.O")
            if ko and ko.Value == true then return true end
            local knocked = bodyeffects:FindFirstChild("Knocked")
            if knocked and knocked.Value == true then return true end
        end
    end
    return false
end

local function CanSee(part)
    if not Config['Settings']['Visible Check'] then return true end
    if not part or not part.Parent then return false end
    local char = part.Parent
    local origin = Camera.CFrame.Position
    local dir = (part.Position - origin).Unit * (part.Position - origin).Magnitude
    RayParams.FilterDescendantsInstances = {LocalPlayer.Character, char, outlinePart}
    local result = Workspace:Raycast(origin, dir, RayParams)
    return result == nil or result.Instance:IsDescendantOf(char)
end

local function GetBodyParts(char)
    return {
        Head = char:FindFirstChild("Head"),
        UpperTorso = char:FindFirstChild("UpperTorso"),
        LowerTorso = char:FindFirstChild("LowerTorso"),
        HumanoidRootPart = char:FindFirstChild("HumanoidRootPart"),
        LeftHand = char:FindFirstChild("LeftHand"),
        RightHand = char:FindFirstChild("RightHand"),
        LeftFoot = char:FindFirstChild("LeftFoot"),
        RightFoot = char:FindFirstChild("RightFoot"),
        LeftUpperArm = char:FindFirstChild("LeftUpperArm"),
        RightUpperArm = char:FindFirstChild("RightUpperArm"),
        LeftLowerArm = char:FindFirstChild("LeftLowerArm"),
        RightLowerArm = char:FindFirstChild("RightLowerArm"),
        LeftUpperLeg = char:FindFirstChild("LeftUpperLeg"),
        RightUpperLeg = char:FindFirstChild("RightUpperLeg"),
        LeftLowerLeg = char:FindFirstChild("LeftLowerLeg"),
        RightLowerLeg = char:FindFirstChild("RightLowerLeg"),
    }
end

local function GetClosestBodyPart(char, mousePos)
    local bodyparts = GetBodyParts(char)
    local validCandidates = {}
    
    for name, part in pairs(bodyparts) do
        if IsValidAddress(part) then
            table.insert(validCandidates, part)
        end
    end
    
    if #validCandidates == 0 then return nil end
    
    local bestPart = nil
    local bestDist = math_huge
    
    for _, part in ipairs(validCandidates) do
        local screenpos, onscreen = Camera:WorldToViewportPoint(part.Position)
        local dist
        if not onscreen or screenpos.Z <= 0 then
            dist = 999999
        else
            local dx = screenpos.X - mousePos.X
            local dy = screenpos.Y - mousePos.Y
            dist = math_sqrt(dx * dx + dy * dy)
        end
        if dist < bestDist then
            bestDist = dist
            bestPart = part
        end
    end
    
    return bestPart
end

local function PredictedPosition(part, config)
    if not config['Use Prediction'] then return part.Position end
    local vel = part.AssemblyLinearVelocity
    local prediction = config['Prediction']
    local predX = prediction['X'] or 0.133
    local predY = prediction['Y'] or 0.133
    local predZ = prediction['Z'] or 0.133
    return part.Position + Vector3_new(vel.X * predX, vel.Y * predY, vel.Z * predZ)
end

local function FindTargetClosestToMouse()
    local mousePos = UserInputService:GetMouseLocation()
    local closestPlayer = nil
    local closestVisible = nil
    local closestDistSquared = math_huge
    local closestVisibleDistSquared = math_huge
    
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not player.Character then continue end
        if not IsValidAddress(player.Character) then continue end
        local head = player.Character:FindFirstChild("Head")
        if not head then continue end
        if PlayerDead(player) then continue end
        if PlayerKnocked(player) then continue end
        
        local screenCoords, onScreen = Camera:WorldToViewportPoint(head.Position)
        if not onScreen or screenCoords.Z <= 0 then continue end
        
        local screenPos2D = Vector2_new(screenCoords.X, screenCoords.Y)
        local dx = mousePos.X - screenPos2D.X
        local dy = mousePos.Y - screenPos2D.Y
        local distSquared = dx * dx + dy * dy
        
        local isVisible = CanSee(head)
        if isVisible then
            if distSquared < closestVisibleDistSquared then
                closestVisibleDistSquared = distSquared
                closestVisible = player
            end
        else
            if distSquared < closestDistSquared then
                closestDistSquared = distSquared
                closestPlayer = player
            end
        end
    end
    
    if closestVisible then return closestVisible end
    return closestPlayer
end

print("Utility functions loaded!")

-- ============================================================================
-- SILENT AIM HOOK (Nova Enhanced)
-- ============================================================================

local grm = getrawmetatable(game)
local oldindex = grm.__index
setreadonly(grm, false)

grm.__index = function(self, key)
    if not checkcaller() and self == Mouse and Config['Silent Aim']['Enabled'] then
        if key == "Hit" then
            if not CurrentTarget then return oldindex(self, key) end
            if not CurrentTarget.Character then return oldindex(self, key) end
            
            if PlayerDead(CurrentTarget) then return oldindex(self, key) end
            if PlayerKnocked(CurrentTarget) then return oldindex(self, key) end
            
            local char = CurrentTarget.Character
            local mousePos = UserInputService:GetMouseLocation()
            local targetPart = nil
            
            if Config['Silent Aim']['Hit Part'] == 'Closest Part' then
                targetPart = GetClosestBodyPart(char, mousePos)
                if not targetPart then
                    targetPart = char:FindFirstChild("HumanoidRootPart")
                end
            else
                targetPart = char:FindFirstChild(Config['Silent Aim']['Hit Part'])
                if not targetPart then
                    targetPart = char:FindFirstChild("HumanoidRootPart")
                end
            end
            
            if targetPart then
                local predictedPos = PredictedPosition(targetPart, Config['Silent Aim'])
                if predictedPos.X ~= predictedPos.X or predictedPos.Y ~= predictedPos.Y or predictedPos.Z ~= predictedPos.Z then
                    predictedPos = targetPart.Position
                end
                return CFrame_new(predictedPos)
            end
        end
    end
    return oldindex(self, key)
end

setreadonly(grm, true)
print("Silent aim hook installed! (Nova Enhanced)")

-- ============================================================================
-- SPREAD HOOK
-- ============================================================================

local oldRandom
oldRandom = hookfunction(math.random, function(...)
    local args = {...}
    if checkcaller() then
        return oldRandom(...)
    end
    
    if (#args == 0) or (args[1] == -0.05 and args[2] == 0.05) or (args[1] == -0.1) or (args[1] == -0.05) then
        if Config['Spread']['Enabled'] then
            if Config['Spread']['Specific Weapons']['Enabled'] then
                local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
                if tool then
                    local weaponName = tool.Name
                    local foundWeapon = false
                    for _, weapon in pairs(Config['Spread']['Specific Weapons']['Weapons']) do
                        if weaponName == weapon then
                            foundWeapon = true
                            break
                        end
                    end
                    if foundWeapon then
                        return oldRandom(...) * (Config['Spread']['Amount'] / 100)
                    end
                end
            else
                return oldRandom(...) * (Config['Spread']['Amount'] / 100)
            end
        end
    end
    
    return oldRandom(...)
end)

print("Spread hook installed!")

-- ============================================================================
-- CAMERA LOCK
-- ============================================================================

local function elasticOut(t)
    local p = 0.3
    return math.pow(2, -10 * t) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
end

local function sineInOut(t)
    return -(math.cos(math.pi * t) - 1) / 2
end

local function getTargetForCameraLock()
    if Config['Settings']['Target Aim'] and CurrentTarget then
        local player = Players:GetPlayerFromCharacter(CurrentTarget.Character)
        if player and not PlayerKnocked(player) then
            local targetPart = nil
            if Config['Camera Lock']['Hit Part'] == 'Closest Part' then
                local mousePos = UserInputService:GetMouseLocation()
                targetPart = GetClosestBodyPart(CurrentTarget.Character, mousePos)
                if targetPart then
                    CurrentTarget = {Character = CurrentTarget.Character}
                end
            else
                targetPart = CurrentTarget.Character:FindFirstChild(Config['Camera Lock']['Hit Part'])
            end
            
            if targetPart then
                if CanSee(targetPart) then
                    lastVisibleTarget = targetPart
                    return targetPart
                else
                    return nil
                end
            end
        else
            CurrentTarget = nil
            isLocking = false
            lastVisibleTarget = nil
            TargetLine.Visible = false
            return nil
        end
        return nil
    else
        local target = FindTargetClosestToMouse()
        if target and target.Character then
            local hrp = target.Character:FindFirstChild("HumanoidRootPart")
            return hrp
        end
        return nil
    end
end

local function applyCameraLock()
    if not isLocking then return end
    if SelfKnocked() then
        CurrentTarget = nil
        isLocking = false
        lastVisibleTarget = nil
        TargetLine.Visible = false
        return
    end
    
    local target = getTargetForCameraLock()
    if target then
        local targetPos = PredictedPosition(target, Config['Camera Lock'])
        local cameraCFrame = Camera.CFrame
        local targetCFrame = CFrame_new(cameraCFrame.Position, targetPos)
        
        local smoothConfig = Config['Camera Lock']['Smoothing']
        local baseAlphaX = 1 / smoothConfig['X']
        local baseAlphaY = 1 / smoothConfig['Y']
        local baseAlphaZ = 1 / smoothConfig['Z']
        
        local elasticAlphaX = elasticOut(math_min(baseAlphaX, 1))
        local elasticAlphaY = elasticOut(math_min(baseAlphaY, 1))
        local elasticAlphaZ = elasticOut(math_min(baseAlphaZ, 1))
        
        local avgElasticAlpha = (elasticAlphaX + elasticAlphaY + elasticAlphaZ) / 3
        local avgBaseAlpha = (baseAlphaX + baseAlphaY + baseAlphaZ) / 3
        
        local smoothCFrame = cameraCFrame:Lerp(targetCFrame, avgElasticAlpha * avgBaseAlpha)
        local sineAlpha = sineInOut(math_min(avgBaseAlpha, 1))
        Camera.CFrame = smoothCFrame:Lerp(targetCFrame, sineAlpha * avgBaseAlpha)
    else
        if lastVisibleTarget then
            local player = Players:GetPlayerFromCharacter(lastVisibleTarget.Parent)
            if player and not PlayerKnocked(player) then
                if CanSee(lastVisibleTarget) then
                    CurrentTarget = {Character = lastVisibleTarget.Parent}
                end
            end
        end
    end
end

local function update3DFOVBox()
    if not Config['FOV']['Enabled'] or not Config['FOV']['Visible'] then
        outlinePart.Transparency = 1
        return
    end
    
    if CurrentTarget and CurrentTarget.Character then
        local rootPart = CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local offset = Config['FOV']['Size']
            outlinePart.Size = rootPart.Size + Vector3_new(offset, offset, offset)
            outlinePart.CFrame = rootPart.CFrame
            outlinePart.Transparency = 0.85
            outlinePart.BrickColor = BrickColor.new(Config['FOV']['Active Color'])
        else
            outlinePart.Transparency = 1
        end
    else
        outlinePart.Transparency = 1
    end
end

local function updateTargetLine()
    if not Config['Target Line']['Enabled'] then
        TargetLine.Visible = false
        return
    end
    
    if not CurrentTarget or not CurrentTarget.Character or not (isLocking or SilentAimActive) then
        TargetLine.Visible = false
        return
    end
    
    local hrp = CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        TargetLine.Visible = false
        return
    end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
    if onScreen and screenPos.Z > 0 then
        local mousePos = UserInputService:GetMouseLocation()
        TargetLine.From = Vector2_new(mousePos.X, mousePos.Y)
        TargetLine.To = Vector2_new(screenPos.X, screenPos.Y)
        TargetLine.Thickness = Config['Target Line']['Thickness']
        TargetLine.Transparency = Config['Target Line']['Transparency']
        
        if CanSee(hrp) then
            TargetLine.Color = Config['Target Line']['Vulnerable']
        else
            TargetLine.Color = Config['Target Line']['Invulnerable']
        end
        TargetLine.Visible = true
    else
        TargetLine.Visible = false
    end
end

print("Camera lock functions loaded!")

-- ============================================================================
-- TRIGGERBOT
-- ============================================================================

local function TriggerBot()
    if not Config['Trigger Bot']['Enabled'] then return end
    if not TriggerBotEnabled then return end
    if tick() - LastTriggerClick < Config['Trigger Bot']['Delay'] then return end
    if Config['Trigger Bot']['Require Target'] and not CurrentTarget then return end
    
    if CurrentTarget and CurrentTarget.Character then
        if PlayerKnocked(CurrentTarget) then return end
        if PlayerDead(CurrentTarget) then return end
        local hrp = CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        if not CanSee(hrp) then return end
    end
    
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not tool then return end
    
    if Config['Trigger Bot']['Specific Weapons']['Enabled'] then
        local weaponValid = false
        for _, weaponName in pairs(Config['Trigger Bot']['Specific Weapons']['Weapons']) do
            local cleanName = weaponName:gsub("%[", ""):gsub("%]", "")
            if tool.Name == weaponName or tool.Name:find(cleanName) then
                weaponValid = true
                break
            end
        end
        if not weaponValid then return end
    end
    
    tool:Activate()
    LastTriggerClick = tick()
end

print("Triggerbot loaded!")

-- ============================================================================
-- ESP SYSTEM
-- ============================================================================

local function AddESP(player)
    if player == LocalPlayer then return end
    if not Config['Visual Awareness']['Enabled'] then return end
    
    local esp = {
        player = player,
        nametag = Drawing.new("Text"),
    }
    
    esp.nametag.Size = 14
    esp.nametag.Center = true
    esp.nametag.Outline = true
    esp.nametag.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.nametag.Color = Config['Visual Awareness']['Color']
    esp.nametag.Font = Drawing.Fonts.Plex
    esp.nametag.Visible = false
    esp.nametag.ZIndex = 1000
    
    ESPLabels[player.UserId] = esp
end

local function RemoveESP(player)
    local esp = ESPLabels[player.UserId]
    if esp then
        esp.nametag:Remove()
        ESPLabels[player.UserId] = nil
    end
end

local function RefreshESP()
    if not Config['Visual Awareness']['Enabled'] then
        for _, esp in pairs(ESPLabels) do
            esp.nametag.Visible = false
        end
        return
    end
    
    for userid, esp in pairs(ESPLabels) do
        local player = esp.player
        if not player or not player.Parent then
            esp.nametag.Visible = false
            esp.nametag:Remove()
            ESPLabels[userid] = nil
            continue
        end
        
        if player.Character and player.Character.Parent and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Head") then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then
                esp.nametag.Visible = false
                continue
            end
            
            local head = player.Character.Head
            local hrp = player.Character.HumanoidRootPart
            local worldpos = head.Position + Vector3_new(0, 1.5, 0)
            
            if Config['Visual Awareness']['Name Above'] then
                worldpos = head.Position + Vector3_new(0, 1.5, 0)
            else
                worldpos = hrp.Position - Vector3_new(0, 2.8, 0)
            end
            
            local esppos, onscreen = Camera:WorldToViewportPoint(worldpos)
            if onscreen and esppos.Z > 0 then
                esp.nametag.Position = Vector2_new(esppos.X, esppos.Y)
                
                if Config['Visual Awareness']['Use Display Name'] then
                    esp.nametag.Text = player.DisplayName
                else
                    esp.nametag.Text = player.Name
                end
                
                if CurrentTarget and CurrentTarget == player then
                    esp.nametag.Color = Config['Visual Awareness']['Target Color']
                else
                    esp.nametag.Color = Config['Visual Awareness']['Color']
                end
                esp.nametag.Visible = true
            else
                esp.nametag.Visible = false
            end
        else
            esp.nametag.Visible = false
        end
    end
end

print("ESP system loaded!")

-- ============================================================================
-- TARGET ACQUISITION LOOP (Nova Enhanced)
-- ============================================================================

local function SilentAimTargetLoop()
    while true do
        task.wait(ScanRate)
        
        if SelfKnocked() then
            CurrentTarget = nil
            CachedTarget = nil
            SilentAimActive = false
            FoundTarget = false
            continue
        end
        
        if not Config['Silent Aim']['Enabled'] then
            if not Config['Settings']['Target Aim'] then
                CurrentTarget = nil
                CachedTarget = nil
            end
            FoundTarget = false
            continue
        end
        
        -- Check targeting mode
        local shouldBeActive = false
        if Config['Targeting']['Mode'] == 'Automatic' then
            shouldBeActive = Config['Silent Aim']['Enabled']
            SilentAimActive = true
        elseif Config['Targeting']['Mode'] == 'Select' then
            shouldBeActive = SilentAimActive and Config['Silent Aim']['Enabled']
        end
        
        if not shouldBeActive then
            if Config['Targeting']['Mode'] == 'Automatic' then
                CurrentTarget = nil
                CachedTarget = nil
            end
            FoundTarget = false
            continue
        end
        
        -- In Select mode, validate existing target
        if Config['Targeting']['Mode'] == 'Select' then
            if CachedTarget then
                local isValid = true
                if not CachedTarget.Character then
                    isValid = false
                elseif PlayerDead(CachedTarget) then
                    isValid = false
                elseif PlayerKnocked(CachedTarget) then
                    isValid = false
                end
                
                if isValid then
                    CurrentTarget = CachedTarget
                    FoundTarget = true
                else
                    CachedTarget = nil
                    CurrentTarget = nil
                    FoundTarget = false
                    SilentAimActive = false
                    print("Target lost - press " .. Config['Keybinds']['Silent Aim']['Key'] .. " to lock new target")
                end
            else
                -- No cached target, find new one
                local target = FindTargetClosestToMouse()
                if target then
                    CurrentTarget = target
                    CachedTarget = target
                    FoundTarget = true
                    print("Locked onto: " .. target.Name)
                else
                    CurrentTarget = nil
                    FoundTarget = false
                end
            end
        else
            -- Automatic mode - always find closest target
            local target = FindTargetClosestToMouse()
            if target then
                CurrentTarget = target
                CachedTarget = target
                FoundTarget = true
            else
                CurrentTarget = nil
                FoundTarget = false
            end
        end
    end
end

print("Target acquisition loop loaded!")

-- ============================================================================
-- HITBOX EXPANDER
-- ============================================================================

RunService.Heartbeat:Connect(function()
    if Config['Hitbox Expander']['Enabled'] then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local bodyEffects = player.Character:FindFirstChild("BodyEffects")
                    local isKOd = bodyEffects and bodyEffects:FindFirstChild("K.O") and bodyEffects["K.O"].Value
                    
                    if isKOd then
                        hrp.Size = Vector3_new(0, 0, 0)
                        hrp.Transparency = 1
                    else
                        hrp.Size = Vector3_new(Config['Hitbox Expander']['Size'], Config['Hitbox Expander']['Size'], Config['Hitbox Expander']['Size'])
                        hrp.Transparency = 0.7
                        hrp.BrickColor = BrickColor.new("Really blue")
                        hrp.Material = "Neon"
                        hrp.CanCollide = false
                    end
                end
            end
        end
    else
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.Size = Vector3_new(2, 2, 1)
                    hrp.Transparency = 1
                end
            end
        end
    end
end)

print("Hitbox expander loaded!")

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    -- Silent Aim keybind (for Select mode)
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Silent Aim']['Key']] then
        if Config['Targeting']['Mode'] == 'Select' then
            local mode = Config['Keybinds']['Silent Aim']['Mode']
            if mode == 'Toggle' then
                if SilentAimActive then
                    -- Unlock current target
                    SilentAimActive = false
                    CurrentTarget = nil
                    CachedTarget = nil
                    FoundTarget = false
                    TargetLine.Visible = false
                    print("Silent Aim: Unlocked")
                else
                    -- Lock onto new target
                    SilentAimActive = true
                    print("Silent Aim: Searching for target...")
                end
            elseif mode == 'Hold' then
                if not SilentAimActive then
                    SilentAimActive = true
                    print("Silent Aim: Searching for target...")
                end
            end
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Target Lock']['Key']] then
        local mode = Config['Keybinds']['Target Lock']['Mode']
        if mode == 'Toggle' then
            if Config['Settings']['Target Aim'] then
                if isLocking then
                    isLocking = false
                    CurrentTarget = nil
                    lastVisibleTarget = nil
                    TargetLine.Visible = false
                else
                    local target = FindTargetClosestToMouse()
                    if target then
                        CurrentTarget = target
                        lastVisibleTarget = target
                        isLocking = true
                        update3DFOVBox()
                    end
                end
            else
                isLocking = not isLocking
                if not isLocking then
                    TargetLine.Visible = false
                end
            end
        elseif mode == 'Hold' then
            if Config['Settings']['Target Aim'] then
                local target = FindTargetClosestToMouse()
                if target then
                    CurrentTarget = target
                    lastVisibleTarget = target
                    isLocking = true
                    update3DFOVBox()
                end
            else
                isLocking = true
            end
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Trigger Bot']['Key']] then
        local mode = Config['Keybinds']['Trigger Bot']['Mode']
        if mode == 'Toggle' then
            TriggerBotEnabled = not TriggerBotEnabled
            print("Triggerbot:", TriggerBotEnabled)
        elseif mode == 'Hold' then
            TriggerBotEnabled = true
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Speed']] then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            if not SpeedEnabled then
                SpeedEnabled = true
            else
                humanoid.WalkSpeed = 16
                SpeedEnabled = false
            end
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['ESP']] then
        Config['Visual Awareness']['Enabled'] = not Config['Visual Awareness']['Enabled']
        print("ESP:", Config['Visual Awareness']['Enabled'])
        if Config['Visual Awareness']['Enabled'] then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    if not ESPLabels[player.UserId] then
                        AddESP(player)
                    end
                end
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    
    -- Silent Aim key release (for Hold mode in Select)
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Silent Aim']['Key']] then
        if Config['Targeting']['Mode'] == 'Select' then
            local mode = Config['Keybinds']['Silent Aim']['Mode']
            if mode == 'Hold' then
                SilentAimActive = false
                CurrentTarget = nil
                CachedTarget = nil
                FoundTarget = false
                TargetLine.Visible = false
                print("Silent Aim: Released and unlocked")
            end
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Target Lock']['Key']] then
        local mode = Config['Keybinds']['Target Lock']['Mode']
        if mode == 'Hold' then
            isLocking = false
            CurrentTarget = nil
            lastVisibleTarget = nil
            TargetLine.Visible = false
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Trigger Bot']['Key']] then
        local mode = Config['Keybinds']['Trigger Bot']['Mode']
        if mode == 'Hold' then
            TriggerBotEnabled = false
        end
    end
end)

print("Input handling loaded!")

-- ============================================================================
-- MAIN RENDER LOOP
-- ============================================================================

RunService.RenderStepped:Connect(function(dt)
    if SelfKnocked() and isLocking then
        CurrentTarget = nil
        isLocking = false
        lastVisibleTarget = nil
        TargetLine.Visible = false
    end
    
    TriggerBot()
    
    if SpeedEnabled and Config['Speed']['Enabled'] then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            local targetSpeed = 16 * Config['Speed']['Multiplier']
            if humanoid.WalkSpeed ~= targetSpeed then
                humanoid.WalkSpeed = targetSpeed
            end
        end
        
        if Config['Speed']['Anti Fling'] then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local vel = hrp.Velocity
                if vel.Y > 50 or vel.Y < -50 then
                    hrp.Velocity = Vector3_new(vel.X, 0, vel.Z)
                end
            end
        end
    end
    
    update3DFOVBox()
    updateTargetLine()
    RefreshESP()
    
    if Config['Camera Lock']['Enabled'] then
        applyCameraLock()
    end
end)

print("Main render loop loaded!")

-- ============================================================================
-- PLAYER MANAGEMENT
-- ============================================================================

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        AddESP(player)
    end
    
    player.CharacterAdded:Connect(function(char)
        RemoveESP(player)
        char:WaitForChild("HumanoidRootPart")
        task.wait(0.1)
        AddESP(player)
    end)
    
    player.CharacterRemoving:Connect(function()
        RemoveESP(player)
    end)
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(char)
            RemoveESP(player)
            char:WaitForChild("HumanoidRootPart")
            task.wait(0.1)
            AddESP(player)
        end)
        
        player.CharacterRemoving:Connect(function()
            RemoveESP(player)
        end)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    RemoveESP(player)
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
end)

-- ============================================================================
-- START SYSTEMS
-- ============================================================================

task.spawn(SilentAimTargetLoop)

print("Nova Silent Aim loaded successfully!")
print("Targeting Mode: " .. Config['Targeting']['Mode'])
if Config['Targeting']['Mode'] == 'Automatic' then
    print("Silent Aim: Always Active (360° mode)")
else
    print("Silent Aim Key: " .. Config['Keybinds']['Silent Aim']['Key'] .. " (" .. Config['Keybinds']['Silent Aim']['Mode'] .. ")")
end
print("Target Lock Key: " .. Config['Keybinds']['Target Lock']['Key'])
print("Trigger Bot Key: " .. Config['Keybinds']['Trigger Bot']['Key'])
print("Speed Key: " .. Config['Keybinds']['Speed'])
print("ESP Key: " .. Config['Keybinds']['ESP'])
