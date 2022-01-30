TARGET = macosx:clang::10.9
ARCHS = x86_64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = emdreader

$(TOOL_NAME)_FILES = emdreader.mm
$(TOOL_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tool.mk

after-all::
	@mkdir -p bin
	@cp -v $(THEOS_OBJ_DIR)/$(TOOL_NAME) bin/
