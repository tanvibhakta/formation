-- REPAIR PATH ONLY. If you opened the tabs in order with new-tab-run.applescript
-- you do not need this. Use it when tabs already exist in the wrong order and you
-- do not want to restart the sessions running in them.
--
-- Performs ONE atomic move: find the leftmost position holding the wrong tab,
-- then nudge the correct tab one slot left. Driven from a shell loop until it
-- prints SORTED. One move per invocation is deliberate -- see the note below.
--
-- usage: osascript reorder-step.applescript "substr for pos 1" "substr for pos 2" ...
--   Each argument is a distinctive substring of the tab title that belongs at that
--   position. Match on something stable: agents rewrite their tab title as work
--   progresses, and the leading status glyph changes constantly.
--
-- Requires a move_tab keybind, which Ghostty does not bind by default. Add
-- temporarily to ~/.config/ghostty/config, reload with Cmd+Shift+comma, and
-- remove afterwards:
--   keybind = super+ctrl+alt+shift+right=move_tab:1
--   keybind = super+ctrl+alt+shift+left=move_tab:-1
--
-- Why one move per run: recovering a dropped AX handle requires clicking a
-- Window-menu entry, which CHANGES the active tab. If that fires between
-- selecting a tab and pressing the arrow, the arrow moves the wrong tab. Keeping
-- recovery at the top of a single short run makes that sequence impossible.

on ensureWindow()
	repeat 12 times
		try
			tell application "System Events"
				tell application process "ghostty"
					set frontmost to true
					delay 0.25
					if (count of windows) > 0 then return true
					set winMenu to menu 1 of menu bar item "Window" of menu bar 1
					repeat with k from (count of menu items of winMenu) to 1 by -1
						set nm to name of menu item k of winMenu
						if nm is not missing value then
							click menu item k of winMenu
							exit repeat
						end if
					end repeat
				end tell
			end tell
		end try
		delay 0.6
	end repeat
	return false
end ensureWindow

on run argv
	if (count of argv) < 2 then error "pass the ordered list of tab-title substrings"

	if not ensureWindow() then return "ERROR no AX window"

	tell application "System Events"
		tell application process "ghostty"
			set names to {}
			repeat with i from 1 to (count of radio buttons of tab group 1 of window 1)
				set end of names to name of radio button i of tab group 1 of window 1
			end repeat
		end tell
	end tell

	set n to count of names
	if n is not (count of argv) then return "ERROR expected " & (count of argv) & " tabs, found " & n

	set badAt to 0
	repeat with i from 1 to n
		if not ((item i of names) contains (item i of argv)) then
			set badAt to i
			exit repeat
		end if
	end repeat
	if badAt is 0 then return "SORTED"

	set wanted to item badAt of argv
	set foundAt to 0
	repeat with k from badAt to n
		if (item k of names) contains wanted then
			set foundAt to k
			exit repeat
		end if
	end repeat
	if foundAt is 0 then return "ERROR no tab matching: " & wanted

	tell application "System Events"
		tell application process "ghostty"
			click radio button foundAt of tab group 1 of window 1
			delay 0.4
			key code 123 using {command down, control down, option down, shift down}
		end tell
	end tell

	return "MOVED " & wanted & " " & foundAt & " -> " & (foundAt - 1)
end run
