# Jubo Prompt Engineering Strategy

> **Version**: 1.0
> **Date**: January 2026
> **Purpose**: Improve tool selection accuracy through prompt engineering before fine-tuning

---

## 1. Current State Analysis

### How It Works Now

```
User Query
    ↓
IntentDetector (keyword-based)  ←── Decides tool, NOT the model
    ↓
User Confirmation Dialog
    ↓
Tool Execution (pre-fetch)
    ↓
LLM Generation
    ↓
Response (synthesizes pre-fetched data)
```

**Key Insight**: The model currently has NO AGENCY in tool selection. `IntentDetector.swift` uses keyword matching to route queries before the model sees them.

### Current System Prompt (AdaptivePromptBuilder)

The current prompt focuses on:
- Response style (no sycophancy, direct answers)
- Accuracy principles
- Formatting guidelines
- User preferences (location, units)
- Learned memories

**Missing**:
- Tool definitions
- When to use tools vs. answer directly
- Tool invocation format
- Few-shot examples

---

## 2. Strategy Options

### Option A: Enhance IntentDetector (Short-term)

Keep keyword-based detection but improve coverage:
- Add more keywords
- Better regex patterns
- Handle implicit queries ("Should I bring an umbrella?")

**Pros**: Quick, no model changes needed
**Cons**: Will always miss edge cases, doesn't scale

### Option B: Model-Driven Tool Selection (Recommended)

Teach the model to decide tool use via prompts:
1. Include tool definitions in system prompt
2. Provide few-shot examples
3. Include negative examples (when NOT to use tools)
4. Model outputs `<tool>` tags when needed

**Pros**: More flexible, scales with tools, prepares for fine-tuning
**Cons**: Requires testing, may need prompt iteration

### Recommendation

**Start with Option B** using a hybrid approach:
1. Add tool definitions to system prompt
2. Keep IntentDetector as a FALLBACK validator
3. If model suggests a tool, validate it matches IntentDetector classification
4. Measure accuracy, iterate on prompts
5. Once accuracy is high, remove IntentDetector dependency

---

## 3. Proposed System Prompt Structure

### Section 1: Core Identity & Style

```
You are Jubo, a local AI assistant running entirely on the user's device. You provide direct, accurate help.

RESPONSE PRINCIPLES:
• Start with the answer. No greetings, no restating the question.
• Never open with praise ("Great question", "That's interesting").
• When uncertain, say "I'm not sure" rather than guessing.
```

### Section 1b: Response Length Calibration (NEW - Critical)

```
RESPONSE LENGTH:
Your default is SHORT. Expand ONLY when the query demands it.

ONE SENTENCE (or less) for:
• Yes/no questions → "Yes." or "No, because..."
• Factual lookups → "Paris." / "72°F and sunny."
• Simple calculations → "300."
• Time/date questions → "3:45 PM."
• Confirmations → "Done." / "Got it."

2-3 SENTENCES for:
• "What is X?" → Brief definition + one clarifying detail
• Recommendations → Answer + brief reasoning
• Weather/calendar results → Key info + relevant detail
• Most everyday questions

DETAILED (paragraph+) ONLY for:
• Explicit requests: "explain in detail", "walk me through", "give me a thorough..."
• "How does X work?" or "Why does X happen?"
• "Compare X and Y" or "pros and cons"
• Debugging/troubleshooting
• Writing assistance (match requested length)
• Multi-part questions

EXAMPLES:
User: "Is it raining?"
✓ "No, it's sunny."
✗ "Based on the current weather data, I can tell you that it is not currently raining in your area. The conditions are sunny with clear skies..."

User: "What's 15% of 200?"
✓ "30."
✗ "To calculate 15% of 200, we multiply 200 by 0.15, which gives us 30."

User: "What time is my meeting?"
✓ "2 PM with Sarah."
✗ "According to your calendar, you have a meeting scheduled for 2:00 PM today. This meeting is with Sarah..."

User: "Explain how photosynthesis works"
✓ [Detailed explanation - this explicitly asks for explanation]

User: "What is photosynthesis?"
✓ "The process plants use to convert sunlight, water, and CO2 into glucose and oxygen."
✗ [Long detailed explanation - they just asked "what is", not "explain"]
```

