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

local tickerWindow   = nil;
local scheduler      = {};      -- { {time=..., fn=...}, ... }
local localPlayer    = Turbine.Gameplay.LocalPlayer.GetInstance();
local myName         = localPlayer:GetName();
if FEATURES.displayLog then
	Log(string.format(L.LogWatching, tostring(myName)));
end
local pollStarted    = nil;

local inFellowship    = false;
local leaderName      = nil;
local memberCount     = 0;
local assistTargetCount = nil;

local amLeader        = false;

local reminderWindow  = nil;
local conditionMet    = false;
local shownForFormation = false;

local function ScheduleOnce(delay, fn)
	scheduler[#scheduler + 1] = { time = Turbine.Engine.GetGameTime() + delay, fn = fn };
end

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

local function SnapshotParty()
	-- Force LOTRO to behave:
	local party = localPlayer:GetParty();
	if (party == nil) then return; end
	local partyMembers = {}
	for i = 1, memberCount do
		partyMembers[i] = party:GetMember(i);
	end
	-- End Force LOTRO to behave

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

	inFellowship = true;
	party = nil;
end

function ShouldRemind(state)
	if state.amLeader and state.memberCount >= 2 then
		return state.assistTargetCount ~= nil and state.assistTargetCount == 0;
	end
	return false;
end

local function HandleCondition(remind)
	if remind and not conditionMet then
		if FEATURES.reShowOnClear or not shownForFormation then
			shownForFormation = true;
			if reminderWindow ~= nil then
				reminderWindow:Show();
			end
		end
	elseif not remind then
		if not inFellowship then
			shownForFormation = false;
		end
		if reminderWindow ~= nil and reminderWindow:IsVisible() then
			reminderWindow:Dismiss();
		end
	end
	conditionMet = remind;
end

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

local function PollLoop()
	ScheduleOnce(FEATURES.pollInterval, PollLoop);
	PollState();
end

local function OnLoad(args)
	if FEATURES.displayLog then
		Log(L.LogLoaded);
	end

	reminderWindow = AssistReminderReminderWindow();

	tickerWindow = Turbine.UI.Window();
	tickerWindow:SetSize(1, 1);
	tickerWindow:SetOpacity(0);
	tickerWindow:SetVisible(true);
	tickerWindow:SetMouseVisible(false);
	tickerWindow:SetWantsUpdates(true);
	tickerWindow.Update = function(sender, args)
		RunScheduler();
		if myName ~= nil and pollStarted == nil then
			pollStarted = true;
			ScheduleOnce(FEATURES.pollInterval, PollLoop);
		end
	end
end

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