KUSTOMIZE ?= oc kustomize
OPERATOR_CHARTS := charts/operators
PROVISIONING_CHART := charts/cluster-provisioning/openshift-provisioning

# PolicyGenerator is a kustomize *exec plugin*, so `oc kustomize` above cannot run
# it: there is no way to pass --enable-alpha-plugins, and oc ships no plugin home.
# validate-policies therefore needs a real kustomize binary with the plugin
# installed beside it, which is what install-policy-generator sets up. Versions
# track the hub stack (ACM 2.17 / OpenShift GitOps 1.21).
TOOLS_DIR := $(CURDIR)/.tools
KUSTOMIZE_VERSION ?= v5.8.1
POLICY_GENERATOR_VERSION ?= v1.19.0
PLUGIN_HOME := $(TOOLS_DIR)/kustomize-plugins
PLUGIN_PATH := $(PLUGIN_HOME)/policy.open-cluster-management.io/v1/policygenerator

.PHONY: help render validate validate-operators validate-operator-install \
	validate-hub validate-provisioning validate-clusters validate-policies \
	validate-onboarding install-policy-generator validate-cmp-parity \
	bootstrap-hub bootstrap-hub-dry-run destroy-hub

# The install templates are duplicated in every operator chart and must stay
# byte-identical — there is nothing per-chart in them to parameterise, so any
# difference is drift, not intent. Nesting them under templates/install/ is
# what makes that mechanically checkable.
SHARED_INSTALL_FILES := _operator.tpl namespace.yaml operatorgroup.yaml \
	subscription.yaml

# extra-subscriptions.yaml is the one install template that is not universal:
# it only ships in the charts that actually declare extraOperators. The two
# have to travel together in both directions — the template without the values
# key is dead code, and the key without the template is worse, because setting
# it would render nothing and report nothing. That second failure can also
# arrive from a cluster or env values file rather than from the chart, so the
# check scans those too.
CONDITIONAL_INSTALL_FILE := extra-subscriptions.yaml
INSTALL_REFERENCE := charts/operators/cert-manager/templates/install
CONDITIONAL_REFERENCE := charts/operators/logging/templates/install

BOOTSTRAP_VALUES ?= clusters/mgt/acm-hub/bootstrap.yaml

help:
	@echo "Targets:"
	@echo "  render                  render one chart for one cluster the way ArgoCD does"
	@echo "                          make render CLUSTER=dev/example-cluster CHART=keycloak"
	@echo "                          add FILES=1 for the values chain, VALUES=1 for merged values"
	@echo "  validate                validate ACM bootstrap and operator targets"
	@echo "  validate-operators      lint and render the operator charts each cluster enables"
	@echo "  validate-operator-install  check the shared install templates, and that no values"
	@echo "                          file sets extraOperators on a chart that ignores it"
	@echo "  validate-hub            validate the ACM hub bootstrap manifests"
	@echo "  validate-policies       build every PolicyGenerator dir under policies/"
	@echo "  validate-cmp-parity     check the CMP matches between bootstrap and the chart"
	@echo "  install-policy-generator  install kustomize + the PolicyGenerator plugin into .tools"
	@echo "  validate-provisioning   lint the provisioning chart for all sample clusters"
	@echo "  validate-onboarding     render both onboarding charts for every cluster/team, and"
	@echo "                          check that neither chart can ever render nothing"
	@echo "  validate-clusters       check clusterRegistered against the live hub (needs a kubeconfig)"
	@echo "  bootstrap-hub           provision the ACM hub cluster on AWS"
	@echo "  bootstrap-hub-dry-run   generate install-config.yaml without installing"
	@echo "  destroy-hub             tear down the bootstrapped hub cluster"

validate: validate-hub validate-operator-install validate-operators \
	validate-provisioning validate-onboarding validate-policies validate-cmp-parity

# Deliberately not part of `validate`: this one answers a question rather than
# checking a rule. The validate targets render every chart and throw the output
# away; this renders one and shows it to you, through the same values chain the
# ApplicationSet uses. See scripts/render.sh for the chain itself.
render:
	@test -n "$(CLUSTER)" || { echo "usage: make render CLUSTER=<env>/<cluster> CHART=<chart> [TEAM=<team>] [FILES=1|VALUES=1]"; exit 2; }
	@test -n "$(CHART)" || { echo "usage: make render CLUSTER=<env>/<cluster> CHART=<chart> [TEAM=<team>] [FILES=1|VALUES=1]"; exit 2; }
	@./scripts/render.sh "$(CLUSTER)" "$(CHART)" \
		$(if $(TEAM),--team "$(TEAM)") \
		$(if $(FILES),--files) $(if $(VALUES),--values)

