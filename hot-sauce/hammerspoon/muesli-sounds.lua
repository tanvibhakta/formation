-- Rising chime when Muesli starts dictating, falling chime when it stops.
-- Muesli only plays fixed system sounds (Tink, Purr) that sound alike, so its
-- sound effects are turned off and this plays our own instead. Muesli logs
-- sound_start_requested / sound_release_requested at the exact moments it
-- would have played its sounds, so this follows those log lines.

local supportDir = os.getenv("HOME") .. "/Library/Application Support/Muesli"
local logPath = supportDir .. "/dictation-latency.log"
local soundDir = hs.fs.pathToAbsolute(debug.getinfo(1, "S").source:sub(2)):match("(.*)/") .. "/sounds"

local VOLUME = 0.6

local function load(name)
  local sound = hs.sound.getByFile(soundDir .. "/" .. name)
  if sound then sound:volume(VOLUME) end
  return sound
end

local startSound = load("dictation-start.wav")
local stopSound = load("dictation-stop.wav")

local logOffset = hs.fs.attributes(logPath, "size") or 0

-- A very short dictation can log start and release in one chunk; let the
-- start chime finish before the stop chime plays.
local function play(events)
  local delay = 0
  for _, event in ipairs(events) do
    local sound = event == "start" and startSound or stopSound
    if sound then
      hs.timer.doAfter(delay, function()
        sound:stop()
        sound:play()
      end)
      delay = delay + sound:duration()
    end
  end
end

muesliSoundsWatcher = hs.pathwatcher.new(supportDir, function(paths)
  for _, path in ipairs(paths) do
    if path == logPath then
      local size = hs.fs.attributes(logPath, "size") or 0
      if size < logOffset then logOffset = 0 end -- log was truncated or rotated
      if size == logOffset then return end
      local file = io.open(logPath, "r")
      if not file then return end
      file:seek("set", logOffset)
      local chunk = file:read("*a") or ""
      file:close()
      logOffset = size

      local events = {}
      for kind in chunk:gmatch("event=sound_(%a+)_requested") do
        table.insert(events, kind == "start" and "start" or "stop")
      end
      play(events)
      return
    end
  end
end):start()
