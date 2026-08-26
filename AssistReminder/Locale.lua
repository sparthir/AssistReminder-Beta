--[[ Locale.lua — all user-facing strings for AssistReminder ]]--

AssistReminderLocale = {
	Title        = "Assist Reminder";
	Heading      = "No assist target set!";
	Body         = "You are leading this fellowship, but no assist target has been set.\n\nSet one so everyone attacks the same foe.";
	OkButton     = "OK";

	LogPrefix    = "[AssistReminder] ";
	LogLoaded    = "Loaded.";
	LogUnloaded  = "Unloaded.";
	LogWatching  = "Watching. My name: %s";
	LogPoll      = "Poll fired.";
	LogDebugFmt  = "poll: inFellowship=%s leader='%s' members=%s targets=%s amLeader=%s remind=%s";
	LogInitFail  = "Error during init: %s";
	LogPollFail  = "Error during poll: %s";
};
