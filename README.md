# AskBar

A native macOS menu-bar AI assistant. Summon a floating bar from anywhere with **⌘⇧Space**, type or speak, and get streaming responses from Claude, ChatGPT, Groq, Gemini, or OpenRouter.

## Features

- Lives in the menu bar — no Dock icon
- Global hotkey: **⌘⇧Space** from any app
- Floating, draggable bar (remembers position)
- Type **or** speak (built-in Speech recognition)
- Pick a provider per-query
- Streaming token-by-token responses
- Settings panel for API keys

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
brew install create-dmg     # one-time
./build_dmg.sh
```

The DMG is written to `build/AskBar.dmg`.

## First-launch permissions

1. **Accessibility** (required for the global hotkey)
   - System Settings → Privacy & Security → **Accessibility** → enable AskBar.
   - Without this, ⌘⇧Space will not work.
2. **Microphone** + **Speech Recognition** (required for voice input)
   - macOS will prompt the first time you tap the mic button. Approve both.

## Configure API keys

1. Click the **sparkle** icon in the menu bar → **Settings…**
2. Open the **API Keys** tab.
3. Paste your key for any/all of:
   - Claude — https://console.anthropic.com/
   - OpenAI — https://platform.openai.com/api-keys
   - Groq — https://console.groq.com/keys
   - Gemini — https://aistudio.google.com/app/apikey
   - OpenRouter — https://openrouter.ai/keys

Keys are stored in `UserDefaults` under `apiKey_<provider>`.

## Usage

- **⌘⇧Space** — toggle the bar
- **Return** — send the query
- **Esc** — hide the bar
- **Mic button** — start/stop voice input (transcript fills the input field)
- Drag the bar to reposition; the position is remembered
