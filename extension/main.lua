----------------------------------------------------------------------
-- ColorCard 游戏风格色卡 v1.5
-- 层级：风格 -> 游戏 -> 大类/中类/小类 -> 细项（每行六层色）
-- 界面：分类浏览（风格/游戏 下拉 + 大中小类级联）或 搜索模式（全库关键词）
--       搜索结果行显示：颜色名称 · 游戏/大类/中类/小类 + 六层色
-- 点击色块 = 设为前景色 + 复制 HEX
-- 需要 Aseprite >= 1.3.6
----------------------------------------------------------------------

local COLORCARD_PATH = nil

local ROLE_ORDER = { "outline", "shade", "base", "light", "highlight", "shadow" }
local ROLE_NAMES = {
  outline = "Outline", shade = "Shade", base = "Base",
  light = "Light", highlight = "Highlight", shadow = "Shadow",
}
local ALL = "(All)"

-- ---------------- 工具 ----------------

local function hexToColor(hex)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  return Color { r = r, g = g, b = b, a = 255 }
end

-- 复制文本：1.3.10+ 用 app.clipboard；旧版没有该字段（索引即报错），走 clip.exe 管道
local function copyText(s)
  local ok = false
  pcall(function()
    local cb = app.clipboard
    if cb ~= nil then
      cb.text = s
      ok = true
    end
  end)
  if not ok then
    pcall(function()
      local p = io.popen("clip", "w")
      if p then p:write(s) p:close() ok = true end
    end)
  end
  return ok
end

local function loadDB()
  local styles = {}
  -- app.fs.joinPath 只接受两个参数，需嵌套调用
  local dir = app.fs.joinPath(app.fs.joinPath(COLORCARD_PATH, "data"), "palettes")
  if not app.fs.isDirectory(dir) then return styles end
  local files = app.fs.listFiles(dir)
  table.sort(files)
  for _, fn in ipairs(files) do
    if fn:lower():match("%.json$") then
      -- listFiles 在不同版本可能返回纯文件名或完整路径，做个兼容
      local full = fn
      if not app.fs.isFile(fn) then full = app.fs.joinPath(dir, fn) end
      local f = io.open(full, "r")
      if f then
        local content = f:read("*a")
        f:close()
        local ok, data = pcall(json.decode, content)
        -- 注意：旧版 Aseprite 的 json.decode 返回 userdata 而非 table，不能检查 type
        if ok and data ~= nil and data.games ~= nil and data.name ~= nil then
          table.insert(styles, data)
        end
      end
    end
  end
  return styles
end

-- 当前 state 跨面板重建保留
local DB = nil
local state = nil
local activeDlg = nil
local pendingTimer = nil

local function currentStyle()
  return DB[state.styleIdx]
end

local function currentGame()
  local st = currentStyle()
  return st.games[state.gameIdx]
end

