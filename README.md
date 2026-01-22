# Jubo - Privacy-First On-Device AI Assistant

<p align="center">
  <img src="Jubo/Assets.xcassets/AppIcon.appiconset/icon_1024.png" width="128" height="128" alt="Jubo App Icon">
</p>

A native iOS/macOS AI assistant that runs small language models entirely on-device using Apple's MLX framework. No cloud, no data collection, fully private.

## Features

### Core AI
- **100% On-Device LLM** - Runs SmolLM3 3B, Qwen2.5 3B, or Llama 3.2 1B locally via MLX
- **Streaming Responses** - Token-by-token display for real-time feedback
- **Adaptive Memory** - Learns your preferences and interaction patterns
- **Multi-Conversation** - Persistent chat history with SwiftData

### Smart Data Integration
- **Weather** - Real-time weather via Apple WeatherKit (with Brave Search fallback)
- **Calendar** - Access your schedule via EventKit
- **Reminders** - View and manage tasks via EventKit
- **Live Sports** - Real-time scores from ESPN API (Champions League, NBA, NFL, etc.)
- **Web Search** - Optional Brave Search integration for current information

### Privacy-First Design
- All AI processing happens on-device
- No data sent to external servers (except optional web search)
- PII detection and sanitization before any external API calls
- User confirmation required before external requests

## Requirements

- **macOS** 14.0+ (Sonoma)
- **iOS** 17.0+
- **Xcode** 15.0+
- **Device** iPhone 12 or later (6GB+ RAM recommended)
- **Storage** ~1GB for model download

## Quick Start

### 1. Clone & Generate Project

```bash
git clone https://github.com/yourusername/jubo.git
cd jubo

# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open project
open Jubo.xcodeproj
```

### 2. Configure Signing

1. Open Jubo.xcodeproj in Xcode
2. Select the Jubo target → Signing & Capabilities
3. Select your development team
4. Ensure these capabilities are enabled:
   - WeatherKit
   - (Calendars and Reminders are requested at runtime)

### 3. Build & Run

1. Connect a physical iPhone (Metal required - no Simulator support)
2. Select your device as the build target
3. Build and run (Cmd+R)
4. Wait for the model to download (~700MB on first run)

## Configuration

### Web Search (Optional)

Jubo can optionally use Brave Search for current information:

