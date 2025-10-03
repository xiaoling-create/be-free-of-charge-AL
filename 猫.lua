game:GetService("VirtualInputManager"):SendKeyEvent(true, "W", false, game) wait(1) game:GetService("VirtualInputManager"):SendKeyEvent(false, "W", false, game) wait(2)
-- 服务声明
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInterfaceService")
-- HTTP客户端兼容性处理
local httpRequest = (syn and syn.request) or (http and http.request) or http_request
    or (fluxus and fluxus.request) or request
-- 本地玩家引用
local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
-- 配置参数
local CONFIG = {
    SERVER_STAY_TIME = 5,              -- 单服务器停留时间(秒)
    SERVER_FETCH_RETRY_DELAY = 10,    -- 服务器列表 获取失败重试间隔(秒)
    ITEM_SCAN_TIMEOUT = 10,           -- 物品扫描超 时(秒)
    TELEPORT_COOLDOWN = 5,            -- 传送冷却时 间(秒)
    MAX_PICKUP_ATTEMPTS = 5,          -- 最大拾取次 数
    MAX_SERVER_SCANS = 5,             -- 最大服务器 扫描数量
    FORBIDDEN_ZONE = {
        center = Vector3.new(352.884155, 13.0287256, -1353.05396)
        radius = 80
    }
    MIN_PLAYERS = 5,                  -- 最低玩家数 量要求
    IDEAL_PLAYER_RANGE = {5, 35},     -- 最理想玩家 数量范围
    NOTIFICATION_DURATION = 5
    SCRIPT_TIMEOUT = 120
}
-- 目标物品列表
local TARGET_ITEMS = {
    "Money Printer", "Blue Candy Cane", "Bunny Balloon", "Ghost Balloon", "Clover Balloon"
    "Bat Balloon", "Gold Clover Balloon", "Golden Rose", "Black Rose", "Heart Balloon"
    "Diamond Ring", "Diamond", "Void Gem", "Dark Matter Gem", "Rollie"
}
-- 状态变量
local servers = {}
local scriptStartTime = os.time()

--[[ 显示通知 ]]
local function showNotification(text)
    StarterGui:SetCore("SendNotification", {
        Title = "自动脚本提示"
        Text = text
        Duration = CONFIG.NOTIFICATION_DURATION
    })


--[[ 屏幕中央打字动画文本 ]]
local function createTypingText()
    -- 创建屏幕GUI容器
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "OhioScriptText"
    screenGui.Parent = StarterGui
    -- 创建文本标签（居中显示）
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "WelcomeText"
    textLabel.Size = UDim2.new(0.8, 0, 0.1, 0)
    textLabel.Position = UDim2.new(0.1, 0, 0.45, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextSize = 32
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.Text = ""
    textLabel.Parent = screenGui
    -- 打字动画逻辑
    local targetText = "猪咪人牛逼\n小宝贝傻逼"
    local currentText = ""
    local typingSpeed = 0.1 -- 每个字符间隔时间（秒 ）
    for i = 1, #targetText do
        currentText = currentText .. string.sub(targetText, i, i)
        textLabel.Text = currentText
        task.wait(typingSpeed)
    end
    -- 显示5秒后自动移除
    task.wait(5)
    screenGui:Destroy()


--[[ 检查脚本超时 ]]
local function checkTimeout()
    return (os.time() - scriptStartTime) >= CONFIG.SCRIPT_TIMEOUT
end

--[[ 带重试的获取服务器列表 ]]
local function fetchServerListWithRetry()
    local retryCount = 0
    while true do
        local success, result = pcall(function()
            local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
            local response = httpRequest({Url = url, Method = "GET", Timeout = 10})
            if not response or response.StatusCode ~= 200 then error("HTTP请求失败") end
            local decoded = HttpService:JSONDecode(response.Body)
            if not decoded or not decoded.data then error("无效响应") end
            -- 过滤服务器
            local filtered = {}
            local currentJobId = game.JobId
            for _, server in ipairs(decoded.data) do
                if server.playing > CONFIG.MIN_PLAYERS and server.playing < server.maxPlayers and server.id ~= currentJobId then
                    table.insert(filtered, server)
                end
            end
            if #filtered == 0 then error("无可用服务器") end
            -- 按玩家数排序
            table.sort(filtered, function(a, b) return a.playing < b.playing end)
            return filtered
        end)
        if success then return result end
        retryCount += 1
        warn("获取服务器失败(第"..retryCount.."次):", result)
        -- 等待重试
        local waitStart = os.time()
        while os.time() - waitStart < CONFIG.SERVER_FETCH_RETRY_DELAY do task.wait(0.5) end
    end
end

--[[ 智能选择最佳服务器 ]]
local function selectOptimalServer()
    if #servers == 0 then return nil end
    -- 优先选理想人数服务器
    for _, server in ipairs(servers) do
        if server.playing >= CONFIG.IDEAL_PLAYER_RANGE[1] and server.playing <= CONFIG.IDEAL_PLAYER_RANGE[2] then
            return server.id
        end
    end
    -- 选其他符合要求的服务器
    for _, server in ipairs(servers) do
        if server.playing > CONFIG.MIN_PLAYERS then return server.id end
    end
    return nil
end

--[[ 传送至服务器 ]]
local function teleportToServer(serverId)
    local success = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, localPlayer)
    end)
    return success
