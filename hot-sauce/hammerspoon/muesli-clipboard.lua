-- Keep the latest Muesli dictation on the clipboard.
-- Muesli pastes by staging the transcript on the pasteboard, sending Cmd-V,
-- then restoring whatever was there before. If the paste lands nowhere, the
-- transcript is gone from the clipboard. This watches Muesli's dictation log
-- and, once a dictation finishes (after the restore), puts the newest
-- transcript back on top of the clipboard.

local supportDir = os.getenv("HOME") .. "/Library/Application Support/Muesli"
local logPath = supportDir .. "/dictation-latency.log"
local cli = "/Applications/Muesli.app/Contents/MacOS/muesli-cli"

local logOffset = 0
local lastId = nil

local function fileSize(path)
  local attrs = hs.fs.attributes(path)
  return attrs and attrs.size or 0
end

-- Run muesli-cli and hand its decoded `data` field to the callback.
local function runCli(args, callback)
  hs.task.new(cli, function(exitCode, stdout)
    if exitCode ~= 0 then return end
    local ok, decoded = pcall(hs.json.decode, stdout)
    if ok and decoded and decoded.ok then callback(decoded.data) end
  end, args):start()
end

local function copyLatestDictation()
  runCli({ "dictations", "list", "--limit", "1" }, function(list)
    local latest = list and list[1]
    if not latest or latest.id == lastId then return end
    lastId = latest.id
    runCli({ "dictations", "get", tostring(latest.id) }, function(record)
      if record and record.rawText and #record.rawText > 0 then
        hs.pasteboard.setContents(record.rawText)
      end
    end)
  end)
end

-- Read only the bytes appended since the last check.
local function readNewLogLines()
  local size = fileSize(logPath)
  if size < logOffset then logOffset = 0 end -- log was truncated or rotated
  if size == logOffset then return "" end
  local file = io.open(logPath, "r")
  if not file then return "" end
  file:seek("set", logOffset)
  local chunk = file:read("*a") or ""
  file:close()
  logOffset = size
  return chunk
end

-- Start at the end of the log so old dictations are not replayed.
logOffset = fileSize(logPath)
runCli({ "dictations", "list", "--limit", "1" }, function(list)
  if list and list[1] then lastId = list[1].id end
end)

muesliClipboardWatcher = hs.pathwatcher.new(supportDir, function(paths)
  for _, path in ipairs(paths) do
    if path == logPath then
      if readNewLogLines():find("event=bookkeeping_completed", 1, true) then
        copyLatestDictation()
      end
      return
    end
  end
end):start()
