# 🌙 Long Night

### A 3D night game in the city

[![Godot 4](https://img.shields.io/badge/Godot-4-478CBF?style=for-the-badge&logo=godot-engine&logoColor=white)](https://godotengine.org)
[![Android](https://img.shields.io/badge/Android-arm64-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/Gass-OS/long-night/actions)
[![Version 0.1](https://img.shields.io/badge/version-0.1-blue?style=for-the-badge)](https://github.com/Gass-OS/long-night)
[![Build](https://github.com/Gass-OS/long-night/actions/workflows/build.yml/badge.svg)](https://github.com/Gass-OS/long-night/actions)

**Long Night** is a 3D night game built with **Godot** for **Android** — a city after dark, a drone intro sweeping over the streets, police on patrol, and a character fighting to survive the night.

---

## 📖 What it is

- 🌃 **A city at night** — streets and a medina (`city.gd`, `medina.gd`), built for a dark, tense atmosphere
- 🎬 **Drone intro** — a cinematic drone flyover with its own HUD, plus a video intro
- 👮 **Police** — patrolling officers in the city
- 🐕 **A dog** — man's best friend, in the night city
- 🧍 **Character v2** — health and blood, with quality settings (LOW / MEDIUM / HIGH), FPS toggle and volume in the menu
- 🎮 **Touch controls** — built for mobile play

> **Status: early prototype (v0.1).** The game is in active development — step by step, with the character, police, drone intro and city already in place. Expect rough edges.

---

## 📦 Get the game

CI builds the APK on push to `main` — download it from the latest successful run's artifacts ([Actions page](https://github.com/Gass-OS/long-night/actions)).

> The game is not on Google Play — the CI artifact is the way to install it for now.

---

## 🛠️ Build it yourself

```bash
git clone https://github.com/Gass-OS/long-night.git
cd long-night
# Open project.godot with Godot 4 — project files live at the repo root
# Android export: arm64-v8a, package com.aymen.longnight
```

Pushing to `main` triggers the same build in CI — no local Android SDK needed.

### Project details

| | |
|:---|---|
| **Engine** | Godot 4, Forward+ renderer |
| **Language** | GDScript |
| **Genre** | 3D night action |
| **Android** | arm64-v8a — package `com.aymen.longnight` |

### Project layout

```
├── main.tscn / menu.tscn / intro.tscn   # game, menu, intro
├── city.gd / medina.gd                 # the night city
├── character.gd / player.gd            # the character + player
├── police.gd / dog.gd / drone.gd       # police, dog, drone intro
├── hud.gd / audio.gd / settings.gd     # HUD, audio, settings
└── assets/                             # character, models, textures
```

---

<div align="center">

**Made with Godot 🇹🇳**

*A Gass-OS game — survive the long night.*

</div>