end

--[[ 传送角色 ]]
local function teleportTo(position)
    if humanoidRootPart then
        humanoidRootPart.CFrame = position
        task.wait(0.2)
    end
end

--[[ 扫描目标物品 ]]
local function scanForTargetItems()
    local foundItems = {}
    for _, itemFolder in pairs(workspace.Game.Entities.ItemPickup:GetChildren()) do
        for _, item in pairs(itemFolder:GetChildren()) do
            if not (item:IsA("MeshPart") or item:IsA("Part")) then continue end
            -- 禁区检查
            local distance = (item.Position - CONFIG.FORBIDDEN_ZONE.center).Magnitude
            if distance <= CONFIG.FORBIDDEN_ZONE.radius then continue end
            -- 匹配目标物品
            for _, child in pairs(item:GetChildren()) do
                if child:IsA("ProximityPrompt") then
                    for _, targetName in pairs(TARGET_ITEMS) do
                        if child.ObjectText == targetName then
                            table.insert(foundItems, {item = item, prompt = child, name = targetName})
                        end
                    end
                end
            end


    return foundItems


--[[ 自动拾取物品 ]]
local function autoPickItems()
    local pickupCount = 0
    local startTime = os.time()
    while task.wait(0.1) do
        -- 超时/次数限制检查
        if checkTimeout() or (os.time() - startTime) >= CONFIG.SERVER_STAY_TIME or pickupCount >= CONFIG.MAX_PICKUP_ATTEMPTS then
            return false
        end
        -- 扫描物品
        local items = scanForTargetItems()
        if #items == 0 then return true end
        -- 拾取物品（带通知）
        for _, data in ipairs(items) do
            if pickupCount >= CONFIG.MAX_PICKUP_ATTEMPTS then break end
            -- 检测到物品通知
            showNotification(string.format("检测到%s，开始抢夺", data.name))
            -- 执行拾取
            data.prompt.RequiresLineOfSight = false
            data.prompt.HoldDuration = 0
            teleportTo(data.item.CFrame * CFrame.new(0, 2, 0))
            fireproximityprompt(data.prompt)
            pickupCount += 1
            task.wait(0.5)

        -- 拾取完成通知
        showNotification("拾取完成准备换服")
        return false

    return false


--[[ 主循环 ]]
local function main()
    -- 角色更新监听
    localPlayer.CharacterAdded:Connect(function(newCharacter)
        character = newCharacter
        humanoid = newCharacter:WaitForChild("Humanoid")
        humanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart")
    end)
    -- 主流程
    while true do
        local success, err = pcall(function()
            -- 获取服务器列表
            servers = fetchServerListWithRetry()
            -- 服务器人数通知
            showNotification(string.format("本地服务器人数：%d", #servers > 0 and servers[1].playing or 0))
            -- 物品拾取
            local noItemFound = autoPickItems()
            -- 无物品通知
            if noItemFound then showNotification("未找到可用物品准备换服") end
            -- 切换服务器
            local targetServer = selectOptimalServer()
            if targetServer and teleportToServer(targetServer) then
                task.wait(CONFIG.TELEPORT_COOLDOWN)
            else
                task.wait(CONFIG.SERVER_FETCH_RETRY_DELAY)
            end
        end)
        -- 错误处理
        if not success then
            warn("主循环错误:", err)
            task.wait(CONFIG.SERVER_FETCH_RETRY_DELAY)
        end
    end
end

-- 启动脚本（执行打字动画+主逻辑）
createTypingText()
showNotification("脚本启动，开始循环检测物品")
main()

-- 销冠：胖猫