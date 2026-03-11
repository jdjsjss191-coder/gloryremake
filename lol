-- Wait for config
local timeout = 0
repeat 
    task.wait(0.1)
    timeout = timeout + 0.1
    if timeout > 5 then
        warn("Config timeout! Make sure config.lua is loaded first.")
        return
    end
until shared.Nova

local cfg = shared.Nova

-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Locals
local LocalPlayer = Players.LocalPlayer
repeat task.wait() until LocalPlayer.Character
local Mouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera

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
local SelectedTarget = nil -- For Target mode
local SilentAimActive = false
local FoundTarget = false
local ESPLabels = {}
local LastTargetScan = 0
local ScanRate = 1 / 60
local SpeedEnabled = false
local RapidFireActive = false

-- Target Tracer Drawing
local TargetTracer = Drawing.new("Line")
TargetTracer.Visible = false
TargetTracer.Thickness = cfg['target tracer']['thickness']
TargetTracer.Color = cfg['target tracer']['color']
TargetTracer.Transparency = cfg['target tracer']['transparency']
TargetTracer.ZIndex = 999

-- Raycast Parameters
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

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

local function HoldingKnife()
    if not cfg['silent aim']['knife_check'] then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    return tool and tool.Name == "[Knife]"
end

local function PlayerKnocked(player)
    if not cfg['silent aim']['knocked_check'] then return false end
    if not player.Character then return false end
    
    local bodyeffects = player.Character:FindFirstChild("BodyEffects")
    if bodyeffects then
        local ko = bodyeffects:FindFirstChild("K.O")
        if ko and ko.Value == true then return true end
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

local function CanSee(part)
    if not cfg['silent aim']['visible_check'] then return true end -- If check disabled, always return true
    if not part or not part.Parent then return false end
    
    local char = part.Parent
    local origin = Camera.CFrame.Position
    local dir = (part.Position - origin).Unit * (part.Position - origin).Magnitude
    
    RayParams.FilterDescendantsInstances = {LocalPlayer.Character, char}
    
    local result = Workspace:Raycast(origin, dir, RayParams)
    
    return result == nil or result.Instance:IsDescendantOf(char)
end

local function GetBodyParts(char)
    return {
        Head = char:FindFirstChild("Head"),
        HumanoidRootPart = char:FindFirstChild("HumanoidRootPart"),
        UpperTorso = char:FindFirstChild("UpperTorso"),
        LowerTorso = char:FindFirstChild("LowerTorso"),
    }
end

local function GetTargetPart(char, mousePos)
    local aimPart = cfg['silent aim']['aim_part']
    
    if aimPart == 'Head' then
        return char:FindFirstChild("Head")
    elseif aimPart == 'HumanoidRootPart' then
        return char:FindFirstChild("HumanoidRootPart")
    elseif aimPart == 'UpperTorso' then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    elseif aimPart == 'ClosestPart' then
        return GetClosestBodyPart(char, mousePos)
    end
    
    -- Fallback
    return char:FindFirstChild("HumanoidRootPart")
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

local function IsTargetAirborne(char)
    if not char then return false end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    
    -- Check if humanoid state is falling, jumping, or freefall
    local state = humanoid:GetState()
    if state == Enum.HumanoidStateType.Freefall or 
       state == Enum.HumanoidStateType.Flying or
       state == Enum.HumanoidStateType.Jumping then
        return true
    end
    
    -- Additional check: if they have significant vertical velocity
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        local velocity = hrp.AssemblyLinearVelocity or hrp.Velocity
        if math_abs(velocity.Y) > 5 then -- Moving up or down fast
            return true
        end
    end
    
    return false
end

local function GetPredictedPosition(part, char)
    if not cfg['silent aim']['prediction']['enabled'] then
        return part.Position
    end
    
    if not part or not part:IsA("BasePart") then
        return part.Position
    end
    
    local velocity = part.AssemblyLinearVelocity or part.Velocity
    local predictionAmount = cfg['silent aim']['prediction']['amount']
    
    -- Apply extra prediction for airborne targets
    if cfg['silent aim']['prediction']['auto_adjust'] and IsTargetAirborne(char) then
        predictionAmount = predictionAmount * cfg['silent aim']['prediction']['airborne_multiplier']
    end
    
    -- Calculate predicted position
    local predictedPos = part.Position + (velocity * predictionAmount)
    
    return predictedPos
