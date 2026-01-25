# Jubo Tool Strategy & Use Case Taxonomy

> **Version**: 1.1
> **Date**: January 25, 2026
> **Purpose**: Define tool priorities, use case mapping, and implementation roadmap

---

## 1. Strategic Approach

### Core Philosophy

**Tools over Agents**: Instead of building a complex agentic system with multi-step reasoning loops, we focus on discrete tools that the model can invoke. This approach:
- Keeps latency low (single inference + tool execution)
- Works reliably with 3B models
- Minimizes battery drain
- Is incrementally buildable and testable

### Implementation Order

1. **Prompt Engineering** - Improve tool selection with better prompts before fine-tuning
2. **Tool Expansion** - Build high-priority tools incrementally
3. **Fine-Tuning** - Train model on Glaive + custom Jubo dataset once tools exist
4. **Iteration** - Measure, collect feedback, improve

---

## 2. Use Case Taxonomy

### Category A: TOOL (Requires External Data)

| Use Case | Tool Name | Status | API/Framework | Priority |
|----------|-----------|--------|---------------|----------|
| Sports scores | `sports` | ✅ Working | ESPN API (provider pattern) | - |
| Web search | `search` | ✅ Working | Brave API (needs key) | - |
| Current weather | `weather` | ✅ Working | WeatherKit + web fallback | - |
| Weather forecast | `weather` | ✅ Working | WeatherKit + web fallback | - |
| Calendar view | `calendar` | ✅ Working | EventKit | - |
| Reminders view | `reminders` | ✅ Working | EventKit | - |
| Reminder creation | `reminder_create` | ✅ Working | EventKit | - |
| Stock prices | `stocks` | To Build | Yahoo Finance | High |
| News headlines | `news` | To Build | NewsAPI/RSS | High |
| Daily briefing | `briefing` | To Build | Aggregate | Medium |
| Timer/Alarm | `timer` | To Build | System | Medium |
| Unit conversion | `convert` | To Build | Local calc | Low |
| Translation | `translate` | To Build | Apple Translate | Low |
| Location/Maps | `maps` | To Build | MapKit | Low |

**Note:** Weather falls back to web search when WeatherKit fails (e.g., entitlement not configured). Sports uses a provider pattern allowing multiple data sources.

### Category B: MODEL-DIRECT (No Tool Needed)

The model should handle these directly from its training:

| Use Case | Examples |
|----------|----------|
| General Q&A | "What is photosynthesis?", "Who wrote Hamlet?" |
| Writing assistance | "Help me write an email", "Edit this paragraph" |
| Summarization | "Summarize this text", "Give me the key points" |
| Explanation | "Explain quantum computing", "What does this mean?" |
| Brainstorming | "Give me ideas for...", "What are some ways to..." |
| Simple math | "What's 15% of 80?", "Convert 5km to miles" |
| Coding concepts | "How do I write a for loop?", "What's a closure?" |
| Grammar/Language | "Is this sentence correct?", "How do I say X?" |

### Category C: OUT OF SCOPE (v1)

| Use Case | Reason | Future Version |
|----------|--------|----------------|
| Image generation | Memory/compute intensive | v2+ (NPU) |
| Video generation | Impossible on mobile | No |
| Voice input (ASR) | Needs Whisper model | v1.5 |
| Voice output (TTS) | Needs TTS model | v1.5 |
| Deep research | Multi-step, slow, battery | Cloud delegation |
| Large file parsing | Memory intensive | v1.5 (limited) |
| Email sending | Auth complexity | v1.5 |
| Calendar writing | Risk of errors | v1.5 (with confirmation) |

### Category D: NEEDS USER RESEARCH

| Use Case | Consideration |
|----------|---------------|
| Contacts lookup | Privacy - is it worth the sensitivity? |
| Health data (HealthKit) | Too sensitive for v1? |
| Smart home (HomeKit) | Useful enough to justify complexity? |
| Music control | Worth the integration effort? |

---

## 3. Research Findings

### What Users Actually Want (2025 Studies)

**ChatGPT Usage (OpenAI Study, Sept 2025)**:
- 70%+ non-work related
- Top 3: Practical guidance, information seeking, writing (~80% combined)
- Coding: only 4.2% of messages

