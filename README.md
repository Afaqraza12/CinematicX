<div align="center">

# 🎥 CinematicX

### Professional Cinematic Mode for iPhone X

*Real optical zoom · Depth‑aware bokeh · Intelligent subject tracking · Cinematic rack focus — all on‑device, in real time.*

<p>
  <a href="https://github.com/Afaqraza12/CinematicX/actions/workflows/build.yml">
    <img src="https://github.com/Afaqraza12/CinematicX/actions/workflows/build.yml/badge.svg" alt="Build Status">
  </a>
  <img src="https://img.shields.io/badge/platform-iOS%2015.0%2B-black.svg" alt="Platform">
  <img src="https://img.shields.io/badge/arch-arm64-blue.svg" alt="Architecture">
  <img src="https://img.shields.io/badge/jailbreak-Dopamine%20(rootless)-purple.svg" alt="Jailbreak">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License"></a>
</p>

<p>
  <a href="https://github.com/Afaqraza12/CinematicX/stargazers">
    <img src="https://img.shields.io/github/stars/Afaqraza12/CinematicX?style=social" alt="Stars">
  </a>
  <a href="https://github.com/Afaqraza12/CinematicX/network/members">
    <img src="https://img.shields.io/github/forks/Afaqraza12/CinematicX?style=social" alt="Forks">
  </a>
  <a href="https://github.com/Afaqraza12/CinematicX/issues">
    <img src="https://img.shields.io/github/issues/Afaqraza12/CinematicX.svg" alt="Issues">
  </a>
  <img src="https://img.shields.io/github/last-commit/Afaqraza12/CinematicX.svg" alt="Last Commit">
  <img src="https://img.shields.io/github/repo-size/Afaqraza12/CinematicX.svg" alt="Repo Size">
</p>

</div>

---

CinematicX is a professional‑grade jailbreak tweak that unlocks cinematic video far beyond what Apple exposes on the iPhone X. It hooks deep into **AVFoundation**, **PLCameraController**, and the **Vision** framework, driving the **A11 Bionic Neural Engine** and **Metal** GPU to deliver a true cinematic recording experience — entirely on device, with no cloud and no latency.

Everything lives behind a **dedicated Cinematic button** inside the stock Camera app, so your normal photo and video modes stay completely untouched until *you* opt in.

---

## ✨ Features

| | Feature | What it does |
|---|---|---|
| 🔍 | **True Zoom Switching** | Smooth, animated 1× / 2× / 3× transitions with native haptic snap. 2× uses the optical telephoto lens; 3× adds a clean digital crop. |
| 🌫️ | **Depth‑Aware Bokeh** | Physically realistic background blur. Uses the real depth/disparity map via `CIDepthBlurEffect` when available, with a `CIBokehBlur` + Neural‑Engine‑mask fallback for genuine disc‑shaped bokeh — never a flat smear. |
| ✂️ | **High‑Quality Edges** | `VNGeneratePersonSegmentation` at **Accurate** quality runs off the capture thread, so hair and edges stay crisp without dropping frames. |
| 🎯 | **Intelligent Subject Tracking** | Self‑seeding person detection locks onto the dominant subject and tracks it cheaply frame‑to‑frame, re‑acquiring automatically when it’s lost. |
| 🎬 | **Cinematic Rack Focus** | Smooth focus pulls when the subject changes, with a subtle, drift‑free lens‑breathing effect and exposure lock to prevent flicker. |
| 🎛️ | **Native Overlay UI** | Zoom pills, a dedicated **CINE** mode button, a tap‑to‑focus square and a live blur slider — styled to feel native, with touch pass‑through so the stock shutter and controls keep working. |
| ⚙️ | **Settings Integration** | A full panel in the **Settings** app to enable/disable the tweak, respring, and view credits. |

---

## 📱 Requirements

