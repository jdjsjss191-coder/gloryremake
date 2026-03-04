-- ============================================
-- LOGIC
-- ============================================

local Config = shared.Glory

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local currentTarget = nil
local isLocking = false
local triggerEnabled = false
local espLabels = {}
local SpeedEnabled = false
local BaseSpeed = 16
local lastVisibleTarget = nil
local lastTriggerClick = 0

local outlinePart = Instance.new("Part")
outlinePart.Anchored = true
outlinePart.CanCollide = false
outlinePart.Transparency = 0.85
outlinePart.BrickColor = BrickColor.new("Grey")
outlinePart.Material = Enum.Material.Neon
outlinePart.Name = "FOVOutline3D"
outlinePart.Parent = Workspace

local targetLine = Drawing.new("Line")
targetLine.Visible = false
targetLine.Thickness = Config['Target Line']['Thickness']
targetLine.Transparency = Config['Target Line']['Transparency']
targetLine.ZIndex = 999

local function elasticOut(t)
    local p = 0.3
    return math.pow(2, -10 * t) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
end

local function sineInOut(t)
    return -(math.cos(math.pi * t) - 1) / 2
end

local function isPlayerKnockedOrKO(player)
    if not Config['Settings']['Knock Check'] then
        return false
    end
    
    if player.Character then
        local bodyEffects = player.Character:FindFirstChild("BodyEffects")
        if bodyEffects then
            local ko = bodyEffects:FindFirstChild("K.O")
            if ko and ko.Value == true then
                return true
            end
            
            local knocked = bodyEffects:FindFirstChild("Knocked")
            if knocked and knocked.Value == true then
                return true
            end
        end
    end
    
    return false
end

local function isSelfKnocked()
    if not Config['Settings']['Self Knock Check'] then
        return false
    end
    
    if LocalPlayer.Character then
        local bodyEffects = LocalPlayer.Character:FindFirstChild("BodyEffects")
        if bodyEffects then
            local ko = bodyEffects:FindFirstChild("K.O")
            if ko and ko.Value == true then
                return true
            end
            
            local knocked = bodyEffects:FindFirstChild("Knocked")
            if knocked and knocked.Value == true then
                return true
            end
        end
    end
    return false
end

local function canSeeTarget(part)
    if not Config['Settings']['Visible Check'] then
        return true
    end
    
    if not part or not part.Parent then return false end
    
    local character = part.Parent
    local origin = Camera.CFrame.Position
    local direction = (part.Position - origin).Unit * (part.Position - origin).Magnitude
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, character, outlinePart}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    
    local rayResult = Workspace:Raycast(origin, direction, raycastParams)
    
    return rayResult == nil or rayResult.Instance:IsDescendantOf(character)
end

local function getBodyParts(character)
    return {
        character:FindFirstChild("Head"),
        character:FindFirstChild("UpperTorso"),
        character:FindFirstChild("HumanoidRootPart"),
        character:FindFirstChild("LowerTorso"),
        character:FindFirstChild("LeftUpperArm"),
        character:FindFirstChild("RightUpperArm"),
        character:FindFirstChild("LeftLowerArm"),
        character:FindFirstChild("RightLowerArm"),
        character:FindFirstChild("LeftHand"),
        character:FindFirstChild("RightHand"),
        character:FindFirstChild("LeftUpperLeg"),
        character:FindFirstChild("RightUpperLeg"),
        character:FindFirstChild("LeftLowerLeg"),
        character:FindFirstChild("RightLowerLeg"),
        character:FindFirstChild("LeftFoot"),
        character:FindFirstChild("RightFoot"),
    }
end

local function getClosestBodyPart(character)
    local closestPart = nil
    local shortestDist = math.huge
    
    local bodyParts = getBodyParts(character)
    
    local mousePos = UserInputService:GetMouseLocation()
    
    for _, part in pairs(bodyParts) do
        if part then
            local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
            
            if onScreen then
                local dist = math.sqrt(
                    (screenPos.X - mousePos.X)^2 + 
                    (screenPos.Y - mousePos.Y)^2
                )
                
                if dist < shortestDist then
                    shortestDist = dist
                    closestPart = part
                end
            end
        end
    end
    
    return closestPart
end

local function isMouseInFOV3D()
    if not Config['FOV']['Enabled'] then return true end
    
    local mouse = UserInputService:GetMouseLocation()
    local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    
    local filterList = {}
    if LocalPlayer.Character then
        table.insert(filterList, LocalPlayer.Character)
    end
    
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(filterList, player.Character)
        end
    end
    
    params.FilterDescendantsInstances = filterList
    
    local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
    
    if hit and hit.Instance == outlinePart then
        return true
    end
    
    return false
end

