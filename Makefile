# VibeTokHD - Theos Makefile

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VibeTokHD
VibeTokHD_FILES = Tweak.x VHDManager.m VHDDownload.m
VibeTokHD_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-unused-variable -Wno-arc-performSelector-leaks -Wno-deprecated-declarations
VibeTokHD_LDFLAGS = -framework UIKit -framework Foundation -framework Photos -framework CoreGraphics -framework AVFoundation

include $(THEOS)/makefiles/tweak.mk