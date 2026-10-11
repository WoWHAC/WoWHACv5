# WoWHACv5 addon | Compatibility with ConRO, Hekili, MaxDps, HeroRotation, AethysRotation, Ovale, Synaptic, JustAC, BetterAssistant
Addon for World of Warcraft that encrypts the recommended ability to click into a pixel for further reading by external software
https://wowhac.fun/

World of Warcraft Forever beta (Interface `16001`) is supported by the separate
`16001JustAC.zip` release package, which includes JustAC `5.9.0-beta2`. The existing
`1200JustAC.zip` package remains available for Retail.

To install on Forever, extract the `JustAC` and `WoWHACv5` folders from
`16001JustAC.zip` into the client's `Interface/AddOns` directory, then enable both
addons. Use the release archive: `prebuilds/16001JustAC.zip` is a packaging template
and does not contain the current WoWHACv5 source until the release build runs.

The release workflow overlays `src` onto each packaging template. For the Forever
package only, it appends `16001` to the packaged WoWHACv5 TOC's Interface list
(`120000, 16001` with the current source); the shared
source TOC and all existing package templates retain their current interfaces.