1. Get a free API key at [brave.com/search/api](https://brave.com/search/api/) (2,000 queries/month free)
2. In the app: Settings → Web Search → Enter API Key

### User Preferences

In Settings, you can configure:
- **Location** - For local weather, sports teams, and news context
- **Temperature Unit** - Celsius or Fahrenheit
- **Time Format** - 12-hour or 24-hour
- **Custom Context** - Additional info for the AI (e.g., "I'm a software developer")

## Architecture

```
Jubo/
├── JuboApp.swift                    # App entry point, SwiftData setup
├── ContentView.swift                # Navigation (conversation list ↔ chat)
│
├── Models/
│   ├── Message.swift                # Chat message model
│   └── Conversation.swift           # Conversation persistence (SwiftData)
│
├── ViewModels/
│   └── ChatViewModel.swift          # Chat state, message flow, orchestration
│
├── Views/
│   ├── ChatView.swift               # Main chat interface
│   ├── ConversationListView.swift   # Conversation management
│   ├── MessageBubble.swift          # Message display component
│   ├── SettingsView.swift           # App settings
│   ├── WebSearchIndicator.swift     # Search status UI
│   ├── LocationSearchView.swift     # Location picker
│   └── LearnedMemoriesView.swift    # Memory visualization
│
└── Services/
    ├── LLMService.swift             # MLX model loading & inference
    ├── UserPreferences.swift        # User settings (UserDefaults)
    │
    ├── Memory/
    │   ├── UserMemory.swift         # Learned facts & patterns
    │   ├── MemoryExtractor.swift    # Preference extraction
    │   └── AdaptivePromptBuilder.swift  # Dynamic system prompts
    │
    ├── Weather/
    │   └── WeatherKitService.swift  # Apple WeatherKit integration
    │
    ├── Calendar/
    │   └── CalendarService.swift    # EventKit (calendar + reminders)
    │
    ├── Sports/
    │   └── ESPNService.swift        # Live sports scores
    │
    └── WebSearch/
        ├── WebSearchCoordinator.swift   # Search orchestration
        ├── BraveSearchService.swift     # Brave Search API
        ├── IntentDetector.swift         # Query classification
        ├── QuerySanitizer.swift         # PII removal
        └── SearchContextFormatter.swift # Result formatting
```

## Model Options

Jubo tries models in this order (automatic fallback):

| Model | Size | Quality | Speed |
|-------|------|---------|-------|
| SmolLM3 3B | ~1.5GB | Best | Medium |
| Qwen2.5 3B | ~1.5GB | Great | Medium |
| Llama 3.2 1B | ~700MB | Good | Fast |

All models use 4-bit quantization for efficient mobile inference.

## Data Flow

```
User Query
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  Intent Detection (on-device LLM)                           │
│  "Does this need external data?"                            │
└─────────────────────────────────────────────────────────────┘
    │
    ├─── Weather ──────► WeatherKit (free) ──► Brave fallback
    ├─── Calendar ─────► EventKit (native)
    ├─── Reminders ────► EventKit (native)
    ├─── Sports ───────► ESPN API (free)
    └─── General ──────► Brave Search (optional, needs API key)
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  User Confirmation (if external request)                    │
│  "Get weather for Boston?"  [Yes] [No]                     │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  LLM Response Generation (on-device)                        │
│  Context = User Query + External Data + Learned Preferences │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
Streaming Response to User
```

## Privacy & Data

| Data Type | Storage | Sent Externally? |
|-----------|---------|------------------|
| Conversations | On-device (SwiftData) | Never |
| User Preferences | On-device (UserDefaults) | Never |
| Learned Memories | On-device (UserDefaults) | Never |
| LLM Model | On-device | Never |
| Weather Queries | - | Apple WeatherKit only |
| Web Searches | - | Brave Search only (if enabled) |
| Sports Queries | - | ESPN public API |

All external requests require explicit user confirmation.

## Troubleshooting

### "Model not loaded" error
- Must run on physical device (Simulator not supported)
- Ensure internet connection for initial model download
- Check device has 6GB+ RAM

### Slow generation
- First generation is slower (model warmup)
- Close memory-intensive background apps
- Check tokens/second in Settings

### WeatherKit not working
- Ensure WeatherKit is enabled in Apple Developer Portal
- App must be registered in App Store Connect
- Try restarting device (WeatherDaemon can get stuck)
- Brave Search fallback will be used automatically

### GPU crashes
- Ensure device isn't overheating
- Close other apps using Metal/GPU
- Try restarting the app

## Building for Release

```bash
# Generate project
xcodegen generate

# Archive (or use Xcode: Product → Archive)
xcodebuild archive \
  -scheme Jubo \
  -archivePath ./build/Jubo.xcarchive \
  -destination "generic/platform=iOS"

# Export for App Store / TestFlight
xcodebuild -exportArchive \
  -archivePath ./build/Jubo.xcarchive \
  -exportPath ./build \
  -exportOptionsPlist ExportOptions.plist
```

## Tech Stack

- **UI**: SwiftUI
- **Data**: SwiftData
- **ML**: MLX Swift (Apple's machine learning framework)
- **Weather**: WeatherKit
- **Calendar/Reminders**: EventKit
- **Sports**: ESPN API
- **Web Search**: Brave Search API

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [MLX Swift](https://github.com/ml-explore/mlx-swift) - Apple's ML framework
- [MLX Community](https://huggingface.co/mlx-community) - Quantized models
- [Brave Search](https://brave.com/search/api/) - Privacy-focused search API
- [ESPN](https://www.espn.com/) - Sports data API
