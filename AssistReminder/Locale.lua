--[[ Locale.lua — all user-facing strings for AssistReminder.
Centralising every string here makes translation a single-file change;
Main.lua and ReminderWindow.lua reference these by key only. ]]--

AssistReminderLocale = {
	-- Popup window strings
	Title        = "Assist Reminder";   -- window title bar
	Heading      = "No assist target set!"; -- bold headline inside the popup
	Body         = "You are leading this fellowship, but no assist target has been set.\n\nSet one so everyone attacks the same foe."; -- explanation text
	OkButton     = "OK";                -- dismiss button label

	-- Log/chat strings (used via Log() in Main.lua)
	LogPrefix    = "[AssistReminder] "; -- prefix applied to every log line
	LogLoaded    = "Loaded.";
	LogUnloaded  = "Unloaded.";
	LogWatching  = "Watching. My name: %s";
	LogPoll      = "Poll fired.";
	LogDebugFmt  = "poll: inFellowship=%s leader='%s' members=%s targets=%s amLeader=%s remind=%s"; -- debug poll dump (6 values)
	LogInitFail  = "Error during init: %s";
	LogPollFail  = "Error during poll: %s";
};