**Claude Usage (Anthropic Study, Sept 2025)**:
- More work-focused
- 36% coding (vs 4.2% ChatGPT)
- 44% of API usage is coding

**Mobile AI Adoption**:
- +82% growth Nov 2024 → June 2025
- 85% of users stick to one platform
- Users expect "reactive" assistants (explicit requests)

### 3B Model Capabilities (Validated)

| Model | Tool Calling | Notes |
|-------|--------------|-------|
| Llama 3.2 3B | ✅ Yes | Designed for on-device tool use |
| SmolLM3 3B | ✅ Yes | Outperforms Llama/Qwen at 3B |
| Qwen2.5 3B | ✅ Yes | Good function calling |
| Apple ~3B | Limited | Focused on summarization/extraction |

**Key Insight**: 3B models already have tool-calling capability. Fine-tuning improves reliability but may not be required for basic functionality.

---

## 4. Implementation Roadmap

### Phase 1: Prompt Engineering (Current)

**Goal**: Maximize tool selection accuracy without fine-tuning

- Improve system prompt with explicit tool descriptions
- Add few-shot examples of tool invocation
- Include negative examples (when NOT to use tools)
- Test and measure accuracy

**Success Criteria**: >75% correct tool selection on test set

### Phase 2: High-Priority Tool Expansion

**Tools to build (in order)**:

1. **Stocks** (`stocks`)
   - API: Yahoo Finance (free)
   - Use case: "How's Apple stock?", "What's the S&P at?"
   - Complexity: Low

2. **News** (`news`)
   - API: NewsAPI or RSS feeds
   - Use case: "What's in the news?", "Tech news today"
   - Complexity: Low

3. **Timer/Alarm** (`timer`)
   - Framework: System notifications
   - Use case: "Set a timer for 5 minutes"
   - Complexity: Medium (system integration)

### Phase 3: Fine-Tuning

**Prerequisites**:
- All Phase 2 tools built and tested
- Test dataset created (500+ examples)
- Baseline accuracy measured

**Datasets**:
- Glaive Function Calling v2 (113K examples) - foundation
- Custom Jubo dataset (5-10K examples) - our specific tools

**Key Requirements**:
- Include negative examples (model should NOT call tool)
- Cover all tool types
- Include multi-tool scenarios
- Include edge cases and clarification requests

### Phase 4: Measurement & Iteration

**Metrics to track**:
- Tool selection accuracy (correct tool chosen)
- False positive rate (tool called when not needed)
- False negative rate (tool not called when needed)
- User satisfaction (thumbs up/down)
- Latency

---

## 5. Tool Schema (Target Format)

### Invocation Format

```xml
<tool>TOOL_NAME|param1=value1|param2=value2</tool>
```

### Result Format

```xml
<tool_result>
Result content here
</tool_result>
```

### Tool Definitions

```yaml
weather:
  description: "Get current weather or forecast for a location"
  parameters:
    - location: string (required) - City name or "user_location"
    - forecast: enum [current, tomorrow, week] (optional, default: current)
  example: "<tool>weather|location=Boston|forecast=tomorrow</tool>"

calendar:
  description: "View calendar events"
  parameters:
    - range: enum [today, tomorrow, this_week] or DATE string
  example: "<tool>calendar|range=today</tool>"

reminders:
  description: "View reminders"
  parameters:
    - filter: enum [all, today, overdue, completed]
  example: "<tool>reminders|filter=today</tool>"

sports:
  description: "Get live sports scores"
  parameters:
    - league: string (required) - nba, nfl, mlb, nhl, premier_league, etc.
    - team: string (optional) - specific team name
  example: "<tool>sports|league=nba|team=lakers</tool>"

search:
  description: "Search the web for current information"
  parameters:
    - query: string (required) - search query
  example: "<tool>search|query=latest iPhone release date</tool>"

stocks:
  description: "Get stock price and market data"
  parameters:
    - symbol: string (required) - stock ticker (AAPL, GOOGL, etc.)
  example: "<tool>stocks|symbol=AAPL</tool>"

news:
  description: "Get news headlines"
  parameters:
    - category: enum [top, tech, business, sports, entertainment] (optional)
    - query: string (optional) - specific topic
  example: "<tool>news|category=tech</tool>"
```

---

