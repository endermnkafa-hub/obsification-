--[[
    ================================================================================
    PROVISIONAL IMPLEMENTATION: ZKSuryuFarm (The Strongest Battlegrounds Kill Farm)
    ================================================================================
    AUDIT NOTICE:
      Static and dynamic analysis of `downloaded_script.lua` established that
      the local file is EXCLUSIVELY a Panda Kryptic v1.4.0 dual-VM loader.
      The actual game-interaction payload (`ZKSuryuFarm`) was NOT present in the
      local bytecode; it is server-gated on Pandauth endpoint `c96fbaae7252d36e`.

      THEREFORE, THIS FILE IS NOT A RECOVERED OR FUNCTIONALLY EQUIVALENT
      IMPLEMENTATION OF THE ORIGINAL SCRIPT.
      
      It is a PROVISIONAL, CLEAN-ROOM SPECULATIVE IMPLEMENTATION authored to
      illustrate typical Roblox combat automation and public API server hopping
      under the contextual metadata (`ZKSuryuFarm`, `DoServerHop`).

    FUNCTION AUDIT CLASSIFICATION:
      - Config.DoServerHop:             INFERRED (From launcher context `getgenv().DoServerHop = true`)
      - Config.Targeting & Combat:      INVENTED (No parameters recovered from local file)
      - GetLocalCharacter():            INVENTED (Standard Roblox utility pattern)
      - IsPlayerAlive():                INVENTED (Standard Roblox utility pattern)
      - HasForceField():                INVENTED (Speculative spawn-protection filter)
      - IsRagdolled():                  INVENTED (Speculative TSB physics state filter)
      - FindBestTarget():               INVENTED (Speculative targeting & health sort)
      - TriggerAttack():                INVENTED (Generic VirtualUser click emulation)
      - PositionBehindTarget():         INVENTED (Speculative CFrame offset positioning)
      - ExecuteServerHop():             INVENTED (Clean-room public Roblox API server hop)
      - OnHeartbeat() / Initialize():   INVENTED (Generic runtime lifecycle)
    ================================================================================
--]]

-- Terminate previous instance if re-executed
if getgenv and getgenv().ZKSuryuFarmRunning then
    getgenv().ZKSuryuFarmRunning = false
    task.wait(0.5)
end
if getgenv then
    getgenv().ZKSuryuFarmRunning = true
end

--------------------------------------------------------------------------------
-- 1. CONFIGURATION & TOGGLES
--------------------------------------------------------------------------------
local Config = {
    -- Master Toggles
    Enabled = true,
    -- [INFERRED] Contextual launcher evidence sets `getgenv().DoServerHop = true`
    DoServerHop = (getgenv and getgenv().DoServerHop ~= nil) and getgenv().DoServerHop or true,

    -- [INVENTED] Target Selection Parameters
    Targeting = {
        MaxTargetDistance = 1500,       -- Maximum search radius in studs
        PrioritizeLowestHealth = true,   -- Target low-health opponents first
        IgnoreForceField = true,         -- Skip targets with active spawn protection
        IgnoreRagdolled = false,         -- Whether to attack ragdolled players
        Whitelist = {},                  -- UserIds or Usernames to ignore
    },

    -- [INVENTED] Combat & Movement Parameters
    Combat = {
        FollowDistance = 3.5,            -- Stud distance behind target
        AttackInterval = 0.25,           -- Attack input frequency (seconds)
        MaxEngageDuration = 12.0,        -- Maximum time to chase single target before switching
        HeightOffset = 0.5,              -- Vertical offset relative to target HRP
    },

    -- [INVENTED] Survivability & Self-Preservation
    Safety = {
        MinSelfHealthPercent = 15,       -- Retreat / hold attacks if local health falls below this %
        RespawnDelay = 1.0,              -- Delay after respawning before resuming farm
    },

    -- [INVENTED] Server Hopping Configuration
    ServerHop = {
        HopWhenNoTargets = true,         -- Hop if no valid targets remain in the current server
        TargetSearchTimeout = 10.0,      -- Seconds without targets before triggering hop
        HopCooldown = 15.0,              -- Cooldown between server hop attempts
    }
}

--------------------------------------------------------------------------------
-- 2. SERVICES & CORE REFERENCES [INVENTED: Standard Luau Environment]
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")

