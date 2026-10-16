TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

# Default rootless; CI / local builds override with THEOS_PACKAGE_SCHEME=roothide
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Sk1n

# ObjC ONLY. A Swift-linked dylib in SpringBoard means Safe Mode
# (SwiftPeek/docs/DEPENDENCY_PLAN.md hazard registry). No .swift, no SwiftUI.
#
# SPKit is shared source. src/spkit is a symlink to ../../SPKit - a literal
# ../ in _FILES makes Theos write objects outside .theos/obj.
Sk1n_FILES = \
	src/spkit/SPKRuntime.m \
	src/Sk1nTweak.m \
	src/Sk1nHook.m \
	src/Sk1nPrefs.m \
	src/Sk1nSkin.m \
	src/Sk1nSkinStore.m \
	src/Sk1nIconEngine.m \
	src/Sk1nDockPlate.m \
	src/Sk1nSlideToUnlockView.m \
	src/Sk1nLockScreen.m \
	src/Sk1nRespring.m

# -DSPK_CLASS_PREFIX: unique per consumer (two dylibs, one SpringBoard).
Sk1n_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations \
	-I$(THEOS_PROJECT_DIR)/src/spkit -I$(THEOS_PROJECT_DIR)/src -DSPK_CLASS_PREFIX=Sk1nSPK
Sk1n_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += sk1nprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
