IMAGE_REG=quay.io
IMAGE_ORG=mstoklus
IMAGE_NAME=cloud-resource-operator
MANIFEST_NAME=cloud-resources
NAMESPACE=cloud-resource-operator
PREV_VERSION=0.22.3
VERSION=0.23.0
COMPILE_TARGET=./tmp/_output/bin/$(IMAGE_NAME)

SHELL=/bin/bash

# If the _correct_ version of operator-sdk is on the path, use that (faster);
# otherwise use it through "go run" (slower but will always work and will use correct version)
OPERATOR_SDK_VERSION=1.2.0
ifeq ($(shell operator-sdk version 2> /dev/null | sed -e 's/", .*/"/' -e 's/.* //'), "v$(OPERATOR_SDK_VERSION)")
	OPERATOR_SDK ?= operator-sdk
else
	OPERATOR_SDK ?= go run github.com/operator-framework/operator-sdk/cmd/operator-sdk
endif

AUTH_TOKEN=$(shell curl -sH "Content-Type: application/json" -XPOST https://quay.io/cnr/api/v1/users/login -d '{"user": {"username": "$(QUAY_USERNAME)", "password": "${QUAY_PASSWORD}"}}' | jq -r '.token')

OS := $(shell uname)
ifeq ($(OS),Darwin)
	OPERATOR_SDK_OS := apple-darwin
else
	OPERATOR_SDK_OS := linux-gnu
endif

.PHONY: build
build:
	@GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o=$(COMPILE_TARGET) ./main.go

.PHONY: run
run:
	RECTIME=30 WATCH_NAMESPACE=$(NAMESPACE) go run ./main.go

.PHONY: setup/service_account
setup/service_account: kustomize
	@-oc new-project $(NAMESPACE)
	@oc project $(NAMESPACE)
	@-oc create -f config/rbac/service_account.yaml -n $(NAMESPACE)
	@$(KUSTOMIZE) build config/rbac | oc replace --force -f -	

.PHONY: code/run/service_account
code/run/service_account: setup/service_account
	@oc login --token=$(shell oc serviceaccounts get-token cloud-resource-operator -n ${NAMESPACE}) --server=$(shell sh -c "oc cluster-info | grep -Eo 'https?://[-a-zA-Z0-9\.:]*'") --kubeconfig=TMP_SA_KUBECONFIG --insecure-skip-tls-verify=true
	WATCH_NAMESPACE=$(NAMESPACE) go run ./main.go

.PHONY: code/gen
code/gen: manifests kustomize generate


## TODO -------------------------------------------------------------------------
.PHONY: gen/csv
gen/csv:
	sed -i.bak 's/image:.*/image: quay\.io\/integreatly\/cloud-resource-operator:v$(VERSION)/g' config/manager/manager.yaml && rm config/manager/manager.yaml.bak
	@$(OPERATOR_SDK) generate csv --operator-name=cloud-resources --csv-version $(VERSION) --from-version $(PREV_VERSION) --make-manifests=false --update-crds --csv-channel=integreatly --default-channel --verbose
	@sed -i.bak 's/$(PREV_VERSION)/$(VERSION)/g' deploy/olm-catalog/cloud-resources/cloud-resources.package.yaml && rm deploy/olm-catalog/cloud-resources/cloud-resources.package.yaml.bak
	@sed -i.bak s/cloud-resource-operator:v$(PREV_VERSION)/cloud-resource-operator:v$(VERSION)/g deploy/olm-catalog/cloud-resources/$(VERSION)/cloud-resources.v$(VERSION).clusterserviceversion.yaml && rm deploy/olm-catalog/cloud-resources/$(VERSION)/cloud-resources.v$(VERSION).clusterserviceversion.yaml.bak

.PHONY: code/fix
code/fix:
	@go mod tidy
	@gofmt -w `find . -type f -name '*.go' -not -path "./vendor/*"`

.PHONY: code/check
code/check:
	@diff -u <(echo -n) <(gofmt -d `find . -type f -name '*.go' -not -path "./vendor/*"`)

.PHONY: vendor/fix
vendor/fix:
	go mod tidy
	go mod vendor

.PHONY: vendor/check
vendor/check: vendor/fix
	git diff --exit-code vendor/

.PHONY: cluster/prepare
cluster/prepare: kustomize
	-oc new-project $(NAMESPACE) || true
	-oc label namespace $(NAMESPACE) monitoring-key=middleware
	$(KUSTOMIZE) build config/crd | oc apply -f -

.PHONY: cluster/seed/workshop/blobstorage
cluster/seed/workshop/blobstorage:
	@cat config/samples/integreatly_v1alpha1_blobstorage.yaml | sed "s/type: REPLACE_ME/type: workshop/g" | oc apply -f - -n $(NAMESPACE)

.PHONY: cluster/seed/managed/blobstorage
cluster/seed/managed/blobstorage:
	@cat config/samples/integreatly_v1alpha1_blobstorage.yaml | sed "s/type: REPLACE_ME/type: managed/g" | oc apply -f - -n $(NAMESPACE)

.PHONY: cluster/seed/workshop/redis
cluster/seed/workshop/redis:
	@cat config/samples/integreatly_v1alpha1_redis.yaml | sed "s/type: REPLACE_ME/type: workshop/g" | oc apply -f - -n $(NAMESPACE)

.PHONY: cluster/seed/managed/redis
cluster/seed/managed/redis:
	@cat config/samples/integreatly_v1alpha1_redis.yaml | sed "s/type: REPLACE_ME/type: managed/g" | oc apply -f - -n $(NAMESPACE)

.PHONY: cluster/seed/workshop/postgres
cluster/seed/workshop/postgres:
	@cat config/samples/integreatly_v1alpha1_postgres.yaml | sed "s/type: REPLACE_ME/type: workshop/g" | oc apply -f - -n $(NAMESPACE)

.PHONY: cluster/seed/managed/postgres
cluster/seed/managed/postgres:
	@cat config/samples/integreatly_v1alpha1_postgres.yaml | sed "s/type: REPLACE_ME/type: managed/g" | oc apply -f - -n $(NAMESPACE)

.PHONY: cluster/clean
cluster/clean:
	@$(KUSTOMIZE) build config/crd | kubectl delete -f -
	@$(KUSTOMIZE) build config/rbac | oc delete --force -f -	
	oc delete project $(NAMESPACE)

.PHONY: test/unit/setup
test/unit/setup:
	@echo Installing gotest
	go get -u github.com/rakyll/gotest

.PHONY: test/unit
test/unit:
	@echo Running tests:
	GO111MODULE=off go get -u github.com/rakyll/gotest
	gotest -v -covermode=count -coverprofile=coverage.out ./pkg/providers/... ./pkg/resources/... ./apis/integreatly/v1alpha1/types/... ./pkg/client/...

.PHONY: test/unit/coverage
test/unit/coverage:
	@echo Running the coverage cli and html
	go tool cover -html=coverage.out
	go tool cover -func=coverage.out

.PHONY: test/unit/ci
test/unit/ci: test/unit
	@echo Removing mock file coverage
	sed -i.bak '/_moq.go/d' coverage.out

.PHONY: image/build
image/build: build
	echo "build image $(IMAGE_REG)/$(IMAGE_ORG)/$(IMAGE_NAME):$(VERSION)"
	docker build . -t $(IMAGE_REG)/$(IMAGE_ORG)/$(IMAGE_NAME):$(VERSION)

.PHONY: image/push
image/push: image/build
	docker push $(IMAGE_REG)/$(IMAGE_ORG)/$(IMAGE_NAME):$(VERSION)

## TODO -----------------

.PHONY: test/e2e/prow
test/e2e/prow: cluster/prepare
	@echo Running e2e tests:
	GO111MODULE=on $(OPERATOR_SDK) test local ./test/e2e --up-local --namespace $(NAMESPACE) --go-test-flags "-timeout=60m -v"
	oc delete project $(NAMESPACE)

.PHONY: test/e2e/local
test/e2e/local: cluster/prepare
	@echo Running e2e tests:
	$(OPERATOR_SDK) test local ./test/e2e --up-local --namespace $(NAMESPACE) --go-test-flags "-timeout=60m -v"
	oc delete project $(NAMESPACE)

.PHONY: test/e2e/image
test/e2e/image:
	@echo Running e2e tests:
	$(OPERATOR_SDK) test local ./test/e2e --go-test-flags "-timeout=60m -v -parallel=2" --image $(IMAGE_REG)/$(IMAGE_ORG)/$(IMAGE_NAME):$(VERSION)


























# Current Operator version
VERSION ?= 0.0.1
# Default bundle image tag
BUNDLE_IMG ?= controller-bundle:$(VERSION)
# Options for 'bundle-build'
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# Image URL to use all building/pushing image targets
IMG ?= controller:latest
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: manager

# Run tests
ENVTEST_ASSETS_DIR = $(shell pwd)/testbin
test: generate fmt vet manifests
	mkdir -p $(ENVTEST_ASSETS_DIR)
	test -f $(ENVTEST_ASSETS_DIR)/setup-envtest.sh || curl -sSLo $(ENVTEST_ASSETS_DIR)/setup-envtest.sh https://raw.githubusercontent.com/kubernetes-sigs/controller-runtime/v0.6.3/hack/setup-envtest.sh
	source $(ENVTEST_ASSETS_DIR)/setup-envtest.sh; fetch_envtest_tools $(ENVTEST_ASSETS_DIR); setup_envtest_env $(ENVTEST_ASSETS_DIR); go test ./... -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager main.go


# Install CRDs into a cluster
install: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests kustomize
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.3.0 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

kustomize:
ifeq (, $(shell which kustomize))
	@{ \
	set -e ;\
	KUSTOMIZE_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$KUSTOMIZE_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/kustomize/kustomize/v3@v3.5.4 ;\
	rm -rf $$KUSTOMIZE_GEN_TMP_DIR ;\
	}
KUSTOMIZE=$(GOBIN)/kustomize
else
KUSTOMIZE=$(shell which kustomize)
endif

# Generate bundle manifests and metadata, then validate generated files.
.PHONY: bundle
bundle: manifests kustomize
	operator-sdk generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | operator-sdk generate bundle -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)
	operator-sdk bundle validate ./bundle

# Build the bundle image.
.PHONY: bundle-build
bundle-build:
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