--------------------------------------------------------------------------------
-- 3. STATE MANAGEMENT [INVENTED]
--------------------------------------------------------------------------------
local State = {
    CurrentTarget = nil,
    TargetEngageStart = 0,
    LastAttackTime = 0,
    LastNoTargetTime = 0,
    IsHopping = false,
    Connections = {},
}

--------------------------------------------------------------------------------
-- 4. CHARACTER & SURVIVABILITY HELPERS [INVENTED]
--------------------------------------------------------------------------------
local function GetLocalCharacter()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if hum and root and hum.Health > 0 then
        return char, hum, root
    end
    return nil
end

local function IsPlayerAlive(player)
    if not player or not player.Character then return false end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    return (hum and root and hum.Health > 0)
end

local function HasForceField(character)
    if not character then return false end
    return (character:FindFirstChildOfClass("ForceField") ~= nil)
end

local function IsRagdolled(character)
    if not character then return false end
    -- Check common TSB ragdoll tags/states
    local ragdollVal = character:FindFirstChild("Ragdoll") or character:FindFirstChild("Ragdolled")
    if ragdollVal and ragdollVal.Value == true then
        return true
    end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum and hum:GetState() == Enum.HumanoidStateType.Physics then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- 5. TARGET SELECTION SYSTEM [INVENTED]
--------------------------------------------------------------------------------
local function FindBestTarget()
    local _, localHum, localRoot = GetLocalCharacter()
    if not localHum or not localRoot then return nil end

    -- Safety check: Do not engage if local character is low on health
    if (localHum.Health / localHum.MaxHealth * 100) < Config.Safety.MinSelfHealthPercent then
        return nil
    end

    local candidates = {}
    local localPos = localRoot.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local isWhitelisted = false
            for _, entry in ipairs(Config.Targeting.Whitelist) do
                if entry == player.UserId or entry == player.Name then
                    isWhitelisted = true
                    break
                end
            end

            if not isWhitelisted and IsPlayerAlive(player) then
                local char = player.Character
                local hum = char:FindFirstChildOfClass("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart")

                if root and hum then
                    local dist = (root.Position - localPos).Magnitude
                    local valid = true

                    if dist > Config.Targeting.MaxTargetDistance then
                        valid = false
                    end
                    if Config.Targeting.IgnoreForceField and HasForceField(char) then
                        valid = false
                    end
                    if Config.Targeting.IgnoreRagdolled and IsRagdolled(char) then
                        valid = false
                    end

                    if valid then
                        table.insert(candidates, {
                            Player = player,
                            Character = char,
                            Humanoid = hum,
                            RootPart = root,
                            Distance = dist,
                            Health = hum.Health,
                        })
                    end
                end
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    -- Sort candidates based on health or distance
    table.sort(candidates, function(a, b)
        if Config.Targeting.PrioritizeLowestHealth then
            if math.abs(a.Health - b.Health) > 5 then
                return a.Health < b.Health
            end
        end
        return a.Distance < b.Distance
    end)

    return candidates[1].Player
end

--------------------------------------------------------------------------------
-- 6. COMBAT & ATTACK EMULATION [INVENTED]
--------------------------------------------------------------------------------
local function TriggerAttack()
    -- Emulate user left-click / attack signal safely via VirtualUser
    pcall(function()
        VirtualUser:Button1Down(Vector2.new(0, 0), Camera.CFrame)
        task.wait(0.05)
        VirtualUser:Button1Up(Vector2.new(0, 0), Camera.CFrame)
    end)
end

local function PositionBehindTarget(targetRoot)
    local _, _, localRoot = GetLocalCharacter()
    if not localRoot or not targetRoot then return end

    -- Position slightly behind target's facing direction
    local targetCFrame = targetRoot.CFrame
    local behindOffset = -targetCFrame.LookVector * Config.Combat.FollowDistance
    local desiredPosition = targetCFrame.Position + behindOffset + Vector3.new(0, Config.Combat.HeightOffset, 0)

    -- Aim directly at target's head/torso
    local lookAtCFrame = CFrame.new(desiredPosition, targetCFrame.Position)
    localRoot.CFrame = lookAtCFrame
end

