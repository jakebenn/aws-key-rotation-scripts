#!/usr/bin/env bash

# ================================================================
# === DESCRIPTION
# ================================================================
#
# Summary: This script automatically rotates the key for an IAM user.
#
# Version: 1.0.0
#
# Command-line arguments:
#    - See the 'PrintHelp' function below for command-line arguments. Or run this script with the --help option.
#
# Legal stuff:
#    - Copyright (c) 2015 Jake Bennett
#    - Licensed under the MIT License - https://opensource.org/licenses/MIT


# ================================================================
# === FUNCTIONS
# ================================================================

function PrintHelp() {
    echo "usage: $__base.sh [options...] "
    echo "options:"
    echo " -a --aws-key-file  The file for the .csv access key file for an AWS administrator. Required. The AWS administrator must"
    echo "                    have the rights to list and update credentials for the IAM user. The script expects the .csv format "
    echo "                    used when you dowload the key from IAM in the AWS console."
    echo " -s --s3-test-file  Specifies a test text file stored in S3 used for testing. Required. The IAM user must have "
    echo "                    GET access to this file."
    echo " -c --csv-key-file  The name of the output .csv file containing the new access key information. Optional."
    echo " -u --user          The IAM user whose key you want to rotate. Required."
    echo " -j --json          A file to send JSON output to. Optional."
    echo "    --help          Prints this help message"
}


# ================================================================
# === INITIALIZATION
# ================================================================

# Exit if there is an error in the script. Get last error for piped commands
set -o errexit
set -o pipefail
#set -o xtrace

# Set magic variables
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(cd "$(dirname "${__dir}")" && pwd)" # <-- change this
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"


# ======================================================
# === PARSE COMMAND-LINE OPTIONS
# ======================================================

IAM_USER=
AWS_KEY_FILE=
JSON_OUTPUT_FILE=
S3_TEST_FILE=
CSV_OUTPUT_FILE=

# Check if any arguments were passed. If not, print an error
if [ $# -eq 0 ]; then
    >&2 echo "error: too few arguments"
    PrintHelp
    exit 2
fi

# Loop through the command-line options
while [ "$1" != "" ]; do

    case "$1" in
        -u | --user)  shift
                      IAM_USER="$1"
                      ;;
        -a | --aws-key-file) shift
                      AWS_KEY_FILE="$1"
                      ;;
        -s | --s3-test-file)  shift
                      S3_TEST_FILE="$1"
                      ;;
        -j | --json)  shift
                      JSON_OUTPUT_FILE="$1"
                      ;;
        -c | --csv-key-file) shift
                      CSV_OUTPUT_FILE="$1"
                      ;;
        --help)       PrintHelp
                      exit 0
                      ;;
        *)            >&2 echo "error: invalid option: '$1'"
                      PrintHelp
                      exit 3
    esac

    # Shift all the parameters down by one
    shift

done

# Make sure that all the required arguments were passed into the script
if [[ -z "$IAM_USER" ]] || [[ -z "$AWS_KEY_FILE" ]] || [[ -z "$S3_TEST_FILE" ]]; then
    >&2 echo "error: too few arguments"
    PrintHelp
    exit 0
fi

function ConfigureAwsCli() {
# Configure the AWS command-line tool with the proper credentials

    if [[ ! -z "$AWS_KEY_FILE" ]] ; then
        echo "Using the AWS administrator key file specified."

        AWS_ACCESS_KEY_ID=$(awk -F ',' 'NR==2 {print $2}' "$AWS_KEY_FILE")
        AWS_SECRET_ACCESS_KEY=$(awk -F ',' 'NR==2 {print $3}' "$AWS_KEY_FILE")

        # Configure temp profile
        aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
        aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
    fi

}

# ======================================================
# === MAIN SCRIPT
# ======================================================


ConfigureAwsCli

# Get the keys for this user and check how many there are. If there are two or more, than stop. The max # of keys
# per IAM user is 2. We need a second key as a temporary key to rotate. So, if there are already two keys, we can't continue.
cd "$__dir"

echo "Verifying the IAM user only has one key currently..."
aws iam list-access-keys --user-name "$IAM_USER" > existing-keys
NUM_OF_KEYS=$(grep -c "AccessKeyId" existing-keys)

if [ "$NUM_OF_KEYS" -gt 1 ] ; then
  echo "There are already two keys in-use for this user (which is the max per IAM user). Unable to rotate keys."
  rm existing-keys
  exit 2
fi

