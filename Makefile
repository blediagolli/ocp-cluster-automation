KUSTOMIZE ?= oc kustomize
OPERATOR_TARGETS := \
	base/operators

.PHONY: help validate validate-operators validate-hub validate-provisioning \
	bootstrap-hub bootstrap-hub-dry-run destroy-hub

BOOTSTRAP_VALUES ?= clusters/mgt/acm-hub/bootstrap.yaml

help:
	@echo "Targets:"
	@echo "  validate                validate ACM bootstrap and operator targets"
	@echo "  validate-operators      validate imported operator manifests"
	@echo "  validate-hub            validate the ACM hub bootstrap manifests"
	@echo "  validate-provisioning   lint the provisioning chart for all sample clusters"
	@echo "  bootstrap-hub           provision the ACM hub cluster on AWS"
	@echo "  bootstrap-hub-dry-run   generate install-config.yaml without installing"
	@echo "  destroy-hub             tear down the bootstrapped hub cluster"

validate: validate-hub validate-operators validate-provisioning

validate-hub:
	@$(KUSTOMIZE) clusters/mgt/acm-hub > /dev/null
	@echo "OK   clusters/mgt/acm-hub"

validate-operators:
	@helm lint $(OPERATOR_TARGETS)
	@for environment in dev prod mgt; do \
		if [ "$$environment" = dev ]; then cluster=dev.example.com; \
		elif [ "$$environment" = prod ]; then cluster=prod.example.com; \
		elif [ "$$environment" = mgt ]; then cluster=acm-hub; \
		fi; \
		helm template cluster-operators $(OPERATOR_TARGETS) \
			-f conf/$$environment/conf.yaml \
			-f clusters/$$environment/$$cluster/conf.yaml > /dev/null || exit 1; \
		echo "OK   operators/$$environment/$$cluster"; \
	done

validate-provisioning:
	@for environment in dev prod; do \
		if [ "$$environment" = dev ]; then cluster=dev.example.com; \
		elif [ "$$environment" = prod ]; then cluster=prod.example.com; \
		fi; \
		helm lint base/provision/openshift-provisioning \
			-f clusters/$$environment/$$cluster/provision.yaml || exit 1; \
		echo "OK   provisioning/$$environment"; \
	done

bootstrap-hub:
	./scripts/bootstrap-aws-hub.sh $(BOOTSTRAP_VALUES)

bootstrap-hub-dry-run:
	./scripts/bootstrap-aws-hub.sh --dry-run $(BOOTSTRAP_VALUES)

destroy-hub:
	./scripts/bootstrap-aws-hub.sh --destroy $(BOOTSTRAP_VALUES)
