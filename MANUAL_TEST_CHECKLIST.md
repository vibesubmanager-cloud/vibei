# Manual test checklist

- [ ] Airplane mode: Tap & Speak → “find a bottle” → camera + ticks + boxes (no crash).
- [ ] Echo test: app speech / ticks do not fire false commands during search.
- [ ] “stop speaking” mutes phrases but search ticks continue.
- [ ] “stop looking” / STOP button / system back → direct HOME, camera released.
- [ ] 60s no-find announcement once; say “keep looking” continues; “stop” → HOME.
- [ ] “describe” with no proxy / no consent → offline object narration (never silent fail).
- [ ] Listening: rising earcon + pulse; 30s “I’m still listening”; 60s ends with descending earcon.
- [ ] Missing camera permission spoken; Settings tick sound / vibration toggles work.
- [ ] “search text bag” → text camera with green match boxes + ticks.
- [ ] “nearby text” → reads OCR lines with positions.
- [ ] “nearby objects” → lists bottles/cups/etc with boxes.
- [ ] “remember this as my mug” then “find my mug” → object search.
- [ ] Airplane mode: find object, find text, describe, read — all work; circle hollow/bobbing; no “offline/internet” speech.
- [ ] Online enhancements off → pure offline behavior unchanged.
- [ ] Describe speaks offline sentence first; with Fake/real cloud, only additions follow.