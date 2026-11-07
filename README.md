# Buzzer

A small macOS menu-bar app for a timeBuzzer knob (`USB 0x04d8` / `0xf300`, Ideas In Logic). It listens for **press**, **turn right**, and **turn left**, runs the actions you assign, and paints the three RGB rings.

The official timeBuzzer app owns those gestures while it is running. Quit it before using Buzzer.

## What you can bind

Each gesture can run any mix of:

- a keystroke, with Command, Option, Control, and Shift
- a media key: volume up, volume down, mute, play/pause
- an LED color
- a shell command (`zsh -lc`)
- a URL

Defaults, once you have learned the knob:

| Gesture | Action |
| --- | --- |
| Press | Play / pause |
| Turn right | Volume up |
| Turn left | Volume down |

Nothing is sent for a gesture until you press **Learn** and perform it. The learn step stores the MIDI message your unit actually emits. LED traffic on channel 12, CC 70–78, is ignored so painting the rings does not count as a turn.

## Run it on your Mac

You need macOS 13 or later and Xcode (the app is SwiftUI).

```bash
./scripts/package-app.sh
open Buzzer.app
```

The menu-bar dial opens the controls again after you close the window. Quit from that menu.

Grant **Accessibility** when you want keystrokes or media keys. System Settings → Privacy & Security → Accessibility → Buzzer. Each rebuild is ad-hoc signed, so macOS may ask again after `package-app.sh`.

Launch at login only works from the packaged `Buzzer.app`, not from `swift run`.

Settings are stored in `~/Library/Application Support/BuzzerMac/config.json`.

## Teach the knob

1. Plug in the buzzer and approve the USB accessory if macOS asks.
2. Quit timeBuzzer.
3. In **MIDI port**, leave Automatic, or pick the port if Automatic does not connect. The name is often `timeBuzzer` or something with Ideas in it.
4. Press **Learn** next to Press, then press the knob once. Repeat for turn right and turn left, one click each.
5. The MIDI log shows every incoming packet. If learn captures the wrong bytes, press **Forget** and try again.

**Match any value on this control** treats every value on that status and controller as the gesture. Use it only when one direction sends many different values. If left and right share a controller and differ only by the third byte (often `01` vs `7F`), leave the box off.

## Lights

The color controls send MIDI control change on **channel 12**:

| Ring | Controllers |
| --- | --- |
| 1 | CC 70 red, 71 green, 72 blue |
| 2 | CC 73–75 |
| 3 | CC 76–78 |

Values are 0–127 (half of 0–255). **Send** paints immediately. The swatches are Warm, Red, Green, Blue, and Off.

## Try the protocol without the app window

```bash
swift run BuzzerMac --cli led FF8800
swift run BuzzerMac --cli led 00FF00 1
swift run BuzzerMac --cli parse "F8 90 3C 7F"
```

`swift test` checks the LED bytes, the learn/decode rules, config saving, and a scripted knob: learn press and both turns, ignore LED echoes, debounce a double press, and fire the default actions. No device required.

```bash
swift test
swift run BuzzerMac --cli simulate
```

On your Mac, with the buzzer plugged in and the official app quit:

1. `./scripts/package-app.sh && open Buzzer.app`
2. Confirm the MIDI log prints a line when you press and when you turn each way.
3. Learn all three gestures. Press should show one learned line, not an LED packet (`BB 46`–`BB 4E`).
4. Press and turn again and confirm the default actions: play/pause, volume up, volume down. Allow Accessibility if those keys do nothing.
5. Pick a color and press **Send**. The rings should change. The log should show outgoing `BB 46`…`BB 4E` packets.

## Inject

The hex field under the log can replay a packet as if the knob sent it (**As input**) or write it to the device (**Send**). Example: `BB 46 40`.

## Limits

- Knob messages are not published by timeBuzzer. Learn is the mapping.
- Shell actions run as your user. A command can do anything your account can do.
- This does not talk to the timeBuzzer cloud or replace the tile UI.
