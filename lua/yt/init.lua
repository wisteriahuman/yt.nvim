local M = {}

M.config = {
  search_count = 12,
  player = 'pane',  -- pane | tab | window | audio
  vo = 'kitty',     -- kitty | tct | tplay
  pane_percent = 42,
  replace = true,
  kitty_use_shm = true,
  volume = nil,
  mpv_args = { '--really-quiet', '--hwdec=auto-safe' },
  -- vo='tplay' のとき使う引数。-x:再生終了で自動exit / -a:遅延時はコマ落としして同期維持
  tplay_args = { '-x', '--allow-frame-skip' },
}

M.state = { active = {} }

local function notify(m, l) vim.notify('[yt] ' .. m, l or vim.log.levels.INFO) end

local function fmt_dur(s)
  if not s then return '--:--' end
  s = math.floor(s)
  local m, sec = math.floor(s / 60), s % 60
  if m >= 60 then return string.format('%d:%02d:%02d', math.floor(m / 60), m % 60, sec) end
  return string.format('%d:%02d', m, sec)
end

local LAYOUTS = { pane = true, wezterm = true, tab = true, window = true, audio = true }
local VOS = { kitty = true, tct = true, tplay = true }
local function apply_mode(token)
  if VOS[token] then M.config.vo = token; return true end
  if LAYOUTS[token] then M.config.player = (token == 'wezterm') and 'pane' or token; return true end
  return false
end

local function kill_active()
  for _, a in ipairs(M.state.active) do
    if a.kind == 'pane' then
      vim.system({ 'wezterm', 'cli', 'kill-pane', '--pane-id', a.id })
    elseif a.kind == 'proc' and a.handle then
      pcall(function() a.handle:kill(15) end)
    end
  end
  M.state.active = {}
end

function M.play(url, title)
  M.state.last = { url = url, title = title }
  if M.config.replace then kill_active() end
  local layout = M.config.player
  if layout == 'wezterm' then layout = 'pane' end
  local mpv = { 'mpv' }
  vim.list_extend(mpv, M.config.mpv_args)
  if M.config.volume then table.insert(mpv, '--volume=' .. M.config.volume) end

  if layout == 'audio' then
    vim.list_extend(mpv, { '--no-video', url })
    notify('♪ ' .. (title or url))
    table.insert(M.state.active, { kind = 'proc', handle = vim.system(mpv) }); return
  end
  if layout == 'window' then
    vim.list_extend(mpv, { url })
    notify('▶ ' .. (title or url))
    table.insert(M.state.active, { kind = 'proc', handle = vim.system(mpv) }); return
  end

  -- ターミナル内描画(pane/tab)。vo に応じて中身のプレイヤーを切り替える
  local inner
  if M.config.vo == 'tplay' then
    -- tplay は単一プロセスで映像+音声+同期を処理する(音ずれしにくい/kitty より軽い)
    inner = { 'tplay' }
    vim.list_extend(inner, M.config.tplay_args)
    table.insert(inner, url)
  else
    inner = mpv -- mpv_args / volume は適用済み
    if M.config.vo == 'tct' then
      table.insert(inner, '--vo=tct')
    else
      table.insert(inner, '--vo=kitty')
      if M.config.kitty_use_shm then table.insert(inner, '--vo-kitty-use-shm=yes') end
    end
    table.insert(inner, url)
  end
  local cmd
  if layout == 'tab' then
    cmd = { 'wezterm', 'cli', 'spawn', '--' }
  else
    cmd = { 'wezterm', 'cli', 'split-pane', '--right', '--percent', tostring(M.config.pane_percent), '--' }
  end
  vim.list_extend(cmd, inner)
  notify('▶ ' .. (title or url))
  vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      notify('wezterm失敗→通常ウィンドウで再生', vim.log.levels.WARN)
      table.insert(M.state.active, { kind = 'proc', handle = vim.system({ 'mpv', '--really-quiet', url }) })
      return
    end
    local id = (res.stdout or ''):match('%d+')
    if id then table.insert(M.state.active, { kind = 'pane', id = id }) end
  end))
end

