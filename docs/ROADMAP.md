# Jubo Development Roadmap

> **Version**: 0.6.0
> **Last Updated**: January 25, 2026
> **Status**: Active Development

---

## Current Version: 0.6.0

### What's Included
- On-device LLM inference (MLX Swift)
- Sports scores via ESPN (refactored architecture)
- Weather via WeatherKit (with web search fallback)
- Calendar & Reminders via EventKit
- Web search via Brave API
- Adaptive prompt building
- User memory and preferences

---

## Short-Term Roadmap (v0.7 - v0.9)

### v0.7 - Sports & Stability
**Target**: 2 weeks

| Task | Priority | Status | Notes |
|------|----------|--------|-------|
| WebSportsProvider | High | Not Started | Fallback to web search for unsupported leagues |
| Model output quality | High | In Progress | 3B model strips information from formatted context |
| Fine-tune prompt instructions | High | In Progress | Improve model compliance with formatting |
| WeatherKit reliability | Medium | Done | Added availability check, fallback to web |
| Sports formatting | Medium | Done | Refactored to provider pattern |

**Known Issues**:
- 3B model sometimes strips scores from sports output
- Model adds extra text ("No games today") despite instructions
- Need more explicit formatting to prevent model "simplification"

### v0.8 - News & Stocks
**Target**: 4 weeks

| Task | Priority | Status | Notes |
|------|----------|--------|-------|
| News tool | High | Not Started | NewsAPI or RSS integration |
| Stocks tool | Medium | Not Started | Yahoo Finance API |
| News formatting | Medium | Not Started | Headlines with summaries |
| Category preferences | Medium | Not Started | User selects topics of interest |

**Architecture Notes**:
- Follow same provider pattern as Sports
- `NewsDataProvider` protocol with `NewsAPIProvider`, `RSSProvider`
- `StocksDataProvider` with `YahooFinanceProvider`

### v0.9 - Daily Briefing
**Target**: 6 weeks

| Task | Priority | Status | Notes |
|------|----------|--------|-------|
| Daily briefing tool | High | Not Started | Aggregate sports, weather, news |
| User topic preferences | High | Not Started | Favorite teams, news categories |
| Morning notification | Medium | Not Started | Push notification with briefing |
| Briefing UI | Medium | Not Started | Dedicated summary view |

**Feature Description**:
Personalized daily update aggregating:
- Weather forecast for user's location
- Sports results for favorite teams/leagues
- News headlines from preferred categories (politics, tech, entertainment)

```
Tool format: <tool>briefing|type=morning</tool>
```

---

## Medium-Term Roadmap (v1.0 - v1.5)

### v1.0 - Production Release
**Target**: 3 months

| Task | Priority | Notes |
|------|----------|-------|
| App Store submission | High | TestFlight → Production |
| Onboarding flow | High | Location, preferences, permissions |
| Error handling polish | High | User-friendly error messages |
| Performance optimization | High | Battery, memory profiling |
| Privacy policy | High | Required for App Store |
| Documentation | Medium | User guide, FAQ |

### v1.1 - Follow-up Questions (Grok-style)
**Target**: 4 months

After model generates response, suggest 2-3 contextual follow-up questions.

**Implementation Approaches**:

1. **Model-generated** (preferred):
   - Add instruction to prompt: "End with 3 follow-up questions in format [FOLLOWUP: q1 | q2 | q3]"
   - Parse and display as tappable chips
   - May require fine-tuning for reliability

2. **Rule-based fallback**:
   - Sports → "Show standings", "Next [team] game", "Season stats"
   - Weather → "Tomorrow's forecast", "Weekend weather", "What to wear"
   - Calendar → "Add event", "Tomorrow's schedule", "Set reminder"

**UI**:
- Horizontal scrollable chips below response
- Tap to send as new message
- Only for tool-augmented responses

### v1.2 - Voice Input
**Target**: 5 months

| Component | Approach |
|-----------|----------|
| Speech-to-text | On-device Whisper (via MLX) or Apple Speech |
| Activation | Hold button or "Hey Jubo" |
| Feedback | Waveform animation while listening |

### v1.5 - Fine-Tuning
**Target**: 6 months

