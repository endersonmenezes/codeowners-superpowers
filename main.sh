#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-05-04
##

# Set strict mode
set -e

# Arguments
OWNER_AND_REPOSITORY=$1
PR_NUMBER=$2
SUPERPOWER=$3

# Transform Args
GH_OWNER=$(echo $OWNER_AND_REPOSITORY | cut -d'/' -f1)
GH_REPOSITORY=$(echo $OWNER_AND_REPOSITORY | cut -d'/' -f2)

# Transparent Args
echo "OWNER: $GH_OWNER"
echo "REPOSITORY: $GH_REPOSITORY"
echo "PR_NUMBER: $PR_NUMBER"

# Validate GH is installed
if ! command -v gh &> /dev/null
then
    echo "gh could not be found"
    exit 1
fi

# Validate jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found"
    exit 1
fi

# Validate Args
## Verify power is available (SUPERPOWER can be require-all-codeowners)
AVAILABLE_SUPERPOWERS=(
    "require-all-codeowners"
)
if ! [[ " ${AVAILABLE_SUPERPOWERS[@]} " =~ " ${SUPERPOWER} " ]]; then
    echo "SUPERPOWER is not available"
    exit 1
fi

## Verify PR is a number
if ! [[ $PR_NUMBER =~ ^[0-9]+$ ]]; then
    echo "PR_NUMBER is not a number"
    exit 1
fi

# Make URL
PR_URL="https://github.com/$GH_OWNER/$GH_REPOSITORY/pull/$PR_NUMBER"
echo "Analyzing PR: $PR_URL"

# Download CODEOWNERs File

gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/$GH_OWNER/$GH_REPOSITORY/contents/.github/CODEOWNERS > pr.json

CODEOWNERS_FILE_PATH="./CODEOWNERS"

# Download CODEOWNERS File
# download_url
CODEOWNERS_DOWNLOAD_URL=$(cat pr.json | jq '.download_url' | tr -d '"')
echo "Downloading CODEOWNERS file..."
curl -s -H "Accept: application/vnd.github.v3.raw" $CODEOWNERS_DOWNLOAD_URL > $CODEOWNERS_FILE_PATH

## Checkout Repo and PR
echo "Trying to get diff files from PR"
gh pr diff ${PR_NUMBER} --repo ${GH_OWNER}/${GH_REPOSITORY} --name-only > changed_files.txt
echo "Changed Files:"
cat changed_files.txt

## If not changed files
if [ ! -s changed_files.txt ]; then
    echo "No files changed"
    exit 0
fi

## Add a slash at the beginning of the all lines
sed -i 's/^/\//' changed_files.txt

## Verify that the CODEOWNERS file exists
if [ ! -f "$CODEOWNERS_FILE_PATH" ]; then
    echo "CODEOWNERS file not found"
    exit 1
fi

## Verify that CODEOWNERS file have blank end of file
if [ ! -z "$(tail -c 1 $CODEOWNERS_FILE_PATH)" ]; then
    echo "CODEOWNERS file must have a blank line at the end of the file"
    ## Add a blank line at the end of the file
    echo "" >> $CODEOWNERS_FILE_PATH
    echo "" >> $CODEOWNERS_FILE_PATH
fi

## Save set for protected dirs 
declare -A SET_FILE_OR_DIR_AND_OWNER

## Read the CODEOWNERS file line by line
echo "Reading CODEOWNERS file..."
while IFS= read -r line; do
    # Skip empty lines
    if [ -z "$line" ]; then
        continue
    fi

    # Skip Comment Line
    REGEX_COMMENT="^#"
    if [[ $line =~ $REGEX_COMMENT ]]; then
        continue
    fi

    # Transform ${line} into a safe array
    OLD_IFS=$IFS
    IFS=' ' read -r -a LINE_ARRAY <<< "$line"
    IFS=$OLD_IFS
    
    # If first element is a * continue
    if [ "${LINE_ARRAY[0]}" == "*" ]; then
        continue
    fi

    # Configure SET_FILE_OR_DIR_AND_OWNER
    SET_FILE_OR_DIR_AND_OWNER["${LINE_ARRAY[0]}"]="${LINE_ARRAY[@]:1}"
done < "${CODEOWNERS_FILE_PATH}"
echo "End of reading CODEOWNERS file"