function M.stop()
  if #M.state.active == 0 then notify('再生中のものは無い'); return end
  kill_active()
  notify('⏹ 停止')
end

function M.switch(token)
  if not M.state.last then notify('直近の再生が無い'); return end
  M.stop()
  if token and token ~= '' then apply_mode(token) end
  M.play(M.state.last.url, M.state.last.title)
end

function M.pick(items)
  local map, display = {}, {}
  for i, it in ipairs(items) do
    local line = string.format('%2d  %s  [%s]  %s', i, it.title, it.dur, it.channel)
    display[#display + 1] = line
    map[line] = it
  end
  local ok, fzf = pcall(require, 'fzf-lua')
  if ok then
    fzf.fzf_exec(display, {
      prompt = 'YouTube❯ ',
      fzf_opts = { ['--no-multi'] = '' },
      actions = {
        ['default'] = function(sel) local it = sel and map[sel[1]]; if it then M.play(it.url, it.title) end end,
        ['ctrl-a'] = function(sel)
          local it = sel and map[sel[1]]
          if it then
            local old = M.config.player; M.config.player = 'audio'
            M.play(it.url, it.title); M.config.player = old
          end
        end,
      },
    })
  else
    vim.ui.select(items, {
      prompt = 'YouTube',
      format_item = function(it) return ('%s [%s] %s'):format(it.title, it.dur, it.channel) end,
    }, function(it) if it then M.play(it.url, it.title) end end)
  end
end

function M.search(query)
  query = query and vim.trim(query) or ''
  if query == '' then
    vim.ui.input({ prompt = 'YouTube検索: ' }, function(q) if q and q ~= '' then M.search(q) end end)
    return
  end
  notify('検索中… ' .. query)
  vim.system({
    'yt-dlp', 'ytsearch' .. M.config.search_count .. ':' .. query,
    '--flat-playlist', '--dump-json', '--no-warnings',
  }, { text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then notify('検索失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR); return end
    local items = {}
    for line in vim.gsplit(res.stdout or '', '\n', { plain = true }) do
      if line ~= '' then
        -- luanil: decode JSON null to nil, else it becomes vim.NIL and breaks fmt_dur
        local ok, d = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
        if ok and type(d) == 'table' and d.id then
          items[#items + 1] = {
            url = 'https://www.youtube.com/watch?v=' .. d.id,
            title = (d.title or d.id):gsub('%s+', ' '),
            channel = d.channel or d.uploader or '',
            dur = fmt_dur(d.duration),
          }
        end
      end
    end
    if #items == 0 then notify('結果なし', vim.log.levels.WARN); return end
    M.pick(items)
  end))
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  vim.api.nvim_create_user_command('Yt', function(o) M.search(o.args) end,
    { nargs = '?', desc = 'YouTube検索→再生' })
  vim.api.nvim_create_user_command('YtStop', function() M.stop() end,
    { desc = 'YouTube再生を止める' })
  local function modes() return { 'pane', 'tab', 'window', 'audio', 'kitty', 'tct', 'tplay' } end
  vim.api.nvim_create_user_command('YtSwitch', function(o) M.switch(o.args) end,
    { nargs = '?', desc = '直近を別モードで再生し直す', complete = modes })
  vim.api.nvim_create_user_command('YtPlayer', function(o)
    if o.args == '' then notify('場所=' .. M.config.player .. '  描画=' .. M.config.vo); return end
    if apply_mode(o.args) then notify('set: ' .. o.args .. ' (場所=' .. M.config.player .. ' 描画=' .. M.config.vo .. ')')
    else notify('不明なモード: ' .. o.args, vim.log.levels.WARN) end
  end, { nargs = '?', complete = modes })
  vim.api.nvim_create_user_command('YtVolume', function(o)
    if o.args == '' then notify('音量=' .. (M.config.volume or 'mpv既定(100)')); return end
    local n = tonumber(o.args)
    if not n or n < 0 or n > 100 then notify('音量は 0-100 で', vim.log.levels.WARN); return end
    M.config.volume = math.floor(n); notify('音量=' .. M.config.volume .. '（次の再生から）')
  end, { nargs = '?' })
  return M
end

return M