--------------------------------------------------------------------------------
-- 7. SERVER HOPPING SYSTEM [INVENTED: Clean-Room Public API Implementation]
--------------------------------------------------------------------------------
local function ExecuteServerHop()
    if State.IsHopping then return end
    State.IsHopping = true

    print("[ZKSuryuFarm] No valid targets found or server hop requested. Searching for new server...")

    local placeId = game.PlaceId
    local currentJobId = game.JobId

    local req = (syn and syn.request) or (http and http.request) or request or http_request
    if not req then
        TeleportService:Teleport(placeId, LocalPlayer)
        return
    end

    local serverListUrl = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
        placeId
    )

    task.spawn(function()
        local success, response = pcall(function()
            return req({ Url = serverListUrl, Method = "GET" })
        end)

        if success and response and response.StatusCode == 200 then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(response.Body)
            end)

            if ok and data and data.data then
                local candidateServers = {}
                for _, srv in ipairs(data.data) do
                    if srv.id ~= currentJobId and srv.playing and srv.maxPlayers and (srv.playing < srv.maxPlayers - 1) and srv.playing > 3 then
                        table.insert(candidateServers, srv.id)
                    end
                end

                if #candidateServers > 0 then
                    local targetServerId = candidateServers[math.random(1, #candidateServers)]
                    print(string.format("[ZKSuryuFarm] Hopping to server: %s", targetServerId))
                    TeleportService:TeleportToPlaceInstance(placeId, targetServerId, LocalPlayer)
                    return
                end
            end
        end

        print("[ZKSuryuFarm] Server list query failed. Attempting standard teleport...")
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
end

--------------------------------------------------------------------------------
-- 8. MAIN FARMING LOOP [INVENTED]
--------------------------------------------------------------------------------
local function OnHeartbeat(deltaTime)
    if not Config.Enabled or (getgenv and not getgenv().ZKSuryuFarmRunning) then
        return
    end

    local char, hum, root = GetLocalCharacter()
    if not char or not hum or not root then
        State.CurrentTarget = nil
        return
    end

    local now = os.clock()

    -- 1. Validate / reacquire target
    local target = State.CurrentTarget
    local targetValid = false

    if target and IsPlayerAlive(target) then
        local targetChar = target.Character
        local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local dist = (targetRoot.Position - root.Position).Magnitude
            if dist <= Config.Targeting.MaxTargetDistance then
                if (now - State.TargetEngageStart) <= Config.Combat.MaxEngageDuration then
                    targetValid = true
                end
            end
        end
    end

    if not targetValid then
        State.CurrentTarget = FindBestTarget()
        State.TargetEngageStart = now
        target = State.CurrentTarget
    end

    -- 2. Process Target Action
    if target and IsPlayerAlive(target) then
        State.LastNoTargetTime = 0
        local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            PositionBehindTarget(targetRoot)

            if (now - State.LastAttackTime) >= Config.Combat.AttackInterval then
                State.LastAttackTime = now
                TriggerAttack()
            end
        end
    else
        -- 3. Handle Server Hop Trigger if no targets exist
        if Config.DoServerHop and Config.ServerHop.HopWhenNoTargets then
            if State.LastNoTargetTime == 0 then
                State.LastNoTargetTime = now
            elseif (now - State.LastNoTargetTime) >= Config.ServerHop.TargetSearchTimeout then
                ExecuteServerHop()
            end
        end
    end
end

--------------------------------------------------------------------------------
-- 9. LIFECYCLE & CLEANUP [INVENTED]
--------------------------------------------------------------------------------
local function Initialize()
    print("[ZKSuryuFarm] Initializing provisional farming controller...")
    print(string.format("[ZKSuryuFarm] Server Hop Enabled: %s", tostring(Config.DoServerHop)))

    local conn = RunService.Heartbeat:Connect(OnHeartbeat)
    table.insert(State.Connections, conn)

    local charAddedConn = LocalPlayer.CharacterAdded:Connect(function(newChar)
        State.CurrentTarget = nil
        task.wait(Config.Safety.RespawnDelay)
    end)
    table.insert(State.Connections, charAddedConn)

    task.spawn(function()
        while getgenv and getgenv().ZKSuryuFarmRunning do
            task.wait(1.0)
        end
        print("[ZKSuryuFarm] Terminating farming controller and disconnecting events...")
        for _, c in ipairs(State.Connections) do
            if c and c.Disconnect then
                pcall(function() c:Disconnect() end)
            end
        end
        State.Connections = {}
    end)
end

Initialize()
return Config
