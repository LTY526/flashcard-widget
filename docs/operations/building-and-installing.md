# Building and installing

[Documentation index](../README.md) | [Persistence and App Groups](../architecture/persistence-and-app-group.md)

## Xcode development install

1. Open flashcard-widget.xcodeproj.
2. Select the main flashcard-widget target and choose your Apple development
   team in Signing & Capabilities.
3. Select FlashcardWidgetExtension and choose the same team.
4. Confirm both targets contain the App Groups capability with
   group.com.xyz7172.flashcard-widget enabled.
5. Connect and trust the iPhone, select it as the run destination, and run the
   main app scheme.
6. If iOS asks, enable Developer Mode and trust the developer certificate.
7. Launch the app once before adding/configuring the Lock Screen widget.

Xcode builds, signs, installs, and launches both the app and embedded extension.
Running again refreshes the installation. If signing state is confused, remove
the app from the phone, let Xcode resolve packages/profiles, and run again; note
that removing the app may remove its local App Group data.

## Required signing relationship

The main app and extension have different bundle identifiers but must be signed
by compatible profiles that both authorize the same App Group. Check the target
capabilities rather than only reading the entitlement files.

## External or unsigned IPA workflow

scripts/build-unsigned-ipa.sh creates an archive suitable for an external
signer. The eventual signer must preserve and provision the shared App Group on
both executables. A successful installation alone does not prove this: iOS may
launch the app but reject access to the group container at runtime.

SideStore and similar services use different signing/provisioning constraints.
If the app reports groupContainerUnavailable after re-signing, the schedule and
widget cannot work until the installed profiles include a valid common group.

## Verification after install

1. Import a small deck and configure its fields.
2. Add the widget and select that deck.
3. Confirm three rows appear and tapping opens Deck Detail.
4. Tap Next in the app, wait for the debounce, and allow WidgetKit time to
   reload.
5. Pause the deck and confirm the widget no longer has advancing entries.
