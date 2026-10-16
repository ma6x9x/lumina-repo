TARGET := iphone:clang:16.5:15.0
# arm64e is required: RootHide/jbroot Settings loads PreferenceBundles as arm64e.
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Sk1nPrefs

# shared -> ../src (symlink); spkit lives under it. No literal ../ in _FILES.
Sk1nPrefs_FILES = Sk1nRootListController.m shared/Sk1nRespring.m shared/spkit/SPKRuntime.m
Sk1nPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
Sk1nPrefs_PRIVATE_FRAMEWORKS = Preferences
Sk1nPrefs_INSTALL_PATH = /Library/PreferenceBundles
Sk1nPrefs_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/shared -I$(THEOS_PROJECT_DIR)/shared/spkit -DSPK_CLASS_PREFIX=Sk1nPrefsSPK

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Sk1n.plist$(ECHO_END)
