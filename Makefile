# Copyright (c) 2018 SPARKL Limited. All Rights Reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Author <jacoby@sparkl.com> Jacoby Thwaites
-include ../../make_inc.mk

# Required pylint version prefix matches e.g. pylint 2.1.1
PYLINT_REQ := pylint 2.1
PYLINT_VER := $(shell which pylint && pylint --version | grep pylint)

COMPILE_FIRST := \
	sse \
	sse_configure \
	sse_svc_provision

BEHAVIOURS := \
	sse \
	sse_configure \
	sse_svc_provision

INCLUDE_APPS := \
	apps/sse \
	apps/sse_cfg \
	apps/sse_configure \
	apps/sse_log \
	apps/sse_listen \
	apps/sse_svc \
	apps/sse_yaws \
	deps/yaws

REQUIRE_APPS := \
	deps/jsx \
	deps/yaws \
	apps/sse \
	apps/sse_cfg \
	apps/sse_log \
	apps/sse_svc \
	apps/sse_yaws \
	apps/sse_listen

CT_REQUIRE_APPS :=	\
	apps/sse \
	apps/sse_ct

.PHONY: deps
deps: super/deps
	@bash $(ROOT_DIR)/apps/sse/priv/ansible/playbook.sh priv/ansible/$(OS)/svc_blockchain.yml

# pylint versions differ in their error reporting for a given syntax
# so we only run if in the lint target if it's the version we know.
ifneq ($(findstring $(PYLINT_REQ), $(PYLINT_VER)),)
.PHONY: lint
lint: super/lint
	@python3 -m pycodestyle priv/scripts
	@PYTHONPATH=priv/scripts/ python3 -m pylint priv/scripts/
endif

.PHONY: compile
compile: super/compile
	@python3 -m compileall priv/scripts

.PHONY: docs
docs: super/docs
	mkdir -p doc/py
	which epydoc && \
	    find priv/scripts/checker -name "*.py" -print -exec epydoc -v --parse-only --html {} -o doc/py \; || \
	    echo skipping python gen

.PHONY: test
test:
	@PYTHONPATH=priv/scripts python3 -m pytest -s priv/scripts/test
