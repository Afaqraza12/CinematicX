# Target: iPhone X arm64, iOS 16.7.6, Dopamine rootless
TARGET := iphone:clang:16.5:14.0
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
                   Modules/CXOverlayUI.x

CinematicX_CFLAGS = -fobjc-arc -O2 -Wall -arch arm64
CinematicX_FRAMEWORKS = AVFoundation CoreImage Vision UIKit CoreMotion Metal MetalKit CoreVideo

include $(THEOS)/makefiles/tweak.mk
