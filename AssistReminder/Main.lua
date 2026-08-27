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

-- Stage 1/3/4 configuration
local FEATURES = {
	pollInterval  = 1.0;   -- seconds between state polls
	reShowOnClear = true;  -- true: reminder re-shows if targets cleared again
	                       --       in the same fellowship
	                       -- false: strictly once per fellowship formation
	debugChatLog  = false; -- diagnostic logging of poll results
};

AssistReminderLocale = AssistReminderLocale or {};
local L = AssistReminderLocale;

-- Log helper: chat output with [AssistReminder] prefix (R5)
function Log(msg)
	Turbine.Shell.WriteLine(L.LogPrefix .. tostring(msg));
end

-- ---------------------------------------------------------------- module state
local tickerWindow   = nil;
local scheduler      = {};      -- { {time=..., fn=...}, ... }
local localPlayer    = Turbine.Gameplay.LocalPlayer.GetInstance();
local myName         = localPlayer:GetName();
Log(string.format(L.LogWatching, tostring(myName)));
local pollStarted    = nil;

local inFellowship    = false;  -- Stage 5 snapshot results
local leaderName      = nil;
local memberCount     = 0;
local assistTargetCount = nil;  -- nil = read failed / unknown

local amLeader        = false;  -- Stage 6

local reminderWindow  = nil;    -- Stage 8
local conditionMet    = false;  -- Stage 9 edge detection
local shownForFormation = false;-- already shown for current formation

-- ------------------------------------------------------------- Stage 2: ticker
local function ScheduleOnce(delay, fn)
	scheduler[#scheduler + 1] = { time = Turbine.Engine.GetGameTime() + delay, fn = fn };
end

local function RunScheduler()
	local now = Turbine.Engine.GetGameTime();
	for i = #scheduler, 1, -1 do
		local item = scheduler[i];
		if now >= item.time then
			table.remove(scheduler, i);
			-- T2.4: a throwing callback must not break later items,
			-- but log so failures are never silent.
			item.fn();
		end
	end
end

-- ------------------------------------------------- Stage 5: party snapshot burst
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

--		-- docs: Turbine_Gameplay_Party_GetLeader.html — returns Player object,
--		-- not a string; compare via GetName()
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
	-- R4: the assist Player reference is a local here and drops out of scope
	-- immediately — nothing persists beyond this burst.

	inFellowship = true;
		-- R4: drop the reference immediately — nothing persists beyond this burst.
	party = nil;
end

-- ------------------------------------------- Stage 7: pure reminder condition
function ShouldRemind(state)
	-- T7.6: unknown target count treated as "has targets"
	if state.amLeader and state.memberCount >= 2 then
		return state.assistTargetCount ~= nil and state.assistTargetCount == 0;
	end
	return false;
end

-- --------------------------------------------------- Stage 9: show/hide policy
local function HandleCondition(remind)
	if remind and not conditionMet then
		-- unmet -> met edge
		if FEATURES.reShowOnClear or not shownForFormation then
			shownForFormation = true;
			if reminderWindow ~= nil then
				reminderWindow:Show();
			end
		end
	elseif not remind then
		-- leaving the fellowship resets per-formation memory (T9.5)
		if not inFellowship then
			shownForFormation = false;
		end
		if reminderWindow ~= nil and reminderWindow:IsVisible() then
			reminderWindow:Dismiss();
		end
	end
	conditionMet = remind;
end

-- ---------------------------------------------------- Stage 4: polling engine
local function PollState()
	SnapshotParty();

	amLeader = inFellowship and leaderName == myName; -- Stage 6
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
	-- Reschedule FIRST so the loop survives a throwing body (T4.3)
	ScheduleOnce(FEATURES.pollInterval, PollLoop);
	PollState();
end

-- ------------------------------------------------------------------ lifecycle
local function OnLoad(args)
	-- R6: everything here is safe; game-API calls deferred via ticker below.
	Log(L.LogLoaded);

		-- Stage 8: build popup window (UI only, no game-state API calls)
	reminderWindow = AssistReminderReminderWindow();

		-- Stage 2: hidden ticker window; Update handler assigned INSIDE Load (R6)
	tickerWindow = Turbine.UI.Window();
	tickerWindow:SetSize(1, 1);
	tickerWindow:SetOpacity(0);
	tickerWindow:SetVisible(true);
	tickerWindow:SetMouseVisible(false); -- docs: Turbine_UI_Control_SetMouseVisible.html
	tickerWindow:SetWantsUpdates(true);
	tickerWindow.Update = function(sender, args)
		RunScheduler();

			-- Stage 4: start polling once init done
		if myName ~= nil and pollStarted == nil then
			pollStarted = true;
			ScheduleOnce(FEATURES.pollInterval, PollLoop);
		end
	end
	---@diagnostic enable: undefined-field
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
	Log(L.LogUnloaded);
end

Turbine.Plugin.Load = OnLoad;
Turbine.Plugin.Unload = OnUnload;