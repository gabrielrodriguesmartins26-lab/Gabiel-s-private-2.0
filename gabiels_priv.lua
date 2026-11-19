-- gabiel's priv | Slap Battles | Delta
local Config = {
    Title = "gabiel's priv",
    Icon = nil,              -- "rbxassetid://ID" da sua imagem
    OwnerUserIds = {},       -- vazio = o primeiro a rodar vira owner (arquivo local)
    OwnerFile = "gabiels_priv_owner.txt",
    LearnSeconds = 8,
    ExternalScripts = {
        -- emanjay06: URL raw montada pelo padrao do GitHub, NAO aberta por mim: confirme no botao Raw
        { name = "emanjay06 (7 remotes, Kavo UI)", url = "https://raw.githubusercontent.com/emanjay06/ROBLOX-SCRIPTS/main/Slap%20Battles%20script%20(to%20get%20bob%20glove).lua" },
        -- URLs abaixo vieram de voce; os dois carregam o modulo CleanClientAntiCheat.luau, que eu NAO li
        { name = "FemboyHub (Slap Battles)", url = "https://raw.githubusercontent.com/nerna-coder/FemboyHub/refs/heads/main/slap%20battles.lua" },
        { name = "Nexer Ultimate Badge Utility", url = "https://raw.githubusercontent.com/NewNexer/NexerHub/refs/heads/main/SB/UBH/Latest.lua" },
    },
}

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local BadgeService = game:GetService("BadgeService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local LP = Players.LocalPlayer

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local function notify(c) WindUI:Notify({ Title = Config.Title, Content = c, Duration = 5 }) end
local function hum() local c = LP.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function root() local c = LP.Character return c and c:FindFirstChild("HumanoidRootPart") end

-- ===== OWNER =====
local function resolveOwner()
    for _, id in ipairs(Config.OwnerUserIds) do
        if id == LP.UserId then return true end
    end
    if #Config.OwnerUserIds > 0 then return false end
    if not (isfile and readfile and writefile) then return false end
    local ok, saved = pcall(function()
        if isfile(Config.OwnerFile) then return readfile(Config.OwnerFile) end
    end)
    if ok and saved then return tonumber(saved) == LP.UserId end
    return pcall(writefile, Config.OwnerFile, tostring(LP.UserId))
end
local isOwner = resolveOwner()

-- ===== infraestrutura =====
local conns, flags = {}, {}
local function setConn(key, signal, fn)
    if conns[key] then conns[key]:Disconnect() conns[key] = nil end
    if signal then conns[key] = signal:Connect(fn) end
end
local function loop(key, interval, fn)
    flags[key] = true
    task.spawn(function()
        while flags[key] do
            local ok, err = pcall(fn)
            if not ok then warn("[" .. key .. "]", err) end
            task.wait(interval)
        end
    end)
end

-- ===== espiao de remotes (aprendizado) =====
local rec = nil
local Learned = {}   -- Learned.glove / hitman / slap / slapple = {remote, method, args}
local canSpy = hookmetamethod and newcclosure and checkcaller and getnamecallmethod
if canSpy then
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if rec and not checkcaller() then
            local m = getnamecallmethod()
            if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance"
                and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
                local e = rec.map[self]
                if not e then
                    e = { remote = self, method = m, n = 0 }
                    rec.map[self] = e
                    rec.order[#rec.order + 1] = e
                end
                e.n += 1
                e.args = table.pack(...)
            end
        end
        return old(self, ...)
    end))
end

local function learn(kind, onDone)
    if not canSpy then notify("Seu executor nao tem hookmetamethod/newcclosure.") return end
    if rec then notify("Ja estou aprendendo outra coisa.") return end
    rec = { map = {}, order = {} }
    notify(("Aprendendo '%s': faca a acao a mao agora (%ds)."):format(kind, Config.LearnSeconds))
    task.delay(Config.LearnSeconds, function()
        local r = rec
        rec = nil
        local pick
        for _, e in ipairs(r.order) do
            print(("[learn %s] %s x%d"):format(kind, e.remote:GetFullName(), e.n))
            if e.n <= 3 then pick = e end   -- remotes de spam (movimento etc.) sao ignorados
        end
        if not pick then notify("Nada capturado. Repita a acao durante a janela.") return end
        Learned[kind] = pick
        notify(("Capturado: %s (veja o console para os outros)"):format(pick.remote.Name))
        if onDone then onDone(pick) end
    end)
