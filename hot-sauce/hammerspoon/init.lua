-- Copy-on-select for a curated set of apps.
-- Subscribes to AXSelectedTextChanged on each watched app's process and
-- writes the new selection to the system pasteboard. Selection events
-- from any app NOT in `watchedApps` are ignored.

local watchedApps = {
  ["com.tinyspeck.slackmacgap"]    = true, -- Slack
  ["org.mozilla.firefox"]          = true, -- Firefox
  ["com.automattic.beeper.desktop"] = true, -- Beeper Desktop
}

local observers = {}

local function attachObserver(app)
  if not app then return end
  local pid = app:pid()
  if not pid or observers[pid] then return end

  local axApp = hs.axuielement.applicationElement(app)
  if not axApp then return end

  local obs = hs.axuielement.observer.new(pid)
  obs:addWatcher(axApp, "AXSelectedTextChanged")
  obs:callback(function(_, element)
    local sel = element:attributeValue("AXSelectedText")
    if sel and #sel > 0 then
      hs.pasteboard.setContents(sel)
    end
  end)
  obs:start()
  observers[pid] = obs
end

local function detachObserver(pid)
  local obs = observers[pid]
  if obs then
    obs:stop()
    observers[pid] = nil
  end
end

-- React to app launch / activation / termination.
local appWatcher = hs.application.watcher.new(function(_, event, app)
  if not app then return end
  local bundleID = app:bundleID()
  if not bundleID or not watchedApps[bundleID] then return end

  if event == hs.application.watcher.launched
     or event == hs.application.watcher.activated then
    attachObserver(app)
  elseif event == hs.application.watcher.terminated then
    detachObserver(app:pid())
  end
end)
appWatcher:start()

-- Attach to anything already running at config load time.
for bundleID, _ in pairs(watchedApps) do
  local app = hs.application.get(bundleID)
  if app then attachObserver(app) end
end

hs.alert.show("Copy-on-select active")
