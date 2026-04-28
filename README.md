# AskBar

A native macOS menu-bar AI assistant. Summon a floating bar from anywhere with **⌘⇧Space**, type or speak, and get streaming responses from Claude, ChatGPT, Groq, Gemini, OpenRouter, or NVIDIA. Includes a **Meeting Mode** that listens to call audio (Zoom, Google Meet, Teams, Webex, Safari, Chrome) and replies inline as the other speaker talks.

## Download

**[⬇︎ Download AskBar.dmg (latest)](https://github.com/aryankinha/AskBar/releases/latest/download/AskBar.dmg)**

All releases: <https://github.com/aryankinha/AskBar/releases>

> The DMG is **ad-hoc signed**, not notarized. macOS will block it on first launch with a Gatekeeper warning. To open it:
>
> 1. Drag **AskBar.app** to **Applications**.
> 2. Right-click **AskBar.app** → **Open** → **Open** in the dialog. *(Required only the first time.)*
>
> Or from a terminal: `xattr -dr com.apple.quarantine /Applications/AskBar.app`

## Features

- Lives in the menu bar — no Dock icon
- Global hotkey: **⌘⇧Space** from any app (uses Carbon API — no Accessibility permission needed)
- Voice session shortcut: **⌘⇧V** opens AskBar and starts dictation
- Floating, draggable bar (remembers position; auto-recovers if dragged off-screen)
- Type **or** speak (built-in `SFSpeechRecognizer`, auto-stop on silence, auto-send on stop)
- 6 providers: Claude, OpenAI, Groq, Gemini, OpenRouter, NVIDIA — with per-provider model picker
- Streaming token-by-token responses
- **Meeting Mode**: captures system audio from call apps via `ScreenCaptureKit`, transcribes it, and replies to each utterance inline in a unified chat thread. Optional auto-suggest on a timer.
- All conversation in one scrolling thread (you / AI / them / auto-suggestions)

## Requirements

- macOS 14.0+
- Xcode 15+

## Build

Open `AskBar.xcodeproj` in Xcode and press ⌘R, or:

```bash
xcodebuild -project AskBar.xcodeproj -scheme AskBar -configuration Release build
```

## Package as DMG

```bash
./build_dmg.sh
```

Uses only macOS built-ins (`xcodebuild` + `hdiutil`). The DMG is written to `build/AskBar.dmg`.

## First-launch permissions

1. **Microphone** + **Speech Recognition** — prompted the first time you tap the mic. Approve both.
2. **Screen & System Audio Recording** — prompted the first time you enable Meeting Mode.
   - System Settings → Privacy & Security → **Screen & System Audio Recording** → enable AskBar.
   - macOS will ask you to relaunch AskBar after enabling.

> The hotkey uses the Carbon API and does **not** require Accessibility permission.
## Configure API keys

1. Click the **sparkle** icon in the menu bar → **Settings…**
2. Open the **API Keys** tab.
3. Paste your key for any/all of:
   - Claude — https://console.anthropic.com/
   - OpenAI — https://platform.openai.com/api-keys
   - Groq — https://console.groq.com/keys
   - Gemini — https://aistudio.google.com/app/apikey
   - OpenRouter — https://openrouter.ai/keys
   - NVIDIA — https://build.nvidia.com/

Keys are stored in `UserDefaults` under `apiKey_<provider>`.

## Usage

- **⌘⇧Space** — toggle the bar
- **⌘⇧V** — open the bar and immediately start dictation
- **Return** — send the query
- **Esc** — hide the bar
- **Mic button** — dictate (auto-stops on silence, auto-sends after stop)
- **Person-wave pill** — open Meeting Mode controls (listen, auto-respond per utterance, auto-suggest on a timer)
- Drag the bar to reposition; the position is remembered

## Releasing a new build

```bash
./build_dmg.sh
gh release create v1.0 --title "AskBar v1.0" --generate-notes build/AskBar.dmg
```

The `Download` link in this README always points at `releases/latest/download/AskBar.dmg`, so it auto-updates with each release.