# Get the existing key
EXISTING_KEY_ID=$(awk '/.AccessKeyId./{print substr($2,2,length($2)-2)}' existing-keys) 
echo "Existing key Id: $EXISTING_KEY_ID"
rm existing-keys

# Create a new access key in AWS for the IAM user
echo "Creating new access key for IAM user..."
aws iam create-access-key --user-name "$IAM_USER" > temp-key
NEW_AWS_ACCESS_KEY_ID=$(awk '/.AccessKeyId./{print substr($2,2,length($2)-2)}' temp-key)
NEW_AWS_SECRET_ACCESS_KEY=$(awk '/.SecretAccessKey./{print substr($2,2,length($2)-3)}' temp-key)
rm temp-key

#######
#
#  Test access by downloading a pre-designated test file.
#  Note: This will need to be changed to accomodate your specific use case.
#  Also Note: This test configures a temporary profile for the AWS CLI based on the user whose keys are being rotated.
#             All AWS calls intended test this user's access should be run using the "--profile" flag so they are
#             under the IAM user's identity, not your default AWS CLI identity.
#

echo "Testing new key..."
echo "New key Id: $NEW_AWS_ACCESS_KEY_ID"

# Configure a temp profile using the new IAM key to test with
aws configure --profile temp-role set aws_access_key_id "$NEW_AWS_ACCESS_KEY_ID"
aws configure --profile temp-role set aws_secret_access_key "$NEW_AWS_SECRET_ACCESS_KEY"

# Wait a few seconds for the new key to propagate in AWS
echo "Pausing to wait for the IAM changes to propagate..."
COUNT=0
MAX_COUNT=20
SUCCESS=false
while [ "$SUCCESS" = false ] && [ "$COUNT" -lt "$MAX_COUNT" ]; do
    sleep 3
    aws s3 cp --profile temp-role "$S3_TEST_FILE" ./KeyRotationTest.txt  && RETURN_CODE=$? || RETURN_CODE=$?
    if [ "$RETURN_CODE" -eq 0 ]; then
        SUCCESS=true
    else
       COUNT=$((COUNT+1))
    fi
done

echo "done pausing.."
rm KeyRotationTest.txt

#
#  End Key testing
#
#######


# If the test was successful, continue. Otherwise rollback.
if [ "$SUCCESS" = true ]; then
  echo "Successfully used new key. Inactivating old key and retesting..."
 
  # Disable the old key, and re-try the test. 
  aws iam update-access-key  --user-name "$IAM_USER" --access-key-id "$EXISTING_KEY_ID" --status Inactive
  aws s3 cp --profile temp-role "$S3_TEST_FILE" ./KeyRotationTest.txt && RETURN_CODE=$? || RETURN_CODE=$?
  rm KeyRotationTest.txt

  if [ "$RETURN_CODE" -eq 0 ]; then SUCCESS=true; else SUCCESS=false; fi

  # If the second test was successful, then delete the old key. Otherwise, notify the user and exit.
  if [ "$SUCCESS" = true ]; then
    echo "Successfully used new key after inactivating the old key. Deleting the old key..."
    aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$EXISTING_KEY_ID"
  else
    >&2 echo "Test failed after trying inactiving the old key. Reactivating the key and stopping the rotation."
    aws iam update-access-key  --user-name "$IAM_USER" --access-key-id "$EXISTING_KEY_ID" --status Active
    exit 6
  fi
else
  >&2 echo "Access test failed for new key. Unable to rotate keys. Rolling back"
  aws iam delete-access-key  --user-name "$IAM_USER"  --access-key-id "$NEW_AWS_ACCESS_KEY_ID"
  exit 7
fi

# Print the JSON file if requested
if [[ ! -z "$JSON_OUTPUT_FILE" ]]; then
    echo "Outputing JSON to $JSON_OUTPUT_FILE..."
    printf '
    {
        "User":"%s",
        "NewAwsAccessKeyId":"%s",
        "NewAwsSecretAccessKey": "%s"
    }\n' "$IAM_USER" "$NEW_AWS_ACCESS_KEY_ID" "$NEW_AWS_SECRET_ACCESS_KEY" > "$JSON_OUTPUT_FILE"
fi

# Print the JSON file if requested
if [[ ! -z "$CSV_OUTPUT_FILE" ]]; then
    echo "Outputing .csv to $CSV_OUTPUT_FILE..."
    printf 'User Name,Access Key Id,Secret Access Key\n%s,%s,%s' \
        "$IAM_USER" "$NEW_AWS_ACCESS_KEY_ID" "$NEW_AWS_SECRET_ACCESS_KEY" > "$CSV_OUTPUT_FILE"
fi

