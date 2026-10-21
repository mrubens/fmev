# Examples

## Away-message emoji

[away_emoji.py](away_emoji.py) picks the best status emoji for each away message. Each message becomes the `state` of one request, with a single Choice question whose options are the candidate emoji and short descriptions of when each fits. It uses only the Python standard library.

```bash
fmev &
python3 examples/away_emoji.py
```

Output on an M4 Max (9 requests, 4 at a time, about 5.5 s in total):

```
🌴  0.72  Out of office until Monday the 14th, sunning myself in Lisbon. For anything urgent ping Priya.
✈️  0.94  Boarding now, back online when I land in Tokyo (~14h).
🤒  0.94  Down with the flu today. I'll catch up on messages tomorrow.
🍽️  0.72  Grabbing a quick bite, back in 30.
📅  0.89  Back-to-back calls until 3pm, I'll reply after.
🎯  0.89  Deep work block. Notifications off until noon.
👶  0.94  On parental leave until March welcoming our daughter. Sam is covering for me.
🎓  0.89  At KubeCon all week, replies will be slow.
🏠  0.89  Moving apartments today, mostly offline.
```

The number is the answer's Choice `confidence`, which comes from the model's stated probability.