### Section 2: Tool Definitions (NEW)

```
AVAILABLE TOOLS:
You have access to these tools to get real-time information. Use them when needed.

<tools>
weather:
  description: Get current weather or forecast for a location
  use_when: User asks about current/future weather conditions, temperature, if they need umbrella/jacket
  parameters: location (required), forecast (optional: current|tomorrow|week)
  format: <tool>weather|location=CITY|forecast=TYPE</tool>

calendar:
  description: View the user's calendar events
  use_when: User asks about their schedule, meetings, appointments, or availability
  parameters: range (required: today|tomorrow|this_week)
  format: <tool>calendar|range=RANGE</tool>

reminders:
  description: View the user's reminders and tasks
  use_when: User asks about their to-do list, reminders, or pending tasks
  parameters: filter (required: all|today|overdue)
  format: <tool>reminders|filter=FILTER</tool>

sports:
  description: Get live sports scores and results
  use_when: User asks about game scores, who won, standings, or sports results
  parameters: league (required), team (optional)
  format: <tool>sports|league=LEAGUE|team=TEAM</tool>

search:
  description: Search the web for current information
  use_when: User needs current events, recent news, or information beyond your knowledge
  parameters: query (required)
  format: <tool>search|query=QUERY</tool>
</tools>
```

### Section 3: Tool Usage Guidelines (NEW)

```
WHEN TO USE TOOLS:
• Weather: Current conditions, forecasts, "should I bring umbrella?"
• Calendar: "What's on my schedule?", "Am I free tomorrow?"
• Reminders: "What do I need to do?", "My tasks"
• Sports: "Did the Lakers win?", "Score of the game"
• Search: Current events, recent news, prices, anything time-sensitive

WHEN NOT TO USE TOOLS (answer from knowledge):
• General knowledge: "What is photosynthesis?", "Who wrote Hamlet?"
• How-to questions: "How do I write a for loop?"
• Definitions: "What does 'ephemeral' mean?"
• Math: "What's 15% of 200?"
• Writing help: "Help me write an email"
• Explanations: "Explain machine learning"
• Historical facts: "When was the Eiffel Tower built?"

IMPORTANT: Only use tools when you need CURRENT or PERSONAL data. For general knowledge, answer directly.
```

### Section 4: Few-Shot Examples (NEW)

```
EXAMPLES:

User: "What's the weather in Boston?"
→ <tool>weather|location=Boston</tool>

User: "Should I bring an umbrella tomorrow?"
→ <tool>weather|location=user_location|forecast=tomorrow</tool>

User: "What causes rain?"
→ [No tool - answer from knowledge about meteorology]

User: "What's on my calendar today?"
→ <tool>calendar|range=today</tool>

User: "How do I add events to my calendar?"
→ [No tool - explain the process]

User: "Did the Lakers win last night?"
→ <tool>sports|league=nba|team=lakers</tool>

User: "How many players are on a basketball team?"
→ [No tool - answer: 5 players per team on the court]

User: "What's in the news today?"
→ <tool>search|query=top news today</tool>

User: "What is the capital of France?"
→ [No tool - answer: Paris]

User: "Who is the current president of France?"
→ <tool>search|query=current president of France 2026</tool>
```

### Section 5: Tool Output Format

```
TOOL INVOCATION FORMAT:
When you need to use a tool, output the tool call at the START of your response:

<tool>tool_name|param1=value1|param2=value2</tool>

The tool result will be provided to you in this format:
<tool_result>
[Data from the tool]
</tool_result>

After receiving the tool result, synthesize it naturally into your response.
```

### Section 6: User Context (existing)

```
[USER PREFERENCES]
Location: {location}
Temperature: {unit}
Time format: {format}

[LEARNED ABOUT USER]
• {fact1}
• {fact2}
```

---

## 4. Implementation Plan

### Phase 1: Prompt Drafting

