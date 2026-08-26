KUSTOMIZE ?= oc kustomize
OPERATOR_TARGETS := \
	operators/chart

.PHONY: help validate validate-operators validate-hub validate-provisioning

help:
	@echo "Targets:"
	@echo "  validate           validate ACM bootstrap and operator targets"
	@echo "  validate-operators validate imported operator manifests"
	@echo "  validate-hub       validate the ACM hub bootstrap manifests"
	@echo "  validate-provisioning lint the provisioning chart for all sample clusters"

validate: validate-hub validate-operators validate-provisioning

validate-hub:
	@$(KUSTOMIZE) clusters/acm-hub.redhat.com > /dev/null
	@echo "OK   clusters/acm-hub.redhat.com"

validate-operators:
	@helm lint $(OPERATOR_TARGETS)
	@for profile in ocp-4.21 ocp-4.22; do \
		for cluster_type in hub prod dev; do \
			helm template cluster-operators $(OPERATOR_TARGETS) \
				--set profile=$$profile --set clusterType=$$cluster_type > /dev/null || exit 1; \
			echo "OK   operators/chart/$$profile/$$cluster_type"; \
		done; \
	done

validate-provisioning:
	@for environment in dev prod; do \
		if [ "$$environment" = dev ]; then cluster=zamora.dev.redhat.com; \
		elif [ "$$environment" = prod ]; then cluster=leon.pro.redhat.com; \
		fi; \
		helm lint base/provision/openshift-provisioning \
			-f conf/$$environment/provision.yaml \
			-f clusters/$$environment/$$cluster/provision.yaml || exit 1; \
		echo "OK   provisioning/$$environment"; \
	done