local function findClosestTarget()
    local closestTarget = nil
    local shortestDistance = math.huge
    
    local mousePos = UserInputService:GetMouseLocation()
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            if not isPlayerKnockedOrKO(player) then
                local character = player.Character
                local bodyParts = getBodyParts(character)
                
                for _, part in pairs(bodyParts) do
                    if part and canSeeTarget(part) then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        
                        if onScreen then
                            local dist = math.sqrt(
                                (screenPos.X - mousePos.X)^2 + 
                                (screenPos.Y - mousePos.Y)^2
                            )
                            
                            if dist < shortestDistance then
                                shortestDistance = dist
                                closestTarget = part
                            end
                        end
                    end
                end
            end
        end
    end
    
    return closestTarget
end

local function getPredictedPosition(part, config)
    if not config['Use Prediction'] then return part.Position end
    
    local velocity = part.AssemblyLinearVelocity
    local prediction = config['Prediction']
    
    local predValue
    if type(prediction) == "table" then
        predValue = prediction['X'] or prediction['Y'] or prediction['Z'] or 0.133
    else
        predValue = (prediction == 0) and 0.133 or prediction
    end
    
    return part.Position + Vector3.new(
        velocity.X * predValue, 
        velocity.Y * predValue, 
        velocity.Z * predValue
    )
end

local function getTargetForCameraLock()
    if Config['Settings']['Target Aim'] and currentTarget then
        local player = Players:GetPlayerFromCharacter(currentTarget.Parent)
        if player and not isPlayerKnockedOrKO(player) then
            local targetPart = nil
            
            if Config['Camera Lock']['Hit Part'] == 'Closest Part' then
                targetPart = getClosestBodyPart(currentTarget.Parent)
                
                if targetPart then
                    currentTarget = targetPart
                end
            else
                targetPart = currentTarget.Parent:FindFirstChild(Config['Camera Lock']['Hit Part'])
            end
            
            if targetPart then
                if canSeeTarget(targetPart) then
                    lastVisibleTarget = targetPart
                    return targetPart
                else
                    return nil
                end
            end
        else
            currentTarget = nil
            isLocking = false
            lastVisibleTarget = nil
            targetLine.Visible = false
            return nil
        end
        
        return nil
    else
        return findClosestTarget()
    end
end

local function applyCameraLock()
    if not isLocking then return end
    
    if isSelfKnocked() then
        currentTarget = nil
        isLocking = false
        lastVisibleTarget = nil
        targetLine.Visible = false
        return
    end
    
    if Config['FOV']['Enabled'] and not isMouseInFOV3D() then
        return
    end
    
    local target = getTargetForCameraLock()
    
    if target then
        local targetPos = getPredictedPosition(target, Config['Camera Lock'])
        
        local cameraCFrame = Camera.CFrame
        local targetCFrame = CFrame.new(cameraCFrame.Position, targetPos)
        
        local smoothConfig = Config['Camera Lock']['Smoothing']
        local baseAlphaX = 1 / smoothConfig['X']
        local baseAlphaY = 1 / smoothConfig['Y']
        local baseAlphaZ = 1 / smoothConfig['Z']
        
        local elasticAlphaX = elasticOut(math.min(baseAlphaX, 1))
        local elasticAlphaY = elasticOut(math.min(baseAlphaY, 1))
        local elasticAlphaZ = elasticOut(math.min(baseAlphaZ, 1))
        
        local avgElasticAlpha = (elasticAlphaX + elasticAlphaY + elasticAlphaZ) / 3
        local avgBaseAlpha = (baseAlphaX + baseAlphaY + baseAlphaZ) / 3
        
        local smoothCFrame = cameraCFrame:Lerp(targetCFrame, avgElasticAlpha * avgBaseAlpha)
        
        local sineAlpha = sineInOut(math.min(avgBaseAlpha, 1))
        Camera.CFrame = smoothCFrame:Lerp(targetCFrame, sineAlpha * avgBaseAlpha)
    else
        if lastVisibleTarget then
            local player = Players:GetPlayerFromCharacter(lastVisibleTarget.Parent)
            if player and not isPlayerKnockedOrKO(player) then
                local targetPart = lastVisibleTarget
                if targetPart and canSeeTarget(targetPart) then
                    currentTarget = lastVisibleTarget
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
    
    if currentTarget and currentTarget.Parent then
        local character = currentTarget.Parent
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        
        if rootPart then
            local offset = Config['FOV']['Size']
            outlinePart.Size = rootPart.Size + Vector3.new(offset, offset, offset)
            outlinePart.CFrame = rootPart.CFrame
            outlinePart.Transparency = 0.85
            
            if isMouseInFOV3D() then
                outlinePart.BrickColor = BrickColor.new(Config['FOV']['Active Color'])
            else
                outlinePart.BrickColor = BrickColor.new("Grey")
            end
        else
            outlinePart.Transparency = 1
        end
    else
        outlinePart.Transparency = 1
    end