end

-- ============================================================================
-- TARGET FINDING
-- ============================================================================
local function FindTargetClosestToMouse()
    if HoldingKnife() then return nil end -- Don't target when holding knife
    
    local mousePos = UserInputService:GetMouseLocation()
    local fovSizeSquared = cfg['silent aim']['use_fov'] and (cfg['silent aim']['fov'] * cfg['silent aim']['fov']) or math_huge
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
        
        if cfg['silent aim']['use_fov'] and distSquared > fovSizeSquared then continue end
        
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

-- ============================================================================
-- ESP SYSTEM
-- ============================================================================
local function AddESP(player)
    if player == LocalPlayer then return end
    if not cfg['esp']['enabled'] then return end
    
    local esp = {
        player = player,
        nametag = Drawing.new("Text"),
    }
    
    esp.nametag.Size = 18
    esp.nametag.Center = true
    esp.nametag.Outline = true
    esp.nametag.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.nametag.Color = cfg['esp']['color']
    esp.nametag.Font = 3
    esp.nametag.Visible = false
    esp.nametag.ZIndex = 1000
    
    ESPLabels[player.UserId] = esp
end

local function RemoveESP(player)
    local esp = ESPLabels[player.UserId]
    if esp then
        pcall(function()
            esp.nametag:Remove()
        end)
        ESPLabels[player.UserId] = nil
    end
end

local function RefreshESP()
    if not cfg['esp']['enabled'] then
        for userid, esp in pairs(ESPLabels) do
            pcall(function()
                esp.nametag.Visible = false
                esp.nametag:Remove()
            end)
            ESPLabels[userid] = nil
        end
        return
    end
    
    for userid, esp in pairs(ESPLabels) do
        local player = esp.player
        
        -- Check if player still exists in game
        if not player or not player.Parent or not Players:FindFirstChild(player.Name) then
            pcall(function()
                esp.nametag.Visible = false
                esp.nametag:Remove()
            end)
            ESPLabels[userid] = nil
            continue
        end
        
        -- Check if character exists
        if not player.Character or not player.Character.Parent then
            esp.nametag.Visible = false
            continue
        end
        
        local head = player.Character:FindFirstChild("Head")
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        
        -- Hide ESP if dead or missing parts
        if not head or not hum or hum.Health <= 0 or PlayerDead(player) then
            esp.nametag.Visible = false
            continue
        end
        
        local worldpos = head.Position + Vector3_new(0, 1.5, 0)
        local esppos, onscreen = Camera:WorldToViewportPoint(worldpos)
        
        -- Only show if on screen and in front of camera
        if onscreen and esppos.Z > 0 then
            esp.nametag.Position = Vector2_new(esppos.X, esppos.Y)
            esp.nametag.Text = player.Name
            
            -- Red for selected target in Target mode, or current target in Auto mode
            if cfg['silent aim']['targeting_mode'] == 'Target' then
                if SelectedTarget and SelectedTarget == player then
                    esp.nametag.Color = cfg['esp']['target_color']
                else
                    esp.nametag.Color = cfg['esp']['color']
                end
            else
                if CurrentTarget and CurrentTarget == player then
                    esp.nametag.Color = cfg['esp']['target_color']
                else
                    esp.nametag.Color = cfg['esp']['color']
                end
            end
            
            esp.nametag.Visible = true
        else
            -- Immediately hide when off screen
            esp.nametag.Visible = false
        end
    end
end

-- Initialize ESP
for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        AddESP(player)
    end
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        AddESP(player)
        player.CharacterAdded:Connect(function(char)
            task.wait(0.1)
            RemoveESP(player)
            AddESP(player)
        end)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    RemoveESP(player)
end)

-- Clean up ESP when character dies/respawns
for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.Died:Connect(function()
                task.wait(0.1)
                RemoveESP(player)
            end)
        end
    end
end

-- ============================================================================
-- SILENT AIM HOOK
-- ============================================================================
local grm = getrawmetatable(game)
local oldindex = grm.__index
setreadonly(grm, false)