# cert-manager is the reference copy only because it is an ordinary chart with
# no install-time quirks; any of the forty would do. Charts may add their own
# files to install/ — cost-management-service puts its CatalogSource there —
# so this checks by name rather than diffing the directories.
validate-operator-install:
	@fail=0; \
	for chart in $(OPERATOR_CHARTS)/*/; do \
		[ -f "$$chart/Chart.yaml" ] || continue; \
		for f in $(SHARED_INSTALL_FILES); do \
			if [ ! -f "$$chart/templates/install/$$f" ]; then \
				echo "MISSING  $$chart/templates/install/$$f"; fail=1; \
			elif ! cmp -s "$(INSTALL_REFERENCE)/$$f" "$$chart/templates/install/$$f"; then \
				echo "DRIFTED  $$chart/templates/install/$$f"; fail=1; \
			fi; \
		done; \
		tpl="$$chart/templates/install/$(CONDITIONAL_INSTALL_FILE)"; \
		grep -q '^  extraOperators:' "$$chart/values.yaml" && key=yes || key=no; \
		if [ -f "$$tpl" ] && [ "$$key" = no ]; then \
			echo "ORPHANED $$tpl — no extraOperators key in values.yaml"; fail=1; \
		elif [ ! -f "$$tpl" ] && [ "$$key" = yes ]; then \
			echo "INERT    $$chart/values.yaml declares extraOperators but has no $(CONDITIONAL_INSTALL_FILE)"; fail=1; \
		elif [ -f "$$tpl" ] && ! cmp -s "$(CONDITIONAL_REFERENCE)/$(CONDITIONAL_INSTALL_FILE)" "$$tpl"; then \
			echo "DRIFTED  $$tpl"; fail=1; \
		fi; \
	done; \
	[ $$fail -eq 0 ] || { echo "install templates are inconsistent across $(OPERATOR_CHARTS)/*"; exit 1; }
	@echo "OK   install templates consistent in all $(OPERATOR_CHARTS)/*"
	@violations=$$(for f in $$(find env clusters -type f \( -name conf.yaml \
			-o -name operators.yaml -o -path '*/operators/*.yaml' \) | sort); do \
		awk '/^[A-Za-z0-9_-]+:/ { chart=$$0; sub(/:.*/, "", chart); next } \
		     /^  extraOperators:/ { rest=$$0; sub(/^  extraOperators:[ \t]*/, "", rest); \
		                            if (rest != "{}") print chart }' "$$f" \
		| sort -u \
		| while read -r chart; do \
			[ -f "$(OPERATOR_CHARTS)/$$chart/templates/install/$(CONDITIONAL_INSTALL_FILE)" ] \
				|| echo "INERT    $$f sets $$chart.extraOperators, but $$chart has no $(CONDITIONAL_INSTALL_FILE)"; \
		done; \
	done); \
	[ -z "$$violations" ] || { echo "$$violations"; \
		echo "a chart only honours extraOperators if it ships $(CONDITIONAL_INSTALL_FILE); copy it in from $(CONDITIONAL_REFERENCE)"; \
		exit 1; }
	@echo "OK   no cluster or env values set extraOperators on a chart that ignores it"

validate-hub:
	@$(KUSTOMIZE) clusters/mgt/acm-hub > /dev/null
	@echo "OK   clusters/mgt/acm-hub"

install-policy-generator:
	@command -v go > /dev/null || { echo "go is required: https://go.dev/dl/"; exit 1; }
	@mkdir -p $(PLUGIN_PATH)
	GOBIN=$(TOOLS_DIR) go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)
	GOBIN=$(PLUGIN_PATH) go install \
		open-cluster-management.io/policy-generator-plugin/cmd/PolicyGenerator@$(POLICY_GENERATOR_VERSION)
	@echo "OK   kustomize $(KUSTOMIZE_VERSION) + PolicyGenerator $(POLICY_GENERATOR_VERSION) in $(TOOLS_DIR)"

