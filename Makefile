IMAGE_NAME ?= aws-cost-report

## Variables for getiing costs from S3
PROFILE?=
BUCKET_NAME?=
PREFIX?=
XLSX_FILE_NAME?=

DOCKER_BUILD ?= docker build -t aws-cost-report .
DOCKER_RUN ?= docker run -v $(PWD)/out:/root/aws-cost-report/out -v ~/.aws:/root/.aws --env-file .env $(IMAGE_NAME) --billing $(PROFILE) $(BUCKET_NAME) $(PREFIX) --ec2 $(PROFILE) --xlsx-name $(XLSX_FILE_NAME) --use-sso-auth True --sso-profile mydeal-nonprod
DOCKER_RUN_SHELL ?= docker run --rm -it --entrypoint=/bin/bash -v $(PWD)/:/root/aws-cost-report/ -v ~/.aws:/root/.aws --env-file .env $(IMAGE_NAME)

all:
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
build:
	$(DOCKER_BUILD)
run:
	$(DOCKER_RUN)

shell:
	$(DOCKER_RUN_SHELL)