grm.__index = function(self, key)
    if not checkcaller() and self == Mouse and cfg['silent aim']['enabled'] then
        if key == "Hit" then
            if not SilentAimActive then return oldindex(self, key) end
            if not CurrentTarget then return oldindex(self, key) end
            if not CurrentTarget.Character then return oldindex(self, key) end
            
            if PlayerDead(CurrentTarget) then return oldindex(self, key) end
            if PlayerKnocked(CurrentTarget) then return oldindex(self, key) end
            
            local char = CurrentTarget.Character
            local mousePos = UserInputService:GetMouseLocation()
            
            -- Get target part based on aim_part setting
            local targetPart = GetTargetPart(char, mousePos)
            
            if not targetPart then
                targetPart = char:FindFirstChild("HumanoidRootPart")
            end
            
            if targetPart then
                -- Use predicted position instead of current position
                local predictedPos = GetPredictedPosition(targetPart, char)
                return CFrame_new(predictedPos)
            end
        end
    end
    return oldindex(self, key)
end

setreadonly(grm, true)

-- ============================================================================
-- TARGET ACQUISITION LOOP
-- ============================================================================
local function SilentAimTargetLoop()
    while true do
        task.wait(ScanRate)
        
        if not SilentAimActive then
            if cfg['silent aim']['targeting_mode'] == 'Auto' then
                CurrentTarget = nil
            end
            FoundTarget = false
            continue
        end
        
        if cfg['silent aim']['targeting_mode'] == 'Target' then
            -- Target mode: Only aim at selected target
            if SelectedTarget then
                if not SelectedTarget.Character or PlayerDead(SelectedTarget) or PlayerKnocked(SelectedTarget) then
                    SelectedTarget = nil
                    CurrentTarget = nil
                    SilentAimActive = false
                    FoundTarget = false
                else
                    CurrentTarget = SelectedTarget
                    FoundTarget = true
                end
            else
                CurrentTarget = nil
                FoundTarget = false
            end
        else
            -- Auto mode: Find closest target
            if cfg['silent aim']['sticky_aim'] and CurrentTarget then
                local isValid = true
                if not CurrentTarget.Character then
                    isValid = false
                elseif PlayerDead(CurrentTarget) then
                    isValid = false
                elseif PlayerKnocked(CurrentTarget) then
                    isValid = false
                end
                
                if isValid then
                    FoundTarget = true
                else
                    CurrentTarget = nil
                    FoundTarget = false
                end
            end
            
            if not FoundTarget then
                local target = FindTargetClosestToMouse()
                if target then
                    CurrentTarget = target
                    FoundTarget = true
                else
                    CurrentTarget = nil
                    FoundTarget = false
                end
            end
        end
    end
end

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    local silentKey = cfg['silent aim']['key']
    if input.KeyCode.Name == silentKey then
        if cfg['silent aim']['mode'] == 'Toggle' then
            if cfg['silent aim']['targeting_mode'] == 'Target' then
                -- Target mode: Select/deselect
                if SelectedTarget then
                    SelectedTarget = nil
                    CurrentTarget = nil
                    SilentAimActive = false
                else
                    local target = FindTargetClosestToMouse()
                    if target then
                        SelectedTarget = target
                        CurrentTarget = target
                        SilentAimActive = true
                    end
                end
            else
                -- Auto mode: Toggle on/off
                SilentAimActive = not SilentAimActive
                if not SilentAimActive then
                    CurrentTarget = nil
                end
            end
        else
            -- Hold mode
            if cfg['silent aim']['targeting_mode'] == 'Target' then
                if not SelectedTarget then
                    local target = FindTargetClosestToMouse()
                    if target then
                        SelectedTarget = target
                        CurrentTarget = target
                    end
                end
                SilentAimActive = SelectedTarget ~= nil
            else
                SilentAimActive = true
            end
        end
    end
    
    -- Walkspeed toggle
    if cfg['walkspeed']['enabled'] then
        local speedKey = cfg['walkspeed']['key']
        if input.KeyCode.Name == speedKey then
            SpeedEnabled = not SpeedEnabled
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    
    local silentKey = cfg['silent aim']['key']
    if input.KeyCode.Name == silentKey then
        if cfg['silent aim']['mode'] == 'Hold' then
            SilentAimActive = false
            if cfg['silent aim']['targeting_mode'] == 'Auto' then
                CurrentTarget = nil
            end
        end
    end
