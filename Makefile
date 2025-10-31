SHELL := /bin/bash

# Root where impala_udf/udf.h is found as $(IMPALA_UDF_INCLUDE_ROOT)/impala_udf/udf.h
IMPALA_UDF_INCLUDE_ROOT ?= /usr/include

CXX ?= g++
CXXFLAGS ?= -O2 -fPIC -std=c++11 -Wall -Wextra -Werror
CPPFLAGS ?= -I$(IMPALA_UDF_INCLUDE_ROOT)
# Optional OpenSSL include/lib override for non-system layouts (e.g., Homebrew)
ifdef OPENSSL_INCLUDE_DIR
CPPFLAGS += -I$(OPENSSL_INCLUDE_DIR)
endif
ifdef OPENSSL_LIB_DIR
LDFLAGS += -L$(OPENSSL_LIB_DIR)
endif
LDFLAGS ?= -shared -Wl,-z,relro,-z,now
LDLIBS ?= -lcrypto

SRC := src/aes_udf.cc
BUILD_DIR := build
DIST_DIR := dist
TARGET := $(BUILD_DIR)/libaes_udf.so
TARGET_RHEL8 := $(DIST_DIR)/rhel8/libaes_udf-rhel8.so
TARGET_RHEL9 := $(DIST_DIR)/rhel9/libaes_udf-rhel9.so

BIN_DIR := bin
CLI := $(BIN_DIR)/aes_cli
CLI_SRC := src/aes_cli.cc

.PHONY: all clean strip print-syms test-cli check dist rhel8 rhel9

all: $(TARGET)

$(BUILD_DIR):
	@mkdir -p $@

$(TARGET): $(SRC) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

$(BIN_DIR):
	@mkdir -p $@

$(CLI): $(CLI_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

strip: $(TARGET)
	strip -s $(TARGET)

print-syms: $(TARGET)
	nm -D $(TARGET) | c++filt | rg 'aes_(en|de)crypt' || true

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR) $(DIST_DIR)

test-cli: $(CLI)
	$(CLI) enc 1234567890123456 ABC | tee /tmp/aes_cli.out

check: test-cli
	@grep -q "b64:y6Ss+zCYObpCbgfWfyNWTw==" /tmp/aes_cli.out && echo "OK" || (echo "Expected base64 not found" && exit 1)

$(DIST_DIR)/rhel8:
	@mkdir -p $@

$(DIST_DIR)/rhel9:
	@mkdir -p $@

# Build with API compat macros to ease building on respective OS
rhel8: CPPFLAGS += -DOPENSSL_API_COMPAT=0x10100000L
rhel8: $(TARGET_RHEL8)

$(TARGET_RHEL8): $(SRC) | $(DIST_DIR)/rhel8
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

rhel9: CPPFLAGS += -DOPENSSL_API_COMPAT=0x30000000L
rhel9: $(TARGET_RHEL9)

$(TARGET_RHEL9): $(SRC) | $(DIST_DIR)/rhel9
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)
