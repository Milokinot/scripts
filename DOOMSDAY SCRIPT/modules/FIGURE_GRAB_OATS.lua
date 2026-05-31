getgenv().FigureGrabModule = getgenv().FigureGrabModule or {}

FigureGrabModule.Players = game:GetService("Players")
FigureGrabModule.RunService = game:GetService("RunService")
FigureGrabModule.ReplicatedStorage = game:GetService("ReplicatedStorage")
FigureGrabModule.UserInputService = game:GetService("UserInputService")

FigureGrabModule.LocalPlayer = FigureGrabModule.Players.LocalPlayer
FigureGrabModule.Mouse = FigureGrabModule.LocalPlayer:GetMouse()

local function figureNotify(title, content, duration)
    if Rayfield and type(Rayfield.Notify) == "function" then
        Rayfield:Notify({
            Title = title,
            Content = content,
            Duration = duration or 3
        })
        return
    end

    if getgenv().DoomsdayNotify then
        getgenv().DoomsdayNotify(title, content, duration or 3)
        return
    end

    warn("[Figure Grab Oats] " .. tostring(title) .. ": " .. tostring(content))
end

FigureGrabModule.GrabEvents = FigureGrabModule.ReplicatedStorage:WaitForChild("GrabEvents")
FigureGrabModule.SetNetworkOwner = FigureGrabModule.GrabEvents:WaitForChild("SetNetworkOwner")

FigureGrabModule.State = {
    FigureGrabEnabled = false,
    FigureGrabConnection = nil,
    TargetCharacter = nil,
    AnimationCopyEnabled = false,
    VectorZero = Vector3.new(0, 0, 0)
}

FigureGrabModule.Configuration = {
    LineDistance = 0,
    HoldPosition = {X = 0, Y = 0, Z = -5},
    HoldRotation = {X = 0, Y = 0, Z = 0},
    LeftArmPosition = {X = 0, Y = 0, Z = 0},
    LeftArmRotation = {X = 0, Y = 0, Z = 0},
    RightArmPosition = {X = 0, Y = 0, Z = 0},
    RightArmRotation = {X = 0, Y = 0, Z = 0},
    LeftLegPosition = {X = 0, Y = 0, Z = 0},
    LeftLegRotation = {X = 0, Y = 0, Z = 0},
    RightLegPosition = {X = 0, Y = 0, Z = 0},
    RightLegRotation = {X = 0, Y = 0, Z = 0},
    HeadPosition = {X = 0, Y = 0, Z = 0},
    HeadRotation = {X = 0, Y = 0, Z = 0}
}

