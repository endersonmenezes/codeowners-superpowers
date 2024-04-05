#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-05-04
##

# Arguments
OWNER=$1
REPOSITORY=$2
PR_NUMBER=$3

# Make URL
PR_URL="https://github.com/$OWNER/$REPOSITORY/pull/$PR_NUMBER"
echo "Analyzing PR: $PR_URL"

## Get Changed Files
gh pr checkout $PR_URL
gh pr diff --name-only $NUMBER > changed_files.txt
echo 
echo "Changed Files:"
cat changed_files.txt

## Add a slash at the beginning of the all lines
sed -i 's/^/\//' changed_files.txt

## Verify that the CODEOWNERS file exists
CODEOWNERS_FILE=".github/CODEOWNERS"
if [ ! -f "$CODEOWNERS_FILE" ]; then
    echo "CODEOWNERS file not found"
    exit 1
fi

## Verify that CODEOWNERS file have blank end of file
if [ ! -z "$(tail -c 1 $CODEOWNERS_FILE)" ]; then
    echo "CODEOWNERS file must have a blank line at the end of the file"
    ## Add a blank line at the end of the file
    echo "" >> $CODEOWNERS_FILE
fi

## Save set for protected dirs 
declare -A SET_FILE_OR_DIR_AND_OWNER

## Read the CODEOWNERS file line by line
while IFS= read -r line; do

    # Skip comments and empty lines and line with "*"
    if [[ "$line" =~ ^\s*# ]] || [[ "$line" =~ ^\s*$ ]] || [[ "$line" =~ ^\s*\* ]]; then
        continue
    fi
    LINE_ARRAY=($line)

    # Retrieve the directory or file and the owners (Can be * CAUTION)
    DIR_OR_FILE=${LINE_ARRAY[0]}

    # Add dir or file on SET_FILE_OR_DIR_AND_OWNER
    SET_FILE_OR_DIR_AND_OWNER["$DIR_OR_FILE"]=${LINE_ARRAY[@]:1}
done < "$CODEOWNERS_FILE"

## Verify if the changed files are in the CODEOWNERs DIRs or files
NECESSARY_APPROVALS=()
for FILE in $(cat changed_files.txt); do
    for DIR_OR_FILE in "${!SET_FILE_OR_DIR_AND_OWNER[@]}"; do
        # Compare if the folder in the tree of protected folders
        if [[ "$FILE" == *"$DIR_OR_FILE"* ]]; then
            echo 
            echo "FILE: $FILE is in CODEOWNERS"
            echo "OWNER: ${SET_FILE_OR_DIR_AND_OWNER[$DIR_OR_FILE]}"
            NECESSARY_APPROVALS+=(${SET_FILE_OR_DIR_AND_OWNER[$DIR_OR_FILE]})
        fi
    done
done

## Remove duplicates
NECESSARY_APPROVALS=($(echo "${NECESSARY_APPROVALS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

## Print the necessary approvals
echo
echo "We identified the following owners are necessary to approve the PR:"
for OWNER in "${NECESSARY_APPROVALS[@]}"; do
    echo $OWNER
done

PR_APPROVED=$(gh pr view $PR_NUMBER --json reviews | jq '.reviews[] | select(.state == "APPROVED") | .author.login')
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