end

local function updateTargetLine()
    if not Config['Target Line']['Enabled'] then
        targetLine.Visible = false
        return
    end
    
    if not currentTarget or not currentTarget.Parent or not isLocking then
        targetLine.Visible = false
        return
    end
    
    local character = currentTarget.Parent
    local hrp = character:FindFirstChild("HumanoidRootPart")
    
    if not hrp then
        targetLine.Visible = false
        return
    end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
    
    if onScreen and screenPos.Z > 0 then
        local mousePos = UserInputService:GetMouseLocation()
        
        targetLine.From = Vector2.new(mousePos.X, mousePos.Y)
        targetLine.To = Vector2.new(screenPos.X, screenPos.Y)
        targetLine.Thickness = Config['Target Line']['Thickness']
        targetLine.Transparency = Config['Target Line']['Transparency']
        
        if canSeeTarget(currentTarget) then
            targetLine.Color = Config['Target Line']['Vulnerable']
        else
            targetLine.Color = Config['Target Line']['Invulnerable']
        end
        
        targetLine.Visible = true
    else
        targetLine.Visible = false
    end
end

local function TriggerBot()
    if not Config['Trigger Bot']['Enabled'] then return end
    if not triggerEnabled then return end
    
    if tick() - lastTriggerClick < Config['Trigger Bot']['Delay'] then return end
    
    if Config['Trigger Bot']['Require Target'] and not currentTarget then return end
    
    if currentTarget then
        local character = currentTarget.Parent
        if not character then return end
        
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        
        if isPlayerKnockedOrKO(player) then return end
        
        if not canSeeTarget(currentTarget) then return end
        
        if Config['FOV']['Enabled'] and not isMouseInFOV3D() then return end
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
    lastTriggerClick = tick()
end

local grm = getrawmetatable(game)
local oldIndex = grm.__index
setreadonly(grm, false)

grm.__index = function(self, key)
    if not checkcaller() and self == Mouse and Config['Silent Aim']['Enabled'] then
        if key == "Hit" then
            if not currentTarget then return oldIndex(self, key) end
            
            local character = currentTarget.Parent
            if not character then return oldIndex(self, key) end
            
            local player = Players:GetPlayerFromCharacter(character)
            if not player then return oldIndex(self, key) end
            
            if isPlayerKnockedOrKO(player) then return oldIndex(self, key) end
            if not canSeeTarget(currentTarget) then return oldIndex(self, key) end
            
            if Config['FOV']['Enabled'] and not isMouseInFOV3D() then
                return oldIndex(self, key)
            end
            
            local targetPart = currentTarget
            if targetPart then
                local predictedPos = getPredictedPosition(targetPart, Config['Silent Aim'])
                return CFrame.new(predictedPos)
            end
        end
    end
    return oldIndex(self, key)
end

setreadonly(grm, true)

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

local function addESPToPlayer(player)
    if player == LocalPlayer then return end
    
    local esp = {
        player = player,
        nameTag = Drawing.new("Text"),
    }
    
    esp.nameTag.Size = 14
    esp.nameTag.Center = true
    esp.nameTag.Outline = true
    esp.nameTag.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.nameTag.Color = Config['Visual Awareness']['Color']
    esp.nameTag.Font = Drawing.Fonts.Plex
    esp.nameTag.Visible = false
    esp.nameTag.ZIndex = 1000
    
    espLabels[player.UserId] = esp
end

local function removeESPFromPlayer(player)
    local esp = espLabels[player.UserId]
    if esp then
        esp.nameTag:Remove()
        espLabels[player.UserId] = nil
    end
end

local function refreshESP()
    if not Config['Visual Awareness']['Enabled'] then
        for _, esp in pairs(espLabels) do
            esp.nameTag.Visible = false
        end
        return
    end
    
    for userId, esp in pairs(espLabels) do
        local player = esp.player
        if not player or not player.Parent then
            esp.nameTag.Visible = false
            esp.nameTag:Remove()
            espLabels[userId] = nil
            continue
        end
        
        if player.Character and player.Character.Parent and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Head") then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then
                esp.nameTag.Visible = false
                continue
            end
            
            local head = player.Character.Head
            local rootPart = player.Character.HumanoidRootPart
            
            local espPosition, onScreen
            if Config['Visual Awareness']['Name Above'] then
                espPosition, onScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1.5, 0))
            else
                espPosition, onScreen = Camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 2.8, 0))
            end
            
            if onScreen and espPosition.Z > 0 then
                esp.nameTag.Position = Vector2.new(espPosition.X, espPosition.Y)
                
                if Config['Visual Awareness']['Use Display Name'] then
                    esp.nameTag.Text = player.DisplayName
                else
                    esp.nameTag.Text = player.Name
                end
                
                local isCurrentTarget = false
                local isTargetVisible = false
                
                if currentTarget and currentTarget.Parent == player.Character then
                    isCurrentTarget = true
                    isTargetVisible = canSeeTarget(currentTarget)
                elseif isLocking and not Config['Settings']['Target Aim'] then
                    local closestTarget = findClosestTarget()
                    if closestTarget and closestTarget.Parent == player.Character then
                        isCurrentTarget = true
                        isTargetVisible = true
                    end
                end
                
                if isCurrentTarget and isTargetVisible then
                    esp.nameTag.Color = Config['Visual Awareness']['Target Color']
                else
                    esp.nameTag.Color = Config['Visual Awareness']['Color']
                end
                
                esp.nameTag.Visible = true
            else
                esp.nameTag.Visible = false
            end
        else
            esp.nameTag.Visible = false
        end
    end
