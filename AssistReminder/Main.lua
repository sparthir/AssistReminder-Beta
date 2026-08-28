--[[ Main.lua — entry point for AssistReminder.
	Implements spec Stages 1–9. Polling only (R1), no slash commands (R2),
	 read-only party bursts with nothing persisted (R4), all API calls
	no game-API work inside Plugin.Load (R6). ]]--

import "Turbine";
import "Turbine.Gameplay"; -- LocalPlayer / Party APIs

-- Import support files explicitly (do NOT rely on __init__.lua auto-loading).
-- Order matters: strings first, then UI class.
import "Sparthir.AssistReminder.Locale";
import "Sparthir.AssistReminder.ReminderWindow";

-- Configuration features - tweak these to suit.
local FEATURES = {
	pollInterval  = 1.0;   -- seconds between state polls
	reShowOnClear = true;  -- true: reminder re-shows if targets cleared again
						   --       in the same fellowship
						   -- false: strictly once per fellowship formation
	debugChatLog  = false; -- diagnostic logging of poll results
	displayLog	  = false; -- display basic logging info
};

AssistReminderLocale = AssistReminderLocale or {};
local L = AssistReminderLocale;

-- Log helper: chat output with [AssistReminder] prefix (R5)
function Log(msg)
	Turbine.Shell.WriteLine(L.LogPrefix .. tostring(msg));
end

-- Globals used by the reminder state machine:
-- tickerWindow   : invisible 1x1 window whose Update() tick drives the scheduler
-- scheduler      : pending one-shot callbacks, each { time = <game time>, fn = <callable> }
-- localPlayer    : cached LocalPlayer instance (obtained once at load, not per-poll)
-- myName         : cached player name for cheap leader comparisons
-- pollStarted    : flag so the poll loop only starts once (first Update tick)
local tickerWindow   = nil;
local scheduler      = {};      -- { {time=..., fn=...}, ... }
local localPlayer    = Turbine.Gameplay.LocalPlayer.GetInstance();
local myName         = localPlayer:GetName();
if FEATURES.displayLog then
	Log(string.format(L.LogWatching, tostring(myName)));
end
local pollStarted    = nil;

-- Cached snapshot of the last poll (used by HandleCondition + debug logging):
local inFellowship    = false;   -- is the player currently in a fellowship?
local leaderName      = nil;     -- name of the current fellowship leader, if any
local memberCount     = 0;       -- number of fellowship members
local assistTargetCount = nil;   -- 0 = no assist target, 1 = at least one target

local amLeader        = false;   -- am I the fellowship leader this poll?

-- UI + reminder-lifecycle state:
local reminderWindow  = nil;         -- the popup window (created on load)
local conditionMet    = false;       -- was the remind condition true last poll?
local shownForFormation = false;     -- have we already shown for this fellowship formation?

