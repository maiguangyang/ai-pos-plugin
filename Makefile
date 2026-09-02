PLUGIN_ROOT ?= .

INTEGRATION_PACKAGE_DIRS := $(patsubst %/pubspec.yaml,%,$(wildcard $(PLUGIN_ROOT)/integrations/*/packages/*/pubspec.yaml))
INTEGRATION_APP_DIRS := $(patsubst %/pubspec.yaml,%,$(wildcard $(PLUGIN_ROOT)/integrations/*/apps/*/pubspec.yaml))

PACKAGE_DIRS := \
	$(PLUGIN_ROOT)/core/ai_pos_plugin_api \
	$(PLUGIN_ROOT)/core/ai_pos_floating_workspace \
	$(PLUGIN_ROOT)/core/ai_pos_plugin_runtime \
	$(PLUGIN_ROOT)/core/ai_pos_plugin_testkit \
	$(INTEGRATION_PACKAGE_DIRS) \
	$(INTEGRATION_APP_DIRS) \
	$(PLUGIN_ROOT)/example/plugin_host/packages/ai_pos_example_plugin \
	$(PLUGIN_ROOT)/example/plugin_host

SOURCE_DIRS := \
	$(PLUGIN_ROOT)/core \
	$(PLUGIN_ROOT)/example \
	$(addsuffix /lib,$(INTEGRATION_PACKAGE_DIRS)) \
	$(addsuffix /test,$(INTEGRATION_PACKAGE_DIRS)) \
	$(addsuffix /lib,$(INTEGRATION_APP_DIRS)) \
	$(addsuffix /test,$(INTEGRATION_APP_DIRS))

.PHONY: list_package_dirs pub_get format format_check analyze test boundaries verify

list_package_dirs:
	@for dir in $(PACKAGE_DIRS); do echo $$dir; done

pub_get:
	@set -e; for dir in $(PACKAGE_DIRS); do \
		(cd $$dir && flutter pub get); \
	done

format:
	dart format $(SOURCE_DIRS)

format_check:
	dart format --output=none --set-exit-if-changed $(SOURCE_DIRS)

analyze:
	@set -e; for dir in $(PACKAGE_DIRS); do \
		(cd $$dir && flutter analyze); \
	done

test:
	@set -e; for dir in $(PACKAGE_DIRS); do \
		(cd $$dir && flutter test); \
	done

boundaries:
	@cd $(PLUGIN_ROOT)/core/ai_pos_plugin_testkit && \
		dart run bin/check_import_boundaries.dart --root ../..

verify: pub_get format_check analyze test boundaries
