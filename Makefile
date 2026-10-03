# VibeTokHD - Theos Makefile

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VibeTokHD
VibeTokHD_FILES = Tweak.x
VibeTokHD_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/tweak.mk

# Build IPA directly
package::
	@echo "Building VibeTokHD package..."
