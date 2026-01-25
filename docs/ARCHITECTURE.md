# Jubo Architecture Documentation

> **Version**: 0.6.0
> **Last Updated**: January 25, 2026
> **Status**: Active Development

---

## 1. Overview

Jubo is a privacy-first, on-device AI assistant for iOS. It runs large language models (LLMs) locally using Apple's MLX framework, ensuring no user data leaves the device.

### Core Principles

1. **Privacy First**: All processing happens on-device. No cloud APIs for inference.
2. **Tool-Augmented**: Instead of complex agentic loops, we use discrete tools the model can invoke.
3. **Low Latency**: Single inference + tool execution. No multi-step reasoning chains.
4. **Battery Efficient**: Optimized for mobile with aggressive caching and minimal GPU usage.

### Tech Stack

| Component | Technology |
|-----------|------------|
| Platform | iOS 17+, macOS (development) |
| Language | Swift 5.9 |
| LLM Framework | MLX Swift |
| Models | SmolLM3 3B, Qwen2.5 3B, Llama 3.2 1B/3B |
| Project Generation | XcodeGen |
| Package Manager | Swift Package Manager |

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           UI Layer                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │  ChatView   │  │ SettingsView│  │  WebSearchIndicator     │  │
│  └──────┬──────┘  └─────────────┘  └───────────┬─────────────┘  │
│         │                                       │                │
└─────────┼───────────────────────────────────────┼────────────────┘
          │                                       │
          ▼                                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                        ViewModel Layer                           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    ChatViewModel                          │   │
│  │  - Manages conversation state                             │   │
│  │  - Coordinates between LLM and tools                      │   │
│  │  - Handles user input/output                              │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Service Layer                             │
│                                                                  │
│  ┌──────────────┐  ┌────────────────────┐  ┌─────────────────┐  │
│  │  LLMService  │  │WebSearchCoordinator│  │ AdaptivePrompt  │  │
│  │              │  │                    │  │    Builder      │  │
│  │ - MLX model  │  │ - Intent detection │  │                 │  │
│  │ - Inference  │  │ - Tool routing     │  │ - System prompt │  │
│  │ - Streaming  │  │ - Context building │  │ - User memory   │  │
│  └──────────────┘  └────────────────────┘  └─────────────────┘  │
│                              │                                   │
│         ┌────────────────────┼────────────────────┐             │
│         ▼                    ▼                    ▼             │
│  ┌─────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │   Sports    │  │    Weather      │  │     Calendar        │  │
│  │ Coordinator │  │  KitService     │  │     Service         │  │
│  └─────────────┘  └─────────────────┘  └─────────────────────┘  │
│         │                                                        │
│         ▼                                                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │    ESPN     │  │   (Future)  │  │   (Future)  │              │
│  │  Provider   │  │ WebProvider │  │ OtherAPIs   │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      External Services                           │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────────┐ │
│  │  ESPN API │  │WeatherKit │  │  EventKit │  │ Brave Search  │ │
│  │  (free)   │  │  (Apple)  │  │  (local)  │  │ (API key)     │ │
│  └───────────┘  └───────────┘  └───────────┘  └───────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Core Components

### 3.1 LLMService

**File**: `Jubo/Services/LLMService.swift`

The heart of the application. Manages on-device LLM inference using MLX Swift.

**Responsibilities**:
- Load and manage MLX model containers
- Stream token generation
- Handle chat sessions with context
- Inject tool results into prompts

**Key Features**:
- Async/await streaming API
- Session management for conversation continuity
- Memory-efficient token generation
- Configurable max tokens based on response type

```swift
// Usage example
for try await token in llmService.generate(
    messages: context,
    searchContext: toolResult,
    detailLevel: .brief
) {
    // Stream tokens to UI
}
```

### 3.2 WebSearchCoordinator

**File**: `Jubo/Services/WebSearch/WebSearchCoordinator.swift`

Central orchestrator for all external data fetching. Routes queries to appropriate tools.

**Responsibilities**:
- Detect query intent (weather, sports, calendar, reminders, general)
- Request user confirmation before external calls
- Route to appropriate service (WeatherKit, ESPN, EventKit, Brave)
- Format results as context for LLM

