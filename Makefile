TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

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

CinematicX_CFLAGS = -fobjc-arc -O2 -Wall
CinematicX_FRAMEWORKS = AVFoundation CoreImage Vision UIKit CoreMotion Metal MetalKit CoreVideo
CinematicX_PRIVATE_FRAMEWORKS = CoreCamera

include $(THEOS)/makefiles/tweak.mk