Train custom LoRA adapter for:
- Improved tool selection accuracy
- Better response formatting
- Reduced "simplification" of structured data
- Domain-specific knowledge (sports, weather)

**Datasets**:
- Glaive Function Calling v2 (113K examples)
- Custom Jubo dataset (5-10K examples)
- Negative examples (when NOT to use tools)

---

## Long-Term Vision (v2.0+)

### v2.0 - Proactive Assistant

Move from reactive to proactive:
- Morning briefing notifications
- "Heads up, your meeting in 30 minutes"
- "Lakers game starting soon"
- Location-aware suggestions

### v2.1 - Multi-Modal

| Feature | Technology |
|---------|------------|
| Image understanding | Vision model (MLX) |
| Screenshot analysis | "What's in this image?" |
| Document parsing | PDF/image text extraction |

### v2.5 - Smart Home

| Feature | Technology |
|---------|------------|
| HomeKit integration | Control lights, thermostat |
| Shortcuts integration | Run user automations |
| Scene suggestions | "Good morning" routine |

---

## Technical Debt & Improvements

### High Priority

| Item | Description | Effort |
|------|-------------|--------|
| API key storage | Move from UserDefaults to Keychain | Small |
| Error recovery | Graceful handling of all error states | Medium |
| Offline mode | Clear messaging when no network | Small |
| Memory leaks | Profile and fix any GPU memory issues | Medium |

### Medium Priority

| Item | Description | Effort |
|------|-------------|--------|
| Unit tests | Add tests for services and formatters | Medium |
| UI tests | Basic flow testing | Medium |
| Logging system | Structured logging with levels | Small |
| Analytics (local) | Track tool usage for optimization | Medium |

### Low Priority

| Item | Description | Effort |
|------|-------------|--------|
| Localization | Multi-language support | Large |
| iPad layout | Optimized for larger screens | Medium |
| macOS app | Native macOS version | Large |
| Widget | iOS widget for quick info | Medium |

---

## Research & Exploration

### Model Improvements

| Area | Question | Priority |
|------|----------|----------|
| Smaller models | Can 1B models handle tool calling? | Medium |
| Quantization | 4-bit vs 8-bit quality tradeoff | Low |
| Speculative decoding | Speed up inference | Low |
| Model switching | Different models for different tasks | Medium |

### Alternative Approaches

| Approach | Pros | Cons |
|----------|------|------|
| Cloud fallback | Better quality for complex queries | Privacy compromise |
| Hybrid inference | Best of both worlds | Complexity |
| Edge functions | Offload some processing | Still requires network |

---

## Success Metrics

### v1.0 Targets

| Metric | Target |
|--------|--------|
| Tool selection accuracy | >80% |
| Response latency (no tool) | <2s |
| Response latency (with tool) | <5s |
| Battery drain | <5%/hour active use |
| Crash-free sessions | >99% |

### Growth Targets

| Metric | Target |
|--------|--------|
| Day-7 retention | >30% |
| Day-30 retention | >20% |
| Daily active users | Track |
| Tool usage distribution | Track |

---

## Decision Log

### January 2026

| Decision | Rationale |
|----------|-----------|
| Tools over agents | Simpler, faster, works with 3B models |
| ESPN for sports | Free, no API key, good coverage |
| Brave for search | Privacy-focused, good results |
| Provider pattern for sports | Flexibility to add sources |
| User confirmation for tools | Privacy, prevent unwanted API calls |

### Future Decisions Needed

| Question | Options | Timeline |
|----------|---------|----------|
| Fine-tuning approach | LoRA vs full fine-tune | v1.5 |
| Voice model | Whisper vs Apple Speech | v1.2 |
| News source | NewsAPI vs RSS vs both | v0.8 |
| Monetization | Free, freemium, paid | v1.0 |

---

## Contributing

### Priority for Contributors

1. **WebSportsProvider** - Add web search fallback for sports
2. **News integration** - NewsAPI or RSS provider
3. **Unit tests** - Service and formatter tests
4. **Documentation** - User guide, API docs

### Code Style

- Swift style guide (see `.swiftlint.yml`)
- Actor-based services for concurrency
- Protocol-first design for extensibility
- Comprehensive error handling

---

*Roadmap maintained by the Jubo development team. Updated as priorities evolve.*
