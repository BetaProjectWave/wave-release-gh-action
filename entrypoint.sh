#!/bin/bash
# Needs the following ENV vars, check action.yml inputs.
# GITHUB_TOKEN_TAG, REPO (BetaProjectWave/auth-service)
echo Using owner/repository: $REPO

GITHUB_TOKEN_TAG="$(vault kv get -field=VALUE -address=https://vault.shared.astoapp.co.uk secret/app/circleci/github_token_tag)"

COMMIT_MSG=$(git log --pretty=format:%s -1 | sed -e 's/\"/\\"/g')

echo $COMMIT_MSG

pr_number_squash_regex='\(#([0-9]+)\)$/?'
pr_number_merge_regex='^Merge pull request #([0-9]+)/?'

if [[ "$COMMIT_MSG" =~ $pr_number_squash_regex ]]
then
    PR_NUMBER=${BASH_REMATCH[1]}
    echo "Found a squashed PR number: $PR_NUMBER"
else
    if [[ "$COMMIT_MSG" =~ $pr_number_merge_regex ]]
    then
        PR_NUMBER=${BASH_REMATCH[1]}
        echo "Found a merged PR number: $PR_NUMBER"
    else
        echo "Couldn't find a valid PR number in '$COMMIT_MSG'"
        exit 1
    fi
fi

prUrl=https://api.github.com/repos/$REPO/pulls/$PR_NUMBER
latestReleaseUrl=https://api.github.com/repos/$REPO/releases/latest
releaseUrl=https://api.github.com/repos/$REPO/releases

prJson=$(curl -H "Authorization: token $GITHUB_TOKEN_TAG" -s $prUrl)

if $(echo $prJson | jq '.labels[].name | contains("dependencies")') == "true"
then
	releaseType="patch"
else
	releaseType=$(echo $prJson | jq '.labels[].name | select(.=="patch" or .=="minor" or .=="major")' -r)
fi

prBody=$(echo $prJson | jq .body)

if [[ $releaseType != "major" &&
    $releaseType != "minor" &&
    $releaseType != "patch" ]]
then
    echo "Invalid release type found: $releaseType"
    exit 1
fi

echo "Using release type from PR: $releaseType"

latestReleaseJson=$(curl -H "Authorization: token $GITHUB_TOKEN_TAG" -s $latestReleaseUrl)
lastVersion=$(echo $latestReleaseJson | jq .tag_name -r)

if [[ $lastVersion == "null" ]]
then
    echo "Last version not found. Bailing out. Please create a release manually first!"
    exit 1
fi

echo "Found last version as $lastVersion"

if [[ ${lastVersion:0:1} == "v" ]]
then
    lastVersion=${lastVersion:1}
fi

a=( ${lastVersion//./ } )

if [[ $releaseType == "major" ]]
then
  swallowErr=$(((a[0]++)))
  a[1]=0
  a[2]=0
fi


if [[ $releaseType == "minor" ]]
then
  swallowErr=$(((a[1]++)))
  a[2]=0
fi


if [[ $releaseType == "patch" ]]
then
  swallowErr=$(((a[2]++)))
fi

newVersion="v${a[0]}.${a[1]}.${a[2]}"

echo "New version number: $newVersion"

curl -X POST -H "Authorization: token $GITHUB_TOKEN_TAG" -s --fail -d "{\"tag_name\": \"$newVersion\",\"target_commitish\":\"$GITHUB_SHA\",\"name\": \"$newVersion - $COMMIT_MSG\",\"body\": $prBody}" $releaseUrl

echo $newVersion >> VERSION
unset GITHUB_TOKEN_TAG

echo "::set-output name=version::$newVersion"