# Renders every PolicyGenerator directory the same way the repo-server CMP does,
# so a broken policy fails here rather than as an opaque ComparisonError in ArgoCD.
# "The same way" is load-bearing: the ${...} tokens are substituted with sed, not
# a template engine, because ACM hub templates ({{hub ... hub}}) live in these
# manifests and must survive the render untouched. Keep this in step with
# clusters/mgt/acm-hub/bootstrap/openshift-gitops/instance/policy-generator-cmp.yaml.
validate-policies:
	@test -x $(TOOLS_DIR)/kustomize || { \
		echo "kustomize with the PolicyGenerator plugin is not installed"; \
		echo "run: make install-policy-generator"; exit 1; }
	@work=$$(mktemp -d); trap 'rm -rf "$$work"' EXIT; \
	cp -R policies "$$work/"; cp -R policy-values "$$work/"; \
	find "$$work/policies" -type f -name '*.yaml' -exec sed -i.bak \
		-e 's|$${POLICY_NAMESPACE}|open-cluster-management-policies|g' \
		-e 's|$${REMEDIATION}|inform|g' \
		-e 's|$${EVAL_COMPLIANT}|10m|g' \
		-e 's|$${EVAL_NONCOMPLIANT}|30s|g' {} +; \
	find "$$work" -name '*.bak' -delete; \
	found=0; \
	for k in policies/*/*/kustomization.yaml; do \
		[ -f "$$k" ] || continue; \
		found=1; dir=$$(dirname "$$k"); \
		if KUSTOMIZE_PLUGIN_HOME=$(PLUGIN_HOME) $(TOOLS_DIR)/kustomize build \
				--enable-alpha-plugins --load-restrictor LoadRestrictionsNone \
				"$$work/$$dir" > /dev/null; then \
			echo "OK   $$dir"; \
		else \
			echo "FAIL $$dir"; exit 1; \
		fi; \
	done; \
	[ $$found -eq 1 ] || echo "OK   no policy directories under policies/"

# The PolicyGenerator CMP is defined twice: the hand-applied bootstrap copy that
# runs today, and charts/operators/openshift-gitops, which takes over when
# openshift-gitops.argocd.include flips. They must agree. If the chart copy drifts
# or loses the sidecar, that flip hands the ArgoCD CR to a repo-server with no
# plugin, and every policy Application fails with an opaque ComparisonError --
# long after the commit that caused it. Compare them semantically (sorted keys,
# so YAML mapping order does not count as a difference) rather than by diffing
# the files, which are legitimately laid out differently.
#
# POLICY_GENERATOR_CMP_CONFIG_SHA is excluded: it is a hash of plugin.yaml that
# only the chart can compute, and its whole job is to differ whenever the plugin
# config changes. Bootstrap has no equivalent and needs none -- it is applied
# once, at install, with nothing running yet to go stale.
validate-cmp-parity:
	@command -v yq > /dev/null 2>&1 || { \
		echo "SKIP cmp-parity (yq not installed)"; exit 0; }
	@boot=clusters/mgt/acm-hub/bootstrap/openshift-gitops/instance; \
	tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	helm template cmp-parity $(OPERATOR_CHARTS)/openshift-gitops \
		--set 'openshift-gitops.argocd.include=true' \
		--set 'openshift-gitops.argocd.policyGenerator.include=true' > "$$tmp/render.yaml" || exit 1; \
	fail=0; \
	yq -o=yaml '.spec.repo | sort_keys(..) | ... comments=""' "$$boot/argocd.yaml" > "$$tmp/repo-boot.yaml" || exit 1; \
	yq -o=yaml 'select(.kind=="ArgoCD") | .spec.repo | (.env |= map(select(.name != "POLICY_GENERATOR_CMP_CONFIG_SHA"))) | sort_keys(..) | ... comments=""' "$$tmp/render.yaml" > "$$tmp/repo-chart.yaml" || exit 1; \
	if ! diff "$$tmp/repo-boot.yaml" "$$tmp/repo-chart.yaml" > /dev/null; then \
		echo "FAIL spec.repo differs between $$boot/argocd.yaml and the chart"; fail=1; \
	fi; \
	yq '.data["plugin.yaml"]' "$$boot/policy-generator-cmp.yaml" > "$$tmp/plugin-boot.yaml" || exit 1; \
	yq 'select(.kind=="ConfigMap") | .data["plugin.yaml"]' "$$tmp/render.yaml" > "$$tmp/plugin-chart.yaml" || exit 1; \
	[ -s "$$tmp/repo-boot.yaml" ] && [ -s "$$tmp/plugin-boot.yaml" ] || { \
		echo "FAIL parity check extracted nothing -- the yq queries no longer match the files"; exit 1; }; \
	if ! diff "$$tmp/plugin-boot.yaml" "$$tmp/plugin-chart.yaml" > /dev/null; then \
		echo "FAIL plugin.yaml differs between $$boot/policy-generator-cmp.yaml and the chart"; fail=1; \
	fi; \
	[ $$fail -eq 0 ] || { echo "     see charts/operators/openshift-gitops/HANDOFF.md"; exit 1; }; \
	echo "OK   PolicyGenerator CMP parity (bootstrap vs chart)"

