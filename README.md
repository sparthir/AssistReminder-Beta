# Assist Reminder

A plugin for **The Lord of the Rings Online** by Sparthir.

## What it does

Assist Reminder watches your fellowship while you are the **leader**, and pops
up a reminder window if **no assist target** has been set.

Coordinated fellowship play works best when everyone attacks the same foe. The
assist target is how a leader tells the fellowship which
enemy to focus on — but it is easy to forget to set one when the fight starts.
This plugin notices the moment leadership is yours, the fellowship has 2+ members,
and no assist target is set, and reminds you so the group never focuses its damage appropriately.

- Polls the game's party API once per second — nothing persisted, no chat spam.
- Reminds **only the leader**; other members see nothing.
- Shows once per fellowship formation by default, or re-shows whenever the
  assist target is cleared again (configurable — see *Configuration*).
- Dismiss via the **OK** button or the **Escape** key.
- The window can be freely moved and stays quiet until it is actually needed.

## Installation

1. Download/copy the plugin folder into your LOTRO plugins directory, so the
   path looks like:

   ```
   <Documents>\The Lord of the Rings Online\Plugins\Sparthir\AssistReminder\
   ```

2. In game load it from the Plugin Manager .

## How to use it

1. Load the plugin (see above). It starts watching quietly — there are no
   slash commands to learn.
2. Form (or be in) a fellowship of two or more players.
3. If you are the leader and no assist target is set, a reminder window
   appears in the centre of the screen.
4. Set an assist target — the window disappears on the next poll.
5. Click **OK** (or press **Escape**) to dismiss the window if you set the
   target while it was showing.

That's it.

## Configuration

Open `AssistReminder\Main.lua` and edit the `FEATURES` table near the top:

| Setting         | Default | Description |
|-----------------|---------|-------------|
| `pollInterval`  | `1.0`   | Seconds between fellowship-state polls. Lower = faster reaction, slightly more overhead. |
| `reShowOnClear` | `true`  | `true`: the reminder re-appears if the assist target is cleared again in the same fellowship. `false`: strictly once per fellowship formation. |
| `debugChatLog`  | `false` | `true`: Prints a line to chat each poll with the raw fellowship state (for troubleshooting). |
| `displayLog`    | `false` | `true`: Prints basic load/unload info messages to chat. |

## Known issues

> ⚠️ **This plugin is BETA and still in development.**

There are no known issues however this plugin hasn't been tested in full.  For example I've only tested it with a small Raid configuration of 3 players.  It works but I don't know if there are any bugs with larger Fellowships or Raids.

## Fair warning

If you don't like the use of coding AIs, then this isn't for you. I'm not that
familiar with Lua, and I've used a coding AI to help me write this plugin.

## Feedback

Bugs and suggestions welcome — open an issue or pull request on GitHub:
[AsssistReminder-Beta](https://github.com/sparthir/AssistReminder-Beta.git)
