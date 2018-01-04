PACKAGE 	= delete-chef-node
DATE 	 	 ?= $(shell date +%FT%T%z)
# VERSION  ?= $(shell git describe --tags --always --dirty --match=v* 2> /dev/null || \
# 									 cat $(CURDIR)/.version 2> /dev/null || echo v0)
VERSION   = $(shell $(GO) run $(PACKAGE).go -v | cut -f 2 -d ' ')

GOPATH 		= $(CURDIR)/.gopath~
BIN 			= $(GOPATH)/bin
BASE 			= $(GOPATH)/src/$(PACKAGE)
PKGS 			= $(or $(PKG),$(shell cd $(BASE) && env GOPATH=$(GOPATH) $(GO) list ./... | grep -v "^$(PACKAGE)/vendor/"))
TESTPKGS	= $(shell env GOPATH=$(GOPATH) $(GO) list -f '{{ if or .TestGoFiles .XTestGoFiles }}{{ .ImportPath }}{{ end }}' $(PKGS))

BUCKET		= binaries.devops.drinks.com

GOARCH = amd64

GO 				= go
GODOC			= godoc
GOFMT			= gofmt
GLIDE			= glide
TIMEOUT		= 15
V 				= 0
Q					= $(if $(filter 1,$V),,@)
M					= $(shell printf "\033[34;1m▶\033[0m")

.PHONY: all
all: fmt lint vendor linux darwin tidy

$(BASE): ; $(info $(M) setting GOPATH...)
	@mkdir -p $(dir $@)
	@ln -sf $(CURDIR) $@

# Tools
GOLINT = $(BIN)/golint
$(BIN)/golint: | $(BASE) ; $(info $(M) building golint…)
	$Q go get github.com/golang/lint/golint

.PHONY: linux
linux: $(BASE) ; $(info $(M) building executable...) @ ## Build binary
	$Q cd $(BASE) && GOOS=linux GOARCH=$(GOARCH) $(GO) build \
		 -tags release \
		 -ldflags '-X $(PACKAGE).Version=$(VERSION) -X $(PACKAGE).BuildDate=$(DATE)' \
		 -o bin/$(PACKAGE)-linux-$(GOARCH)

.PHONY: darwin
darwin: $(BASE) ; $(info $(M) building executable...) @ ## Build binary
	$Q cd $(BASE) && GOOS=darwin GOARCH=$(GOARCH) $(GO) build \
		 -tags release \
		 -ldflags '-X $(PACKAGE).Version=$(VERSION) -X $(PACKAGE).BuildDate=$(DATE)' \
		 -o bin/$(PACKAGE)-darwin-$(GOARCH)

.PHONY: lint
lint: vendor | $(BASE) $(GOLINT) ; $(info $(M) running golint…) @ ## Run golint
				$Q cd $(BASE) && ret=0 && for pkg in $(PKGS); do \
				 				test -z "$$($(GOLINT) $$pkg | tee /dev/stderr)" || ret=1 ; \
				 done ; exit $$ret

.PHONY: fmt
fmt: ; $(info $(M) running gofmt…) @ ## Run gofmt on all source files
	@ret=0 && for d in $$($(GO) list -f '{{.Dir}}' ./... | grep -v /vendor/); do \
		$(GOFMT) -l -w $$d/*.go || ret=$$? ; \
	 done ; exit $$ret

# Depenency management

glide.lock: glide.yaml | $(BASE) ; $(info $(M) updating dependencies...)
	$Q cd $(BASE) && $(GLIDE) update
	@touch $@
vendor: glide.lock | $(BASE) ; $(info $(M) retrieving dependencies...)
	$Q cd $(BASE) && $(GLIDE) --quiet install
	# @ln -nsf . vendor/src
	@touch $@

.PHONY: upload
upload: ; $(info $(M) uploading binary to S3...) @
	@aws s3 cp bin/$(PACKAGE)-linux-$(GOARCH) s3://$(BUCKET)/$(PACKAGE)/$(PACKAGE)-linux-$(GOARCH)-$(VERSION) 2> /dev/null
	@aws s3 cp bin/$(PACKAGE)-darwin-$(GOARCH) s3://$(BUCKET)/$(PACKAGE)/$(PACKAGE)-darwin-$(GOARCH)-$(VERSION) 2> /dev/null

.PHONY: clean
clean: ; $(info $(M) cleaning...) @ ## Clean shit up
	@rm -rf $(GOPATH)
	@rm -rf bin
	@rm -rf test/tests.* test/coverage.*

.PHONY: tidy
tidy: ; $(info $(M) tidying up build...) @ ## Tidy shit up
	@rm -rf $(GOPATH)

.PHONY: help
help:
	@grep -E '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: version
version:
	@echo $(VERSION)
