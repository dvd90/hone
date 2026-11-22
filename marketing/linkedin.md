I built Hone, an open-source macOS app, because most of my prompts were worse than they needed to be.

The model was rarely the problem. The prompt was: one line, with no project, no stack and no definition of done. Fixing it by hand meant a trip to a chat window, so I rarely did.

Hone works on the text you select, in any app. Press Control-Option-Space and pick an action. Improve Prompt rewrites the draft for the model you target (Claude, GPT, Gemini, a coding agent), scores it before and after, and explains what changed. It uses your context: a saved profile about you or a project, notes for the run, attached text files, and the app and window you came from. When something is missing, it makes an assumption, writes it into the prompt and lists it so you can correct it, instead of leaving placeholders. The hotkey also runs actions like Proofread, plus your own.

A few decisions, and why:
- It runs on subscriptions you already pay for, through the official Claude Code, Codex and Gemini CLIs. Claude Code calls run with tools, MCP servers and personal settings turned off; Codex and Gemini run read-only. API keys also work and stay in the Keychain.
- No backend and no telemetry. Text goes only to the provider you choose.
- Native SwiftUI with no third-party dependencies, and a CI gate of 95% line coverage on the logic code.

It's MIT licensed. Feedback and pull requests are welcome:
https://github.com/dvd90/prompt-forge
