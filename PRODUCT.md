# DR3 Mobile

A local macOS/iOS native port for the user's verified Diablo III Eternal Collection Switch build. The current iOS test device is iPhone Air; the UIKit target also includes iPad. Product copy is Chinese first with English fallback.

## Current work

On Mac, use a native AppKit startup window adapted from the iOS launcher: NSWindow, NSBox groups, segmented mode selection, native checkboxes, an explicit Play action and persistent preferences. Show when an independent test save is selected. Apply settings before executing the guest host.

The player chooses normal 16:9 or native widescreen, Metal HUD, MetalFX Spatial, and local Wi-Fi multiplayer before starting the game. Save these preferences for the next launch. Start the game only after valid private game resources and a choice are available. Preserve the user's save and existing touch/controller behavior.

## Interface references

Inherit the current Bayonetta3 Mobile native launcher's two-column UIKit settings layout and semantic light/dark colors. Touch controls inherit D2R Mobile revision 9393b00's generic matte joystick and thin round socket artwork, retaining D3's actual A/B/X/Y bindings. Do not substitute unrelated class icons or imply dynamic skill icons.

## Rendering and network truth

The selected Air widescreen profile renders 1920×720 with expanded horizontal camera view. MetalFX Spatial targets 2560×960; normal mode targets 2560×1440. Device rendering and performance must be verified separately from build or simulator UI results. Local multiplayer uses a native LAN transport and Bonjour discovery; actual two-device gameplay requires an end-to-end test. Battle.net and mesh are outside this request's implementation.

## Constraints

No redistributed game assets or keys. Keep private resources and runtime evidence in ignored work/. No shader translation chain change for these features. Test screenshots from a UI-only simulator fixture demonstrate layout only. Keep the native system settings vocabulary, readable text, accessible controls and safe areas; preserve the full-screen game view and input geometry.
