# RideStream developer commands. Run `make help` for the list.
# CI runs these same targets, so a green `make lint test` locally means a
# green pipeline.

ENV ?= dev
TF_DIR := infra/envs/$(ENV)

.DEFAULT_GOAL := help
.PHONY: help fmt lint test plan

help: ## Show this help
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

fmt: ## Rewrite Python and Terraform files into the standard format
	uv run ruff format .
	uv run ruff check --fix .
	terraform fmt -recursive infra

lint: ## Check format and lint rules without changing any file
	uv run ruff format --check .
	uv run ruff check .
	terraform fmt -check -recursive infra

test: ## Run the Python tests
	uv run pytest

plan: ## Show what Terraform would change: make plan ENV=dev
	@test -d $(TF_DIR) || { echo "No Terraform configuration in $(TF_DIR) yet"; exit 1; }
	terraform -chdir=$(TF_DIR) init -input=false
	terraform -chdir=$(TF_DIR) plan -input=false