## 6. Future Features (Roadmap)

### 6.1 Daily Briefing Tool (`briefing`)

**Priority:** High (v1.5)

A personalized daily update that aggregates content based on user preferences:

| Component | Source | User Customization |
|-----------|--------|-------------------|
| Sports results | ESPN API | Favorite teams, leagues |
| Weather forecast | WeatherKit | Location, daily/weekly |
| News - Politics | NewsAPI/RSS | Topics, sources |
| News - Economy | NewsAPI/RSS | Markets, sectors |
| News - Entertainment | NewsAPI/RSS | Categories, celebrities |

**User Preferences to Store:**
- Favorite sports teams (e.g., "Lakers", "Patriots")
- Favorite leagues (e.g., "NBA", "Premier League")
- News categories of interest
- Preferred news sources
- Briefing time preference (morning/evening)

**Tool Format:**
```xml
<tool>briefing|type=morning</tool>
<tool>briefing|type=sports_only</tool>
```

**Implementation Notes:**
- Fetch all data in parallel for speed
- Cache results for battery efficiency
- Consider push notification for morning briefing
- Format as concise bullet points, not verbose paragraphs

---

### 6.2 Follow-up Question Suggestions (Grok-style)

**Priority:** Medium (v1.5)

After the model generates a response, suggest 2-3 contextual follow-up questions the user might want to ask. User can tap to ask them instantly.

**Example:**
```
User: What were the NBA scores yesterday?
Jubo: [Shows scores]

Suggested follow-ups:
• "How is my team doing this season?"
• "When is the next Lakers game?"
• "Show me the standings"
```

**Implementation Approaches:**

1. **Model-generated (preferred):** Add instruction to system prompt asking model to output suggestions in a specific format (e.g., `[FOLLOWUP: question1 | question2 | question3]`). Parse and display as tappable chips.

2. **Rule-based fallback:** For common query types, have predefined follow-ups:
   - Sports → standings, next game, season stats
   - Weather → forecast, other locations, what to wear
   - Calendar → add event, tomorrow's schedule, reminders
   - News → more details, related topics, different source

**UI Considerations:**
- Display as horizontal scrollable chips below response
- Tapping sends the question as new user message
- Limit to 2-3 suggestions to avoid clutter
- Only show for tool-augmented responses (not general Q&A)

**Technical Notes:**
- May need fine-tuning to reliably generate follow-ups
- Parse with regex: `\[FOLLOWUP:(.+?)\]`
- Store successful follow-up patterns for improvement

---

## 8. Success Metrics

### Phase 1 (Prompt Engineering)
- Tool selection accuracy: >75%
- No regression in response quality

### Phase 2 (Tool Expansion)
- New tools functional and tested
- <500ms tool execution time
- User-confirmed tool invocation working

### Phase 3 (Fine-Tuning)
- Tool selection accuracy: >90%
- False positive rate: <5%
- No tool when appropriate: >85%

### Long-term
- Day-30 retention: >20%
- Context density increasing week-over-week
- Battery drain: <5%/hour active use

---

## 9. References

### Research Sources
- [Fortune: ChatGPT/Claude Usage Study (Sept 2025)](https://fortune.com/2025/09/15/openai-chatgpt-claude-anthropic-work-personal-use-new-data/)
- [Comscore: Mobile AI Adoption](https://www.comscore.com/Insights/Press-Releases/2025/9/AI-Assistants-Go-Mobile)
- [Berkeley Function-Calling Leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html)
- [Deloitte: On-device Gen AI](https://www.deloitte.com/us/en/insights/industry/technology/technology-media-and-telecom-predictions/2025/gen-ai-on-smartphones.html)

### Datasets
- [Glaive Function Calling v2](https://huggingface.co/datasets/glaiveai/glaive-function-calling-v2)
- [Glaive v2 ShareGPT Format](https://huggingface.co/datasets/hiyouga/glaive-function-calling-v2-sharegpt)

### Model Documentation
- [Llama 3.2 (Meta)](https://ai.meta.com/blog/llama-3-2-connect-2024-vision-edge-mobile-devices/)
- [SmolLM3 (Hugging Face)](https://huggingface.co/HuggingFaceTB/SmolLM3-3B)

---

*Document created January 2026. Review and update as implementation progresses.*
