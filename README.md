# Jubo - On-Device AI Assistant

A proof-of-concept iOS app that runs a small LLM (Llama 3.2 1B) entirely on-device using Apple's MLX framework.

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- iPhone 14 or later (6GB+ RAM) for testing
- iOS 17.0+

## Setup

### Option 1: Using XcodeGen (Recommended)

1. Install XcodeGen if not already installed:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   cd /Users/bnico/Documents/Jubo
   xcodegen generate
   ```

3. Open the generated project:
   ```bash
   open Jubo.xcodeproj
   ```

### Option 2: Manual Xcode Setup

1. Open Xcode and create a new iOS App project named "Jubo"
2. Set minimum deployment target to iOS 17.0
3. Add Swift Package dependencies:
   - `https://github.com/ml-explore/mlx-swift` (from 0.21.0)
   - `https://github.com/ml-explore/mlx-swift-examples` (branch: main)
4. Add products: `MLX`, `MLXLLM`, `MLXLMCommon`
5. Copy the Swift files from `Jubo/` into your project
6. Add the entitlements file and enable "Increased Memory Limit"

## Building

1. Select your physical iPhone as the build target (MLX requires Metal, no simulator)
2. Sign the app with your development team
3. Build and run (Cmd+R)

## First Run

1. The app will automatically start downloading the Llama 3.2 1B model (~700MB)
2. Wait for the download to complete (progress shown in UI)
3. Once loaded, you can start chatting!

## Architecture

```
Jubo/
├── JuboApp.swift           # App entry point
├── ContentView.swift       # Main navigation
├── Models/
│   └── Message.swift       # Chat message model
├── ViewModels/
│   └── ChatViewModel.swift # Chat state & logic
├── Views/
│   ├── ChatView.swift      # Main chat interface
│   ├── MessageBubble.swift # Message UI component
│   └── SettingsView.swift  # Settings & model info
└── Services/
    └── LLMService.swift    # MLX Swift LLM wrapper
```

## Features

- **Fully Offline**: No internet required after model download
- **Private**: All processing happens on-device
- **Streaming**: Token-by-token response display
- **Context**: Maintains last 10 messages for context

## Model

Uses `mlx-community/Llama-3.2-1B-Instruct-4bit`:
- 1 billion parameters
- 4-bit quantization (~700MB)
- Optimized for mobile devices

## Troubleshooting

### "Model not loaded" error
- Ensure you're running on a physical device, not simulator
- Check internet connection for initial model download
- Try clearing app data and reinstalling

### Slow generation
- First generation may be slower due to model warmup
- Ensure no other heavy apps are running
- Check Settings for tokens/second metric

### App crashes
- Verify device has 6GB+ RAM
- Close other memory-intensive apps
- Check that entitlements file is properly configured

## Next Steps (Beta Features)

- [ ] Chat history persistence
- [ ] Voice input (WhisperKit)
- [ ] GPU/Metal acceleration
- [ ] Larger model support for Pro devices