end

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        addESPToPlayer(player)
    end
    
    player.CharacterAdded:Connect(function(char)
        removeESPFromPlayer(player)
        char:WaitForChild("HumanoidRootPart")
        task.wait(0.1)
        addESPToPlayer(player)
    end)
    
    player.CharacterRemoving:Connect(function()
        removeESPFromPlayer(player)
    end)
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(char)
            removeESPFromPlayer(player)
            char:WaitForChild("HumanoidRootPart")
            task.wait(0.1)
            addESPToPlayer(player)
        end)
        
        player.CharacterRemoving:Connect(function()
            removeESPFromPlayer(player)
        end)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeESPFromPlayer(player)
end)

RunService.RenderStepped:Connect(function()
    if isSelfKnocked() and isLocking then
        currentTarget = nil
        isLocking = false
        lastVisibleTarget = nil
        targetLine.Visible = false
    end
    
    TriggerBot()
    
    if SpeedEnabled and Config['Speed']['Enabled'] then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            local targetSpeed = BaseSpeed * Config['Speed']['Multiplier']
            
            if humanoid.WalkSpeed ~= targetSpeed then
                humanoid.WalkSpeed = targetSpeed
            end
        end
        
        if Config['Speed']['Anti Fling'] then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local vel = hrp.Velocity
                if vel.Y > 50 or vel.Y < -50 then
                    hrp.Velocity = Vector3.new(vel.X, 0, vel.Z)
                end
            end
        end
    end
    
    if Config['Hitbox Expander']['Enabled'] then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.Size = Vector3.new(Config['Hitbox Expander']['Size'], Config['Hitbox Expander']['Size'], Config['Hitbox Expander']['Size'])
                    
                    if Config['Hitbox Expander']['Visualize'] then
                        hrp.Transparency = 0.7
                        hrp.BrickColor = BrickColor.new("Really blue")
                        hrp.Material = "Neon"
                        hrp.CanCollide = false
                    else
                        hrp.Transparency = 1
                    end
                end
            end
        end
    end
    
    update3DFOVBox()
    updateTargetLine()
    refreshESP()
    
    if Config['Camera Lock']['Enabled'] then
        applyCameraLock()
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Target Lock']['Key']] then
        local mode = Config['Keybinds']['Target Lock']['Mode']
        
        if mode == 'Toggle' then
            if Config['Settings']['Target Aim'] then
                if isLocking then
                    isLocking = false
                    currentTarget = nil
                    lastVisibleTarget = nil
                    targetLine.Visible = false
                else
                    local target = findClosestTarget()
                    if target then
                        currentTarget = target
                        lastVisibleTarget = target
                        isLocking = true
                        update3DFOVBox()
                    end
                end
            else
                isLocking = not isLocking
                if not isLocking then
                    targetLine.Visible = false
                end
            end
        elseif mode == 'Hold' then
            if Config['Settings']['Target Aim'] then
                local target = findClosestTarget()
                if target then
                    currentTarget = target
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
            triggerEnabled = not triggerEnabled
        elseif mode == 'Hold' then
            triggerEnabled = true
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Speed']] then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            if not SpeedEnabled then
                BaseSpeed = 16
                SpeedEnabled = true
            else
                humanoid.WalkSpeed = BaseSpeed
                SpeedEnabled = false
            end
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['ESP']] then
        Config['Visual Awareness']['Enabled'] = not Config['Visual Awareness']['Enabled']
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Target Lock']['Key']] then
        local mode = Config['Keybinds']['Target Lock']['Mode']
        
        if mode == 'Hold' then
            isLocking = false
            currentTarget = nil
            lastVisibleTarget = nil
            targetLine.Visible = false
        end
    end
    
    if input.KeyCode == Enum.KeyCode[Config['Keybinds']['Trigger Bot']['Key']] then
        local mode = Config['Keybinds']['Trigger Bot']['Mode']
        
        if mode == 'Hold' then
            triggerEnabled = false
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
end)