# Both targets discover clusters from disk rather than hardcoding a list, so
# they keep working as clusters are added or removed — including in the
# sanitized public copy, which ships only a subset of them.
#
# Each cluster's operatorCharts list is read straight out of its conf.yaml and
# every chart in it is rendered through the same six-file chain the
# cluster-operators ApplicationSet uses, missing files skipped the way
# ignoreMissingValueFiles skips them. A chart is only rendered for clusters
# that actually list it, because a chart's required values (compliance's
# operator.channel, for one) only exist where it is enabled.
validate-operators:
	@for chart in $(OPERATOR_CHARTS)/*/; do \
		[ -f "$$chart/Chart.yaml" ] || continue; \
		helm lint "$$chart" > /dev/null 2>&1 || { helm lint "$$chart"; exit 1; }; \
	done
	@echo "OK   helm lint $(OPERATOR_CHARTS)/*"
	@for dir in $$(find clusters -mindepth 2 -maxdepth 2 -type d | sort); do \
		[ -f "$$dir/conf.yaml" ] || continue; \
		environment=$$(basename $$(dirname $$dir)); \
		for chart in $$(awk '/^operatorCharts:/{f=1;next} f&&/^[^ #-]/{f=0} f&&/^[ ]*-[ ]*chart:/{print $$3}' "$$dir/conf.yaml"); do \
			args=""; \
			for v in env/$$environment/conf.yaml env/$$environment/operators.yaml \
				env/$$environment/operators/$$chart.yaml $$dir/conf.yaml \
				$$dir/operators.yaml $$dir/operators/$$chart.yaml; do \
				[ -f "$$v" ] && args="$$args -f $$v"; \
			done; \
			helm template $$chart $(OPERATOR_CHARTS)/$$chart $$args > /dev/null || exit 1; \
			echo "OK   $$dir/$$chart"; \
		done; \
	done

# Deliberately not part of `validate`: everything else there runs offline, and
# this needs a kubeconfig for the hub. clusterRegistered is a hand-maintained
# claim about the world, so the thing worth checking is whether it is still
# true — see the script header for why the flag exists at all.
validate-clusters:
	@./scripts/validate-clusters.sh

# Unlike the other validate targets this one is a script rather than an inline
# recipe, for two reasons: the values chain it needs is already written down in
# scripts/render.sh and is asked for rather than copied a third time, and the
# namespace-collision scan is an awk program that would need every $$ doubled
# to live in a recipe. See scripts/validate-clusters.sh for the same call.
validate-onboarding:
	@./scripts/validate-onboarding.sh

validate-provisioning:
	@helm lint $(PROVISIONING_CHART)
	@for dir in $$(find clusters -mindepth 2 -maxdepth 2 -type d | sort); do \
		[ -f "$$dir/provision.yaml" ] || continue; \
		helm template provisioning $(PROVISIONING_CHART) \
			-f $$dir/provision.yaml > /dev/null || exit 1; \
		echo "OK   provisioning/$$dir"; \
	done

bootstrap-hub:
	./scripts/bootstrap-aws-hub.sh $(BOOTSTRAP_VALUES)

bootstrap-hub-dry-run:
	./scripts/bootstrap-aws-hub.sh --dry-run $(BOOTSTRAP_VALUES)

destroy-hub:
	./scripts/bootstrap-aws-hub.sh --destroy $(BOOTSTRAP_VALUES)