**Query Flow**:
```
User Query → Intent Detection → Confirmation UI → Tool Execution → LLM Context
```

**Supported Query Types**:
| Type | Service | Confirmation |
|------|---------|--------------|
| Weather | WeatherKit (fallback: Brave) | Yes |
| Sports | SportsCoordinator → ESPN | Yes |
| Calendar | EventKit | Yes |
| Reminders | EventKit | Yes |
| General | Brave Search | Yes |

### 3.3 SportsCoordinator (New Architecture)

**Files**: `Jubo/Services/Sports/`
- `SportsModels.swift` - Domain models
- `SportsDataProvider.swift` - Provider protocol
- `SportsCoordinator.swift` - Orchestration
- `SportsFormatter.swift` - LLM formatting
- `ESPNService.swift` - ESPN implementation

**Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│                    SportsFormatter                       │
│         (Converts domain model → LLM context)           │
└─────────────────────────────────────────────────────────┘
                           ▲
                           │
┌─────────────────────────────────────────────────────────┐
│              SportsResult (Domain Model)                 │
│     API-agnostic: games, league, status, scores         │
└─────────────────────────────────────────────────────────┘
                           ▲
          ┌────────────────┼────────────────┐
          │                │                │
┌─────────────────┐ ┌─────────────┐ ┌───────────────┐
│  ESPNProvider   │ │ WebProvider │ │ FutureProvider│
│  (priority: 10) │ │ (priority:50)│ │               │
└─────────────────┘ └─────────────┘ └───────────────┘
```

**Key Design Decisions**:
- **Provider Protocol**: All data sources implement `SportsDataProvider`
- **Priority-based Fallback**: Tries providers in order, falls back on failure
- **Centralized Formatting**: Single `SportsFormatter` for consistent LLM output
- **Caching**: 1-minute cache to reduce API calls

### 3.4 AdaptivePromptBuilder

**File**: `Jubo/Services/Memory/AdaptivePromptBuilder.swift`

Builds dynamic system prompts based on user context and preferences.

**Components**:
1. **Base Prompt**: Core instructions (anti-sycophancy, brevity, accuracy)
2. **Tool Definitions**: Available tools and when to use them
3. **User Preferences**: Location, units, custom context
4. **Learned Memory**: Facts about the user from past interactions
5. **Style Hints**: Adaptive adjustments based on interaction patterns

**Response Length Calibration**:
- ONE SENTENCE: Yes/no, factual lookups, simple math
- 2-3 SENTENCES: Definitions, recommendations
- LONGER: Explicit "explain", "compare", multi-part questions

### 3.5 CalendarService

**File**: `Jubo/Services/Calendar/CalendarService.swift`

EventKit integration for calendar and reminders.

**Capabilities**:
- Fetch today/tomorrow/week events
- Fetch specific date events
- View pending reminders
- Create new reminders

**Permission Handling**:
- Pre-checks permission status before confirmation UI
- Shows appropriate message if permission not granted
- Requests access on first use

### 3.6 WeatherKitService

**File**: `Jubo/Services/Weather/WeatherKitService.swift`

Apple WeatherKit integration for weather data.

**Features**:
- Geocoding location strings to coordinates
- Current conditions + 7-day forecast
- Availability check before fetching
- Fallback to web search if unavailable

**Requirements**:
- WeatherKit entitlement
- WeatherKit enabled in Apple Developer Portal

---

## 4. Data Flow

### 4.1 Chat Message Flow

```
┌─────────┐     ┌──────────────┐     ┌────────────────────┐
│  User   │────▶│ ChatViewModel│────▶│WebSearchCoordinator│
│ Message │     │              │     │                    │
└─────────┘     └──────────────┘     └────────────────────┘
                                              │
                      ┌───────────────────────┼───────────────────────┐
                      ▼                       ▼                       ▼
               ┌─────────────┐       ┌───────────────┐       ┌───────────────┐
               │IntentDetector│       │ConfirmationUI │       │  Tool Service │
               │              │       │               │       │               │
               │ weather?     │       │ "Get scores?" │       │ ESPN/Weather/ │
               │ sports?      │       │ [Yes] [No]    │       │ Calendar/etc  │
               │ calendar?    │       │               │       │               │
               └─────────────┘       └───────────────┘       └───────────────┘
                                                                     │
                                                                     ▼
                                                             ┌───────────────┐
                                                             │   Formatter   │
                                                             │               │
                                                             │ Tool result → │
                                                             │ LLM context   │
                                                             └───────────────┘
                                                                     │
                                                                     ▼
                                              ┌──────────────────────────────────┐
                                              │           LLMService              │
                                              │                                  │
                                              │  System Prompt + Tool Context    │
                                              │         + User Query             │
                                              │              │                   │
                                              │              ▼                   │
                                              │        MLX Inference             │
                                              │              │                   │
                                              │              ▼                   │
                                              │      Streamed Response           │
                                              └──────────────────────────────────┘
                                                                     │
                                                                     ▼
                                                             ┌───────────────┐
                                                             │   ChatView    │
                                                             │               │
                                                             │ Display to    │
                                                             │ user          │
                                                             └───────────────┘