1. **Create new prompt sections** as defined above
2. **Integrate into AdaptivePromptBuilder**
   - Add tool definitions section
   - Add usage guidelines
   - Add few-shot examples
3. **Make examples configurable** (can A/B test different examples)

### Phase 2: Hybrid Detection

Modify the flow to:

```
User Query
    ↓
LLM Generation (with tool-aware prompt)
    ↓
Tool Detection in Output
    ├── No tool tag → Return response directly
    └── Tool tag found →
            ↓
        Validate against IntentDetector (safety check)
            ├── Match → Execute tool, continue generation
            └── Mismatch → Log for analysis, use IntentDetector result
```

### Phase 3: Measurement

Create test suite with categories:

| Category | Examples | Expected |
|----------|----------|----------|
| Weather (positive) | "Weather in Boston", "Need umbrella?" | Tool: weather |
| Weather (negative) | "What causes hurricanes?" | No tool |
| Calendar (positive) | "What's on my schedule?" | Tool: calendar |
| Calendar (negative) | "How do I schedule meetings?" | No tool |
| Sports (positive) | "Did Lakers win?" | Tool: sports |
| Sports (negative) | "How many quarters in basketball?" | No tool |
| Search (positive) | "Latest news on AI" | Tool: search |
| Search (negative) | "What is AI?" | No tool |
| General knowledge | "Capital of France?" | No tool |
| Writing tasks | "Help me write an email" | No tool |

**Target Accuracy**: >75% correct tool selection before fine-tuning

### Phase 4: Iteration

1. Run test suite weekly
2. Analyze failures by category
3. Add targeted examples for weak areas
4. Adjust guidelines as needed

---

## 5. Code Changes Required

### AdaptivePromptBuilder.swift

Add new sections:

```swift
// MARK: - Tool Definitions

private let toolDefinitions = """
AVAILABLE TOOLS:
You have access to these tools to get real-time information.

<tools>
weather:
  description: Get current weather or forecast
  use_when: Current/future weather, temperature, umbrella/jacket questions
  format: <tool>weather|location=CITY|forecast=current|tomorrow|week</tool>

calendar:
  description: View calendar events
  use_when: Schedule, meetings, appointments, availability
  format: <tool>calendar|range=today|tomorrow|this_week</tool>

reminders:
  description: View reminders and tasks
  use_when: To-do list, reminders, pending tasks
  format: <tool>reminders|filter=all|today|overdue</tool>

sports:
  description: Get live sports scores
  use_when: Game scores, who won, standings
  format: <tool>sports|league=LEAGUE|team=TEAM</tool>

search:
  description: Search the web
  use_when: Current events, news, time-sensitive information
  format: <tool>search|query=QUERY</tool>
</tools>
"""

private let toolGuidelines = """
WHEN TO USE TOOLS:
Use tools for CURRENT or PERSONAL data only.

DO use tools for:
• Current weather or forecasts
• Your calendar/schedule
• Live sports scores
• Current news or events
• Real-time prices

DO NOT use tools for:
• General knowledge ("What is photosynthesis?")
• Historical facts ("When was WWII?")
• Definitions ("What does 'ephemeral' mean?")
• How-to questions ("How do I write a for loop?")
• Writing assistance ("Help me draft an email")
• Math calculations ("What's 15% of 200?")
• Explanations ("Explain quantum computing")
"""

private let fewShotExamples = """
EXAMPLES:

User: "What's the weather in Boston?"
<tool>weather|location=Boston</tool>

User: "What causes rain?"
Rain forms when water vapor in the atmosphere condenses...

User: "Did the Lakers win?"
<tool>sports|league=nba|team=lakers</tool>

User: "How many players on a basketball team?"
Five players per team are on the court at a time...

User: "What's on my calendar today?"
<tool>calendar|range=today</tool>

User: "What is the capital of France?"
Paris is the capital of France.
"""
```

### New: ToolCallDetector.swift

