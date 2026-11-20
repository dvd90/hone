# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users
People who write prompts for AI tools and people editing everyday text (email, docs, messages) in any Mac app. Both are first-class: Improve Prompt and the quick text actions are co-equal. They want to sharpen a prompt or transform a selection without leaving the app they are in.

## Product Purpose
Hone improves prompts (scores before and after, diagnoses weaknesses, rewrites with prompt-engineering techniques, asks questions to fill placeholders) and runs text actions (Rewrite, Proofread, Concise, tone, Summarize, Explain, Translate, Draft Reply, custom actions) on any selected text. Success: a better prompt or text back in place in seconds.

## Positioning
Runs on the AI subscription the user already pays for, through the official Claude Code, Codex and Gemini CLIs, or on an API key. No backend, no account.

## Operating Context
Entry points: main window, global hotkey (Control-Option-Space) floating quick panel with Replace and Copy, right-click Services menu, menu bar item. Users switch in from another app, act, and return to it.

## Capabilities and Constraints
Native macOS app (SwiftUI, macOS 14+, no third-party dependencies). Selected text is content, never instructions. Keys only in the Keychain; no telemetry; no new network destinations. Distributed as a Developer ID signed and notarized DMG, not the Mac App Store (sandboxing would remove subscription providers).

## Brand Commitments
Name: Hone (formerly Prompt Forge). Visual reference made binding by the owner on 2026-11-20: adopt the look of Dial, a macOS menu-bar time tracker (graphite surfaces, periwinkle accent, hairline-ruled sections, a sunrise-gradient slider). Follow the system light/dark appearance.

## Evidence on Hand
No testimonials, user counts or benchmarks exist; do not invent them.

## Product Principles
- Stay out of the way: the user came from another app and wants to get back to it.
- The result is the hero: the improved prompt or rewritten text leads every screen it appears on.
- Native first: standard macOS controls and navigation; the brand lives in palette, density and one signature moment.
- Private by design: nothing leaves the Mac except the request to the provider the user chose.

## Accessibility & Inclusion
WCAG AA text contrast in light and dark, Reduce Motion honored, VoiceOver labels on non-text indicators.