end)

-- ============================================================================
-- MAIN RENDER LOOP
-- ============================================================================
RunService.RenderStepped:Connect(function(dt)
    RefreshESP()
    
    -- Update target tracer
    if cfg['target tracer']['enabled'] and SilentAimActive and CurrentTarget then
        if CurrentTarget.Character then
            local head = CurrentTarget.Character:FindFirstChild("Head")
            if head and not PlayerDead(CurrentTarget) and not PlayerKnocked(CurrentTarget) then
                local headPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen and headPos.Z > 0 then
                    local mousePos = UserInputService:GetMouseLocation()
                    TargetTracer.From = Vector2_new(mousePos.X, mousePos.Y)
                    TargetTracer.To = Vector2_new(headPos.X, headPos.Y)
                    TargetTracer.Visible = true
                else
                    TargetTracer.Visible = false
                end
            else
                TargetTracer.Visible = false
            end
        else
            TargetTracer.Visible = false
        end
    else
        TargetTracer.Visible = false
    end
    
    -- Apply walkspeed
    if cfg['walkspeed']['enabled'] and SpeedEnabled then
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = cfg['walkspeed']['speed']
            end
        end
    end
end)

-- Start systems
task.spawn(SilentAimTargetLoop)

-- ============================================================================
-- RAPID FIRE
-- ============================================================================
local function StartRapidFire()
    if RapidFireActive then return end
    RapidFireActive = true
    
    local isMouseDown = false
    
    -- Mouse button tracking
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isMouseDown = true
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isMouseDown = false
        end
    end)
    
    -- Rapid fire loop
    task.spawn(function()
        while cfg['rapid fire']['enabled'] do
            if isMouseDown then
                local char = LocalPlayer.Character
                if char then
                    local tool = char:FindFirstChildOfClass("Tool")
                    if tool then
                        tool:Activate()
                    end
                end
            end
            task.wait(0.01) -- 100 shots per second
        end
    end)
end

-- Start Rapid Fire if enabled
if cfg['rapid fire'] and cfg['rapid fire']['enabled'] then
    StartRapidFire()
end

-- ============================================================================
-- SPREAD MODIFICATIONS
-- ============================================================================
local oldRandom = nil

local function HookSpread()
    if oldRandom then return end -- Already hooked
    
    oldRandom = hookfunction(math.random, function(...)
        local args = {...}
        
        -- If called from our script, use original
        if checkcaller() then
            return oldRandom(...)
        end
        
        -- Check if this is a spread-related random call
        -- Game uses math.random with specific ranges for bullet spread
        if (#args == 0) or
            (args[1] == -0.05 and args[2] == 0.05) or
            (args[1] == -0.1) or
            (args[1] == -0.05) then
            
            if cfg['spread modifications']['enabled'] then
                -- Check if specific weapons mode is enabled
                if cfg['spread modifications']['specific weapons']['enabled'] then
                    local char = LocalPlayer.Character
                    if char then
                        local tool = char:FindFirstChildOfClass("Tool")
                        if tool then
                            local weaponName = tool.Name
                            local found = false
                            
                            -- Check if current weapon is in the list
                            for _, weapon in pairs(cfg['spread modifications']['specific weapons']['weapons']) do
                                if weaponName == weapon then
                                    found = true
                                    break
                                end
                            end
                            
                            if found then
                                -- Reduce spread by multiplying by amount/100
                                return oldRandom(...) * (cfg['spread modifications']['amount'] / 100)
                            end
                        end
                    end
                else
                    -- Apply to all weapons
                    return oldRandom(...) * (cfg['spread modifications']['amount'] / 100)
                end
            end
        end
        
        -- Default behavior for non-spread calls
        return oldRandom(...)
    end)
end

-- Initialize spread modifications if enabled
if cfg['spread modifications'] and cfg['spread modifications']['enabled'] then
    HookSpread()
end
