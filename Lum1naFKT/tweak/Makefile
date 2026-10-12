TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Lum1naFKT

Lum1naFKT_FILES = Tweak.x ../KReader.m
Lum1naFKT_CFLAGS = -fobjc-arc -Wno-unused-function -I..
Lum1naFKT_FRAMEWORKS = UIKit Foundation IOSurface Metal IOKit

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS_MAKE_PATH)/tweak.mk
