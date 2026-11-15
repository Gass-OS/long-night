# 🏛️ Kasserine Stories 3D

### An interactive 3D open-world story about Kasserine, Tunisia

[![React](https://img.shields.io/badge/React-18-61DAFB?style=for-the-badge&logo=react&logoColor=white)](https://react.dev)
[![Three.js](https://img.shields.io/badge/Three.js-3D-000000?style=for-the-badge&logo=three.js&logoColor=white)](https://threejs.org)
[![Capacitor](https://img.shields.io/badge/Capacitor-Android-119EFF?style=for-the-badge&logo=capacitor&logoColor=white)](https://capacitorjs.com)
[![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=for-the-badge&logo=typescript&logoColor=white)](https://www.typescriptlang.org)

**Kasserine Stories 3D** is an interactive 3D open-world story experience set in Kasserine, Tunisia. Explore a living 3D world in your browser or on Android, follow story missions, and meet the city — with a minimap radar, a game HUD, touch controls, and AI-powered storytelling.

---

## 📖 What it is

- 🌍 **A 3D open world** — a Three.js world of Kasserine (`src/game/world.ts`, `models.ts`, `textures.ts`), with an engine, audio and story system
- 📖 **Story missions** — follow the story (`story.ts`) with mission briefings, objectives and a pause/settings flow
- 🧭 **Game HUD** — health/objective HUD, minimap radar, touch controls built for mobile
- 🌐 **Multilingual** — interface text in several languages (`i18n.ts`)
- 🤖 **AI storytelling** — optional Gemini AI integration for story content (needs your own API key)
- 📱 **Android app** — packaged with Capacitor (`com.kasserine.stories`), so the same world runs as a native Android app

> **Status: early development.** The world, missions and HUD are in place and actively built. Expect rough edges.

---

## 🚀 Run locally

**Prerequisites:** Node.js

```bash
npm install
```

Set your Gemini API key in `.env.local` (only needed for the AI story features):

```
GEMINI_API_KEY=your_key_here
```

Then run the app:

```bash
npm run dev
```

Open the Vite dev server (port 3000) in your browser.

## 📦 Build

```bash
npm run build        # vite build --base=./  → dist/
npx cap sync android # sync the web build into the Android app
```

The Android project lives in `android/` (Capacitor 8). Open it in Android Studio to build and install the APK.

### Project layout

```
├── src/
│   ├── game/        # engine, world, models, textures, story, audio, i18n
│   ├── components/  # GameHUD, MinimapRadar, MissionModal, TouchControls,
│   │                # IntroModal, PauseSettingsModal
│   ├── App.tsx
│   └── main.tsx
├── android/         # Capacitor Android app (com.kasserine.stories)
├── public/
├── index.html       # "Kasserine Stories 3D — Tunisia Open World"
└── vite.config.ts
```

### Tech

| | |
|:---|---|
| **Frontend** | React 18 + TypeScript + Vite + Tailwind CSS |
| **3D** | Three.js |
| **Mobile** | Capacitor 8 (Android) |
| **AI** | Google Gemini (`@google/genai`, optional) |

---

<div align="center">

**Made in Kasserine, Tunisia 🇹🇳**

*A Gass-OS project — stories from the city, in 3D.*

</div>
