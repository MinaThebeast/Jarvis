# J.A.R.V.I.S — Just A Rather Very Intelligent System

> *"At your service, sir."*

A fully native macOS AI assistant inspired by Iron Man's JARVIS — with a futuristic full-screen HUD, voice activation, and powered by OpenAI GPT-4o.

---

## Features

- **Wake Word Detection** — Say *"Hey JARVIS"*, *"Wake up JARVIS"*, or *"OK JARVIS"* to activate
- **Natural Voice Conversation** — Speaks and listens using OpenAI's GPT-4o + TTS
- **Full-Screen HUD** — Iron Man style animated interface with arc reactor, hex grid, waveform, and status rings
- **Apple Native** — Built with Swift + SwiftUI, AVFoundation, and Apple Speech framework
- **Secure Key Storage** — API key stored in macOS Keychain, never transmitted elsewhere
- **Conversation Memory** — Maintains context across multiple exchanges

---

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS       | 13 Ventura or later |
| Xcode       | 15+ |
| Swift       | 5.9+ |
| OpenAI Key  | Any GPT-4o-capable key |

---

## Quick Start

### 1. Clone / Open the project

Open `Package.swift` in **Xcode** (double-click it or use File → Open):

```bash
open "/Users/thebeastmini1/Desktop/Jarvis V1.0.3/Package.swift"
```

### 2. Grant Permissions (first run)

macOS will prompt you for:
- **Microphone access** — required for voice input
- **Speech Recognition** — required for wake word detection

Grant both in **System Settings → Privacy & Security**.

### 3. Add your OpenAI API Key

On first launch, JARVIS will display the setup screen. Enter your OpenAI API key (starts with `sk-`). It will be saved securely to the macOS Keychain.

Alternatively, set the environment variable before running:

```bash
export OPENAI_API_KEY=sk-your-key-here
```

### 4. Build & Run

In Xcode: **Product → Run** (`⌘R`)

Or from the terminal:

```bash
cd "/Users/thebeastmini1/Desktop/Jarvis V1.0.3"
swift run
```

Or use the desktop **Start JARVIS** shortcut, which rebuilds and opens `Jarvis.app` when sources have changed.

---

## Packaging

JARVIS ships as a signed **`Jarvis.app`** bundle in the project root. The launcher runs `scripts/package-app.sh`, which:

1. Builds a release binary (`swift build -c release`)
2. Assembles `Jarvis.app` with `Contents/MacOS/Jarvis`, `Contents/Info.plist`, and `Contents/Resources/`
3. Ad-hoc code-signs the bundle with a stable identifier (`com.stark.jarvis`)

macOS TCC (Accessibility, Screen Recording, Automation, Microphone, Speech Recognition) binds permissions to that bundle identity. Because the identifier stays the same across rebuilds, grants persist instead of resetting every time you recompile.

To build the app manually:

```bash
./scripts/package-app.sh
open Jarvis.app
```

---

## Wake Words

| Say...             | Effect                   |
|--------------------|--------------------------|
| "Hey JARVIS"       | Wake + wait for command  |
| "Wake up JARVIS"   | Wake + wait for command  |
| "OK JARVIS"        | Wake + wait for command  |
| "Hey JARVIS, ..."  | Wake + immediate command |

After the wake word, speak your command naturally. JARVIS will respond after ~1.8 seconds of silence.

---

## Project Structure

```
Sources/Jarvis/
├── JarvisApp.swift               — @main App entry point
├── AppDelegate.swift             — Full-screen + window setup
├── JarvisConfig.swift            — Wake words, model settings
├── KeychainHelper.swift          — Secure API key storage
├── Services/
│   ├── JarvisStorage.swift       — Application Support directory helper
│   ├── ConversationStore.swift   — Persistent chat history (conversation.json)
│   ├── MemoryStore.swift         — Long-term fact memory (memory.json)
│   ├── VoiceStore.swift          — Persisted TTS voice preference (voice.json)
│   ├── ActionAuditLog.swift      — OS action audit trail (actions.log)
│   ├── ActionSafety.swift        — Thread-safe kill-switch for action tools
│   ├── OpenAIService.swift       — GPT-4o chat + TTS + Whisper + tool calling + vision
│   ├── ScreenCaptureService.swift — Full-screen and active-window capture for vision tools
│   ├── SpeechRecognitionService.swift — Wake word + live transcription
│   ├── AudioPlaybackService.swift     — TTS audio playback + levels
│   └── Tools/
│       ├── Tool.swift            — JarvisTool protocol + ToolRegistry
│       ├── GetTimeTool.swift     — Example tool: current date/time
│       ├── RememberFactTool.swift — Store a durable fact in memory
│       ├── RecallFactsTool.swift — Search and retrieve stored facts
│       ├── SeeScreenTool.swift   — Capture full screen and answer vision questions
│       ├── SeeActiveWindowTool.swift — Capture active window and answer vision questions
│       ├── AppControlTool.swift  — Open, activate, or quit applications
│       ├── AppleScriptTool.swift — Execute AppleScript for OS automation
│       └── SetVoiceTool.swift    — Switch TTS voice (female/male)
├── Models/
│   ├── Message.swift             — Chat message model
│   └── JarvisPhase.swift         — App state enum + color palette
├── ViewModels/
│   └── JarvisViewModel.swift     — Main coordinator (state machine + agent loop)
└── Views/
    ├── ContentView.swift         — Root (Setup ↔ HUD router)
    ├── HUDView.swift             — Full-screen Iron Man HUD
    ├── BackgroundView.swift      — Hex grid + scanline background
    ├── ArcReactorView.swift      — Animated central arc reactor
    ├── WaveformView.swift        — Circular + linear audio waveform
    ├── StatusRingsView.swift     — Outer rotating rings + corner brackets
    ├── ParticleFieldView.swift   — Ambient floating particles
    ├── ConversationView.swift    — Chat history + live transcript
    └── SetupView.swift           — First-run API key configuration
```

---

## Configuration

Edit `Sources/Jarvis/JarvisConfig.swift` to tweak:

| Setting | Default | Description |
|---------|---------|-------------|
| `wakeWords` | `["hey jarvis", ...]` | Phrases that activate JARVIS |
| `silenceThresholdSeconds` | `1.8` | Pause before finalizing command |
| `defaultTtsVoiceKey` | `"female"` | Default spoken voice profile |
| `maxContextMessages` | `12` | Conversation memory length |

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `⌘Q` | Quit JARVIS |
| `⌃⌘F` | Toggle full screen |

---

## Troubleshooting

**Microphone not working?**  
→ System Settings → Privacy & Security → Microphone → Enable for Jarvis

**Speech Recognition not detecting wake word?**  
→ System Settings → Privacy & Security → Speech Recognition → Enable for Jarvis  
→ Speak clearly, at a normal pace, ~0.5m from microphone

**Vision / screen tools not working?**  
→ System Settings → Privacy & Security → Screen Recording → Enable for Jarvis  
→ Required for `see_screen` and `see_active_window` to capture the display

**OS control / AppleScript tools not working?**  
→ System Settings → Privacy & Security → Automation → Allow Jarvis to control other apps  
→ macOS prompts on first AppleScript or app-control action  
→ Say **"Jarvis stop"** or **"stop stop"** anytime to abort running actions

**API errors?**  
→ Verify your OpenAI API key has GPT-4o and TTS access  
→ Check your OpenAI account has available credits

---

*Built with Swift + SwiftUI · Powered by OpenAI · Inspired by Tony Stark*