FigureGrabModule.Presets = {
    Pose1 = {
        HoldPosition = {X = 0, Y = 0, Z = -7.5},
        HoldRotation = {X = 90, Y = 0, Z = 108},
        LeftArmPosition = {X = -1.5, Y = 1, Z = -1},
        LeftArmRotation = {X = 283, Y = 0, Z = 0},
        RightArmPosition = {X = 1.5, Y = 0.5, Z = 1},
        RightArmRotation = {X = 270, Y = 0, Z = 0},
        LeftLegPosition = {X = 0.5, Y = -1.5, Z = 0.5},
        LeftLegRotation = {X = 312, Y = 0, Z = 0},
        RightLegPosition = {X = -0.5, Y = -1.5, Z = 0.5},
        RightLegRotation = {X = 283, Y = 0, Z = 0},
        HeadPosition = {X = 0, Y = 1.5, Z = 0},
        HeadRotation = {X = 0, Y = 0, Z = 0},
    },
    Pose2 = {
        HoldPosition = {X = 0, Y = -1.5, Z = -12.5},
        HoldRotation = {X = 272, Y = 0, Z = 0},
        LeftArmPosition = {X = -1, Y = 1, Z = -0.5},
        LeftArmRotation = {X = 90, Y = 0, Z = 0},
        RightArmPosition = {X = 1, Y = 1, Z = -0.5},
        RightArmRotation = {X = 90, Y = 0, Z = 0},
        LeftLegPosition = {X = 1, Y = -1, Z = -0.5},
        LeftLegRotation = {X = 90, Y = 0, Z = 0},
        RightLegPosition = {X = -1, Y = -1, Z = -0.5},
        RightLegRotation = {X = 90, Y = 0, Z = 0},
        HeadPosition = {X = 0, Y = 1, Z = 1},
        HeadRotation = {X = 90, Y = 0, Z = 0},
    },
    Pose3 = {
        HoldPosition = {X = 0, Y = -5.5, Z = -4},
        HoldRotation = {X = 0, Y = 0, Z = 0},
        LeftArmPosition = {X = 1, Y = 7.5, Z = 1.5},
        LeftArmRotation = {X = 0, Y = 0, Z = 0},
        RightArmPosition = {X = 1, Y = 6, Z = 1.5},
        RightArmRotation = {X = 0, Y = 0, Z = 0},
        LeftLegPosition = {X = 0.5, Y = 5, Z = 1.5},
        LeftLegRotation = {X = 0, Y = 0, Z = 92},
        RightLegPosition = {X = -0.5, Y = 5, Z = 1.5},
        RightLegRotation = {X = 0, Y = 0, Z = 90},
        HeadPosition = {X = 0, Y = 0, Z = 0},
        HeadRotation = {X = 0, Y = 0, Z = 0},
    },
    Pose4 = {
        HoldPosition = {X = 1.5, Y = -8.5, Z = -1.5},
        HoldRotation = {X = 0, Y = 0, Z = 0},
        LeftArmPosition = {X = 0, Y = 0, Z = 0},
        LeftArmRotation = {X = 0, Y = 0, Z = 0},
        RightArmPosition = {X = 0, Y = 0, Z = 0},
        RightArmRotation = {X = 0, Y = 0, Z = 0},
        LeftLegPosition = {X = 0, Y = 0, Z = 0},
        LeftLegRotation = {X = 0, Y = 0, Z = 0},
        RightLegPosition = {X = 1.5, Y = 0, Z = 0},
        RightLegRotation = {X = 0, Y = 0, Z = 0},
        HeadPosition = {X = 0, Y = 9, Z = 0},
        HeadRotation = {X = 0, Y = 0, Z = 0},
    },
    Pose5 = {
        HoldPosition = {X = 0, Y = -3, Z = -6},
        HoldRotation = {X = 270, Y = 0, Z = 0},
        LeftArmPosition = {X = -1, Y = 0.5, Z = 0},
        LeftArmRotation = {X = 180, Y = 0, Z = 0},
        RightArmPosition = {X = 1, Y = 0.5, Z = 0},
        RightArmRotation = {X = 180, Y = 0, Z = 0},
        LeftLegPosition = {X = 0, Y = -3, Z = 0},
        LeftLegRotation = {X = 0, Y = 0, Z = 0},
        RightLegPosition = {X = 0, Y = -2, Z = 0.5},
        RightLegRotation = {X = 45, Y = 0, Z = 0},
        HeadPosition = {X = 0, Y = 1.5, Z = -0.5},
        HeadRotation = {X = 270, Y = 0, Z = 0},
    },
    Pose6 = {
        HoldPosition = {X = 5.5, Y = 0.5, Z = -1.5},
        HoldRotation = {X = 345, Y = 39, Z = 0},
        LeftArmPosition = {X = 2, Y = 0.5, Z = 0},
        LeftArmRotation = {X = 0, Y = 43, Z = 121},
        RightArmPosition = {X = -2, Y = 0, Z = -0},
        RightArmRotation = {X = 64, Y = 112, Z = 0},
        LeftLegPosition = {X = -0.5, Y = -2, Z = 0},
        LeftLegRotation = {X = 349, Y = 0, Z = 360},
        RightLegPosition = {X = 0.5, Y = -2, Z = 0},
        RightLegRotation = {X = 345, Y = 360, Z = 10},
        HeadPosition = {X = 0, Y = 1.5, Z = 0},
        HeadRotation = {X = 0, Y = 344, Z = 0},
    },
    Pose7 = {
        HoldPosition = {X = 0, Y = -2, Z = -10},
        HoldRotation = {X = 90, Y = 0, Z = 0},
        LeftArmPosition = {X = -1.5, Y = 0, Z = 0},
        LeftArmRotation = {X = 270, Y = 0, Z = 315},
        RightArmPosition = {X = 1.5, Y = 0, Z = 0},
        RightArmRotation = {X = 270, Y = 0, Z = 45},
        LeftLegPosition = {X = -1, Y = -1.5, Z = 0},
        LeftLegRotation = {X = 90, Y = 0, Z = 0},
        RightLegPosition = {X = 1, Y = -1.5, Z = 0},
        RightLegRotation = {X = 90, Y = 0, Z = 0},
        HeadPosition = {X = 0, Y = 1.5, Z = 0},
        HeadRotation = {X = 0, Y = 0, Z = 0},
    },
    JojoStand = {
        HoldPosition = {X = -4.5, Y = 0.5, Z = -1.5},
        HoldRotation = {X = 8, Y = 349, Z = 0},
        LeftArmPosition = {X = 1.5, Y = 0, Z = -0},
        LeftArmRotation = {X = 15, Y = 62, Z = 41},
        RightArmPosition = {X = -1.5, Y = 0.5, Z = -0.5},
        RightArmRotation = {X = 65, Y = 149, Z = 6},
        LeftLegPosition = {X = -0.5, Y = -2, Z = 0},
        LeftLegRotation = {X = 349, Y = 0, Z = 360},
        RightLegPosition = {X = 0.5, Y = -2, Z = 0},
        RightLegRotation = {X = 345, Y = 360, Z = 10},
        HeadPosition = {X = 0, Y = 1.5, Z = 0},
        HeadRotation = {X = 0, Y = 344, Z = 0},
    }
}