```

### 4.2 Tool Invocation Flow

```
1. User asks: "What are the NBA scores?"
2. IntentDetector classifies: QueryType.sports
3. WebSearchCoordinator detects league: SportsLeague.nba
4. UI shows: "Get NBA scores?" [Yes] [No]
5. User confirms
6. SportsCoordinator.fetchScores(for: .nba)
   a. Try ESPNProvider (priority 10)
   b. If fails, try next provider
   c. Cache result
7. SportsFormatter.formatForLLM(result, query)
8. LLMService.generate(searchContext: formattedContext)
9. Stream response to UI
```

---

## 5. File Structure

```
Jubo/
├── JuboApp.swift                    # App entry point
├── Models/
│   └── Message.swift                # Chat message model
├── ViewModels/
│   └── ChatViewModel.swift          # Main view model
├── Views/
│   ├── ChatView.swift               # Main chat interface
│   ├── MessageView.swift            # Individual message
│   ├── SettingsView.swift           # User settings
│   └── WebSearchIndicator.swift     # Tool confirmation UI
├── Services/
│   ├── LLMService.swift             # MLX inference
│   ├── Calendar/
│   │   └── CalendarService.swift    # EventKit integration
│   ├── Memory/
│   │   ├── AdaptivePromptBuilder.swift
│   │   ├── UserMemory.swift
│   │   └── UserPreferences.swift
│   ├── Sports/
│   │   ├── SportsModels.swift       # Domain models
│   │   ├── SportsDataProvider.swift # Provider protocol
│   │   ├── SportsCoordinator.swift  # Orchestration
│   │   ├── SportsFormatter.swift    # LLM formatting
│   │   └── ESPNService.swift        # ESPN implementation
│   ├── Weather/
│   │   └── WeatherKitService.swift  # WeatherKit
│   └── WebSearch/
│       ├── WebSearchCoordinator.swift
│       ├── BraveSearchService.swift
│       └── IntentDetector.swift
└── Resources/
    └── Assets.xcassets

docs/
├── ARCHITECTURE.md                  # This file
├── ROADMAP.md                       # Development roadmap
├── TOOL_STRATEGY.md                 # Tool taxonomy
├── PROMPT_ENGINEERING_STRATEGY.md   # Prompt design
└── FINE_TUNING_ARCHITECTURE.md      # Future fine-tuning plans
```

---

## 6. Design Patterns

### 6.1 Repository Pattern (Sports)

The sports service uses the Repository pattern to abstract data sources:

```swift
protocol SportsDataProvider {
    var providerName: String { get }
    var priority: Int { get }
    func fetchScores(for league: SportsLeague) async throws -> SportsResult
    func supportsLeague(_ league: SportsLeague) -> Bool
}
```

**Benefits**:
- Swap providers without changing consumers
- Add new data sources easily
- Consistent error handling
- Testable with mock providers

### 6.2 Coordinator Pattern

`WebSearchCoordinator` acts as a coordinator, managing the flow between:
- Intent detection
- User confirmation
- Service invocation
- Result formatting

### 6.3 Actor Isolation

Services that manage state or make network calls use Swift actors:

```swift
actor ESPNService: SportsDataProvider { ... }
actor WeatherKitService { ... }
actor SportsCoordinator { ... }
```

**Benefits**:
- Thread-safe by default
- No manual locking needed
- Clear concurrency boundaries

### 6.4 Builder Pattern (Prompts)

`AdaptivePromptBuilder` constructs prompts by composing multiple sections:

```swift
func buildSystemPrompt() -> String {
    var sections: [String] = [basePrompt]
    sections.append(toolDefinitions)
    sections.append(buildPreferencesContext())
    sections.append(buildMemoryContext())
    sections.append(buildStyleHints())
    return sections.joined(separator: "\n\n")
}
```

---

## 7. Configuration

### 7.1 project.yml (XcodeGen)

Key settings:
```yaml
targets:
  Jubo:
    type: application
    platform: iOS
    entitlements:
      path: Jubo/Jubo.entitlements
      properties:
        com.apple.developer.weatherkit: true
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.jubo.ai
      INFOPLIST_KEY_NSCalendarsUsageDescription: "..."
      INFOPLIST_KEY_NSRemindersUsageDescription: "..."
