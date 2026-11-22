# Hone: 60-second video script

Audience: developers and tech leads who write prompts every day.
Tone: plain and practical. Real screen recordings of the app, no stock footage, no music swells.

## Before recording
- Use a real provider (Claude Code logged in is the default) and record real output. Don't type fake results into the UI.
- Grant Accessibility (System Settings → Privacy & Security → Accessibility → Hone) so the hotkey reads the selection and Replace appears.
- Create a profile in Settings → Context with a neutral name such as "Side project", so no personal details appear on screen.
- Settings → Provider shows where each CLI was found, and that path contains your macOS user name. Crop or blur it.

## Script

| Time | Shot | On-screen text | Voiceover |
|---|---|---|---|
| 0:00–0:05 | A code editor. A one-line prompt is selected: "add tests for the payment service". | Most prompts start like this | Most prompts start like this: one line, no project, no stack, no idea what done looks like. |
| 0:05–0:13 | Press ⌃⌥Space. Hone's quick panel opens near the cursor while the editor keeps focus. The action list shows number keys 1–9. The "Prompt context" row shows the profile and a chip with the app and window title. | Select text in any app · ⌃⌥Space | Hone is a native Mac app. Select text in any app, press Control-Option-Space, and pick an action. |
| 0:13–0:24 | Press 1 (Improve Prompt). The improved prompt streams in. A short "Assumed: …" line appears under it. | Grounded in your context | Improve Prompt rewrites it using your saved profile and the app you were in. When something is missing, it makes an assumption and tells you, instead of leaving blanks. |
| 0:24–0:29 | Press Return. The improved prompt replaces the selection in the editor. | ⏎ Replace | Press Return, and it replaces your selection in place. |
| 0:29–0:40 | Main window, Improve Prompt result: the score track (before and after), the improved prompt, then the Assumptions list. Type a correction under one assumption and click "Re-run with corrections". | Score before and after · Assumptions you can correct | In the main window you see a score before and after, what changed, and every assumption, with a field to correct it and run again. |
| 0:40–0:47 | Select a paragraph in a mail draft. ⌃⌥Space, then Proofread. Cut to Settings → Actions, adding a custom action. | Proofread · Summarize · your own actions | The same hotkey runs everyday actions like Proofread and Summarize, plus actions you write yourself. |
| 0:47–0:55 | Settings → Provider: Claude Code selected, click "Test connection". Then briefly show the provider list. | Your Claude, ChatGPT or Gemini subscription, or an API key | It runs on the subscription you already have, through the official Claude Code, Codex or Gemini CLI, or on an API key. No backend, no telemetry. |
| 0:55–1:00 | The GitHub repository page, then a terminal running `./install.sh`. | Hone · open source, MIT · github.com/dvd90/prompt-forge | Hone is open source under the MIT license. Clone it and run the install script. |

## Voiceover only (for timing, about 140 words)

Most prompts start like this: one line, no project, no stack, no idea what done looks like.

Hone is a native Mac app. Select text in any app, press Control-Option-Space, and pick an action.

Improve Prompt rewrites it using your saved profile and the app you were in. When something is missing, it makes an assumption and tells you, instead of leaving blanks.

Press Return, and it replaces your selection in place.

In the main window you see a score before and after, what changed, and every assumption, with a field to correct it and run again.

The same hotkey runs everyday actions like Proofread and Summarize, plus actions you write yourself.

It runs on the subscription you already have, through the official Claude Code, Codex or Gemini CLI, or on an API key. No backend, no telemetry.

Hone is open source under the MIT license. Clone it and run the install script.