function FigureGrabModule.GetCharacter(player)
    character = player.Character
    if not character then
        if player.CharacterAdded then
            character = player.CharacterAdded:Wait()
        end
    end
    return character
end

function FigureGrabModule.getLimbCFrame(limbName)
    char = FigureGrabModule.LocalPlayer.Character
    if not char then return CFrame.new() end
    
    hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return CFrame.new() end
    
    if limbName == "Head" then
        head = char:FindFirstChild("Head")
        if head then return head.CFrame end
        return hrp.CFrame * CFrame.new(0, 1.5, 0)
    elseif limbName == "Right Arm" then
        rightArm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightUpperArm")
        if rightArm then return rightArm.CFrame end
        return hrp.CFrame * CFrame.new(1.5, 0.5, 0)
    elseif limbName == "Left Arm" then
        leftArm = char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftUpperArm")
        if leftArm then return leftArm.CFrame end
        return hrp.CFrame * CFrame.new(-1.5, 0.5, 0)
    elseif limbName == "Right Leg" then
        rightLeg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightUpperLeg")
        if rightLeg then return rightLeg.CFrame end
        return hrp.CFrame * CFrame.new(0.5, -1.5, 0)
    elseif limbName == "Left Leg" then
        leftLeg = char:FindFirstChild("Left Leg") or char:FindFirstChild("LeftUpperLeg")
        if leftLeg then return leftLeg.CFrame end
        return hrp.CFrame * CFrame.new(-0.5, -1.5, 0)
    end
    
    return hrp.CFrame
end

function FigureGrabModule.CopyAnimationsFromLimbs()
    if not FigureGrabModule.State.AnimationCopyEnabled then return end
    if not FigureGrabModule.State.TargetCharacter then return end
    
    local MyCharacter = FigureGrabModule.GetCharacter(FigureGrabModule.LocalPlayer)
    if not MyCharacter then return end
    
    local MyHRP = MyCharacter:FindFirstChild("HumanoidRootPart")
    local MyTorso = MyCharacter:FindFirstChild("Torso")
    local TargetTorso = FigureGrabModule.State.TargetCharacter:FindFirstChild("Torso")

    if not MyHRP or not MyTorso or not TargetTorso then return end
    

    local holdCFrame = MyHRP.CFrame * CFrame.new(
        FigureGrabModule.Configuration.HoldPosition.X, 
        FigureGrabModule.Configuration.HoldPosition.Y, 
        FigureGrabModule.Configuration.HoldPosition.Z
    ) * CFrame.Angles(
        math.rad(FigureGrabModule.Configuration.HoldRotation.X), 
        math.rad(FigureGrabModule.Configuration.HoldRotation.Y), 
        math.rad(FigureGrabModule.Configuration.HoldRotation.Z)
    )

   
    TargetTorso.CFrame = holdCFrame
    

    local torsoRelative = MyHRP.CFrame:ToObjectSpace(MyTorso.CFrame)
    
   
    TargetTorso.CFrame = TargetTorso.CFrame * torsoRelative.Rotation
    
    TargetTorso.Velocity = FigureGrabModule.State.VectorZero
    TargetTorso.RotVelocity = FigureGrabModule.State.VectorZero


    local limbs = {"Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"}

    for _, limbName in ipairs(limbs) do
        local myPart = MyCharacter:FindFirstChild(limbName)
        local targetPart = FigureGrabModule.State.TargetCharacter:FindFirstChild(limbName)

        if myPart and targetPart then

            local relative = MyTorso.CFrame:ToObjectSpace(myPart.CFrame)
            

            targetPart.CFrame = TargetTorso.CFrame:ToWorldSpace(relative)
            
            targetPart.Velocity = FigureGrabModule.State.VectorZero
            targetPart.RotVelocity = FigureGrabModule.State.VectorZero
        end
    end
end