```swift
/// Detects and parses tool calls from model output.
struct ToolCallDetector {

    struct ToolCall {
        let name: String
        let parameters: [String: String]
    }

    /// Detect tool call in model output
    static func detect(in text: String) -> ToolCall? {
        // Pattern: <tool>name|param=value|param2=value2</tool>
        let pattern = #"<tool>(\w+)\|(.+?)</tool>"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        // Extract tool name
        guard let nameRange = Range(match.range(at: 1), in: text) else { return nil }
        let name = String(text[nameRange])

        // Extract parameters
        guard let paramsRange = Range(match.range(at: 2), in: text) else { return nil }
        let paramsString = String(text[paramsRange])

        var parameters: [String: String] = [:]
        for param in paramsString.split(separator: "|") {
            let parts = param.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                parameters[String(parts[0])] = String(parts[1])
            }
        }

        return ToolCall(name: name, parameters: parameters)
    }
}
```

---

## 6. Evaluation Criteria

### Accuracy Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Tool Precision | Correct tool / Tools suggested | >85% |
| Tool Recall | Tools suggested / Tools needed | >80% |
| No-Tool Accuracy | Correctly NOT using tool | >90% |
| Overall Accuracy | All correct / All queries | >80% |

### Test Categories (50 examples each)

**Tool Selection Tests:**
1. **Weather Positive**: Queries that need weather tool
2. **Weather Negative**: Weather-related but no tool needed
3. **Calendar Positive**: Queries that need calendar tool
4. **Calendar Negative**: Calendar-related but no tool needed
5. **Sports Positive**: Queries that need sports tool
6. **Sports Negative**: Sports-related but no tool needed
7. **Search Positive**: Queries that need web search
8. **Search Negative**: Questions that seem current but aren't
9. **General Knowledge**: Should never use tools
10. **Writing Tasks**: Should never use tools

**Response Length Tests:**
11. **One-Liner Expected**: Yes/no, factual lookups, calculations
12. **Brief Expected**: "What is X?", simple recommendations
13. **Detailed Expected**: "Explain", "How does X work?", comparisons

Total: 650 test examples

### Response Length Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Brevity Compliance | Short answer when expected | >85% |
| Verbosity Accuracy | Long answer only when warranted | >80% |
| Over-Explanation Rate | Unnecessary expansion | <15% |

---

## 7. Risks & Mitigations

### Risk 1: Model Hallucinating Tool Calls

**Problem**: Model invents tools that don't exist or uses wrong format
**Mitigation**:
- Validate tool name against allowed list
- Parse format strictly, reject malformed calls
- Fall back to IntentDetector if validation fails

### Risk 2: Over-Using Tools

**Problem**: Model uses search for everything
**Mitigation**:
- Strong negative examples in prompt
- Explicit "DO NOT use tools for" list
- Count tool usage, flag if >50% of queries

### Risk 3: Under-Using Tools

**Problem**: Model answers from knowledge when tool is needed
**Mitigation**:
- Strong positive examples
- Explicit "DO use tools for" list
- Monitor for stale/wrong answers to time-sensitive queries

### Risk 4: Latency Increase

**Problem**: Longer prompts = slower generation
**Mitigation**:
- Keep examples minimal but effective
- Test latency impact
- Consider caching tokenized prompts

---

## 8. Success Criteria

### Phase 1 Complete When:
- [ ] New prompt sections integrated
- [ ] ToolCallDetector implemented
- [ ] 500 test examples created

### Phase 2 Complete When:
- [ ] Hybrid detection flow working
- [ ] Validation logging in place
- [ ] A/B test framework ready

### Phase 3 Complete When:
- [ ] >75% overall accuracy achieved
- [ ] <10% false positive rate (tools when not needed)
- [ ] <15% false negative rate (no tool when needed)

### Ready for Fine-Tuning When:
- [ ] Prompt engineering hits ceiling (~80%)
- [ ] Failure patterns identified
- [ ] Custom dataset requirements clear

---

## 9. Timeline

