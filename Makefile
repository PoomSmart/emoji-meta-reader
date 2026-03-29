TARGET = macosx:clang::10.9
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = emdreader

MARISA_PREFIX = /opt/homebrew

$(TOOL_NAME)_FILES = emdreader.mm
$(TOOL_NAME)_CFLAGS = -fobjc-arc -std=c++17 -I$(MARISA_PREFIX)/include
$(TOOL_NAME)_LDFLAGS = -L$(MARISA_PREFIX)/lib -lmarisa

include $(THEOS_MAKE_PATH)/tool.mk

after-all::
	@mkdir -p bin
	@cp -v $(THEOS_OBJ_DIR)/$(TOOL_NAME) bin/
