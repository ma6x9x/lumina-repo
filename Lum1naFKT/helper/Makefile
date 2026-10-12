# Root CLI: Dopamine jbclient_initialize_primitives requires uid 0.
# postinst marks this setuid; app/tweak also try persona spawn.
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = lum1na-fkt-dump

lum1na-fkt-dump_FILES = main.m ../KReader.m
lum1na-fkt-dump_CFLAGS = -fobjc-arc -Wno-unused-function -I..
lum1na-fkt-dump_FRAMEWORKS = Foundation IOSurface Metal IOKit
lum1na-fkt-dump_CODESIGN_FLAGS = -Sentitlements.plist
lum1na-fkt-dump_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
