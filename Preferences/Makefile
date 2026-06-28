TARGET := iphone:clang:16.5:15.0
ARCHS = arm64
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CinematicXPrefs

CinematicXPrefs_FILES = CXPrefsController.m
CinematicXPrefs_INSTALL_PATH = /Library/PreferenceBundles
CinematicXPrefs_FRAMEWORKS = UIKit
CinematicXPrefs_PRIVATE_FRAMEWORKS = Preferences
CinematicXPrefs_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CinematicX.plist$(ECHO_END)
