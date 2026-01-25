# Jubo Fine-Tuning & Architecture Strategy

> **Document Version**: 1.0
> **Last Updated**: January 2026
> **Purpose**: Technical reference for model fine-tuning and tool-use architecture decisions

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Decision: Agentic vs Tool-Augmented](#2-architecture-decision)
3. [The Tool-Augmented Generation Pattern](#3-tool-augmented-generation-pattern)
4. [Fine-Tuning Strategy](#4-fine-tuning-strategy)
5. [Dataset Selection](#5-dataset-selection)
6. [Custom Jubo Tool Dataset](#6-custom-jubo-tool-dataset)
7. [Training Pipeline](#7-training-pipeline)
8. [Implementation Changes](#8-implementation-changes)
9. [Evaluation & Quality Gates](#9-evaluation--quality-gates)
10. [Roadmap](#10-roadmap)

---

## 1. Executive Summary

### The Problem

The current Jubo implementation has two issues:

1. **Model responses are not great** - The base models (SmolLM3, Qwen2.5, Llama 3.2) lack personality, helpfulness, and consistency without fine-tuning.

2. **Tool use is disconnected** - Intent detection is keyword-based and separate from the model. The model doesn't "decide" to use tools; the orchestrator pre-fetches data and injects it.

### The Solution

1. **Two-stage LoRA fine-tuning**:
   - Stage 1: General assistant behavior (LIMA, OpenHermes)
   - Stage 2: Tool use behavior (Glaive + Custom Jubo dataset)

2. **Tool-Augmented Generation** architecture:
   - Single model that outputs tool calls when needed
   - Tools executed mid-generation
   - Results injected, generation continues
   - No separate "agents" or multi-step reasoning loops

### Why Not Agentic?

| Factor | Full Agentic | Tool-Augmented (Recommended) |
|--------|--------------|------------------------------|
| **Latency** | 4-8 seconds (3-4 inference passes) | 1-2 seconds (single pass + tool) |
| **Reliability** | Poor with 3B models | Good with fine-tuning |
| **Battery** | High (multiple inferences) | Low (single inference) |
| **Complexity** | ReAct loops, state machines | Simple tool detection |
| **3B Model Suitability** | Not recommended | Well suited |

---

## 2. Architecture Decision

### Current Architecture (v0.5)

```
User Query
    │
    ▼
┌─────────────────────────────────────────┐
│  IntentDetector (Keyword-based)         │  ◄── No LLM involved
│  if "weather" in query → weather tool   │
│  if "calendar" in query → calendar tool │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  User Confirmation Dialog               │
│  "Search for weather in Boston?"        │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  Tool Execution (Pre-fetch)             │
│  Results stored in searchContext        │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  LLM Generation                         │
│  Context = Query + Pre-fetched Results  │  ◄── Model just synthesizes
└─────────────────────────────────────────┘
```

**Problems:**
- Keyword detection misses nuanced queries ("Should I bring an umbrella?")
- Model has no agency - can't decide when it needs information
- Rigid routing logic that doesn't understand context
- Tool results are always pre-fetched even when model might not need them

### Rejected: Full Agentic Architecture

```
User Query
    │
    ▼
┌─────────────────────────────────────────┐
│  LLM: "Let me think about this..."      │  ◄── Inference #1 (~1.5s)
│  Output: "I need to check the weather"  │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  LLM: "Action: weather_tool(Boston)"    │  ◄── Inference #2 (~1.5s)
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  Tool Execution                         │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  LLM: "Observation: 45°F, cloudy..."    │  ◄── Inference #3 (~1.5s)
│  "Final Answer: It's 45 degrees..."     │
└─────────────────────────────────────────┘
```

**Why Rejected:**
- 3-4 inference passes = 4-8 seconds total latency
- 3B models fail at consistent ReAct formatting (~30% error rate)
- Battery drain unacceptable for mobile
- Overkill for simple tool routing

### Recommended: Tool-Augmented Generation

```
User Query
    │
    ▼
┌─────────────────────────────────────────┐
│  LLM Generation (Fine-tuned)            │
│                                         │
│  Model outputs:                         │
│  "Let me check that for you.            │
│   <tool>weather|location=Boston</tool>" │  ◄── Single inference
│                                         │
│  [Generation pauses at tool tag]        │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  Tool Detection & Execution             │
│  Parse: weather tool, location=Boston   │
│  Execute: WeatherKitService.fetch()     │
│  Result: "45°F, Cloudy, Wind 12mph"     │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  Continue Generation                    │
│                                         │
│  Context now includes tool result       │
│  Model continues: "It's currently 45°F  │  ◄── Same inference continues
│  and cloudy in Boston with 12mph wind." │
└─────────────────────────────────────────┘
```

**Advantages:**
- Single inference pass (with pause/continue)
- Model decides when tools are needed
- Natural integration of tool results
- Works well with fine-tuned 3B models
- Low latency, low battery

---

## 3. Tool-Augmented Generation Pattern

### Tool Schema Definition

```xml
<!-- Weather -->
<tool>weather|location=STRING</tool>

<!-- Calendar -->
<tool>calendar|range=today|tomorrow|this_week|DATE</tool>

<!-- Reminders -->
<tool>reminders|filter=all|today|overdue|completed</tool>

<!-- Sports -->
<tool>sports|league=STRING|team=STRING?</tool>

<!-- Web Search -->
<tool>search|query=STRING</tool>
```

### Tool Result Injection Format

```xml
<tool_result>
Weather for Boston, MA:
Temperature: 45°F (7°C)
Conditions: Cloudy
Wind: 12 mph NW
Humidity: 65%
</tool_result>
```

### Complete Interaction Example

**User**: "Should I bring an umbrella tomorrow?"

**Model Output** (with tool call):
```
Let me check tomorrow's weather for you.
<tool>weather|location=user_location|forecast=tomorrow</tool>
```

**After Tool Injection**:
```
Let me check tomorrow's weather for you.
<tool>weather|location=user_location|forecast=tomorrow</tool>
<tool_result>
Tomorrow in San Francisco:
High: 58°F, Low: 49°F
Conditions: Rain likely (80% chance)
Precipitation: 0.4 inches expected
</tool_result>

Yes, definitely bring an umbrella! Tomorrow has an 80% chance of rain with about 0.4 inches expected. You might also want a jacket since it'll be cool, around 49-58°F.
```

### When NOT to Call Tools

The model must learn when tools are unnecessary:

| Query | Tool Needed? | Reason |
|-------|--------------|--------|
| "What's the weather in Boston?" | Yes | Current/live data |
| "What causes rain?" | No | General knowledge |
| "Did the Lakers win?" | Yes | Live sports data |
| "How many players on a basketball team?" | No | General knowledge |
| "What's on my calendar?" | Yes | Personal data |
| "How do I add a calendar event?" | No | General knowledge |

---

## 4. Fine-Tuning Strategy

### Two-Stage LoRA Approach

```
┌─────────────────────────────────────────────────────────────┐
│                    BASE MODEL                                │
│              (SmolLM3 3B / Qwen2.5 3B)                      │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 STAGE 1: ASSISTANT LORA                      │
│                                                              │
│  Datasets:                                                   │
│  • LIMA (1K examples) - High-quality instruction following  │
│  • OpenHermes 2.5 (subset) - Diverse capabilities           │
│  • SlimOrca (subset) - Reasoning chains                     │
│                                                              │
│  Goal: Helpful, harmless, honest base behavior              │
│  Output: adapter_stage1.safetensors (~50MB)                 │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 STAGE 2: TOOL USE LORA                       │
│                                                              │
│  Datasets:                                                   │
│  • Glaive Function Calling v2 (113K) - General tool use     │
│  • Custom Jubo Dataset (5-10K) - Jubo-specific tools        │
│                                                              │
│  Goal: Reliable tool invocation and result synthesis        │
│  Output: adapter_stage2.safetensors (~50MB)                 │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   MERGED ADAPTER                             │
│                                                              │
│  Combine Stage 1 + Stage 2 adapters                         │
│  Output: jubo_adapter_v1.safetensors (~80-100MB)            │
└─────────────────────────────────────────────────────────────┘
```

### LoRA Hyperparameters (Recommended Starting Point)

```yaml
# For 3B models on consumer GPU (RTX 3090/4090 or A100)
lora:
  r: 64                    # Rank - higher = more capacity
  lora_alpha: 128          # Scaling factor (usually 2x rank)
  lora_dropout: 0.05       # Light dropout
  target_modules:          # Which layers to adapt
    - q_proj
    - k_proj
    - v_proj
    - o_proj
    - gate_proj
    - up_proj
    - down_proj

training:
  epochs: 3
  batch_size: 4
  gradient_accumulation: 4  # Effective batch = 16
  learning_rate: 2e-4
  warmup_ratio: 0.03
  lr_scheduler: cosine
  max_seq_length: 2048
```

---

## 5. Dataset Selection

### Stage 1: Base Assistant Behavior

#### LIMA (Less Is More for Alignment)

- **Source**: [LIMA on HuggingFace](https://huggingface.co/datasets/GAIR/lima)
- **Size**: 1,000 examples
- **Why**: High-quality, diverse instructions. Proves that quality > quantity.
- **Format**: Instruction-response pairs

```json
{
  "conversations": [
    {"from": "human", "value": "How do I make sourdough bread?"},
    {"from": "gpt", "value": "Here's a beginner-friendly sourdough recipe..."}
  ]
}
```

#### OpenHermes 2.5

- **Source**: [OpenHermes 2.5 on HuggingFace](https://huggingface.co/datasets/teknium/OpenHermes-2.5)
- **Size**: 1M examples (use 50-100K subset)
- **Why**: Diverse tasks, good reasoning, clean data
- **Subset Strategy**: Filter for:
  - General assistance
  - Explanation tasks
  - Coding help (if desired)
  - Avoid: roleplay, creative writing (unless wanted)

#### SlimOrca (Optional)

- **Source**: [SlimOrca on HuggingFace](https://huggingface.co/datasets/Open-Orca/SlimOrca)
- **Size**: 518K examples
- **Why**: Chain-of-thought reasoning
- **Use Case**: If you want the model to "show its work"

### Stage 2: Tool Use Behavior

#### Glaive Function Calling v2

- **Source**: [glaiveai/glaive-function-calling-v2](https://huggingface.co/datasets/glaiveai/glaive-function-calling-v2)
- **Size**: 113K examples
- **Why**: Comprehensive function calling training data
- **Format Variants**:
  - Original format (requires conversion)
  - [ShareGPT format](https://huggingface.co/datasets/hiyouga/glaive-function-calling-v2-sharegpt) - Ready for Axolotl
  - [Llama format](https://huggingface.co/datasets/rizerphe/glaive-function-calling-v2-llama) - With `<function>` tokens

**Example from Glaive v2:**

```json
{
  "system": "You have access to the following functions...",
  "chat": [
    {"role": "user", "content": "Can you book a flight for me?"},
    {"role": "assistant", "content": null, "function_call": {
      "name": "book_flight",
      "arguments": "{\"destination\": \"NYC\", \"date\": \"2024-01-15\"}"
    }},
    {"role": "function", "name": "book_flight", "content": "{\"status\": \"booked\", \"confirmation\": \"ABC123\"}"},
    {"role": "assistant", "content": "I've booked your flight to NYC. Your confirmation number is ABC123."}
  ]
}
```

**Relevance to Jubo:**
- Teaches general function calling patterns
- Model learns when to call functions vs answer directly
- Learns to synthesize function results naturally
- **Limitation**: Functions don't match Jubo's tools exactly

#### Why Glaive Is Useful But Not Sufficient

| Glaive Covers | Jubo Needs (Custom) |
|---------------|---------------------|
| Generic function calling syntax | Jubo's specific `<tool>` format |
| When to call vs not call | Jubo's 5 specific tools |
| Multi-turn with functions | Weather/Calendar/Sports edge cases |
| Result synthesis | User preference awareness |

**Recommendation**: Use Glaive as foundation, then fine-tune further on Jubo-specific data.

---

## 6. Custom Jubo Tool Dataset

### Required: Jubo-Specific Training Data

You need 5,000-10,000 examples covering:

1. **Each tool type** (weather, calendar, reminders, sports, search)
2. **Positive examples** (tool needed)
3. **Negative examples** (no tool needed - critical!)
4. **Edge cases** (ambiguous, multi-tool, clarification needed)
5. **Result synthesis styles** (brief vs detailed)

### Dataset Structure

```json
{
  "id": "jubo_weather_001",
  "messages": [
    {
      "role": "system",
      "content": "You are Jubo, a helpful AI assistant. You have access to tools: weather, calendar, reminders, sports, search. Use <tool>name|param=value</tool> format when needed."
    },
    {
      "role": "user",
      "content": "What's the weather like?"
    },
    {
      "role": "assistant",
      "content": "<tool>weather|location=user_location</tool>"
    },
    {
      "role": "tool",
      "content": "San Francisco, CA: 62°F, Partly Cloudy, Humidity 70%, Wind 8mph W"
    },
    {
      "role": "assistant",
      "content": "It's 62°F and partly cloudy right now. Humidity is at 70% with a light 8mph westerly breeze."
    }
  ],
  "metadata": {
    "tool_used": "weather",
    "category": "current_weather",
    "complexity": "simple"
  }
}
```

### Example Categories to Cover

#### Weather Tool (Target: 1,500 examples)

```yaml
categories:
  current_weather:
    - "What's the weather?"
    - "How's the weather in Boston?"
    - "Is it raining?"
    - "What's the temperature?"

  forecast:
    - "What's the weather tomorrow?"
    - "Will it rain this weekend?"
    - "What's the forecast for next week?"

  implicit_weather:
    - "Should I bring an umbrella?"
    - "Is it good weather for a picnic?"
    - "Do I need a jacket today?"
    - "Can I go running outside?"

  no_tool_needed:  # CRITICAL - negative examples
    - "What causes hurricanes?"
    - "Why is the sky blue?"
    - "What's the average rainfall in Seattle?"
    - "How do weather forecasts work?"
```

#### Calendar Tool (Target: 1,000 examples)

```yaml
categories:
  view_schedule:
    - "What's on my calendar today?"
    - "What do I have tomorrow?"
    - "Am I free next Tuesday?"
    - "What's my schedule this week?"

  specific_queries:
    - "When is my dentist appointment?"
    - "Do I have any meetings today?"
    - "What time is the team standup?"

  no_tool_needed:
    - "How do I add a calendar event?"
    - "What's a good calendar app?"
    - "How do I set recurring events?"
```

#### Sports Tool (Target: 1,000 examples)

```yaml
categories:
  live_scores:
    - "Did the Lakers win?"
    - "What's the score of the Arsenal game?"
    - "Who won the Super Bowl?"
    - "How are the Yankees doing?"

  league_queries:
    - "What are today's NBA games?"
    - "Premier League results"
    - "Champions League scores"

  no_tool_needed:
    - "How many players on a soccer team?"
    - "What are the rules of basketball?"
    - "Who is the best NBA player of all time?"
    - "When was the NFL founded?"
```

#### Web Search Tool (Target: 1,500 examples)

```yaml
categories:
  current_events:
    - "What's happening in the news?"
    - "Latest on the election"
    - "Recent tech news"

  factual_lookup:
    - "What's the population of Tokyo?"
    - "Who is the CEO of Apple?"
    - "When did X happen?"

  no_tool_needed:  # Model should use knowledge
    - "What's the capital of France?"
    - "Who wrote Romeo and Juliet?"
    - "What's 2 + 2?"
    - "How do I write a for loop in Python?"
```

#### Multi-Tool Examples (Target: 500 examples)

```json
{
  "messages": [
    {"role": "user", "content": "What's on my calendar tomorrow and will I need an umbrella?"},
    {"role": "assistant", "content": "Let me check both for you.\n<tool>calendar|range=tomorrow</tool>"},
    {"role": "tool", "content": "Tomorrow:\n9:00 AM - Team standup\n2:00 PM - Client call\n6:00 PM - Dinner with Sarah"},
    {"role": "assistant", "content": "<tool>weather|location=user_location|forecast=tomorrow</tool>"},
    {"role": "tool", "content": "Tomorrow: High 55°F, Low 48°F, 70% chance of rain"},
    {"role": "assistant", "content": "Tomorrow you have three things: team standup at 9 AM, a client call at 2 PM, and dinner with Sarah at 6 PM. And yes, bring an umbrella - there's a 70% chance of rain with temperatures in the upper 40s to mid 50s."}
  ]
}
```

### Synthetic Data Generation Script

Use GPT-4 to generate training data:

```python
"""
Jubo Training Data Generator
Uses GPT-4 to create synthetic training examples for Jubo tool use.
"""

import json
import openai
from typing import List, Dict
import random

SYSTEM_PROMPT = """You are generating training data for an AI assistant called Jubo.

Jubo has these tools:
- <tool>weather|location=STRING|forecast=current|tomorrow|week</tool>
- <tool>calendar|range=today|tomorrow|this_week|DATE</tool>
- <tool>reminders|filter=all|today|overdue</tool>
- <tool>sports|league=STRING|team=STRING</tool>
- <tool>search|query=STRING</tool>

Generate realistic conversations where:
1. User asks something
2. Assistant decides if a tool is needed
3. If yes: outputs tool call, receives result, synthesizes response
4. If no: answers directly from knowledge

CRITICAL: Include negative examples where tools are NOT needed.
"""

GENERATION_PROMPT = """Generate {count} training examples for the "{category}" category.

Category description: {description}

Requirements:
- Realistic user queries (varied phrasing)
- Correct tool usage (or no tool if not needed)
- Natural response synthesis
- Mix of simple and complex queries

Output as JSON array of conversations.
"""

def generate_examples(category: str, description: str, count: int) -> List[Dict]:
    response = openai.ChatCompletion.create(
        model="gpt-4",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": GENERATION_PROMPT.format(
                count=count,
                category=category,
                description=description
            )}
        ],
        temperature=0.8,
        max_tokens=4000
    )
    return json.loads(response.choices[0].message.content)

# Example usage
categories = [
    ("weather_current", "User asks about current weather conditions", 200),
    ("weather_forecast", "User asks about future weather", 200),
    ("weather_implicit", "User asks something that implies weather need", 200),
    ("weather_negative", "User asks about weather concepts (no tool needed)", 200),
    ("calendar_view", "User wants to see their schedule", 200),
    ("calendar_negative", "User asks about calendar features (no tool)", 150),
    ("sports_scores", "User asks about game results or scores", 200),
    ("sports_negative", "User asks about sports rules/history (no tool)", 150),
    ("search_current", "User needs current information", 300),
    ("search_negative", "User asks general knowledge questions", 300),
    ("multi_tool", "User needs multiple pieces of information", 100),
]

all_examples = []
for category, description, count in categories:
    examples = generate_examples(category, description, count)
    all_examples.extend(examples)
    print(f"Generated {len(examples)} examples for {category}")

# Save dataset
with open("jubo_tool_training_data.jsonl", "w") as f:
    for example in all_examples:
        f.write(json.dumps(example) + "\n")

print(f"Total examples: {len(all_examples)}")
```

---

## 7. Training Pipeline

### Recommended Setup: Unsloth + Axolotl

#### Option A: Unsloth (Faster, Simpler)

```bash
# Install
pip install unsloth

# Clone training scripts
git clone https://github.com/unslothai/unsloth
```

```python
from unsloth import FastLanguageModel
import torch

# Load base model
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/SmolLM2-1.7B-Instruct",  # or Qwen2.5-3B
    max_seq_length=2048,
    load_in_4bit=True,
)

# Add LoRA adapters
model = FastLanguageModel.get_peft_model(
    model,
    r=64,
    lora_alpha=128,
    lora_dropout=0.05,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                    "gate_proj", "up_proj", "down_proj"],
)

# Training config
from trl import SFTTrainer
from transformers import TrainingArguments

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=2048,
    args=TrainingArguments(
        per_device_train_batch_size=4,
        gradient_accumulation_steps=4,
        warmup_ratio=0.03,
        num_train_epochs=3,
        learning_rate=2e-4,
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(),
        output_dir="outputs",
    ),
)

trainer.train()

# Save adapter
model.save_pretrained("jubo_adapter_v1")
```

#### Option B: Axolotl (More Configurable)

```yaml
# axolotl_config.yaml
base_model: Qwen/Qwen2.5-3B-Instruct
model_type: AutoModelForCausalLM

load_in_8bit: false
load_in_4bit: true

datasets:
  # Stage 1: Base behavior
  - path: GAIR/lima
    type: sharegpt

  - path: teknium/OpenHermes-2.5
    type: sharegpt
    shards: 10  # Use 10% subset

  # Stage 2: Tool use
  - path: hiyouga/glaive-function-calling-v2-sharegpt
    type: sharegpt

  - path: ./jubo_tool_training_data.jsonl
    type: sharegpt

dataset_prepared_path: ./prepared_data
output_dir: ./outputs/jubo_v1

adapter: lora
lora_r: 64
lora_alpha: 128
lora_dropout: 0.05
lora_target_modules:
  - q_proj
  - k_proj
  - v_proj
  - o_proj
  - gate_proj
  - up_proj
  - down_proj

sequence_len: 2048
sample_packing: true
pad_to_sequence_len: true

micro_batch_size: 4
gradient_accumulation_steps: 4
num_epochs: 3
learning_rate: 2e-4
lr_scheduler: cosine
warmup_ratio: 0.03

train_on_inputs: false
group_by_length: false

bf16: auto
tf32: true
gradient_checkpointing: true

logging_steps: 10
save_steps: 500
eval_steps: 500

deepspeed: null  # or deepspeed_configs/zero2.json for multi-GPU
```

```bash
# Run training
accelerate launch -m axolotl.cli.train axolotl_config.yaml

# Merge adapter (optional)
python -m axolotl.cli.merge_lora axolotl_config.yaml --lora_model_dir="./outputs/jubo_v1"
```

### Cloud GPU Options

| Provider | GPU | Cost | Notes |
|----------|-----|------|-------|
| RunPod | A100 80GB | ~$2/hr | Best for 3B models |
| Lambda Labs | A100 40GB | ~$1.50/hr | Good value |
| Vast.ai | RTX 4090 | ~$0.50/hr | Budget option |
| Google Colab Pro | A100 | $10/month | Limited hours |

For a 3B model with 10K examples:
- Training time: ~2-4 hours
- Estimated cost: $5-15

---

## 8. Implementation Changes

### Current LLMService Changes Required

The `LLMService.swift` needs modification to:
1. Detect tool calls in generated output
2. Pause generation at tool call
3. Execute tool and inject result
4. Continue generation

```swift
// Pseudocode for modified LLMService

func generate(messages: [Message]) -> AsyncThrowingStream<String, Error> {
    return AsyncThrowingStream { continuation in
        var fullResponse = ""

        // Start generation
        for await token in modelGenerate(messages) {
            fullResponse += token
            continuation.yield(token)

            // Check for tool call
            if let toolCall = detectToolCall(in: fullResponse) {
                // Pause generation
                continuation.yield("\n") // Visual separator

                // Execute tool
                let toolResult = await executeToolCall(toolCall)

                // Inject result into context
                let resultText = "<tool_result>\n\(toolResult)\n</tool_result>\n"
                continuation.yield(resultText)

                // Continue generation with updated context
                let updatedMessages = messages + [
                    Message(role: .assistant, content: fullResponse),
                    Message(role: .tool, content: toolResult)
                ]

                for await token in modelGenerate(updatedMessages, continueFrom: fullResponse) {
                    continuation.yield(token)
                }
            }
        }

        continuation.finish()
    }
}

func detectToolCall(in text: String) -> ToolCall? {
    // Regex: <tool>name|param=value|param2=value2</tool>
    let pattern = #"<tool>(\w+)\|(.+?)</tool>"#
    guard let match = text.range(of: pattern, options: .regularExpression) else {
        return nil
    }
    // Parse and return ToolCall struct
}

func executeToolCall(_ call: ToolCall) async -> String {
    switch call.name {
    case "weather":
        return await weatherService.fetch(location: call.params["location"])
    case "calendar":
        return await calendarService.fetch(range: call.params["range"])
    case "sports":
        return await sportsService.fetch(league: call.params["league"])
    case "search":
        return await searchService.search(query: call.params["query"])
    default:
        return "Unknown tool"
    }
}
```

### User Confirmation Flow

For privacy, we still want user confirmation before external requests:

```swift
func generate(messages: [Message]) -> AsyncThrowingStream<String, Error> {
    return AsyncThrowingStream { continuation in
        // ... generation code ...

        if let toolCall = detectToolCall(in: fullResponse) {
            // Check if tool requires confirmation
            if toolCall.requiresConfirmation {
                // Emit special token for UI to show confirmation dialog
                continuation.yield("<confirm_tool>\(toolCall.description)</confirm_tool>")

                // Wait for user confirmation (via separate channel)
                let confirmed = await waitForUserConfirmation()

                if confirmed {
                    let result = await executeToolCall(toolCall)
                    // ... continue ...
                } else {
                    continuation.yield("\nI'll answer based on my knowledge instead.\n")
                    // ... continue without tool ...
                }
            }
        }
    }
}
```

---

## 9. Evaluation & Quality Gates

### The Gauntlet (from Requirements Doc)

Before deploying any fine-tuned model, run automated evaluation:

```python
"""
Jubo Model Evaluation Suite ("The Gauntlet")
"""

import json
from typing import List, Dict, Tuple

class JuboEvaluator:
    def __init__(self, model, judge_model="gpt-4"):
        self.model = model
        self.judge = judge_model

    def evaluate(self, test_suite: List[Dict]) -> Dict:
        results = {
            "json_syntax_rate": 0,
            "tool_accuracy": 0,
            "no_tool_accuracy": 0,
            "response_quality": 0,
            "total_tests": len(test_suite)
        }

        for test in test_suite:
            response = self.model.generate(test["input"])

            # 1. JSON/Tool Syntax Check
            if self.check_tool_syntax(response):
                results["json_syntax_rate"] += 1

            # 2. Tool Usage Accuracy
            expected_tool = test.get("expected_tool")
            actual_tool = self.extract_tool(response)
            if expected_tool == actual_tool:
                if expected_tool:
                    results["tool_accuracy"] += 1
                else:
                    results["no_tool_accuracy"] += 1

            # 3. Response Quality (LLM-as-Judge)
            quality_score = self.judge_quality(
                query=test["input"],
                response=response,
                expected=test.get("expected_response")
            )
            results["response_quality"] += quality_score

        # Normalize scores
        results["json_syntax_rate"] /= results["total_tests"]
        results["tool_accuracy"] /= sum(1 for t in test_suite if t.get("expected_tool"))
        results["no_tool_accuracy"] /= sum(1 for t in test_suite if not t.get("expected_tool"))
        results["response_quality"] /= results["total_tests"]

        return results

# Quality Gates
MINIMUM_THRESHOLDS = {
    "json_syntax_rate": 0.98,      # Must be near-perfect
    "tool_accuracy": 0.85,          # When tool needed, use correct one
    "no_tool_accuracy": 0.90,       # Don't hallucinate tool use
    "response_quality": 0.75,       # Subjective quality score
}
```

### Test Suite Categories

```yaml
test_categories:
  tool_syntax:
    description: "Model outputs valid tool call format"
    count: 100

  tool_selection:
    description: "Model selects correct tool for query"
    count: 200

  no_tool_needed:
    description: "Model answers without tool when appropriate"
    count: 200

  result_synthesis:
    description: "Model naturally integrates tool results"
    count: 100

  edge_cases:
    description: "Ambiguous queries, clarification needed"
    count: 50

  multi_tool:
    description: "Queries requiring multiple tools"
    count: 50
```

---

## 10. Roadmap

### Phase 1: Data Preparation (Week 1-2)

- [ ] Download and prepare LIMA, OpenHermes subsets
- [ ] Download Glaive Function Calling v2 (ShareGPT format)
- [ ] Create Jubo-specific dataset generation script
- [ ] Generate 5,000+ custom tool use examples
- [ ] Create evaluation test suite (500 examples)

### Phase 2: Training Infrastructure (Week 2-3)

- [ ] Set up Axolotl/Unsloth environment
- [ ] Configure cloud GPU access (RunPod/Lambda)
- [ ] Create training configuration files
- [ ] Test training pipeline with small subset

### Phase 3: Stage 1 Training (Week 3-4)

- [ ] Train base assistant LoRA (LIMA + OpenHermes)
- [ ] Evaluate on general helpfulness benchmarks
- [ ] Iterate on hyperparameters if needed

### Phase 4: Stage 2 Training (Week 4-5)

- [ ] Train tool use LoRA (Glaive + Custom)
- [ ] Run "The Gauntlet" evaluation
- [ ] Iterate until quality gates pass

### Phase 5: Integration (Week 5-6)

- [ ] Modify LLMService for tool-augmented generation
- [ ] Update ChatViewModel for new flow
- [ ] Test on-device performance
- [ ] Quantize final model (4-bit for MLX)

### Phase 6: Validation (Week 6-7)

- [ ] Internal testing on real devices
- [ ] Battery/performance benchmarks
- [ ] User acceptance testing
- [ ] Iterate based on feedback

---

## Appendix A: Dataset Links

### Base Assistant Datasets
- [LIMA](https://huggingface.co/datasets/GAIR/lima)
- [OpenHermes 2.5](https://huggingface.co/datasets/teknium/OpenHermes-2.5)
- [SlimOrca](https://huggingface.co/datasets/Open-Orca/SlimOrca)

### Tool Use Datasets
- [Glaive Function Calling v2](https://huggingface.co/datasets/glaiveai/glaive-function-calling-v2)
- [Glaive v2 ShareGPT Format](https://huggingface.co/datasets/hiyouga/glaive-function-calling-v2-sharegpt)
- [Glaive v2 Llama Format](https://huggingface.co/datasets/rizerphe/glaive-function-calling-v2-llama)

### Training Frameworks
- [Unsloth](https://github.com/unslothai/unsloth)
- [Axolotl](https://github.com/axolotl-ai-cloud/axolotl)
- [TRL (Transformers Reinforcement Learning)](https://github.com/huggingface/trl)

---

## Appendix B: Tool Format Reference

### Tool Call Format

```xml
<tool>TOOL_NAME|param1=value1|param2=value2</tool>
```

### Tool Result Format

```xml
<tool_result>
Result content here (plain text, structured)
</tool_result>
```

### Complete Tool Definitions

```yaml
weather:
  format: "<tool>weather|location=STRING|forecast=current|tomorrow|week</tool>"
  examples:
    - "<tool>weather|location=Boston</tool>"
    - "<tool>weather|location=user_location|forecast=tomorrow</tool>"
  result_format: "Location: CITY\nTemperature: XX°F\nConditions: TEXT\n..."

calendar:
  format: "<tool>calendar|range=today|tomorrow|this_week|DATE</tool>"
  examples:
    - "<tool>calendar|range=today</tool>"
    - "<tool>calendar|range=2024-01-15</tool>"
  result_format: "TIME - Event name\nTIME - Event name\n..."

reminders:
  format: "<tool>reminders|filter=all|today|overdue|completed</tool>"
  examples:
    - "<tool>reminders|filter=today</tool>"
  result_format: "[ ] Reminder text (due: DATE)\n[x] Completed reminder\n..."

sports:
  format: "<tool>sports|league=STRING|team=STRING?</tool>"
  examples:
    - "<tool>sports|league=nba|team=lakers</tool>"
    - "<tool>sports|league=premier_league</tool>"
  result_format: "Team1 SCORE - SCORE Team2 (Status)\n..."

search:
  format: "<tool>search|query=STRING</tool>"
  examples:
    - "<tool>search|query=latest tech news</tool>"
  result_format: "Source: TITLE\nSummary: TEXT\n\nSource: TITLE\n..."
```

---

*Document created for Jubo project. Review and update as implementation progresses.*