```

### 7.2 Entitlements

**Required**:
- `com.apple.developer.weatherkit` - For WeatherKit API

**Not Required** (automatic):
- EventKit (Calendars/Reminders) - Just needs Info.plist descriptions

### 7.3 Info.plist Keys

```
NSCalendarsUsageDescription - Calendar access prompt
NSRemindersUsageDescription - Reminders access prompt
```

---

## 8. Error Handling

### 8.1 Error Types

| Service | Error Type | Handling |
|---------|------------|----------|
| Sports | `SportsError` | Fallback to next provider, then web search |
| Weather | `WeatherError` | Fallback to web search |
| Calendar | Permission denied | Show permission UI |
| LLM | `LLMServiceError` | Display to user |

### 8.2 Fallback Strategy

```
Primary Service → Alternative Provider → Web Search → Error Message
```

Example: Weather
1. Try WeatherKit
2. If unavailable/fails → Brave Search for "weather [location]"
3. If Brave fails → Show error

---

## 9. Performance Considerations

### 9.1 Memory Management

- Fresh LLM sessions for tool-augmented responses (prevents memory overflow)
- GPU synchronization before session creation
- Aggressive cache clearing

### 9.2 Battery Optimization

- 1-minute caching for API results
- User confirmation before network calls
- Minimal GPU wake-ups

### 9.3 Token Limits

| Response Type | Max Tokens |
|---------------|------------|
| Brief (factual) | 100 |
| Detailed | 200 |

---

## 10. Testing

### 10.1 Unit Testing

Mock providers for testing:
```swift
actor MockSportsProvider: SportsDataProvider {
    var providerName = "Mock"
    var priority = 1
    var mockResult: SportsResult?

    func fetchScores(for league: SportsLeague) async throws -> SportsResult {
        return mockResult ?? SportsResult(...)
    }
}
```

### 10.2 Integration Testing

Test on real device for:
- EventKit (requires real calendar)
- WeatherKit (requires entitlement + network)
- LLM inference (requires GPU)

---

## 11. Security Considerations

### 11.1 Data Privacy

- **No cloud inference**: All LLM processing on-device
- **No telemetry**: No usage data sent to servers
- **Local storage only**: Conversations stored in local Core Data

### 11.2 API Keys

- Brave Search API key stored in UserDefaults (could be improved with Keychain)
- No other API keys required (ESPN is free, WeatherKit uses entitlement)

### 11.3 Permissions

- Calendar/Reminders: Requested only when needed, with clear purpose
- Location: Not required (user sets location in preferences)

---

## 12. Future Architecture Considerations

### 12.1 Planned Improvements

1. **WebSportsProvider**: Fallback to web search for sports not supported by ESPN
2. **News Aggregation**: RSS/NewsAPI integration with similar provider pattern
3. **Push Notifications**: Morning briefings
4. **Siri Integration**: App Intents for voice commands

### 12.2 Potential Refactors

1. **Generic Tool Protocol**: Unify all tools under a common protocol
2. **Plugin Architecture**: Dynamic tool loading
3. **Keychain Storage**: Move API keys from UserDefaults to Keychain

---

*Document maintained by the Jubo development team. Last updated January 25, 2026.*
