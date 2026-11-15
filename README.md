# WoWHACv5 addon | Compatibility with ConRO, Hekili, MaxDps, HeroRotation, AethysRotation, Ovale, Synaptic, JustAC, BetterAssistant
Addon for World of Warcraft that encrypts the recommended ability to click into a pixel for further reading by external software
https://wowhac.fun/

## Versioning

`VERSION` is the source of the addon's SemVer version. After changing it, run
`python scripts/sync_version.py` to regenerate the TOC version, or use `--check`
to verify that they agree. Release builds run the same generator and tag the
release as `v<VERSION>`.

## Provider selection and priority actions

These controls are available only on **Retail Midnight or later** (mainline
interface `120000` or newer) and **WoW Forever** (identified by
`WOW_PROJECT_CAMELOT`). Other clients retain the original automatic provider
startup and pixel pipeline. They do not initialize the minimap menu, language
settings, priority editor, conditions, or priority overlays, and ignore saved
modern provider/language/priority preferences without deleting them.

Click the WoWHACv5 gear icon on the minimap, or enter `/wowhac`, to choose a
rotation provider. The menu lists supported addons enabled for this character,
plus **Assisted Combat (Blizzard)** when its native API is available. The choice
persists across reloads. If it disappears, selection falls back to the first
available provider in the `Providers` file order of `src/WoWHACv5.toc`.
Providers can be switched outside combat. Drag the minimap icon to move it.

Open **Settings...** from the minimap menu to choose **Automatic**, **Русский**,
or **English**. Automatic follows the WoW interface language: Russian for
`ruRU`, English for other locales. The preference is saved across reloads;
manual changes update open menus, labels, condition arguments, and help without
discarding unfinished input. Settings remain available when no provider is loaded
and defer opening until combat ends.

**Show recommendation icon** in Settings toggles a single action icon with its
hotkey, enabled by default. Hold **Shift** and drag it to move; its position and
visibility are saved. It displays the eligible priority action above the selected
provider's suggestion, using the same native alpha gates as the priority pixels.
When no action is recommended it is empty; holding Shift reveals a placement
preview. This display is available on the same Midnight/Forever clients as the
other new controls.

Choose **Priority actions...** for any provider. Drag spells from the spellbook
or items from bags into the shared action area. Priority runs left to right,
then down; a translucent preview marks insertion while dragging. Existing
entries move instead of duplicating. The selected provider is always the last
action, with its addon icon when available. It cannot be moved, disabled, or
removed. The trailing **+** opens a Spell/Item ID dialog and inserts before
the provider. This gray tile also accepts drops and uses a larger plus sign.
The editor stays open above the spellbook. Its fixed provider displays the
provider icon, including Blizzard's Assisted Combat icon when available.

The conditions panel docks to the right of the editor at the same height and
moves with it. Close the panel independently, or close the editor to close both.
Entering combat hides the editor and its dialogs; leaving combat restores the
windows that were open, including unfinished condition input. An attempt to open
the editor in combat is deferred until combat ends.

Click an action to edit its conditions. All conditions must pass. Available
rules include player combat, a living hostile target, health, primary
resource, aura presence/absence, range, activation glow, an interruptible target cast/channel,
repeat delay, usage limits, enemies in range, and mounted state. Actions require
a valid key binding. Ordinary actions also require readiness and usability,
and wait until your own cast or channel ends. Spells with the Interrupt condition
use a separate readiness check: the current hostile target must be casting or
channeling an interruptible spell, and the interrupt's remaining cooldown must
be below 200 ms. A missing cooldown object means ready. The implicit range check
blocks an out-of-range result but allows an unknown result; an explicitly enabled
In range condition remains strict. Interrupt spells skip the general usability
and player-casting checks. They read the current target on every update, including
when it was already casting before you selected it. No enemy count is required
unless you add that condition. New entries start with player-combat and action-range conditions.
Each condition appears as a checkbox, name, and inline arguments. Hover the
circled **?** after its name for an explanation and examples. Check a rule
to use it, or uncheck it to exclude it; unchecked arguments remain available
while editing. Uncheck all rules for an unconditional action when ready and
usable. Conditions and list changes apply immediately. Closing the panel does
not undo changes. While a number is empty or invalid, that condition retains
its last valid settings and other conditions remain editable. A new condition
with invalid arguments takes effect once they are valid.

