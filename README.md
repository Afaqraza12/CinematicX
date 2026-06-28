<div align="center">
  <h1>🎥 CinematicX</h1>
  <p><b>Professional Cinematic Mode for iPhone X (iOS 14-16)</b></p>

  <p>
    <a href="https://github.com/Afaqraza12/CinematicX/actions/workflows/build.yml">
      <img src="https://github.com/Afaqraza12/CinematicX/actions/workflows/build.yml/badge.svg" alt="Build Status">
    </a>
    <a href="https://github.com/Afaqraza12/CinematicX/blob/main/LICENSE">
      <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License">
    </a>
  </p>
</div>

<br/>

CinematicX is a professional-grade iOS jailbreak tweak that unlocks cinematic video capabilities far beyond what Apple exposes by default. Built specifically for the iPhone X, this tweak hooks deep into AVFoundation, PLCameraController, and the Vision framework to deliver an unparalleled recording experience.

## ✨ Features

- **🔍 True Zoom Switching:** Smooth, animated transitions between 1x, 2x, and 3x zoom levels with native haptic feedback.
- **🌫️ Depth-Aware Bokeh (Coming Soon):** Real-time, physically-realistic background blur utilizing depth data mapped directly to the camera sensor.
- **🎯 Intelligent Subject Tracking (Coming Soon):** Lock focus on moving subjects with advanced Vision framework tracking.
- **🎬 Rack Focus (Coming Soon):** Cinematic, smooth focus pulls mimicking physical lens mechanics, complete with a subtle "breathing" effect.
- **🎛️ Native Overlay UI (Coming Soon):** Seamlessly integrated controls within the default Camera app for a native look and feel.

## 🛠️ Architecture

CinematicX is built module-by-module to ensure stability and high performance, even on the A11 Bionic chip.

1. **Zoom Controller:** `CXZoomController.x` handles virtual device zoom factors.
2. **Depth Engine:** `CXDepthEngine.x` forces depth data output during video recording.
3. **Edge Detector:** `CXEdgeDetector.x` uses Vision and Metal for crisp semantic segmentation.
4. **Bokeh Renderer:** `CXBokehRenderer.x` applies realistic `CIDepthBlurEffect`.
5. **Subject Tracker:** `CXSubjectTracker.x` maintains subject focus across frames.
6. **Rack Focus:** `CXRackFocus.x` animates `AVCaptureDevice` properties.
7. **Overlay UI:** `CXOverlayUI.x` injects controls into `PLCameraView`.

## 🚀 Installation

### Automated Build (GitHub Actions)
1. Fork or clone this repository.
2. Navigate to the **Actions** tab and wait for the `Build CinematicX` workflow to complete.
3. Download the `.deb` file from the artifacts section.

### Manual Installation
Transfer the downloaded `.deb` file to your jailbroken iPhone X:
```bash
scp packages/com.afaq.cinematicx_1.0.0_iphoneos-arm.deb root@<iPhone-IP>:/tmp/
ssh root@<iPhone-IP>
dpkg -i /tmp/com.afaq.cinematicx_1.0.0_iphoneos-arm.deb
killall SpringBoard
```

## 🏗️ Development Setup

To build this project locally, you need [Theos](https://github.com/theos/theos) installed on macOS or a jailbroken iOS device.

```bash
export THEOS=~/theos
make package FINALPACKAGE=1
```

## 👨‍💻 Author

**Afaq Raza**

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