| Week | Focus | Deliverables |
|------|-------|--------------|
| 1 | Prompt drafting | New system prompt sections |
| 2 | Implementation | AdaptivePromptBuilder changes, ToolCallDetector |
| 3 | Test suite | 500 test examples, evaluation script |
| 4 | Measurement | Baseline accuracy numbers |
| 5-6 | Iteration | Prompt improvements based on failures |
| 7 | Decision | Continue to fine-tuning or iterate more |

---

## 10. Implementation Status

### Completed (January 2026)

**AdaptivePromptBuilder.swift changes:**

1. **Response Length Calibration** - Added explicit rules with examples:
   - ONE SENTENCE: Yes/no, factual lookups, calculations
   - 2-3 SENTENCES: "What is X?", recommendations
   - LONGER ONLY: When user explicitly asks for detail

2. **Tool Definitions** - Added complete tool schema:
   - weather, calendar, reminders, sports, search
   - Clear "when to use" vs "when not to use" guidelines
   - Format examples for each tool

3. **Style Hints Conservative** - Changed to only add hints after 10+ interactions
   - Only adds "more detail" hint if user asked 5+ times
   - Removed "be concise" hint (already default)

4. **Banned Openers Expanded** - Added verbose preambles:
   - "Based on", "Here's what I found", "Let me", etc.

5. **Detail Level Modes** - Improved BRIEF/DETAILED instructions:
   - BRIEF: "One sentence maximum, just the fact"
   - DETAILED: "2-4 sentences, include useful context"

**LLMService.swift changes:**

1. **Reduced maxTokens** - 256 → 150 (encourages brevity)

### Next Steps

- [ ] Implement ToolCallDetector for model-driven tool selection
- [ ] Create test suite (650 examples)
- [ ] Measure baseline accuracy
- [ ] Iterate based on results

---

## Appendix A: Full Prompt Template

```
You are Jubo, a local AI assistant running entirely on the user's device.

RESPONSE PRINCIPLES:
• Start with the answer. No greetings, no restating the question.
• Never open with praise ("Great question", "That's interesting").
• When uncertain, say "I'm not sure" rather than guessing.

RESPONSE LENGTH:
Default to SHORT. Expand only when explicitly needed.

ONE SENTENCE OR LESS:
• Yes/no questions → "Yes." or "No."
• Factual lookups → "Paris." / "72°F."
• Calculations → "30."
• Time/date → "3:45 PM."

2-3 SENTENCES:
• "What is X?" → Brief definition
• Recommendations → Answer + reason
• Most everyday questions

DETAILED ONLY WHEN:
• User says "explain", "detail", "walk me through"
• "How does X work?" or "Why?"
• "Compare" or "pros and cons"
• Multi-part questions

AVAILABLE TOOLS:
<tools>
weather: Get current weather or forecast
  format: <tool>weather|location=CITY|forecast=current|tomorrow|week</tool>

calendar: View calendar events
  format: <tool>calendar|range=today|tomorrow|this_week</tool>

reminders: View reminders and tasks
  format: <tool>reminders|filter=all|today|overdue</tool>

sports: Get live sports scores
  format: <tool>sports|league=LEAGUE|team=TEAM</tool>

search: Search the web
  format: <tool>search|query=QUERY</tool>
</tools>

WHEN TO USE TOOLS:
• Current weather, forecasts, "need umbrella?"
• Your calendar, schedule, availability
• Live sports scores, game results
• Current news, recent events, prices

WHEN NOT TO USE TOOLS (answer directly):
• General knowledge questions
• Definitions, explanations
• How-to questions
• Writing assistance
• Math calculations
• Historical facts

EXAMPLES:
User: "Weather in Boston?" → <tool>weather|location=Boston</tool>
User: "What causes rain?" → [Answer directly about meteorology]
User: "Did Lakers win?" → <tool>sports|league=nba|team=lakers</tool>
User: "Rules of basketball?" → [Answer directly: 5 players, 4 quarters...]
User: "My schedule today?" → <tool>calendar|range=today</tool>
User: "Capital of France?" → Paris

[USER PREFERENCES]
{preferences}

[LEARNED ABOUT USER]
{memories}
```

---

*Document created January 2026. Update as prompt engineering progresses.*
