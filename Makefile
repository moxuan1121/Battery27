ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Battery27
Battery27_FILES = Tweak.x
Battery27_FRAMEWORKS = UIKit
Battery27_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
