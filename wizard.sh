#!/bin/bash

set -e

DEFAULT_EDITOR=nano
PROFILE_ENV=env # AWS profile which uses environment variables instead of credentials file.
MAX_RETRY=5

DIR_BILLS='in/usagecost'

for pgm in shasum sha1sum md5sum md5
do
	pgm_path=$(which $pgm) 2>/dev/null
	if [[ -x "$pgm_path" ]]
	then
		HASH_INSECURE="$pgm_path"
		break
	fi
done
if [[ -z "$HASH_INSECURE" ]]
then
	echo "Could not find hash function." 1>&2
	exit 1
fi

current_profile=default
current_region=us-east-1

mkdir -p in/{usagecost}
mkdir -p out/{instance-,}reservation-usage
mkdir -p out/instance-size-recommendation

function clear_data() {
	find in -type f ! -path 'in/persistent/*' -delete
	find out -type f -delete
}

function prepare_env_file() {
	echo '# This file will be sourced by bash.'
	echo '# Set your environment variables.'
	for env_var in AWS_{ACCESS_KEY_ID,SECRET_ACCESS_KEY,SESSION_TOKEN}
	do
		if [[ -z "${!env_var}" ]]
		then
			echo "# export ${env_var}="
		else
			echo "export ${env_var}=${!env_var}"
		fi
	done
}

function set_profile() {
	read -p "AWS profile (or '${PROFILE_ENV}'): " current_profile
	if [[ "$current_profile" == "$PROFILE_ENV" ]]
	then
		tmp_env="$(mktemp)"
		prepare_env_file > "$tmp_env"
		${EDITOR:-${DEFAULT_EDITOR}} "$tmp_env"
		source "$tmp_env"
		rm "$tmp_env"
	else
		unset AWS_{ACCESS_KEY_ID,SECRET_ACCESS_KEY,SESSION_TOKEN}
	fi
	util/awsdumpenv
}

function set_region() {
	read -p "AWS region: " current_region
}

function get_billing_data() {
	local bill_bucket
	local bill_prefix
	read -p "Bucket name: " bill_bucket
	read -p "Key prefix:  " bill_prefix
	local bill_tmp=$(mktemp -d)
	local nonce=$($HASH_INSECURE <<<"$bill_bucket$bill_prefix" | head -c 12)
	aws_cli s3 sync --exclude '*' --include '*.json' "s3://$bill_bucket/$bill_prefix" "$bill_tmp/"
	jq -r '.reportKeys | .[]' "$bill_tmp"/*/*/*.json | \
		perl -pe 's/(csv\.(?:gz|zip))$/\1\x00\1/' | \
		parallel \
			--jobs 4 \
			--colsep '\0' \
			aws "${aws_cli_args[@]}" s3 cp "s3://$bill_bucket/{1}" "$DIR_BILLS/$nonce.{#}.{2}"
	pushd "$DIR_BILLS"
	for z in *.gz
	do
		[[ "$z" == '*.gz' ]] || gzip -d "$z"
	done
	for z in *.zip
	do
		[[ "$z" == '*.zip' ]] || unzip -d "$z"
	done
	popd
}

function get_cost_data() {
	retry src/get_ec2_costs.sh
}

function get_instance_data() {
	retry aws_env src/get_ec2_data.py
	retry aws_env src/get_ec2_recommendations.py
}

function retry() {
	local retry=$MAX_RETRY
	while ! "$@" && [[ $retry > 1 ]]
	do
		retry=$((retry - 1))
	done
	if [[ $retry = 1 ]]
	then
		return 1
	else
		return 0
	fi
}

function build_billing_diff() {
	src/get_bill_diff.py
}

function build_instance_history() {
	src/get_ec2_instance_history.py
}

function build_sheet() {
	retry src/make_sheet.py
}

function before_action_choice() {
	echo "Current profile: ${current_profile}"
	echo "Current region:  ${current_region}"
	echo
	echo "Select next action."
}

function aws_cli() {
	if [[ "${current_profile}" != "${PROFILE_ENV}" ]]
	then
		aws_cli_args=(--region "${current_region}" --profile "${current_profile}")
	else
		aws_cli_args=()
	fi
	aws "${aws_cli_args[@]}" "$@"
}

function aws_env() {
	if [[ "${current_profile}" != "${PROFILE_ENV}" ]]
	then
		util/awsenv --profile "${current_profile}" --region "${current_region}" "$@"
	else
		"$@"
	fi
}

function auto_report() {
	clear_data
	set_profile
	set_region
	get_billing_data
	get_cost_data
	get_instance_data
	build_billing_diff
	build_instance_history
	build_sheet
}

function main() {
	before_action_choice
	select action in \
		auto_report \
		clear_data \
		set_profile \
		set_region \
		get_cost_data \
		get_billing_data \
		get_instance_data \
		build_billing_diff \
		build_instance_history \
		build_sheet
	do
		if [[ -z "$action" ]]
		then
			exit
		fi
		"$action"
		before_action_choice
	done
}

main
