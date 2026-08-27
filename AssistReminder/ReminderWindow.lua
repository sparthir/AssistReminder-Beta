--[[ ReminderWindow.lua — popup reminder UI (Stage 8) ]]--

import "Turbine.UI";
import "Turbine.UI.Lotro";

-- NOTE: class() is provided by the Turbine Lua runtime at load time; it has
-- no declaration in the lotro-api EmmyLua stubs, hence the suppression.
---@diagnostic disable-next-line: undefined-global
AssistReminderReminderWindow = class(Turbine.UI.Lotro.Window);

function AssistReminderReminderWindow:Constructor()
	Turbine.UI.Lotro.Window.Constructor(self);

	self:SetText(AssistReminderLocale.Title);
	self:SetSize(360, 200);
	self:SetPosition(
		(Turbine.UI.Display.GetWidth() - self:GetWidth()) / 2,
		(Turbine.UI.Display.GetHeight() - self:GetHeight()) / 2);
	self:SetOpacity(1);

	self:SetWantsKeyEvents(true);

	self.heading = Turbine.UI.Label();
	self.heading:SetParent(self);
	self.heading:SetText(AssistReminderLocale.Heading);
	self.heading:SetFont(Turbine.UI.Lotro.Font.Verdana16);
	self.heading:SetForeColor(Turbine.UI.Color(0.9, 0.8, 0.2));
	self.heading:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
	self.heading:SetPosition(20, 45);
	self.heading:SetSize(320, 24);

	self.body = Turbine.UI.Label();
	self.body:SetParent(self);
	self.body:SetText(AssistReminderLocale.Body);
	self.body:SetFont(Turbine.UI.Lotro.Font.Verdana14);
	self.body:SetForeColor(Turbine.UI.Color(0.85, 0.85, 0.85));
	self.body:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
	self.body:SetMultiline(true);
	self.body:SetPosition(20, 75);
	self.body:SetSize(320, 70);

	self.okButton = Turbine.UI.Lotro.Button();
	self.okButton:SetParent(self);
	self.okButton:SetText(AssistReminderLocale.OkButton);
	self.okButton:SetSize(80, 26);
	self.okButton:SetPosition((self:GetWidth() - 80) / 2, 150);

	-- optional callback invoked on dismissal
	self.onDismiss = nil;

	self.okButton.Click = function(sender, args)
		self:Dismiss();
	end;

	self.KeyDown = function(sender, args)
		-- Documented KeyDown args fields are Action / Alt / Control / Shift
		-- (there is no args.Key). On KeyDown, args.Action carries the
		-- Windows virtual-key code; Escape = VK 0x1B (27).
		if args.Action == 27 then
			self:Dismiss();
		end
	end;
end

function AssistReminderReminderWindow:SetOnDismiss(fn)
	self.onDismiss = fn;
end

function AssistReminderReminderWindow:Show()
	self:SetVisible(true);
	self:Activate();
end

function AssistReminderReminderWindow:Dismiss()
	self:SetVisible(false);
	if self.onDismiss ~= nil then
		self.onDismiss();
	end
end