| | |
|---|---|
| **Device** | iPhone X (Apple A11 Bionic) |
| **Architecture** | `arm64` |
| **Minimum iOS** | **15.0** (developed & tuned on iOS 16.7.6) |
| **Jailbreak** | Dopamine 2.x **rootless** |
| **Injector** | **ElleKit** (`org.coolstar.ellekit`) |
| **Extras** | PreferenceLoader (for the Settings panel) |

> CinematicX is **rootless‑native** — it installs under `/var/jb` and depends on ElleKit, not Substrate/MobileSubstrate.

---

## 🚀 Installation

### Option A — From a built `.deb`
1. Grab the latest `.deb` from the **[Actions](https://github.com/Afaqraza12/CinematicX/actions)** tab (artifacts) or the Releases page.
2. Open it in **Sileo** (or install via Filza) and let it pull in ElleKit + PreferenceLoader.
3. Respring when prompted.

### Option B — Build it yourself (GitHub Actions)
1. Fork this repo.
2. Open the **Actions** tab and run the **Build CinematicX** workflow.
3. Download the `.deb` artifact and install as above.

### Option C — Manual (SSH, rootless)
```bash
# Transfer the package to the device
scp packages/com.afaq.cinematicx_1.0.0_iphoneos-arm64.deb mobile@<iphone-ip>:/var/mobile/Documents/

# Install and apply
ssh mobile@<iphone-ip>
sudo dpkg -i /var/mobile/Documents/com.afaq.cinematicx_1.0.0_iphoneos-arm64.deb
sudo ldrestart   # light restart — no full reboot needed on Dopamine
```

---

## 🎬 Using CinematicX

1. Open the stock **Camera** app.
2. Tap the **CINE** button (top‑right). It turns solid yellow when Cinematic Mode is active — features run **only** while it’s on, never in plain photo/video mode.
3. Pick a zoom level with the **1× / 2× / 3×** pills.
4. Drag the **blur slider** (right edge) to dial bokeh from sharp to creamy.
5. Tap anywhere to set focus; move your subject to see the rack‑focus pull.

Prefer it off for a while? Flip the master switch in **Settings → CinematicX** and respring.

---

## 🏗️ Architecture

CinematicX is built module‑by‑module for stability and performance on the A11. The heavy Vision/CoreImage work runs on background queues; the capture thread only does a cached‑mask composite, so the preview stays smooth.

| Module | File | Responsibility |
|---|---|---|
| Zoom Controller | `Modules/CXZoomController.x` | Animated zoom ramps, snap points, haptics |
| Depth Engine | `Modules/CXDepthEngine.x` | Safe depth‑output attach + disparity map delivery |
| Edge Detector | `Modules/CXEdgeDetector.x` | Async Accurate person segmentation, cached mask |
| Bokeh Renderer | `Modules/CXBokehRenderer.x` | Depth blur → bokeh → Gaussian fallback (Metal) |
| Subject Tracker | `Modules/CXSubjectTracker.x` | Self‑seeding detection + cheap frame tracking |
| Rack Focus | `Modules/CXRackFocus.x` | Focus pulls, exposure lock, lens breathing |
| Overlay UI | `Modules/CXOverlayUI.x` | Native‑feeling controls injected into the Camera app |
| Orchestrator | `Tweak.x` | Wires the per‑frame cinematic pipeline |
| Settings | `Preferences/` | Settings.app panel (enable/disable, respring, credits) |

---

## 🧑‍💻 Development

You need [Theos](https://github.com/theos/theos) on macOS (or a jailbroken device) with the **iPhoneOS 16.5 SDK**.

```bash
export THEOS=~/theos
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless ARCHS=arm64
```

The build produces both the tweak and the Settings preference bundle in one `.deb`.

---

## 👨‍💻 Credits

**Designed & developed by [Afaq Raza](https://github.com/Afaqraza12).**

Built with care for the jailbreak community. If CinematicX makes your shots look better, a ⭐ on the repo means a lot.

> Credits are also shown in‑app under **Settings → CinematicX → Credits**.

---

## 📄 License

Released under the **MIT License** — see [LICENSE](LICENSE).

<div align="center">
<sub>© 2026 Afaq Raza · CinematicX</sub>
</div>
