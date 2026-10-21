# fmev

A local server that speaks TypeSafe's System One API (`POST /v1/systemone`, `GET /v1/models`) and answers with the Apple Foundation Models model built into macOS. Nothing to download: on an Apple Silicon Mac with Apple Intelligence on, existing Jev clients and the official SDKs work against it once you change the base URL.

fmev is an independent project. It is not affiliated with or endorsed by TypeSafe AI or Apple; "Jev" and "System One" refer to TypeSafe's API, which fmev implements.

## Requirements

- Apple Silicon Mac, macOS 27+, Apple Intelligence turned on (System Settings → Apple Intelligence & Siri)
- To build it: Xcode 27 / Swift 6.4 toolchain

## Install

With [Homebrew](https://brew.sh):

```bash
brew install mrubens/tap/fmev
fmev                          # run in the foreground, or:
brew services start fmev      # run in the background, and again at every login
```

If `brew services info fmev` shows `Running: false` right after you start it, launchd has deferred the first start until your next login. Start it now with `launchctl kickstart gui/$(id -u)/sh.brew.fmev`. Logs go to `$(brew --prefix)/var/log/fmev.log`.

Without Homebrew, download `fmev-<version>-macos-arm64.zip` from the [releases page](https://github.com/mrubens/fmev/releases). The binary is signed and notarized. Or build from source:

```bash
swift build -c release
.build/release/fmev
```

## Use

```bash
curl -s localhost:8787/v1/systemone -H 'Content-Type: application/json' -d '{
  "model": "jev-latest",
  "state": "I was charged twice. Please refund the extra charge.",
  "questions": {
    "billing": {"type": "noul", "instructions": "Is this message about billing?"},
    "urgency": {"type": "score", "instructions": "How urgent is this?", "criteria": ["Can wait", "This week", "Today"]}
  }
}'
```

With the SDK:

```python
from typesafe_sdk import TypeSafeClient
client = TypeSafeClient(api_key="local", base_url="http://127.0.0.1:8787")
```

```js
const client = new TypeSafeClient({ apiKey: "local", baseURL: "http://127.0.0.1:8787" });
```

## Configuration (environment variables)

`fmev --help` lists these settings; `fmev --version` prints the version.

| Variable | Default | Meaning |
| --- | --- | --- |
| `FMEV_PORT` / `FMEV_HOST` | `8787` / `127.0.0.1` | Listen address |
| `FMEV_API_KEY` | unset | If set, requests need `Authorization: Bearer <key>` |
| `FMEV_MODE` | `verbal` | How probabilities are produced: `verbal` or `adaptive` (see below) |
| `FMEV_SAMPLES` | `8` | Adaptive mode: the most samples per question |
| `FMEV_EARLY_STOP` | `3` | Adaptive mode: samples drawn before stopping on a unanimous answer |
| `FMEV_TEMPERATURE` | `1.0` | Adaptive mode: sampling temperature |
| `FMEV_SMOOTHING` | `0.25` | Adaptive mode: additive smoothing on the vote counts |
| `FMEV_CONCURRENCY` | `4` | On-device generations in flight at once |

In adaptive mode, the `X-FM-Samples: <n>` request header overrides the sample count for a single request (non-standard).

## How it works, and how it differs from Jev

Foundation Models exposes no token probabilities, so fmev builds them in one of two ways. In both, the answer is constrained by a schema to an allowed option: `yes`/`no` for Noul, a criteria name for Choice, a level number for Score. `score` and `confidence` then use TypeSafe's published formulas.

- **`verbal` (default):** one greedy generation returns the answer plus the model's stated probability (0–100) that it is correct. The prompt anchors each range to a situation ("95–100 only when the state states the answer directly…"). The stated answer gets that probability, and the remainder is spread evenly over the other options. These are verbalized probabilities, not the model's internal ones.
- **`adaptive`:** draws 3 sampled answers and stops if they agree, otherwise draws up to `FMEV_SAMPLES`. The probabilities are smoothed vote shares. Choice and Noul options are shuffled for each sample to reduce position bias, and seeds come from a hash of the request, so the same request returns the same answer.

Measured on [jevbench](https://github.com/fstandhartinger/jevbench)'s 231 public decisions (M4 Max, macOS 27, on-device model variant AFM 3 Core Advanced). Macs with the AFM 3 Core variant may score differently. To reproduce, see [eval/](eval/README.md).

| Mode | Accuracy | p50 latency | Hard-tier ECE | AUROC |
| --- | --- | --- | --- | --- |
| verbal | 66.2% | 0.58 s | 0.38 | 0.60 |
| adaptive | 65.4% | 1.07 s | 0.40 | 0.46 |

Other approaches were measured and dropped: always drawing 8 samples (same accuracy as adaptive at twice the latency), four other confidence prompts, and Apple's content-tagging adapter (2 points less accurate and slower).

AUROC measures how well the confidence separates right answers from wrong ones (0.5 is chance).

- No mode is calibrated like Jev. The model is often confidently wrong on hard items, so treat confidence as a weak signal and check thresholds on your own data.
- `usage` counts the tokens of every generation.
- `box` questions and image `assets` return 422.
- The context window is small (8,192 tokens), so a long `state` returns 413.
- Apple's guardrails can refuse some content, which returns 422.

## Example: the best emoji for an away message

The away message is the state, and the candidate emoji are the options of a Choice question:

```bash
curl -s localhost:8787/v1/systemone -H 'Content-Type: application/json' -d '{
  "model": "jev-latest",
  "state": {"away_message": "Boarding now, back online when I land in Tokyo (~14h)."},
  "questions": {
    "emoji": {
      "type": "choice",
      "instructions": "Which status emoji best fits this away message?",
      "criteria": {
        "🌴": "On vacation or holiday",
        "✈️": "Traveling: on a flight or in transit",
        "🤒": "Out sick",
        "🍽️": "On a meal break, back shortly",
        "📅": "In meetings, available later today",
        "🎯": "Focus time, do not disturb"
      }
    }
  }
}'
```

```json
{
  "answers": {
    "emoji": {
      "choice": "✈️",
      "confidence": 0.94,
      "probabilities": {"✈️": 0.95, "🌴": 0.01, "🍽️": 0.01, "🎯": 0.01, "📅": 0.01, "🤒": 0.01},
      "type": "choice"
    }
  },
  "model": "fmev",
  "usage": {"input_tokens": 360, "output_tokens": 18}
}
```
