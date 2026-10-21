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

For example, to pick the best status emoji for an away message, make the message the state and the candidate emoji the options of a Choice question:

```bash
curl -s localhost:8787/v1/systemone -H 'Content-Type: application/json' -d '{
  "model": "fmev",
  "state": {"away_message": "Dentist appointment then lunch, back around 2."},
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

Response:

```json
{
  "answers": {
    "emoji": {
      "choice": "🍽️",
      "confidence": 0.7,
      "probabilities": {"✈️": 0.05, "🌴": 0.05, "🍽️": 0.75, "🎯": 0.05, "📅": 0.05, "🤒": 0.05},
      "type": "choice"
    }
  },
  "model": "fmev",
  "usage": {"input_tokens": 355, "output_tokens": 18}
}
```

The message fits both 🍽️ and 🤒, so the model reports only 75% confidence in its pick. fmev gets one stated probability from the model, so the other options share the remainder equally.

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
| `FMEV_CONCURRENCY` | `4` | On-device generations in flight at once |

## How it works, and how it differs from Jev

Foundation Models exposes no token probabilities, so fmev asks the model for them. Each question is one greedy generation, constrained by a schema to an allowed option (`yes`/`no` for Noul, a criteria name for Choice, a level number for Score) plus the model's stated probability, 0–100, that its answer is correct. The prompt anchors each range to a situation ("95–100 only when the state states the answer directly…"). The chosen option gets that probability, and the remainder is spread evenly over the other options. `score` and `confidence` then use TypeSafe's published formulas.

These are verbalized probabilities, not the model's internal ones, and they are not calibrated like Jev's. The model is often confidently wrong on hard items, so treat confidence as a weak signal and check thresholds on your own data.

Measured on [jevbench](https://github.com/fstandhartinger/jevbench)'s 231 public decisions (M4 Max, macOS 27, on-device model variant AFM 3 Core Advanced). Macs with the AFM 3 Core variant may score differently. To reproduce, see [eval/](eval/README.md).

| Set | Accuracy | p50 latency | ECE |
| --- | --- | --- | --- |
| standard (72) | 84.7% | 0.58 s | 0.12 |
| easy (48) | 100% | 0.60 s | 0.09 |
| hard (111) | 39.6% | 0.90 s | 0.38 |

Other approaches were measured and dropped: sampling the model several times and using vote shares as probabilities (same accuracy, 2–4× slower, no better calibrated), four other confidence prompts, and Apple's content-tagging adapter (2 points less accurate and slower).

- Questions in one request run in parallel.
- `box` questions and image `assets` return 422.
- The context window is small (8,192 tokens), so a long `state` returns 413.
- Apple's guardrails can refuse some content, which returns 422.
