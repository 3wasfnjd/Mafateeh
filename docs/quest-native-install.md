# Installing the Mafateeh APK on Meta Quest 3 (sideloading)

Downloading the APK only puts a file on your computer. To play, the APK must be **installed onto
the headset** over USB (or Wi-Fi ADB). This is developer sideloading: it is **not** a Meta Horizon
Store release and does not mean Meta has reviewed or approved the app.

## 1. Download and check the file

Download `mafateeh-quest-<version>-<build>.apk` from the repository's **Releases** page (or the
*Quest APK* workflow run's artifacts). Compare its SHA-256 with the value published next to it:

- macOS / Linux: `shasum -a 256 mafateeh-quest-*.apk`
- Windows (PowerShell): `Get-FileHash .\mafateeh-quest-*.apk -Algorithm SHA256`

## 2. Enable developer mode (once)

1. Sign in at developer.meta.com and create (or join) a developer organisation — a Meta account
   requirement for developer mode.
2. In the **Meta Horizon** phone app: *Devices* → your headset → *Headset settings* →
   *Developer mode* → on. Restart the headset if asked.

## 3. Install

Connect the headset to the computer with a USB-C data cable and put it on: accept **Allow USB
debugging** (tick *Always allow from this computer*). Then use one of:

- **Meta Quest Developer Hub** (Meta's desktop tool): select the device and drag the APK onto
  *Apps*, or use *Install APK*.
- **ADB** (Android platform-tools): `adb devices` (the headset should be listed), then
  `adb install -r mafateeh-quest-*.apk`.
- **SideQuest** (third-party desktop app): drag the APK onto its window.

## 4. Play

In the headset open **Library** → filter **Unknown sources** → **مفاتيح — Mafateeh**. The game starts
directly in mixed reality (passthrough) when available, otherwise in VR; switch in the settings panel.

On first launch Quest may ask to allow **spatial data**. Allowing it lets the game place the board on a
table you defined in *Space setup*. If you deny it, or there is no room data, the game uses manual
placement (hold the grip button to move the board) and says so.

## Controls

| Input | Action |
|---|---|
| Right thumbstick | Move the character (relative to where you look) |
| Left thumbstick ↔ / ↕ | Rotate / resize the miniature world |
| Trigger | Select: interact with puzzle objects, walk to a spot, push a crate; point at the character to put down a carried brick |
| Grip (tap) | Recenter / re-place the board (snaps to a detected table in mixed reality) |
| Grip (hold) | Drag the board |
| Left menu button ☰ | Menu: resume, restart, previous/next level, level list (every level reached so far), settings (sound: master/effects/ambience, mute; controls: smooth or 30° snap turning, turn speed, left-handed stick swap, vibration, show controller hints; display: mixed reality / VR, weather per level or always clear, board size/position, language Arabic / English, graphics high / balanced, studio intro on/off, reset progress), about |

At launch the studio name (عبودين قيمز — Aboden Games) floats in front of you for about four
seconds; press the trigger or ☰ to skip it, or turn it off under Settings → Display. The
interface follows the headset language (Arabic or English) until you pick one in the settings.

## Updating and uninstalling

- Builds signed with the repository's test key install over each other (`adb install -r`); local
  progress is kept.
- If you switch to a build signed with a different key, uninstall first
  (`adb uninstall com.abodengames.mafateeh`); this deletes local progress.
