# Lum1na-FKT — aggregate: SpringBoard tweak + Dump app (12 mini 17.3 / 21D50)
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
# Device dpkg on Dopamine 17.x cannot unpack data.tar.lzma ("split"/unpack error).
# This Mac has no dpkg-deb, so Theos dm.pl would default to lzma without this.
export THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += tweak app helper
include $(THEOS_MAKE_PATH)/aggregate.mk