-- 级联取值：某层级在给定父级筛选下的去重列表（保持出现顺序）
local function distinct(game, field, f1, f2)
  local out, seen = {}, {}
  for _, e in ipairs(game.entries) do
    if (not f1 or e.cat1 == f1) and (not f2 or e.cat2 == f2) then
      local v = e[field]
      if v and v ~= "" and not seen[v] then
        seen[v] = true
        out[#out + 1] = v
      end
    end
  end
  return out
end

local function filterEntries(game)
  local out = {}
  for _, e in ipairs(game.entries) do
    if (state.c1 == ALL or e.cat1 == state.c1)
        and (state.c2 == ALL or e.cat2 == state.c2)
        and (state.c3 == ALL or e.cat3 == state.c3) then
      out[#out + 1] = e
    end
  end
  return out
end

-- 组合框选中值（兼容 data 返回文本或索引两种实现）
local function resolveOption(options, value)
  if value == nil then return nil end
  if type(value) == "number" then
    if value >= 1 and value <= #options then return options[value] end
    return nil
  end
  for _, o in ipairs(options) do
    if o == value then return o end
  end
  return nil
end

-- ---------------- 面板重建（级联下拉时关闭旧窗口重开） ----------------

local function buildDialog(bounds)

  local st = currentStyle()
  local game = currentGame()

  local styleOpts = {}
  for i, s in ipairs(DB) do styleOpts[i] = s.name .. " (" .. s.id .. ")" end
  local gameOpts = {}
  for i, g in ipairs(st.games) do gameOpts[i] = g.name end
  local cat1Opts = { ALL }
  for _, v in ipairs(distinct(game, "cat1")) do cat1Opts[#cat1Opts + 1] = v end
  local cat2Opts = { ALL }
  if state.c1 ~= ALL then
    for _, v in ipairs(distinct(game, "cat2", state.c1)) do cat2Opts[#cat2Opts + 1] = v end
  end
  local cat3Opts = { ALL }
  if state.c1 ~= ALL and state.c2 ~= ALL then
    for _, v in ipairs(distinct(game, "cat3", state.c1, state.c2)) do cat3Opts[#cat3Opts + 1] = v end
  end

  local dlg = Dialog("ColorCard")
  activeDlg = dlg

  -- 表格 canvas 常量
  local PAD = 6
  local SEARCH = (state.tab == "search")
  local NAME_W = SEARCH and 320 or 140
  local HDR_H = 22
  local ROW_H = 22
  local VISIBLE = 12
  -- 六层色块：正方形、按 outline/shade/base/light/highlight/shadow 顺序紧贴排列
  local SW = ROW_H - 7          -- swatch size (square)

  -- 搜索模式：全库扁平搜索（颜色名/游戏/风格/各级类别），结果带完整路径
  -- 同「游戏+类别+名称」只保留一条（通用材质在多个风格里各有一份，避免刷屏）
  local function searchList()
    local q = (state.query or ""):lower()
    if q == "" then return {} end
    if state._scache and state._scache.q == q then return state._scache.list end
    local out, seen = {}, {}
    for _, s in ipairs(DB) do
      for _, g in ipairs(s.games) do
        for _, e in ipairs(g.entries) do
          local hay = (e.name or "") .. "\n" .. (g.name or "") .. "\n" .. (s.name or "")
            .. "\n" .. (e.cat1 or "") .. "\n" .. (e.cat2 or "") .. "\n" .. (e.cat3 or "")
          if hay:lower():find(q, 1, true) then
            local key = (g.name or "") .. "|" .. (e.name or "") .. "|" .. (e.cat1 or "")
              .. "|" .. (e.cat2 or "") .. "|" .. (e.cat3 or "")
            if not seen[key] then
              seen[key] = true
              out[#out + 1] = {
                e = e,
                path = (e.name or "") .. " · " .. (g.name or "") .. "/"
                  .. (e.cat1 or "") .. "/" .. (e.cat2 or "") .. "/" .. (e.cat3 or ""),
              }
            end
          end
        end
      end
    end
    state._scache = { q = q, list = out }
    return out
  end

  local function pageList()
    if SEARCH then return searchList() end
    return filterEntries(game)
  end

  local function pageCount(list)
    local n = math.ceil(#list / VISIBLE)
    if n < 1 then n = 1 end
    return n
  end

  local function updatePageLabel()
    local list = pageList()
    dlg:modify {
      id = "pagelabel",
      text = (state.page + 1) .. "/" .. pageCount(list) .. "p · " .. #list .. " items",
    }
  end

  -- 行数：搜索模式固定 12 行（输入关键词只重绘不重建面板，行数不能随结果变化）
  local visRows = SEARCH and VISIBLE or math.max(1, math.min(VISIBLE, #pageList()))
  local CANVAS_W = PAD * 2 + NAME_W + SW * #ROLE_ORDER
  local CANVAS_H = HDR_H + ROW_H * visRows + 2

  local function rowAt(y)
    local row = math.floor((y - HDR_H) / ROW_H) + 1
    if y >= HDR_H and row >= 1 and row <= visRows then return row end
    return nil
  end

  local function colAt(x)
    local col = math.floor((x - PAD - NAME_W) / SW) + 1
    if x >= PAD + NAME_W and col >= 1 and col <= #ROLE_ORDER then return col end
    return nil
  end

  -- ---------- 模式切换（分类浏览 / 全库搜索） ----------
  dlg:newrow()
  dlg:button {
    text = SEARCH and "« Back to Browse" or "🔍 Search Mode",
    onclick = function()
      state.tab = SEARCH and "browse" or "search"
      state.page = 0
      scheduleRebuild()
    end,
  }

  if not SEARCH then
  -- ---------- 风格 / 游戏 ----------
  dlg:combobox {
    id = "style", label = "Style",
    options = styleOpts,
    option = styleOpts[state.styleIdx],
    onchange = function()
      local v = resolveOption(styleOpts, dlg.data["style"])
      if v then
        local idx = 0
        for i, o in ipairs(styleOpts) do if o == v then idx = i end end
        if idx > 0 and idx ~= state.styleIdx then
          state.styleIdx = idx
          state.gameIdx = 1
          state.c1, state.c2, state.c3 = ALL, ALL, ALL
          state.page = 0
          scheduleRebuild()
        end
      end
    end,
  }

  dlg:combobox {
    id = "game", label = "Game",
    options = gameOpts,
    option = gameOpts[state.gameIdx],
    onchange = function()
      local v = resolveOption(gameOpts, dlg.data["game"])
      if v then
        local idx = 0
        for i, o in ipairs(gameOpts) do if o == v then idx = i end end
        if idx > 0 and idx ~= state.gameIdx then
          state.gameIdx = idx
          state.c1, state.c2, state.c3 = ALL, ALL, ALL
          state.page = 0
          scheduleRebuild()
        end
      end
    end,
  }

  -- ---------- 大类 / 中类 / 小类 ----------
  dlg:combobox {
    id = "cat1", label = "Category",
    options = cat1Opts,
    option = state.c1,
    onchange = function()
      local v = resolveOption(cat1Opts, dlg.data["cat1"])
      if v and v ~= state.c1 then
        state.c1 = v
        state.c2, state.c3 = ALL, ALL
        state.page = 0
        scheduleRebuild()
      end
    end,
  }

  dlg:combobox {
    id = "cat2", label = "Subcat",
    options = cat2Opts,
    option = state.c2,
    onchange = function()
      local v = resolveOption(cat2Opts, dlg.data["cat2"])
      if v and v ~= state.c2 then
        state.c2 = v
        state.c3 = ALL
        state.page = 0
        scheduleRebuild()
      end
    end,
  }

  dlg:combobox {
    id = "cat3", label = "Type",
    options = cat3Opts,
    option = state.c3,
    onchange = function()
      local v = resolveOption(cat3Opts, dlg.data["cat3"])
      if v and v ~= state.c3 then
        state.c3 = v
        state.page = 0
        dlg:repaint()
      end
    end,
  }

  else
  -- ---------- 搜索框（英文关键词） ----------
  dlg:entry {
    id = "search", label = "Search",
    text = state.query or "",
    onchange = function()
      state.query = dlg.data["search"] or ""
      state.page = 0
      updatePageLabel()
      dlg:repaint()
    end,
  }
  end

  -- ---------- 细项色表 ----------
  dlg:canvas {
    id = "table",
    width = CANVAS_W,
    height = CANVAS_H,
    onpaint = function(ev)
      local gc = ev.context
      local list = pageList()
      local text = app.theme.color["text"]
      local faint = app.theme.color["disabled"]

      -- 搜索模式提示
      if SEARCH and (state.query or "") == "" then
        gc.color = faint
        gc:fillText("Search by item name / game / category (English keywords)", PAD, HDR_H + 8)
        return
      end
      if SEARCH and #list == 0 then
        gc.color = faint
        gc:fillText("No matches", PAD, HDR_H + 8)
        return
      end

      gc.color = text
      -- 色块顺序写在表头：紧贴方块按此顺序排列
      gc:fillText("Item(outline/shade/base/light/highlight/shadow)", PAD, 6)

      local start = state.page * VISIBLE
      for row = 1, visRows do
        local item = list[start + row]
        local e = item and (item.e or item)
        local y = HDR_H + (row - 1) * ROW_H
        if not e then break end
        -- 行分隔线
        gc.color = faint
        gc:fillRect(Rectangle(PAD, y + ROW_H - 1, CANVAS_W - PAD * 2, 1))
        -- 名称（搜索模式显示完整路径，超宽截断）
        gc.color = text
        local label = (SEARCH and item.path) or e.name or ""
        if gc:measureText(label).width > NAME_W - 6 then
          local n = #label
          while n > 1 and gc:measureText(label:sub(1, n) .. "…").width > NAME_W - 6 do
            n = n - 1
          end
          label = label:sub(1, n) .. "…"
        end
        gc:fillText(label, PAD, y + 6)
        -- 六层色块：正方形紧贴
        for i, role in ipairs(ROLE_ORDER) do
          local x = PAD + NAME_W + (i - 1) * SW
          gc.color = hexToColor(e.colors[role])
          gc:fillRect(Rectangle(x, y + 3, SW, SW))
          if state.hover and state.hover.row == row and state.hover.col == i then
            gc.color = Color { r = 255, g = 255, b = 255, a = 255 }
            gc.strokeWidth = 2
            gc:strokeRect(Rectangle(x - 1, y + 2, SW + 2, SW + 2))
            gc.strokeWidth = 1
          end
        end
      end
    end,
    onmousemove = function(ev)
      local row, col = rowAt(ev.y), colAt(ev.x)
      if row and not col then row = nil end
      if not (state.hover and state.hover.row == row and state.hover.col == col) then
        state.hover = row and { row = row, col = col } or nil
        dlg:repaint()
      end
    end,
    onmouseexit = function()
      if state.hover then
        state.hover = nil
        dlg:repaint()
      end
    end,
    onmouseup = function(ev)
      if ev.button ~= MouseButton.LEFT then return end
      local row, col = rowAt(ev.y), colAt(ev.x)
      if not row or not col then return end
      local item = pageList()[state.page * VISIBLE + row]
      local e = item and (item.e or item)
      if not e then return end
      local role = ROLE_ORDER[col]
      local hex = e.colors[role]
      app.fgColor = hexToColor(hex)
      local copied = copyText(hex)
      dlg:modify {
        id = "status",
        text = "Picked " .. ((SEARCH and item.path) or e.name or "") .. " · "
          .. ROLE_NAMES[role] .. " " .. hex
          .. (copied and " (copied)" or ""),
      }
    end,
  }

  -- ---------- 翻页 / 操作（紧凑：一行放翻页三件套，一行放操作按钮） ----------
  dlg:newrow()
  dlg:button {
    text = "‹",
    onclick = function()
      if state.page > 0 then
        state.page = state.page - 1
        updatePageLabel()
        dlg:repaint()
      end
    end,
  }
  dlg:label { id = "pagelabel", text = "" }
  dlg:button {
    text = "›",
    onclick = function()
      local list = pageList()
      if state.page < pageCount(list) - 1 then
        state.page = state.page + 1
        updatePageLabel()
        dlg:repaint()
      end
    end,
  }

  if not SEARCH then
  dlg:newrow()
  dlg:button {
    text = "Copy All HEX",
    onclick = function()
      local list = pageList()
      local out = {}
      for _, e in ipairs(list) do
        local parts = {}
        for _, role in ipairs(ROLE_ORDER) do
          parts[#parts + 1] = ROLE_NAMES[role] .. e.colors[role]
        end
        out[#out + 1] = (e.name or "") .. " " .. table.concat(parts, " ")
      end
      copyText(st.name .. " / " .. game.name .. "\n" .. table.concat(out, "\n"))
      dlg:modify { id = "status", text = "Copied " .. #list .. " items" }
    end,
  }

  dlg:button {
    text = "Load Palette",
    onclick = function()
      local spr = app.activeSprite
      if not spr then
        app.alert("Open a sprite first, then load the palette.")
        return
      end
      local n = #game.entries * #ROLE_ORDER
      if n > 256 then n = 256 end
      local pal = Palette(n)
      local i = 0
      for _, e in ipairs(game.entries) do
        for _, role in ipairs(ROLE_ORDER) do
          if i >= n then break end
          pal:setColor(i, hexToColor(e.colors[role]))
          i = i + 1
        end
      end
      spr:setPalette(pal)
      dlg:modify { id = "status", text = "Wrote " .. i .. " colors to the sprite palette" }
    end,
  }

  end

  dlg:label { id = "status", text = "Click swatch = set FG + copy HEX" }

  dlg:show { wait = false }
  if bounds then
    dlg.bounds = Rectangle(bounds.x, bounds.y, bounds.width, bounds.height)
  end
  updatePageLabel()
end

-- 用 Timer 延迟重建（不能在 combobox 回调里直接 close）
function scheduleRebuild()
  if pendingTimer == nil then
    pendingTimer = Timer {
      interval = 0.01,
      ontick = function()
        pendingTimer:stop()
        pendingTimer = nil
        local b = nil
        if activeDlg then
          b = activeDlg.bounds
          activeDlg:close()
          activeDlg = nil
        end
        buildDialog(b)
      end,
    }
  end
  pendingTimer:start()
end

-- ---------------- 入口 ----------------

local function openDialog()
  DB = loadDB()
  if #DB == 0 then
    -- 自诊断：加载失败时写日志文件 + 弹窗（弹窗可能显示不全，文件为准）
    local base = COLORCARD_PATH or "(nil)"
    local dataDir = app.fs.joinPath(base, "data")
    local dir = app.fs.joinPath(dataDir, "palettes")
    local files = nil
    if app.fs.isDirectory(dir) then files = app.fs.listFiles(dir) end
    local fileList = "(dir missing)"
    if files then
      local names = {}
      for i, f in ipairs(files) do
        names[i] = tostring(f)
        if i >= 6 then break end
      end
      fileList = #files .. " files: " .. table.concat(names, " | ")
    end
    local probe = "us.json missing"
    if app.fs.isFile(app.fs.joinPath(dir, "us.json")) then
      local f = io.open(app.fs.joinPath(dir, "us.json"), "r")
      if f then
        local content = f:read("*a")
        f:close()
        local ok, data = pcall(json.decode, content)
        probe = "us.json: " .. #content .. " bytes, decode:"
          .. (ok and ("OK games=" .. tostring(data and data.games and #data.games)) or "FAILED")
      else
        probe = "us.json unreadable"
      end
    end
    local report = table.concat({
      "path=" .. base,
      "palettes dir=" .. dir,
      "dir exists=" .. tostring(app.fs.isDirectory(dir)),
      "files=" .. fileList,
      "json=" .. tostring(json ~= nil),
      probe,
    }, "\n")
    -- 写日志文件到扩展目录和用户目录（两处都试）
    for _, logpath in ipairs({ app.fs.joinPath(base, "colorcard-debug.txt"),
                               app.fs.joinPath(app.fs.userDocsPath or base, "colorcard-debug.txt") }) do
      local lf = io.open(logpath, "w")
      if lf then lf:write(report) lf:close() end
    end
    app.alert("ColorCard: failed to load palette data.\nSee colorcard-debug.txt in the extension folder.\n" .. report)
    return
  end
  if state == nil then
    state = { styleIdx = 1, gameIdx = 1, c1 = ALL, c2 = ALL, c3 = ALL,
              page = 0, hover = nil, tab = "browse", query = "" }
  end
  -- 数据可能已更新：钳制索引
  state.styleIdx = math.min(state.styleIdx, #DB)
  state.gameIdx = math.min(state.gameIdx, #currentStyle().games)
  state.page = 0
  buildDialog(nil)
end

function init(plugin)
  COLORCARD_PATH = plugin.path

  -- 挂到 View 菜单；失败也不影响键盘快捷键入口
  local ok = pcall(function()
    plugin:newMenuGroup { id = "colorcard_menu", title = "ColorCard", group = "view_menu" }
  end)
  if ok then
    pcall(function()
      plugin:newCommand {
        id = "ColorCardOpen",
        title = "Open ColorCard Panel",
        group = "colorcard_menu",
        onclick = openDialog,
      }
    end)
  end

  -- 无菜单入口：可在 编辑 > 键盘快捷键 中搜索 ColorCard 绑定快捷键
  pcall(function()
    plugin:newCommand {
      id = "ColorCardOpenShortcut",
      title = "ColorCard",
      onclick = openDialog,
    }
  end)
end

function exit(plugin) end
