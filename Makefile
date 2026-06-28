# Target: iPhone X arm64, iOS 16.7.6, Dopamine rootless. Minimum supported OS: iOS 15.0.
TARGET := iphone:clang:16.5:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

# CRITICAL: Dopamine rootless scheme
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CinematicX

CinematicX_FILES = Tweak.x \
                   Modules/CXZoomController.x \
                   Modules/CXDepthEngine.x \
                   Modules/CXEdgeDetector.x \
                   Modules/CXBokehRenderer.x \
                   Modules/CXSubjectTracker.x \
                   Modules/CXRackFocus.x \
                   Modules/CXNativeUI.x \
                   Modules/CXLivePreview.x \
                   Modules/CXVideoRecorder.m

CinematicX_CFLAGS = -fobjc-arc -O2 -Wall -arch arm64
CinematicX_FRAMEWORKS = AVFoundation CoreImage Vision UIKit CoreMotion Metal MetalKit CoreVideo Photos
# NOTE: CoreCamera is NOT linked. PLCameraController/PLCameraView are hooked at runtime by
# Logos/ElleKit, so no link-time private framework is needed — and the CI SDK has no
# CoreCamera stub to link against (ld: framework 'CoreCamera' not found).

include $(THEOS)/makefiles/tweak.mk

# Build the Settings preference bundle alongside the tweak so a single .deb ships both.
SUBPROJECTS += Preferences
include $(THEOS)/makefiles/aggregate.mk