function FigureGrabModule.ToggleFigureGrab()
    if not FigureGrabModule.State.FigureGrabEnabled then
        MouseTarget = FigureGrabModule.Mouse.Target
        if not MouseTarget then
            figureNotify("Error", "Aim at a player first", 3)
            return
        end
        
        FigureGrabModule.State.TargetCharacter = MouseTarget.Parent
        MyCharacter = FigureGrabModule.GetCharacter(FigureGrabModule.LocalPlayer)
        
        if not FigureGrabModule.State.TargetCharacter or not MyCharacter then
            figureNotify("Error", "Invalid target", 3)
            return
        end
        
        BodyParts = {"Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}
        TargetTorso = FigureGrabModule.State.TargetCharacter:FindFirstChild("Torso")
        
        if not TargetTorso then
            figureNotify("Error", "Torso not found", 3)
            return
        end
        
        for _, partName in pairs(BodyParts) do
            part = FigureGrabModule.State.TargetCharacter:FindFirstChild(partName)
            if part then
                part.Anchored = false
                part.CanCollide = true
                part.Massless = true
            end
        end
        
        FigureGrabModule.State.FigureGrabEnabled = true
        FigureGrabModule.Configuration.LineDistance = 5
        
        if FigureGrabModule.State.FigureGrabConnection then
            FigureGrabModule.State.FigureGrabConnection:Disconnect()
        end
        
        FigureGrabModule.State.FigureGrabConnection = FigureGrabModule.RunService.Heartbeat:Connect(function()
            if not FigureGrabModule.State.TargetCharacter or not MyCharacter then
                FigureGrabModule.State.FigureGrabEnabled = false
                if FigureGrabModule.State.FigureGrabConnection then
                    FigureGrabModule.State.FigureGrabConnection:Disconnect()
                end
                return
            end
            
            MyRoot = MyCharacter:FindFirstChild("HumanoidRootPart")
            if not MyRoot then return end
            
            holdCFrame = MyRoot.CFrame * CFrame.new(
                FigureGrabModule.Configuration.HoldPosition.X, 
                FigureGrabModule.Configuration.HoldPosition.Y, 
                FigureGrabModule.Configuration.HoldPosition.Z
            )
            
            TargetTorso.CFrame = holdCFrame * CFrame.Angles(
                math.rad(FigureGrabModule.Configuration.HoldRotation.X), 
                math.rad(FigureGrabModule.Configuration.HoldRotation.Y), 
                math.rad(FigureGrabModule.Configuration.HoldRotation.Z)
            )
            TargetTorso.Velocity = FigureGrabModule.State.VectorZero
            TargetTorso.RotVelocity = FigureGrabModule.State.VectorZero
            
            if FigureGrabModule.State.AnimationCopyEnabled then
                FigureGrabModule.CopyAnimationsFromLimbs()
            else
                for _, partName in pairs(BodyParts) do
                    part = FigureGrabModule.State.TargetCharacter:FindFirstChild(partName)
                    if part and part ~= TargetTorso then
                        if partName == "Left Arm" then
                            part.CFrame = TargetTorso.CFrame * CFrame.new(
                                FigureGrabModule.Configuration.LeftArmPosition.X, 
                                FigureGrabModule.Configuration.LeftArmPosition.Y, 
                                FigureGrabModule.Configuration.LeftArmPosition.Z
                            ) * CFrame.Angles(
                                math.rad(FigureGrabModule.Configuration.LeftArmRotation.X), 
                                math.rad(FigureGrabModule.Configuration.LeftArmRotation.Y), 
                                math.rad(FigureGrabModule.Configuration.LeftArmRotation.Z)
                            )
                            part.Velocity = FigureGrabModule.State.VectorZero
                            part.RotVelocity = FigureGrabModule.State.VectorZero
                        end
                        
                        if partName == "Right Arm" then
                            part.CFrame = TargetTorso.CFrame * CFrame.new(
                                FigureGrabModule.Configuration.RightArmPosition.X, 
                                FigureGrabModule.Configuration.RightArmPosition.Y, 
                                FigureGrabModule.Configuration.RightArmPosition.Z
                            ) * CFrame.Angles(
                                math.rad(FigureGrabModule.Configuration.RightArmRotation.X), 
                                math.rad(FigureGrabModule.Configuration.RightArmRotation.Y), 
                                math.rad(FigureGrabModule.Configuration.RightArmRotation.Z)
                            )
                            part.Velocity = FigureGrabModule.State.VectorZero
                            part.RotVelocity = FigureGrabModule.State.VectorZero
                        end
                        
                        if partName == "Left Leg" then
                            part.CFrame = TargetTorso.CFrame * CFrame.new(
                                FigureGrabModule.Configuration.LeftLegPosition.X, 
                                FigureGrabModule.Configuration.LeftLegPosition.Y, 
                                FigureGrabModule.Configuration.LeftLegPosition.Z
                            ) * CFrame.Angles(
                                math.rad(FigureGrabModule.Configuration.LeftLegRotation.X), 
                                math.rad(FigureGrabModule.Configuration.LeftLegRotation.Y), 
                                math.rad(FigureGrabModule.Configuration.LeftLegRotation.Z)
                            )
                            part.Velocity = FigureGrabModule.State.VectorZero
                            part.RotVelocity = FigureGrabModule.State.VectorZero
                        end
                        
                        if partName == "Right Leg" then
                            part.CFrame = TargetTorso.CFrame * CFrame.new(
                                FigureGrabModule.Configuration.RightLegPosition.X, 
                                FigureGrabModule.Configuration.RightLegPosition.Y, 
                                FigureGrabModule.Configuration.RightLegPosition.Z
                            ) * CFrame.Angles(
                                math.rad(FigureGrabModule.Configuration.RightLegRotation.X), 
                                math.rad(FigureGrabModule.Configuration.RightLegRotation.Y), 
                                math.rad(FigureGrabModule.Configuration.RightLegRotation.Z)
                            )
                            part.Velocity = FigureGrabModule.State.VectorZero
                            part.RotVelocity = FigureGrabModule.State.VectorZero
                        end
                        
                        if partName == "Head" then
                            part.CFrame = TargetTorso.CFrame * CFrame.new(
                                FigureGrabModule.Configuration.HeadPosition.X, 
                                FigureGrabModule.Configuration.HeadPosition.Y, 
                                FigureGrabModule.Configuration.HeadPosition.Z
                            ) * CFrame.Angles(
                                math.rad(FigureGrabModule.Configuration.HeadRotation.X), 
                                math.rad(FigureGrabModule.Configuration.HeadRotation.Y), 
                                math.rad(FigureGrabModule.Configuration.HeadRotation.Z)
                            )
                            part.Velocity = FigureGrabModule.State.VectorZero
                            part.RotVelocity = FigureGrabModule.State.VectorZero
                        end
                    end
                end
            end
            
            FigureGrabModule.SetNetworkOwner:FireServer(MouseTarget, holdCFrame)
        end)
        
        figureNotify("Figure Grab", "Figure Grab Activated", 3)
    else
        FigureGrabModule.State.FigureGrabEnabled = false
        FigureGrabModule.State.AnimationCopyEnabled = false
        if FigureGrabModule.State.FigureGrabConnection then
            FigureGrabModule.State.FigureGrabConnection:Disconnect()
            FigureGrabModule.State.FigureGrabConnection = nil
        end
        
        figureNotify("Figure Grab", "Figure Grab Deactivated", 3)
    end
end

function FigureGrabModule.SetAnimationCopy(enabled)
    FigureGrabModule.State.AnimationCopyEnabled = enabled
end

function FigureGrabModule.ResetPose()
    for section, values in pairs(FigureGrabModule.Configuration) do
        if typeof(values) == "table" then
            for axis, _ in pairs(values) do
                values[axis] = 0
            end
        end
    end
end

function FigureGrabModule.ApplyPreset(presetName)
    preset = FigureGrabModule.Presets[presetName]
    if preset then
        for section, values in pairs(preset) do
            if FigureGrabModule.Configuration[section] then
                for axis, value in pairs(values) do
                    FigureGrabModule.Configuration[section][axis] = value
                end
            end
        end
    end
end

function FigureGrabModule.UpdateConfig(section, axis, value)
    if FigureGrabModule.Configuration[section] and FigureGrabModule.Configuration[section][axis] ~= nil then
        FigureGrabModule.Configuration[section][axis] = value
    end
end

if not FigureTab or not GrabTab then
    return FigureGrabModule
end

local FunnyRigLoaded = false

FigureTab:CreateButton({
    Name = "Custom rig(reanimation + copy anims)",
    Callback = function()
        if FunnyRigLoaded then
            Rayfield:Notify({
                Title = "Already Active",
                Content = "idiot",
                Duration = 4
            })
            return
        end
        FunnyRigLoaded = true



        local plr = game.Players.LocalPlayer
        local ch = plr.Character or plr.CharacterAdded:Wait()
        local delayed = 0
        local childrens = {}

        local children = {
            "Right Arm", "Right Leg", "Left Arm", "Left Leg", "Torso"
        }

        local function rma()
            for _, acc in pairs(ch:GetDescendants()) do
                if acc:IsA("Accessory") then
                    acc:Destroy()
                end
            end
        end

        local function inv()
            for _, v in pairs(ch:GetDescendants()) do
                if v:IsA("BasePart") then
                    v.Transparency = 1
                    v.CanCollide = true
                    v.Anchored = false
                end
            end
        end

        local very_funne_rig = Instance.new("Model")
        very_funne_rig.Name = "very funne rig"
        very_funne_rig.Parent = workspace

        local function clone()
            for _, v in pairs(ch:GetDescendants()) do
                if v:IsA("BasePart") and table.find(children, v.Name) then
                    local c = Instance.new("Part")
                    c.Size = v.Size
                    c.Material = Enum.Material.SmoothPlastic
                    c.Transparency = 0
                    c.CanCollide = false
                    c.Anchored = true
                    c.Name = v.Name .. "_funnyrig"

                    if v.Name == "Left Arm" or v.Name == "Right Arm" then
                        c.Color = Color3.fromRGB(255, 255, 255)
                    elseif v.Name == "Torso" then
                        c.Color = Color3.fromRGB(75, 151, 75)
                    elseif v.Name == "Left Leg" or v.Name == "Right Leg" then
                        c.Color = Color3.fromRGB(110, 153, 202)
                    else
                        c.Color = v.Color
                    end

                    local rigo = Instance.new("Highlight")
                    rigo.Parent = c
                    rigo.FillTransparency = 1
                    rigo.OutlineTransparency = 0.5
                    rigo.OutlineColor = Color3.fromRGB(0, 0, 0)
                    rigo.DepthMode = Enum.HighlightDepthMode.Occluded

                    c.Parent = very_funne_rig
                    table.insert(childrens, {original = v, clone = c, highlight = rigo})
                end
            end
        end

        rma()
        inv()
        clone()

        if plr.Character:FindFirstChild("Head") and plr.Character.Head:FindFirstChild("face") then
            plr.Character.Head.face:Destroy()
        end

        task.spawn(function()
            local credits = Instance.new("Message")
            credits.Parent = workspace
            credits.Text = [[
Skibidi mango
Custom rig
Can reanimate
Just fun
]]
            task.wait(5)
            credits:Destroy()
        end)

        task.spawn(function()
            while FunnyRigLoaded do
                for _, p in pairs(childrens) do
                    if p.original and p.original.Parent then
                        p.clone.CFrame = p.original.CFrame
                    end
                end
                delayed = math.random(1,7) / 100
                task.wait(delayed)
            end
        end)

        Rayfield:Notify({
            Title = "Rig loaded",
            Content = "Can be used for reanimation",
            Duration = 5
        })

    end
})


    FigureTab:CreateKeybind({
        Name = "Toggle Figure Grab (Aim at target)",
        CurrentKeybind = "V",
        HoldToInteract = false,
        Flag = "FG_ToggleKeybind",
        Callback = function()
            FigureGrabModule.ToggleFigureGrab()
        end,
    })

    FigureTab:CreateToggle({
        Name = "Copy My Animations to Target",
        CurrentValue = false,
        Flag = "FG_AnimCopyToggle",
        Callback = function(Value)
            FigureGrabModule.SetAnimationCopy(Value)
            if Value then
                Rayfield:Notify({
                    Title = "Animation Copy",
                    Content = "Now copying your animations!",
                    Duration = 3
                })
            else
                Rayfield:Notify({
                    Title = "Animation Copy",
                    Content = "Manual control restored",
                    Duration = 3
                })
            end
        end,
    })

	GrabTab:CreateSection("Remove things")

local SelectedLimbs = {
    ["Right Arm"] = false,
    ["Left Arm"] = false,
    ["Right Leg"] = true,
    ["Left Leg"] = true,
}

GrabTab:CreateDropdown({
    Name = "Limbs to Remove",
    Options = {
        "Right Arm",
        "Left Arm",
        "Right Leg",
        "Left Leg",
    },
    CurrentOption = {
        "Right Leg",
        "Left Leg",
    },
    MultipleOptions = true,
    Callback = function(options)
        -- Reset all limbs to false
        for k in pairs(SelectedLimbs) do
            SelectedLimbs[k] = false
        end

        -- Enable selected limbs
        for _, limb in ipairs(options) do
            SelectedLimbs[limb] = true
        end
    end
})

local function deleteLimbs(plrModel)
    if not plrModel then return end

    for limbName, enabled in pairs(SelectedLimbs) do
        if enabled then
            local limb = plrModel:FindFirstChild(limbName)
            if limb then
                for _, obj in ipairs(limb:GetChildren()) do
                    if obj:IsA("Motor6D") or obj:IsA("Weld") or obj:IsA("WeldConstraint") then
                        obj:Destroy()
                    end
                end
                limb.CFrame = CFrame.new(0, -10000, 0)
            end
        end
    end
end

GrabTab:CreateKeybind({
    Name = 'Remove limbs  <font face="GothamBlack" color="rgb(7,255,0)">ragdoll grab advised</font>   <font face="GothamBlack" color="rgb(39,245,218)">for exp❤️😇</font>',
    CurrentKeybind = "T",
    HoldToInteract = false,
    Callback = function()
        local g = workspace:FindFirstChild("GrabParts")
        local gp = g and g:FindFirstChild("GrabPart")
        if not gp then return end

        local weld = gp:FindFirstChild("WeldConstraint")
        if not weld or not weld.Part1 then return end

        local grabbedPlayerModel = weld.Part1:FindFirstAncestorOfClass("Model")
        if not grabbedPlayerModel then return end

        local spawnCFrame = gp.CFrame

        deleteLimbs(grabbedPlayerModel)


        if SpawnToyRF then
            SpawnToyRF:InvokeServer(
                "FoodHamburger",
                spawnCFrame,
                Vector3.new(0, 0, 0)
            )
        end
    end,
})

local Players = game:GetService("Players")
local me = Players.LocalPlayer
local Mouse = me:GetMouse()
local rs = game:GetService("ReplicatedStorage")
local GrabEvent = rs.GrabEvents.SetNetworkOwner

function grab(prt) GrabEvent:FireServer(prt, prt.CFrame) end

function FWC(parent, name, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        local child = parent:FindFirstChild(name)
        if child then
            return child
        end
        task.wait(0.1)
    end
    return nil
end


GrabTab:CreateKeybind({
    Name = "Unweld / delete toys",
    CurrentKeybind = "H",
    HoldToInteract = false,
    Flag = "DeleteObjectBind",

    Callback = function()
        local obj = Mouse.Target
        if obj then
            if not obj:FindFirstAncestor("Map") and 
               not obj:FindFirstAncestor("Slots") and 
               not obj:FindFirstAncestor("Plots") then
                
                local character = me.Character
                if character then
                    local humanoidRootPart = FWC(character, "HumanoidRootPart")
                    if humanoidRootPart then
                        local distance = (obj.Position - humanoidRootPart.Position).Magnitude
                        if distance < 30 then
                            
                            if not obj.Parent:FindFirstChildOfClass("Humanoid") then
                                local startTime = tick()
                                while obj and obj.Parent and (not obj:FindFirstChild("PartOwner") or 
                                       (obj:FindFirstChild("PartOwner") and obj.PartOwner.Value ~= me.Name)) do
                                    
                                    if tick() - startTime > 10 then
                                        warn("Tm")
                                        break
                                    end
                                    
                                    spawn(function()
                                        pcall(function()
                                            grab(obj)
                                        end)
                                    end)
                                    
                                    task.wait(0.1)
                                end
                            else
                                local Head = FWC(obj.Parent, "Head")
                                local startTime = tick()
                                while obj and Head and Head.Parent and (not Head:FindFirstChild("PartOwner") or 
                                       (Head:FindFirstChild("PartOwner") and Head.PartOwner.Value ~= me.Name)) do
                                    
                                    if tick() - startTime > 10 then
                                        warn("tm")
                                        break
                                    end
                                    
                                    spawn(function()
                                        pcall(function()
                                            grab(obj)
                                        end)
                                    end)
                                    
                                    task.wait(0.1)
                                end
                            end
                            
                            if obj and obj.Parent then
                                pcall(function()
                                    obj.CFrame = CFrame.new(300, -97, 3000)
                                end)
                            end
                        else
                            Rayfield:Notify({
                                Title = "Error",
                                Content = "Too far away",
                                Duration = 2,
                                Image = 7743878056
                            })
                        end
                    end
                end
            else
                print("ee")
            end
        end
    end
})


    FigureTab:CreateSection("Hold (Torso) - Position")
    FigureTab:CreateSlider({
        Name = "Hold Position X",
        Range = {-50, 50},
        Increment = 0.1,
        Suffix = "units",
        CurrentValue = 0,
        Flag = "FG_HoldPosX",
        Callback = function(value)
            FigureGrabModule.UpdateConfig("HoldPosition", "X", value)
        end
    })

    FigureTab:CreateSlider({
        Name = "Hold Position Y",
        Range = {-50, 50},
        Increment = 0.1,
        Suffix = "units",
        CurrentValue = 0,
        Flag = "FG_HoldPosY",
        Callback = function(value)
            FigureGrabModule.UpdateConfig("HoldPosition", "Y", value)
        end
    })

    FigureTab:CreateSlider({
        Name = "Hold Position Z",
        Range = {-50, 50},
        Increment = 0.1,
        Suffix = "units",
        CurrentValue = -5,
        Flag = "FG_HoldPosZ",
        Callback = function(value)
            FigureGrabModule.UpdateConfig("HoldPosition", "Z", value)
        end
    })

    FigureTab:CreateSection("Hold (Torso) - Rotation")
    FigureTab:CreateSlider({
        Name = "Hold Rotation X",
        Range = {0, 360},
        Increment = 1,
        Suffix = "°",
        CurrentValue = 0,
        Flag = "FG_HoldRotX",
        Callback = function(value)
            FigureGrabModule.UpdateConfig("HoldRotation", "X", value)
        end
    })

    FigureTab:CreateSlider({
        Name = "Hold Rotation Y",
        Range = {0, 360},
        Increment = 1,
        Suffix = "°",
        CurrentValue = 0,
        Flag = "FG_HoldRotY",
        Callback = function(value)
            FigureGrabModule.UpdateConfig("HoldRotation", "Y", value)
        end
    })

    FigureTab:CreateSlider({
        Name = "Hold Rotation Z",
        Range = {0, 360},
        Increment = 1,
        Suffix = "°",
        CurrentValue = 0,
        Flag = "FG_HoldRotZ",
        Callback = function(value)
            FigureGrabModule.UpdateConfig("HoldRotation", "Z", value)
        end
    })

    FigureTab:CreateSection("Left Arm - Position")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Left Arm Position " .. axis,
            Range = {-50, 50},
            Increment = 0.1,
            Suffix = "units",
            CurrentValue = 0,
            Flag = "FG_LArmPos" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("LeftArmPosition", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Left Arm - Rotation")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Left Arm Rotation " .. axis,
            Range = {0, 360},
            Increment = 1,
            Suffix = "°",
            CurrentValue = 0,
            Flag = "FG_LArmRot" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("LeftArmRotation", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Right Arm - Position")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Right Arm Position " .. axis,
            Range = {-50, 50},
            Increment = 0.1,
            Suffix = "units",
            CurrentValue = 0,
            Flag = "FG_RArmPos" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("RightArmPosition", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Right Arm - Rotation")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Right Arm Rotation " .. axis,
            Range = {0, 360},
            Increment = 1,
            Suffix = "°",
            CurrentValue = 0,
            Flag = "FG_RArmRot" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("RightArmRotation", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Left Leg - Position")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Left Leg Position " .. axis,
            Range = {-50, 50},
            Increment = 0.1,
            Suffix = "units",
            CurrentValue = 0,
            Flag = "FG_LLegPos" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("LeftLegPosition", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Left Leg - Rotation")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Left Leg Rotation " .. axis,
            Range = {0, 360},
            Increment = 1,
            Suffix = "°",
            CurrentValue = 0,
            Flag = "FG_LLegRot" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("LeftLegRotation", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Right Leg - Position")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Right Leg Position " .. axis,
            Range = {-50, 50},
            Increment = 0.1,
            Suffix = "units",
            CurrentValue = 0,
            Flag = "FG_RLegPos" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("RightLegPosition", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Right Leg - Rotation")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Right Leg Rotation " .. axis,
            Range = {0, 360},
            Increment = 1,
            Suffix = "°",
            CurrentValue = 0,
            Flag = "FG_RLegRot" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("RightLegRotation", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Head - Position")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Head Position " .. axis,
            Range = {-25, 25 },
            Increment = 0.05,
            Suffix = "units",
            CurrentValue = 0,
            Flag = "FG_HeadPos" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("HeadPosition", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Head - Rotation")
    for _, axis in ipairs({"X", "Y", "Z"}) do
        FigureTab:CreateSlider({
            Name = "Head Rotation " .. axis,
            Range = {0, 360},
            Increment = 1,
            Suffix = "°",
            CurrentValue = 0,
            Flag = "FG_HeadRot" .. axis,
            Callback = function(value)
                FigureGrabModule.UpdateConfig("HeadRotation", axis, value)
            end
        })
    end

    FigureTab:CreateSection("Saves")
    FigureTab:CreateButton({
        Name = "Reset Pose",
        Callback = function()
            FigureGrabModule.ResetPose()
        end
    })

    FigureTab:CreateButton({
        Name = "Pose 1 Jesus",
        Callback = function()
            FigureGrabModule.ApplyPreset("Pose1")
        end
    })

    FigureTab:CreateButton({
        Name = "Pose 2 Dog",
        Callback = function()
            FigureGrabModule.ApplyPreset("Pose2")
        end
    })

    FigureTab:CreateButton({
        Name = "Pose 3 L",
        Callback = function()
            FigureGrabModule.ApplyPreset("Pose3")
        end
    })

    FigureTab:CreateButton({
        Name = "Pose 4 Head Hold",
        Callback = function()
            FigureGrabModule.ApplyPreset("Pose4")
        end
    })

    FigureTab:CreateButton({
        Name = "Pose 5 Handstand",
        Callback = function()
            FigureGrabModule.ApplyPreset("Pose5")
        end
    })

    FigureTab:CreateButton({
        Name = "Pose 6 Stand 1",
        Callback = function()
            FigureGrabModule.ApplyPreset("Pose6")
        end
    })

    FigureTab:CreateButton({
        Name = "Pose 7 T-Pose",
        Callback = function()
            FigureGrabModule.ApplyPreset("Pose7")
        end
    })

    FigureTab:CreateButton({
        Name = "Pose 8 Stand 2",
        Callback = function()
            FigureGrabModule.ApplyPreset("JojoStand")
        end
    })

	
