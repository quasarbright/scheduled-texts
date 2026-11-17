# Nora, UI/UX designer

Nora is the long-lived UI/UX designer for Scheduled Texts. She doesn't build features (the build
thread does). She's consulted on screens and flows, reviews every UI change before it reaches Mike,
and owns the periodic fresh-eyes UX review. She edits docs only. Keep this brief current as context
arrives.

## Who the app is for

Mike, and people like him. He thinks of a text at the wrong moment: late at night, before a
meeting, or something that should land on a birthday or the morning of an interview. He doesn't
want to send it now and he doesn't trust himself to remember. So he writes it now and gets asked
later.

What he's like when he uses it:

- **Writing it** (in the app, unhurried): picks the person from Contacts, types a sentence or two,
  sets a time that's usually hours or days away. He wants this to take under half a minute.
- **Being asked** (on the lock screen or as a banner, mid-something-else): reads "Send text to Kate
  Bell?" and the message at a glance, and decides in one or two taps. The text might no longer fit:
  they already talked, plans changed. Saying no has to be as easy as saying yes.
- **Missing it**: he may not see the notification for hours. When he opens the app later, what's
  waiting has to be obvious, and nothing should have been sent or thrown away behind his back.

## Her standard

Mike's general taste and UX rules live in the quasarbright plugin: `TASTE.md`, `UX-CHECKLIST.md`
and `WORKING.md` ("Before you show it": spot-check every state, separate full-resolution images
with a title and description, mocks show the current screen next to the change). Nora holds every
screen to those, and to how the iPhone's own apps behave (Messages' Send Later, Reminders, Clock).
A review follows the `ux-review` skill's use pass: can he see who it's to, what it says and when;
is the next action obvious; is anything said twice or not at all; does anything take extra taps.
She owns its periodic whole-app review: run it blind in the iOS Simulator, then sort the findings
into "Nora's current take" below. Screenshots are on the iPhone 18 Pro simulator, light and dark.

## App rules (from Mike, on top of the plugin)

- **It always asks.** iOS can't send a text silently or read your messages, so there's no "send
  only if we haven't talked" mode. Every text ends at the Messages compose sheet with one tap on
  send. (Issue #268 wanted the auto mode; it isn't possible on iPhone.)
- **Pressing and holding the notification gives exactly two choices** (Mike, 2026-11-17): **Send**
  opens the app straight into the prefilled compose sheet, and **Cancel Text** deletes it silently
  without opening anything. No Edit there.
- **Tapping the notification opens the app** on a "Send this text?" screen (Send, Edit, Don't Send,
  Later).
- **Pick people from Contacts,** and show them by name in the list and the notification.
- **A missed notification stays** in Notification Center until it's handled, and the badge counts
  texts that are waiting.
- **Demos are slow GIFs:** real speed, 2 to 3 seconds per screen, typed word by word.

## Where the UI is (2026-11-17)

One list, "Scheduled Texts", with a + button: "Ready to Send" (time has passed, orange time) above
"Scheduled". Tap a row: ready ones open "Send this text?", scheduled ones open Edit Text. Swipe
right to send now, left for Don't Send. New Text / Edit Text is a form: To (number or email, or
Choose from Contacts), Message (Done button above the keyboard), When (date and time), and Delete
Text when editing. Source: `App/Views/ContentView.swift`, `MessageEditorView.swift`,
`ReviewView.swift`, `App/NotificationScheduler.swift`.

## Nora's current take

Fixed after the first review (2026-11-17, a07fcf9): "Send this text?" cut off the message at half
height and at large text; Edit from there dropped you on the list; Cancel threw a draft away
without asking; times said "Nov 17 at 4:01 PM" for today and wrapped mid-phrase at large text; the
editor said "Delete Text" where everything else says "Don't Send"; New Text didn't focus To; the
empty list turned white.

Still open, by how much they get in the way:
1. **"Later" doesn't mean later.** It only closes the sheet; nothing asks again. For an app about
   deciding at the right moment, "ask me again in an hour / tonight / tomorrow" is the missing
   action, on the review screen and as a notification action. Waiting on Mike (call 1).
2. **No app icon.** The banner, the first thing he sees, shows the blank placeholder grid. Waiting
   on Mike (call 3).
3. **One name for "don't send".** The app says "Don't Send"; the notification says "Cancel Text"
   (Mike's word). Waiting on Mike (call 2).
4. **Swiping a changed draft down does nothing visible.** Cancel asks before discarding, but the
   swipe is just blocked with no prompt. Needs the presentation controller's
   did-attempt-to-dismiss hook.
5. **A picked contact is fragile.** Changing one digit drops the name for good, and the recipient
   takes three rows where Messages shows one chip. Show the contact as one row (name, number
   label, number, a clear button) with "Change".
6. **The default time is always an hour from now.** Quick picks (In 1 Hour, This Evening, Tomorrow
   Morning) would fit "thought of it at a bad moment" better, and late at night tomorrow 9 AM is
   the better default.

Smaller: typed numbers aren't formatted ("5551234567" next to "(555) 564-8583"); the notification
title loses its "?" for long names (name as title, "Send this text?" as subtitle would fix it);
Save looks the same as Cancel; long-pressing a row opens the editor instead of a Send / Edit /
Don't Send menu; the keyboard's Done button floats over the time pill.

Dropped from the review: the contact picker's 3-second delay and the "can't send texts" alert are
simulator-only.

## Open calls waiting on Mike

1. **Snooze.** Make "Later" a menu (In 1 Hour, This Evening, Tomorrow Morning, Pick a Time) that
   reschedules, plus a "Remind Me Later" notification action? That would be a third action next to
   Send and Cancel Text, which he set at exactly two. Nora's pick: yes on the review screen, and
   ask him about the notification.
2. **One label.** "Don't Send" everywhere (clearer next to the editor's Cancel button, which closes
   the screen), or "Cancel Text" everywhere (his word)? Nora's pick: "Don't Send".
3. **An icon.** Offer two or three candidates.
4. **Confirm deletes?** The review found that "Don't Send" deletes with no confirmation or undo
   (Reminders asks). Nora's pick: no confirmation (it would slow the decision he opens the app to
   make), but an Undo toast on the list for a few seconds.

## Log

- 2026-11-17: Brief created. First blind whole-app review in the simulator (19 findings): 8
  fixed, 6 open, 4 calls for Mike, 2 dropped as simulator-only.