-- Schedule a one-shot callback after `delay` seconds (game time).
-- Callbacks fire from RunScheduler(), driven by the ticker window's Update.
local function ScheduleOnce(delay, fn)
	scheduler[#scheduler + 1] = { time = Turbine.Engine.GetGameTime() + delay, fn = fn };
end

-- Run all scheduler callbacks whose time has come.
-- Iterates backwards because table.remove() shifts later indices down;
-- iterating from the end keeps pending (not-yet-due) items indexed correctly.
local function RunScheduler()
	local now = Turbine.Engine.GetGameTime();
	for i = #scheduler, 1, -1 do
		local item = scheduler[i];
		if now >= item.time then
			table.remove(scheduler, i);
			item.fn();
		end
	end
end

-- Read the current fellowship state from the game API into the cached
-- snapshot variables (inFellowship, leaderName, memberCount, assistTargetCount).
local function SnapshotParty()
	-- Force LOTRO to behave:
	-- Touching the party + members once up front seems to be required before
	-- the assist-target reads return valid data (client quirk workaround).
	local party = localPlayer:GetParty();
	if (party == nil) then return; end
	local partyMembers = {}
	for i = 1, memberCount do
		partyMembers[i] = party:GetMember(i);
	end
	-- End Force LOTRO to behave

	-- Reset the snapshot; it is rebuilt below. If any API read fails or the
	-- player is not in a fellowship, these defaults are what remains.
	inFellowship = false;
	leaderName = nil;
	memberCount = 0;
	assistTargetCount = nil;

	-- docs: Turbine_Gameplay_Party_GetLeader.html — returns Player object,
	-- not a string; compare via GetName()
	local leader = party:GetLeader();
		if leader ~= nil then
			leaderName = leader:GetName();
		end

	memberCount = party:GetMemberCount();

	-- KNOWN CLIENT BUG: Party:GetAssistTargetCount() CTDs the game client
	-- whenever zero assist targets are set (which is exactly the state this
	-- plugin polls for). Workaround: probe GetAssistTarget(1) instead —
	-- it returns nil when no assist target exists and does not crash.
	-- We only need "some target" vs "no target", so 0/1 is sufficient.
	assistTargetCount = 0;
	local assist = party:GetAssistTarget(1);
	if assist ~= nil then
		assistTargetCount = 1;
	end
	--assistTargetCount = party:GetAssistTargetCount(); -- API bug CTD with 0 assist targets

	-- All reads succeeded, so we have a valid fellowship snapshot.
	inFellowship = true;
	party = nil;
end

-- Decide whether the reminder should currently be shown.
-- Only the fellowship leader (in a real fellowship of 2+ members) with zero
-- assist targets set should be reminded.
function ShouldRemind(state)
	if state.amLeader and state.memberCount >= 2 then
		return state.assistTargetCount ~= nil and state.assistTargetCount == 0;
	end
	return false;
end

-- Show or hide the reminder window based on the condition, honouring the
-- reShowOnClear / shownForFormation rules, and reset state when it clears.
local function HandleCondition(remind)
	if remind and not conditionMet then
		-- Condition just became true. Show the popup unless it was already
		-- shown for this formation and reShowOnClear is disabled.
		if FEATURES.reShowOnClear or not shownForFormation then
			shownForFormation = true;
			if reminderWindow ~= nil then
				reminderWindow:Show();
			end
		end
	elseif not remind then
		-- Condition is false: reset the once-per-formation flag if we left
		-- the fellowship entirely, and hide the popup if it is showing.
		if not inFellowship then
			shownForFormation = false;
		end
		if reminderWindow ~= nil and reminderWindow:IsVisible() then
			reminderWindow:Dismiss();
		end
	end
	conditionMet = remind;
end

-- One poll cycle: snapshot the party, evaluate the remind condition,
-- optionally log it, then update the reminder window accordingly.
local function PollState()
	SnapshotParty();

	amLeader = inFellowship and leaderName == myName;
	local remind = ShouldRemind({
		amLeader = amLeader;
		memberCount = memberCount;
		assistTargetCount = assistTargetCount;
	});

	if FEATURES.debugChatLog then
		Log(string.format(L.LogDebugFmt,
			tostring(inFellowship),
			tostring(leaderName),
			tostring(memberCount),
			tostring(assistTargetCount),
			tostring(amLeader),
			tostring(remind)));
	end

	HandleCondition(remind);
end

-- Self-rescheduling poll loop: schedules the next run first (so a slow or
-- erroring poll can't stop future polls), then performs this cycle's work.
local function PollLoop()
	ScheduleOnce(FEATURES.pollInterval, PollLoop);
	PollState();
end

-- Plugin load handler: create the reminder window, then set up an invisible
-- 1x1 "ticker" window whose Update() drives the scheduler and starts polling.
local function OnLoad(args)
	if FEATURES.displayLog then
		Log(L.LogLoaded);
	end

	reminderWindow = AssistReminderReminderWindow();

	tickerWindow = Turbine.UI.Window();
	-- An invisible 1x1 window used purely as an Update() tick source
	-- (the only reliable way to get periodic callbacks in LOTRO plugins).
	tickerWindow:SetSize(1, 1);
	tickerWindow:SetOpacity(0);
	tickerWindow:SetVisible(true);
	tickerWindow:SetMouseVisible(false);
	tickerWindow:SetWantsUpdates(true);
	tickerWindow.Update = function(sender, args)
		-- Fire any due scheduled callbacks...
		RunScheduler();
		-- ...and kick off the poll loop exactly once, but only once we know
		-- the player's name (myName is nil during early client startup).
		if myName ~= nil and pollStarted == nil then
			pollStarted = true;
			ScheduleOnce(FEATURES.pollInterval, PollLoop);
		end
	end
end

-- Plugin unload handler: stop the ticker, drop all scheduled callbacks,
-- and hide/destroy the reminder window.
local function OnUnload(args)
	if tickerWindow ~= nil then
		tickerWindow:SetWantsUpdates(false);
		tickerWindow.Update = nil;
		tickerWindow:SetVisible(false);
		tickerWindow = nil;
	end
	scheduler = {};
	pollStarted = nil;
	if reminderWindow ~= nil then
		reminderWindow:SetVisible(false);
		reminderWindow = nil;
	end
	if FEATURES.displayLog then
		Log(L.LogUnloaded);
	end
end

Turbine.Plugin.Load = OnLoad;
Turbine.Plugin.Unload = OnUnload;