## Verify if the changed files are in the CODEOWNERs DIRs or files
NECESSARY_APPROVALS=()
while IFS= read -r FILE; do
    for DIR_OR_FILE_OR_REGEX in "${!SET_FILE_OR_DIR_AND_OWNER[@]}"; do
        if [[ "$FILE" =~ $DIR_OR_FILE_OR_REGEX ]]; then
            echo 
            echo "FILE: $FILE is in CODEOWNERS"
            echo "OWNER: ${SET_FILE_OR_DIR_AND_OWNER[$DIR_OR_FILE_OR_REGEX]}"
            echo "LINE: ${DIR_OR_FILE_OR_REGEX}"
            NECESSARY_APPROVALS+=(${SET_FILE_OR_DIR_AND_OWNER[$DIR_OR_FILE_OR_REGEX]})
        elif [[ "$FILE" == $DIR_OR_FILE_OR_REGEX ]]; then
            echo 
            echo "FILE: $FILE is in CODEOWNERS"
            echo "OWNER: ${SET_FILE_OR_DIR_AND_OWNER[$DIR_OR_FILE_OR_REGEX]}"
            echo "LINE: ${DIR_OR_FILE_OR_REGEX}"
            NECESSARY_APPROVALS+=(${SET_FILE_OR_DIR_AND_OWNER[$DIR_OR_FILE_OR_REGEX]})
        fi
    done
done < changed_files.txt

## Remove duplicates
NECESSARY_APPROVALS=($(echo "${NECESSARY_APPROVALS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

## If no necessary approvals
if [ ${#NECESSARY_APPROVALS[@]} -eq 0 ]; then
    echo "No necessary approvals"
    exit 0
fi

## Print the necessary approvals
echo
echo "We identified the following owners are necessary to approve the PR:"
for OWNER in "${NECESSARY_APPROVALS[@]}"; do
    echo $OWNER
done

echo "Catch the PR approvals"
gh pr view $PR_NUMBER --repo ${GH_OWNER}/${GH_REPOSITORY} --json reviews > pr_approvals.json
PR_APPROVED=$(echo $PR_APPROVED | jq '.reviews[].author.login' | tr '\n' ' ')
PR_APPROVED=$(echo $PR_APPROVED | tr -d '"')

echo 
for NECESSARY_OWNER in "${NECESSARY_APPROVALS[@]}"; do
    # Verify is a TEAM or USER spliting /
    IS_A_TEAM=$(echo $NECESSARY_OWNER | grep -o '/' | wc -l)
    if [ $IS_A_TEAM -eq 0 ]; then
        echo "$NECESSARY_OWNER" > member_list_$NECESSARY_OWNER.txt
        continue
    fi
    OWNER_ORGANIZATION=$(echo $NECESSARY_OWNER | cut -d'/' -f1)
    OWNER_ORGANIZATION=$(echo $OWNER_ORGANIZATION | cut -c 2-)
    OWNER_TEAM=$(echo $NECESSARY_OWNER | cut -d'/' -f2)
    API_CALL="/orgs/$OWNER_ORGANIZATION/teams/$OWNER_TEAM/members"
    MEMBER_LIST=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        $API_CALL | jq '.[].login' | tr -d '"')
    echo $MEMBER_LIST > member_list_$OWNER_TEAM.txt
done
echo 
MEMBER_LIST_FILES=$(ls member_list_*.txt)
TEAMS_APPROVED=()
TEAMS_MISSING_APPROVAL=()
echo "We identified the following approvals:"
for OWNER in $PR_APPROVED; do
    for MEMBER_LIST_FILE in $MEMBER_LIST_FILES; do
        TEAM=$(echo $MEMBER_LIST_FILE | cut -d'_' -f3 | cut -d'.' -f1)
        if grep -q $OWNER $MEMBER_LIST_FILE; then
            echo "$OWNER is a member of $TEAM"
            if [[ " ${TEAMS_APPROVED[@]} " =~ " ${TEAM} " ]]; then
                continue
            fi
            TEAMS_APPROVED+=($TEAM)
        fi
    done
done

## Compare the necessary with the approved
for NECESSARY_OWNER in "${NECESSARY_APPROVALS[@]}"; do
    OWNER_ORGANIZATION=$(echo $NECESSARY_OWNER | cut -d'/' -f1)
    OWNER_ORGANIZATION=$(echo $OWNER_ORGANIZATION | cut -c 2-)
    OWNER_TEAM=$(echo $NECESSARY_OWNER | cut -d'/' -f2)
    if [[ " ${TEAMS_APPROVED[@]} " =~ " ${OWNER_TEAM} " ]]; then
        continue
    fi
    TEAMS_MISSING_APPROVAL+=($NECESSARY_OWNER)
done

## Conclusion
echo 
echo "Teams that approved the PR:"
for TEAM in "${TEAMS_APPROVED[@]}"; do
    echo $TEAM
done
echo 
echo "Teams that missing approval:"
for TEAM in "${TEAMS_MISSING_APPROVAL[@]}"; do
    echo $TEAM
done

if [ ${#TEAMS_MISSING_APPROVAL[@]} -gt 0 ]; then
    exit 1
fi