# Entry points. Each target runs one script from scripts/; `make` lists them.
.DEFAULT_GOAL := help
.PHONY: help on off traffic check batch dashboard spark lambda-zip readers-on readers-off readers-test

help:            ## list the targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

on:              ## lab on: Docker up, connectors, dynamic tables resume
	scripts/lab-on.sh
off:             ## lab off: stop spending, keep the data
	scripts/lab-off.sh
traffic:         ## run the traffic generator (Ctrl-C to stop)
	uv run python source/generator.py
check:           ## local health: Postgres → Debezium → Kafka
	scripts/check-local.sh
batch:           ## batch path + reconciliation
	scripts/run-batch.sh
dashboard:       ## Streamlit dashboard on gold, http://localhost:8501
	scripts/dashboard.sh
spark:           ## read gold with Spark in Docker through Horizon
	scripts/spark-read.sh GOLD.TRANSACTION_ENRICHED

lambda-zip:      ## build build/lambda.zip (needed by the readers stack)
	scripts/build-lambda.sh
readers-on:      ## AWS readers: create the hourly-billed parts (NAT gateway, notebook)
	scripts/aws-readers.sh on
readers-test:    ## AWS readers: run Lambda, EMR Serverless and SageMaker
	scripts/aws-readers.sh lambda && scripts/aws-readers.sh emr && scripts/aws-readers.sh sagemaker
readers-off:     ## AWS readers: remove the hourly-billed parts
	scripts/aws-readers.sh off