The conditions footer links to **Rotation Builder**. Click its name to open a
selected Discord invite URL and copy it with **Ctrl+C**. The link follows the
addon's language: Russian or English, including a manual language override.

**Aura (unstabile)** checks a buff or debuff by its exact aura spell ID on
Player, Pet, Mouseover, or Target. Choose **Present** or **Absent**; auras from
any caster count. The aura ID can differ from the spell used to apply it.
This experimental condition checks presence only, without stacks or duration.
The unit must exist and be visible to the client. Restricted, private, or
unavailable data blocks both modes, so a hidden aura never counts as absent.
Clients with only the player-aura lookup support Player only.

The master checkbox enables user actions; the provider continues underneath.
Uncheck individual actions to retain them without using them. Remove via the
small close button or right-click. Profiles remain separate by character and
specialization; previous offensive-cooldown entries migrate with their order
and enabled flags preserved. Spell and item IDs are separate namespaces.

Each action has preallocated layers over the two existing data pixels. Its
binding color is fixed; condition frames control only alpha, and frame order
selects the highest eligible action. Calibration pixels are unchanged. Native
secret-capable alpha APIs consume restricted values directly, without reading
rendered alpha or converting those values into ordinary Lua decisions.
Unsupported or unknown condition data keeps the affected action transparent,
except for the interrupt cooldown and implicit range cases described above.
Enemy target uses separate native alpha gates for target existence, being alive,
and attackability. These combine with Interrupt and other enabled conditions
through the same AND chain.

Bindings come from standard action bars, recognized macros, and direct
spell/item bindings. Full binding scans and layer changes happen outside combat.
During combat, action-bar and binding updates revalidate each existing mapping;
unchanged actions remain available. Only changed or unreadable mappings are
hidden, and they recover if the original mapping becomes valid again. New
bindings and profile edits take effect after combat. The provider remains
available while priority layers await a safe refresh. Priority actions can run
without an active provider, and a provider failure does not invalidate them.

Usage limits count confirmed cast/channel/empower starts or instant successes
once per attempt, including interrupted casts that already began. The window
is rolling; an event exactly at its boundary still counts. Per-target limits
require readable target identity. Repeat delay counts successful casts only.
Usage history resets with a profile/provider change, world entry, or rule edit.
Enemy counting deduplicates target/boss/nameplate units and filters engagement
and action range. Decreases are immediate; increases are confirmed over time.
Uncertain observations may establish a minimum, but never an exact or maximum
count. Some conditions can therefore remain unavailable during restricted
combat observations on a particular client.

Aura reads use Blizzard's spell-ID lookup and current per-spell secrecy check.
The [aura API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua)
can return no data for a restricted aura; the
[secret predicate API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua)
is checked before interpreting a missing result. The condition updates through
the existing priority refresh loop and does not infer auras from timers or
read back rendered alpha.

JustAC's own fallback still uses interrupt, emergency group healing,
low-health defense, tank maintenance, then rotation. User actions now run above
the entire provider rather than inside JustAC's queue.
These additions also follow the client restriction above. Older clients keep
JustAC's interrupt, low-health defense, then rotation sequence.

## WoW Forever

World of Warcraft Forever beta (Interface `16001`) has separate release packages:

- `16001Hekili.zip` includes Hekili Forever `v0.8.2`, its shared content, and all
  nine class modules. The supplied beta has no default Warlock priority.
- `16001JustAC.zip` includes JustAC `5.9.0-beta2`.

To install on Forever, extract all addon folders from the chosen release archive
into the client's `Interface/AddOns` directory and enable WoWHACv5 and the chosen
rotation addon. For Hekili, keep `Hekili_Shared` and the `Hekili_<Class>` folders
installed and enabled; Hekili loads the relevant content on demand. Select the
provider through the WoWHACv5 minimap menu or `/wowhac`.

Use the release archives: `prebuilds/16001Hekili.zip` and
`prebuilds/16001JustAC.zip` are packaging templates and do not contain the current
WoWHACv5 source until the release build runs. Existing Retail packages remain
available unchanged.

The release workflow overlays `src` onto each packaging template. For the Forever
packages only, it appends `16001` to the packaged WoWHACv5 TOC's Interface list
(`120000, 16001` with the current source); the shared
source TOC and all existing package templates retain their current interfaces.
