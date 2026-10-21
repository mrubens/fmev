"""Picks the best status emoji for away messages with fmev.

Each away message is the state of one System One request, with a single Choice
question whose options are the candidate emoji. Requires a running fmev server:

    fmev &
    python3 examples/away_emoji.py

Uses only the Python standard library. Set FMEV_URL to point at another server.
"""

import json
import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

URL = os.environ.get("FMEV_URL", "http://127.0.0.1:8787") + "/v1/systemone"

EMOJI = {
    "🌴": "On vacation or holiday, relaxing away from work",
    "✈️": "Traveling: on a flight, in transit or on a business trip",
    "🤒": "Out sick or recovering from illness or a medical appointment",
    "🍽️": "On a lunch or meal break, back shortly",
    "📅": "In meetings or a workshop, available later the same day",
    "🎯": "Heads-down focus time; do not disturb, notifications paused",
    "👶": "On parental leave caring for a new child",
    "🎓": "At a conference, training or course",
    "🏠": "Out for a personal matter such as moving house or family time",
}

MESSAGES = [
    "Out of office until Monday the 14th, sunning myself in Lisbon. For anything urgent ping Priya.",
    "Boarding now, back online when I land in Tokyo (~14h).",
    "Down with the flu today. I'll catch up on messages tomorrow.",
    "Grabbing a quick bite, back in 30.",
    "Back-to-back calls until 3pm, I'll reply after.",
    "Deep work block. Notifications off until noon.",
    "On parental leave until March welcoming our daughter. Sam is covering for me.",
    "At KubeCon all week, replies will be slow.",
    "Moving apartments today, mostly offline.",
]


def best_emoji(message):
    body = json.dumps({
        "model": "jev-latest",
        "state": {"away_message": message},
        "questions": {
            "emoji": {
                "type": "choice",
                "instructions": "Which status emoji best fits this away message?",
                "criteria": EMOJI,
            }
        },
    }).encode()
    request = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request) as response:
        return json.load(response)["answers"]["emoji"]


if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=4) as pool:
        answers = list(pool.map(best_emoji, MESSAGES))
    for message, answer in zip(MESSAGES, answers):
        print(f"{answer['choice']}  {answer['confidence']:.2f}  {message}")