end

local function replay(entry, mutate)
    local args = table.pack(table.unpack(entry.args, 1, entry.args.n))
    if mutate then mutate(args) end
    if entry.method == "FireServer" then
        entry.remote:FireServer(table.unpack(args, 1, args.n))
    else
        entry.remote:InvokeServer(table.unpack(args, 1, args.n))
    end
end

-- ===== medicao: nomes de luvas =====
local GloveNames = {}
local function scanGloveNames()
    local bestParent, bestCount = nil, 0
    local function consider(p)
        local n = 0
        for _, c in ipairs(p:GetChildren()) do if c:IsA("Tool") then n += 1 end end
        if n > bestCount then bestParent, bestCount = p, n end
    end
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("Folder") or d:IsA("Model") or d:IsA("Configuration") then consider(d) end
    end
    consider(RS)
    GloveNames = {}
    if bestParent and bestCount >= 5 then
        for _, c in ipairs(bestParent:GetChildren()) do
            if c:IsA("Tool") then GloveNames[#GloveNames + 1] = c.Name end
        end
        table.sort(GloveNames)
        notify(("%d luvas em %s"):format(#GloveNames, bestParent:GetFullName()))
    else
        notify("Nao achei pasta de luvas em ReplicatedStorage (ficam so no servidor?).")
    end
    return #GloveNames
end

-- ===== medicao: badges =====
local BadgeTargets = {}   -- {badge, glove}
local function scanBadges()
    if #GloveNames == 0 then scanGloveNames() end
    local badges, cursor = {}, nil
    for _ = 1, 10 do
        local url = "https://badges.roblox.com/v1/universes/" .. game.GameId .. "/badges?limit=100&sortOrder=Asc"
            .. (cursor and ("&cursor=" .. cursor) or "")
        local ok, body = pcall(game.HttpGet, game, url)
        if not ok then notify("Falha ao buscar badges (HttpGet bloqueado?).") break end
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, body)
        if not (ok2 and type(data) == "table" and data.data) then break end
        for _, b in ipairs(data.data) do badges[#badges + 1] = { id = b.id, name = b.name } end
        cursor = data.nextPageCursor
        if not cursor then break end
    end
    BadgeTargets = {}
    for _, b in ipairs(badges) do
        local okOwn, owned = pcall(BadgeService.UserHasBadgeAsync, BadgeService, LP.UserId, b.id)
        b.owned = okOwn and owned or false
        task.wait(0.12)
        if not b.owned then
            local lname = b.name:lower()
            for _, g in ipairs(GloveNames) do
                if lname:find(g:lower(), 1, true) then
                    BadgeTargets[#BadgeTargets + 1] = { badge = b, glove = g }
                    break
                end
            end
        end
    end
    print(("[badges] total=%d, faltando com luva associada=%d"):format(#badges, #BadgeTargets))
    for _, t in ipairs(BadgeTargets) do print("  falta:", t.badge.id, t.badge.name, "->", t.glove) end
    notify(("%d badges no jogo, %d faltando com luva associada (console)"):format(#badges, #BadgeTargets))
end

local function trigger(inst)
    local r = root()
    if not r then return false end
    local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
        or (inst.Parent and inst.Parent:IsA("BasePart") and inst.Parent)
    if part then r.CFrame = part.CFrame * CFrame.new(0, 3, 0) task.wait(0.2) end
    if inst:IsA("ProximityPrompt") and fireproximityprompt then fireproximityprompt(inst) return true end
    if inst:IsA("ClickDetector") and fireclickdetector then fireclickdetector(inst) return true end
    if part and firetouchinterest then
        firetouchinterest(r, part, 0) task.wait() firetouchinterest(r, part, 1) return true
    end
    return false
end

local function nameMatches(inst, needle)
    local n = needle:lower()
    local cur, depth = inst, 0
    while cur and cur ~= workspace and depth < 3 do
        if cur.Name:lower():find(n, 1, true) then return true end
        cur, depth = cur.Parent, depth + 1
    end
    return false
end

local function findTriggers(needle)
    local list = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if (d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("TouchTransmitter"))
            and nameMatches(d, needle) then
            list[#list + 1] = d:IsA("TouchTransmitter") and d.Parent or d
        end
    end
    return list
end

-- ===== janela =====
local Window = WindUI:CreateWindow({
    Title = Config.Title, Icon = Config.Icon, Author = "KS NEXUS",
    Folder = "gabiels_priv", Size = UDim2.fromOffset(520, 420),
})

-- LUVAS
local Gloves = Window:Tab({ Title = "Luvas" })
local gloveSlot  -- indice do argumento que carrega o nome da luva

Gloves:Button({ Title = "1) Escanear luvas e badges", Callback = function() task.spawn(scanBadges) end })
Gloves:Button({ Title = "2) Aprender equipar luva (equipe uma a mao)", Callback = function()
    if #GloveNames == 0 then scanGloveNames() end
    learn("glove", function(e)
        local known = {}
        for _, n in ipairs(GloveNames) do known[n:lower()] = true end
        gloveSlot = nil
        for i = 1, e.args.n do
            local v = e.args[i]
            if type(v) == "string" and known[v:lower()] then gloveSlot = i break end
        end
        if not gloveSlot then
            for i = 1, e.args.n do if type(e.args[i]) == "string" then gloveSlot = i break end end
        end
        notify(gloveSlot and ("Nome da luva e o argumento #" .. gloveSlot)
            or "Nenhum argumento string: o remote nao leva o nome da luva.")
    end)
end })

Gloves:Toggle({ Title = "Auto Glove (percorre as luvas escaneadas)", Value = false, Callback = function(on)
    if not on then flags.autoglove = false return end
    if not (Learned.glove and gloveSlot and #GloveNames > 0) then
        notify("Bloqueado: rode 'Escanear' e 'Aprender equipar luva' antes.")
        return
    end
    loop("autoglove", 1, function()
        for _, name in ipairs(GloveNames) do
            if not flags.autoglove then return end
            replay(Learned.glove, function(a) a[gloveSlot] = name end)
            task.wait(0.5)
        end
    end)
end })

Gloves:Toggle({ Title = "Auto Badge Gloves (heuristico)", Value = false, Callback = function(on)
    if not on then flags.badgeglove = false return end
    if #BadgeTargets == 0 then
        notify("Sem alvos: rode 'Escanear luvas e badges' primeiro.")
        return
    end
    loop("badgeglove", 3, function()
        for _, t in ipairs(BadgeTargets) do
            if not flags.badgeglove then return end
            local okOwn, owned = pcall(BadgeService.UserHasBadgeAsync, BadgeService, LP.UserId, t.badge.id)
            if okOwn and owned then
                t.done = true
            elseif not t.done then
                local trg = findTriggers(t.glove)
                if #trg == 0 then
                    print("[badgeglove] nenhum gatilho no mapa para", t.glove)
                else
                    for _, inst in ipairs(trg) do
                        if not flags.badgeglove then return end
                        trigger(inst)
                        task.wait(0.5)
                    end
                end
            end
        end
    end)
end })

-- QUESTS
local Quests = Window:Tab({ Title = "Quests" })
Quests:Button({ Title = "Aprender remote do Hitman (fale com ele a mao)", Callback = function()
    learn("hitman")
end })
Quests:Toggle({ Title = "Auto Quest Hitman", Value = false, Callback = function(on)
    if not on then flags.hitman = false return end
    loop("hitman", 3, function()
        local done = false
        for _, inst in ipairs(findTriggers("hitman")) do
            if not flags.hitman then return end
            if trigger(inst) then done = true end
            task.wait(0.4)
        end
        if Learned.hitman then replay(Learned.hitman) done = true end
        if not done then
            print("[hitman] nenhum NPC/prompt achado e nenhum remote aprendido")
            flags.hitman = false
            notify("Hitman nao encontrado. Aprenda o remote falando com ele a mao.")
        end
    end)
end })

Quests:Button({ Title = "Listar remotes suspeitos (console)", Callback = function()
    local kw = { "glove", "equip", "hitman", "quest", "badge", "reward" }
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            local l = d.Name:lower()
            for _, k in ipairs(kw) do
                if l:find(k, 1, true) then print("[remote?]", d:GetFullName()) break end
            end
        end
    end
    notify("Candidatos impressos no console.")
end })

-- ===== OBTIVEIS =====
local Catalog, CatalogByLabel, selectedLabel = {}, {}, nil

local function hasTool(name)
    local n = name:lower()
    for _, holder in ipairs({ LP.Backpack, LP.Character }) do
        if holder then
            for _, t in ipairs(holder:GetChildren()) do
                if t:IsA("Tool") and t.Name:lower() == n then return true end
            end
        end
    end
    return false
end

local function buildCatalog()
    if #GloveNames == 0 then scanGloveNames() end
    local missing = {}
    for _, t in ipairs(BadgeTargets) do missing[t.glove] = t.badge end

    -- uma unica passada pelo workspace; cada gatilho guarda o texto dos 3 niveis de nome
    local trig, count = {}, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("TouchTransmitter") then
            local text, cur, depth = "", d, 0
            while cur and cur ~= workspace and depth < 3 do
                text ..= cur.Name:lower() .. "|"
                cur, depth = cur.Parent, depth + 1
            end
            trig[#trig + 1] = { inst = d:IsA("TouchTransmitter") and d.Parent or d, text = text }
        end
        count += 1
        if count % 2000 == 0 then task.wait() end
    end

    Catalog, CatalogByLabel = {}, {}
    for _, g in ipairs(GloveNames) do
        local via, insts, needle = {}, {}, g:lower()
        for _, t in ipairs(trig) do
            if t.text:find(needle, 1, true) then insts[#insts + 1] = t.inst end
        end
        if #insts > 0 then via[#via + 1] = "gatilho no mapa (" .. #insts .. ")" end
        if missing[g] then via[#via + 1] = "badge: " .. missing[g].name end
        if Learned.glove and gloveSlot then via[#via + 1] = "remote (sem garantia)" end
        if #via > 0 then
            local e = { name = g, insts = insts, via = via, label = g .. "  [" .. table.concat(via, ", ") .. "]" }
            Catalog[#Catalog + 1] = e
            CatalogByLabel[e.label] = e
        end
    end
    print(("[obtiveis] %d luvas com pelo menos um caminho"):format(#Catalog))
    for _, e in ipairs(Catalog) do print("  ", e.label) end
end

local function grabGlove(e)
    if hasTool(e.name) then return true end
    if #e.insts > 0 then
        for _, inst in ipairs(e.insts) do
            trigger(inst)
            task.wait(0.6)
            if hasTool(e.name) then return true end
        end
    end
    if Learned.glove and gloveSlot then
        replay(Learned.glove, function(a) a[gloveSlot] = e.name end)
        task.wait(0.8)
    end
    return hasTool(e.name)
end

local Obt = Window:Tab({ Title = "Obtiveis" })
local obtDropdown = Obt:Dropdown({
    Title = "Luvas que o script consegue tentar pegar",
    Values = { "(clique em Atualizar)" },
    Value = "(clique em Atualizar)",
    Callback = function(v) selectedLabel = v end,
})
Obt:Button({ Title = "Atualizar lista (use depois de Escanear)", Callback = function()
    task.spawn(function()
        buildCatalog()
        local labels = {}
        for _, e in ipairs(Catalog) do labels[#labels + 1] = e.label end
        if #labels == 0 then labels = { "(nenhuma encontrada)" } end
        local ok = pcall(function() obtDropdown:Refresh(labels) end)
        notify(ok and (#Catalog .. " luvas listadas") or (#Catalog .. " luvas no console (Refresh do Dropdown falhou nesta versao do WindUI)"))
    end)
end })
Obt:Button({ Title = "Pegar a luva selecionada", Callback = function()
    local e = selectedLabel and CatalogByLabel[selectedLabel]
    if not e then notify("Selecione uma luva da lista primeiro.") return end
    task.spawn(function()
        notify(grabGlove(e) and (e.name .. ": confirmada no inventario") or (e.name .. ": NAO confirmada"))
    end)
end })
Obt:Toggle({ Title = "Pegar todas as listadas", Value = false, Callback = function(on)
    if not on then flags.grabAll = false return end
    if #Catalog == 0 then notify("Lista vazia: Atualize primeiro.") return end
    loop("grabAll", 2, function()
        for _, e in ipairs(Catalog) do
            if not flags.grabAll then return end
            if not hasTool(e.name) then
                local ok = grabGlove(e)
                print(("[grabAll] %s: %s"):format(e.name, ok and "confirmada" or "nao confirmada"))
            end
        end
    end)
end })
for _, ext in ipairs(Config.ExternalScripts) do
    Obt:Button({ Title = "Carregar: " .. ext.name, Callback = function()
        local ok, err = pcall(function() loadstring(game:HttpGet(ext.url))() end)
        print("[external]", ext.url, ok and "ok" or err)
        notify(ok and (ext.name .. ": carregado") or (ext.name .. ": falhou, veja o console"))
    end })
end

local extUrl = ""
Obt:Input({ Title = "URL de script externo", Placeholder = "https://...", Callback = function(v) extUrl = v end })
Obt:Button({ Title = "Carregar URL colada", Callback = function()
    if not extUrl:match("^https://") then notify("URL invalida: precisa comecar com https://") return end
    local ok, err = pcall(function() loadstring(game:HttpGet(extUrl))() end)
    print("[external]", extUrl, ok and "ok" or err)
    notify(ok and "Script carregado." or "Falhou: veja o console.")
end })

local CitedRemotes = { "Barrier", "Sentry", "lbrick", "VineThud", "RockyShoot", "PusherWall", "bob" }
Obt:Button({ Title = "Verificar remotes citados pelo script externo", Callback = function()
    local found = 0
    for _, n in ipairs(CitedRemotes) do
        local r = RS:FindFirstChild(n)
        local ok = r ~= nil and r:IsA("RemoteEvent")
        print("[cited]", n, ok and "existe" or "NAO existe")
        if ok then found += 1 end
    end
    notify(found .. " de " .. #CitedRemotes .. " existem (console)")
end })
Obt:Button({ Title = "Disparar remote 'bob' (script externo diz que precisa da Replica)", Callback = function()
    local r = RS:FindFirstChild("bob")
    if r and r:IsA("RemoteEvent") then
        r:FireServer()
        notify("bob disparado; confira se a luva ou a badge apareceu.")
    else
        notify("Remote 'bob' nao existe nesta build.")
    end
end })

-- PLAYER
local Player = Window:Tab({ Title = "Player" })
Player:Slider({ Title = "WalkSpeed", Value = { Min = 16, Max = 120, Default = 16 }, Callback = function(v)
    local h = hum() if h then h.WalkSpeed = v end
end })
Player:Slider({ Title = "JumpPower", Value = { Min = 50, Max = 250, Default = 50 }, Callback = function(v)
    local h = hum() if h then h.UseJumpPower = true h.JumpPower = v end
end })
Player:Toggle({ Title = "Pulo infinito", Value = false, Callback = function(on)
    setConn("infjump", on and UIS.JumpRequest or nil, function()
        local h = hum() if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end })
Player:Toggle({ Title = "Noclip", Value = false, Callback = function(on)
    setConn("noclip", on and RunService.Stepped or nil, function()
        local c = LP.Character if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end })
Player:Toggle({ Title = "Anti-AFK", Value = false, Callback = function(on)
    setConn("afk", on and LP.Idled or nil, function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end })

-- DIVERSAO
local Fun = Window:Tab({ Title = "Diversao" })
local spin
Fun:Toggle({ Title = "Girar", Value = false, Callback = function(on)
    if spin then spin:Destroy() spin = nil end
    local r = root()
    if on and r then
        spin = Instance.new("BodyAngularVelocity")
        spin.MaxTorque = Vector3.new(0, math.huge, 0)
        spin.AngularVelocity = Vector3.new(0, 20, 0)
        spin.Parent = r
    end
end })
Fun:Toggle({ Title = "Gravidade baixa", Value = false, Callback = function(on)
    workspace.Gravity = on and 60 or 196.2
end })
Fun:Toggle({ Title = "Personagem arco-iris", Value = false, Callback = function(on)
    if not on then flags.rainbow = false return end
    loop("rainbow", 0.05, function()
        local c = LP.Character if not c then return end
        local col = Color3.fromHSV((tick() % 5) / 5, 1, 1)
        for _, p in ipairs(c:GetChildren()) do
            if p:IsA("BasePart") then p.Color = col end
        end
    end)
end })

-- ===== EXTRAS =====
local Extras = Window:Tab({ Title = "Extras" })

local function characterOwner(inst)
    local cur = inst
    while cur and cur ~= workspace do
        local p = Players:GetPlayerFromCharacter(cur)
        if p then return p, cur end
        cur = cur.Parent
    end
end

local function nearestOther(maxDist)
    local mine = root()
    if not mine then return nil end
    local best, bestD = nil, maxDist or math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p ~= LP and p.Character
        local r = ch and ch:FindFirstChild("HumanoidRootPart")
        local h = ch and ch:FindFirstChildOfClass("Humanoid")
        if r and h and h.Health > 0 then
            local d = (r.Position - mine.Position).Magnitude
            if d < bestD then best, bestD = { player = p, root = r }, d end
        end
    end
    return best
end

-- Voo (usa o joystick/WASD via MoveDirection e a direcao da camera)
local flySpeed, flyBV, flyBG = 60, nil, nil
local function stopFly()
    setConn("fly", nil)
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    local h = hum() if h then h.PlatformStand = false end
end
Extras:Slider({ Title = "Velocidade do voo", Value = { Min = 20, Max = 200, Default = 60 }, Callback = function(v) flySpeed = v end })
Extras:Toggle({ Title = "Voo", Value = false, Callback = function(on)
    stopFly()
    if not on then return end
    local r, h = root(), hum()
    if not (r and h) then notify("Sem personagem.") return end
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9) flyBV.Velocity = Vector3.zero flyBV.Parent = r
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9) flyBG.P = 1e4 flyBG.CFrame = r.CFrame flyBG.Parent = r
    h.PlatformStand = true
    setConn("fly", RunService.Heartbeat, function()
        local cam, hh = workspace.CurrentCamera, hum()
        if not (cam and hh and flyBV and flyBV.Parent) then return end
        local loc = cam.CFrame:VectorToObjectSpace(hh.MoveDirection)
        flyBV.Velocity = (cam.CFrame.RightVector * loc.X + cam.CFrame.LookVector * -loc.Z) * flySpeed
        flyBG.CFrame = cam.CFrame
    end)
end })
LP.CharacterAdded:Connect(stopFly)

-- ESP (Highlight sempre visivel, recriado quando o jogador respawna)
local espObjs = {}
local function clearEsp() for _, o in pairs(espObjs) do o:Destroy() end espObjs = {} end
Extras:Toggle({ Title = "ESP de jogadores", Value = false, Callback = function(on)
    if not on then flags.esp = false clearEsp() return end
    loop("esp", 1, function()
        for p, h in pairs(espObjs) do
            if not p.Parent or not p.Character or h.Parent ~= p.Character then h:Destroy() espObjs[p] = nil end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character and not espObjs[p] then
                local h = Instance.new("Highlight")
                h.FillColor = Color3.fromRGB(255, 60, 60) h.OutlineColor = Color3.new(1, 1, 1)
                h.FillTransparency = 0.5 h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = p.Character
                espObjs[p] = h
            end
        end
    end)
end })

-- Teleporte ate jogador
local tpTarget
local tpDropdown = Extras:Dropdown({ Title = "Jogador", Values = { "(clique em Atualizar)" }, Value = "(clique em Atualizar)",
    Callback = function(v) tpTarget = v end })
Extras:Button({ Title = "Atualizar jogadores", Callback = function()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do if p ~= LP then names[#names + 1] = p.Name end end
    if #names == 0 then names = { "(ninguem)" } end
    if not pcall(function() tpDropdown:Refresh(names) end) then notify("Refresh do Dropdown falhou nesta versao do WindUI.") end
end })
Extras:Button({ Title = "Teleportar ate o jogador", Callback = function()
    local p = tpTarget and Players:FindFirstChild(tpTarget)
    local tr = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    local r = root()
    if tr and r then r.CFrame = tr.CFrame * CFrame.new(0, 0, 3) else notify("Jogador invalido ou sem personagem.") end
end })

-- Click TP, FOV, Fullbright
Extras:Toggle({ Title = "Click TP (toque/clique no chao)", Value = false, Callback = function(on)
    local mouse = LP:GetMouse()
    setConn("clicktp", on and mouse.Button1Down or nil, function()
        local r = root()
        if r and mouse.Hit then r.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0)) end
    end)
end })
Extras:Slider({ Title = "FOV da camera", Value = { Min = 40, Max = 120, Default = 70 }, Callback = function(v)
    if workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = v end
end })
local fbSaved
Extras:Toggle({ Title = "Fullbright", Value = false, Callback = function(on)
    if on then
        fbSaved = fbSaved or { Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient }
        Lighting.Brightness = 2 Lighting.ClockTime = 14 Lighting.FogEnd = 1e6
        Lighting.GlobalShadows = false Lighting.Ambient = Color3.new(1, 1, 1)
    elseif fbSaved then
        for k, v in pairs(fbSaved) do Lighting[k] = v end
        fbSaved = nil
    end
end })

-- Anti-void: NAO CALIBRADO. 60 studs abaixo do ultimo chao e um palpite, nao uma medida do mapa.
local VOID_DROP = 60
Extras:Toggle({ Title = "Anti-void (volta ao ultimo chao)", Value = false, Callback = function(on)
    if not on then flags.antivoid = false return end
    local safe
    loop("antivoid", 0.1, function()
        local r, h = root(), hum()
        if not (r and h and h.Health > 0) then safe = nil return end
        if h.FloorMaterial ~= Enum.Material.Air then
            safe = r.CFrame
        elseif safe and r.Position.Y < safe.Position.Y - VOID_DROP then
            r.AssemblyLinearVelocity = Vector3.zero
            r.CFrame = safe + Vector3.new(0, 5, 0)
        end
    end)
end })

-- Auto Slap: replica o remote que voce ensinar, trocando o alvo pelo jogador mais proximo
local slapRange = 12
Extras:Button({ Title = "Aprender slap (de 1 ou 2 tapas a mao)", Callback = function() learn("slap") end })
Extras:Slider({ Title = "Alcance do Auto Slap", Value = { Min = 5, Max = 40, Default = 12 }, Callback = function(v) slapRange = v end })
Extras:Toggle({ Title = "Auto Slap (jogador mais proximo)", Value = false, Callback = function(on)
    if not on then flags.autoslap = false return end
    if not Learned.slap then notify("Bloqueado: aprenda o slap primeiro.") return end
    loop("autoslap", 0.4, function()
        local target = nearestOther(slapRange)
        if not target then return end
        replay(Learned.slap, function(a)
            local tch = target.player.Character
            for i = 1, a.n do
                local v = a[i]
                if typeof(v) == "Instance" then
                    local p, ch = characterOwner(v)
                    if p and p ~= LP and tch then
                        a[i] = (v == ch) and tch or (tch:FindFirstChild(v.Name, true) or target.root)
                    end
                end
            end
        end)
    end)
end })

-- AUTO FARM SLAP: teleporta atras do jogador vivo mais proximo e repete o slap aprendido
local farmOffset, farmAttempts = 3, 0

local function retarget(a, target)
    local tch = target.player.Character
    if not tch then return end
    for i = 1, a.n do
        local v = a[i]
        if typeof(v) == "Instance" then
            local p, ch = characterOwner(v)
            if p and p ~= LP then
                a[i] = (v == ch) and tch or (tch:FindFirstChild(v.Name, true) or target.root)
            end
        end
    end
end

Extras:Slider({ Title = "Distancia atras do alvo (farm)", Value = { Min = 2, Max = 10, Default = 3 }, Callback = function(v) farmOffset = v end })
Extras:Toggle({ Title = "Auto Farm Slap", Value = false, Callback = function(on)
    if not on then flags.farmslap = false return end
    if not Learned.slap then notify("Bloqueado: use 'Aprender slap' e de um tapa a mao antes.") return end
    farmAttempts = 0
    loop("farmslap", 0.35, function()
        local r, h = root(), hum()
        if not (r and h and h.Health > 0) then return end
        local target = nearestOther(math.huge)
        if not target then return end
        r.CFrame = target.root.CFrame * CFrame.new(0, 0, farmOffset)
        replay(Learned.slap, function(a) retarget(a, target) end)
        farmAttempts += 1
        if farmAttempts % 25 == 0 then print("[farmslap] tentativas:", farmAttempts) end
    end)
end })

-- AUTO FARM SLAPPLE
-- SLAPPLE_NEEDLE e um palpite de nome (nao medido). Use "Listar slapples" para conferir o que existe de fato.
local SLAPPLE_NEEDLE = "slapple"
local slappleOffset, slappleDone, slappleAttempts = 3, 0, 0

local function slapplePos(inst)
    if inst:IsA("Model") then
        local ok, cf = pcall(inst.GetPivot, inst)
        return ok and cf.Position or nil
    end
    return inst:IsA("BasePart") and inst.Position or nil
end

local function nameHasSlapple(inst)
    local cur, depth = inst, 0
    while cur and cur ~= workspace and depth < 4 do
        if cur.Name:lower():find(SLAPPLE_NEEDLE, 1, true) then return true end
        cur, depth = cur.Parent, depth + 1
    end
    return false
end

local function scanSlapples()
    local found, set, n = {}, {}, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        n += 1
        if n % 3000 == 0 then task.wait() end
        if (d:IsA("Model") or d:IsA("BasePart")) and d.Name:lower():find(SLAPPLE_NEEDLE, 1, true)
            and not characterOwner(d) then
            found[#found + 1] = d
            set[d] = true
        end
    end
    local top = {}   -- fica so o objeto mais alto de cada grupo (nao conta as partes internas)
    for _, d in ipairs(found) do
        local p, nested = d.Parent, false
        while p and p ~= workspace do
            if set[p] then nested = true break end
            p = p.Parent
        end
        if not nested and slapplePos(d) then top[#top + 1] = d end
    end
    return top
end

local function nearestSlapple(list)
    local r = root()
    if not r then return nil end
    local best, bestD = nil, math.huge
    for _, d in ipairs(list) do
        if d:IsDescendantOf(workspace) then
            local pos = slapplePos(d)
            if pos then
                local dist = (pos - r.Position).Magnitude
                if dist < bestD then best, bestD = d, dist end
            end
        end
    end
    return best
end

local function retargetSlapple(a, target)
    local mine = LP.Character
    for i = 1, a.n do
        local v = a[i]
        if typeof(v) == "Instance" and not (mine and v:IsDescendantOf(mine)) then
            if nameHasSlapple(v) or characterOwner(v) then
                a[i] = target   -- argumento que apontava para slapple ou jogador vira o slapple alvo
            end
        end
    end
end

Extras:Button({ Title = "Aprender slap em slapple (bata em um slapple a mao)", Callback = function() learn("slapple") end })
Extras:Button({ Title = "Listar slapples (console)", Callback = function()
    task.spawn(function()
        local list = scanSlapples()
        print(("[slapple] %d objetos com '%s' no nome"):format(#list, SLAPPLE_NEEDLE))
        for i, d in ipairs(list) do
            if i > 40 then print("  ...") break end
            print("  ", d.ClassName, d:GetFullName())
        end
        notify(#list .. " slapples achados (veja o console)")
    end)
end })
Extras:Slider({ Title = "Distancia do slapple (farm)", Value = { Min = 2, Max = 10, Default = 3 }, Callback = function(v) slappleOffset = v end })
Extras:Toggle({ Title = "Auto Farm Slapple", Value = false, Callback = function(on)
    if not on then flags.farmslapple = false return end
    local entry = Learned.slapple or Learned.slap
    if not entry then notify("Bloqueado: aprenda o slap (de preferencia em um slapple) antes.") return end
    slappleDone, slappleAttempts = 0, 0
    local list, scannedAt = {}, 0
    loop("farmslapple", 0.35, function()
        local r, h = root(), hum()
        if not (r and h and h.Health > 0) then return end
        if tick() - scannedAt > 3 then list, scannedAt = scanSlapples(), tick() end
        local target = nearestSlapple(list)
        if not target then
            if #list == 0 then print("[farmslapple] nenhum objeto com '" .. SLAPPLE_NEEDLE .. "' no mapa") end
            scannedAt = 0
            return
        end
        r.CFrame = CFrame.new(slapplePos(target) + Vector3.new(0, 0, slappleOffset))
        replay(entry, function(a) retargetSlapple(a, target) end)
        slappleAttempts += 1
        task.wait(0.15)
        if not target:IsDescendantOf(workspace) then
            slappleDone += 1
            print(("[farmslapple] slapple removido (%d). tentativas=%d"):format(slappleDone, slappleAttempts))
        end
    end)
end })

-- OWNER
if isOwner then
    local Owner = Window:Tab({ Title = "Owner" })
    Owner:Slider({ Title = "WalkSpeed (owner)", Value = { Min = 16, Max = 300, Default = 16 }, Callback = function(v)
        local h = hum() if h then h.WalkSpeed = v end
    end })
    Owner:Button({ Title = "Parar todos os loops", Callback = function()
        for k in pairs(flags) do flags[k] = false end
        notify("Loops parados.")
    end })
    Owner:Button({ Title = "Limpar remotes aprendidos", Callback = function()
        Learned = {} gloveSlot = nil
        notify("Aprendizado limpo.")
    end })
end

LP.CharacterAdded:Connect(function() spin = nil end)
notify(isOwner and "Owner detectado." or "Carregado.")
