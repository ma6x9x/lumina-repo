# App: arm64 so Procursus libkrw.0 (arm64-only) can load.
# Also uses direct krw_initializer on libkrw-dopamine (works when loader arch mismatches).
TARGET := iphone:clang:latest:15.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Lum1naFKTApp

Lum1naFKTApp_FILES = main.m AppDelegate.m RootViewController.m ../KReader.m ../ANEYcraft.m
Lum1naFKTApp_CFLAGS = -fobjc-arc -Wno-unused-function -I..
Lum1naFKTApp_FRAMEWORKS = UIKit Foundation IOSurface Metal IOKit CoreML
Lum1naFKTApp_CODESIGN_FLAGS = -Sentitlements.plist
Lum1naFKTApp_INSTALL_PATH = /Applications
Lum1naFKTApp_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk
