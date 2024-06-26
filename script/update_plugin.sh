#!/bin/bash

sourceDir=$1
targetDir=$2

if [ -z "$sourceDir" ]; then
  echo "sourceDir is required"
  exit 1
fi

if [ -z "$targetDir" ]; then
  echo "targetDir is required"
  exit 1
fi

if [ ! -d "$targetDir" ]; then
  mkdir -p $targetDir
fi

git config --local user.email "41898282+github-actions[bot]@users.noreply.github.com"
git config --local user.name "github-actions[bot]"

echo "Updating plugin index, sourceDir: $sourceDir, targetDir: $targetDir"

indexJsonFile="$targetDir/index.json"
tmpPluginJsonFile="tmp.json"

echo "[" >$indexJsonFile

for file in $sourceDir/*.json; do
  sourceName=$(jq -r '.name' $file)
  manifestUrl=$(jq -r '.manifestUrl' $file)

  echo "::::Processing [$sourceName] => [$manifestUrl]"

  response=$(curl -# -o $tmpPluginJsonFile -w "%{http_code}" -L $manifestUrl)

  if [ "$response" != "200" ]; then
    echo "Failed to download manifest: $manifestUrl"
    continue
  fi

  pluginName=$(jq -r '.name' $tmpPluginJsonFile)

  # Check if the plugin name is consistent with the manifest name,
  # ensure that the manifest changes names randomly at a later stage,
  # which not affects the registry.
  if [ "$pluginName" != "$sourceName" ]; then
    echo "The manifest name is inconsistent with the recorded name: sourcePluginName => $sourceName, manifestPluginName => $pluginName"
    continue
  fi

  # compare the version
  isEqualVersion=false
  pluginJsonFile="$targetDir/$pluginName.json"
  if [ -f $pluginJsonFile ]; then
    currentVersion=$(jq -r '.version' $pluginJsonFile)
    newVersion=$(jq -r '.version' $tmpPluginJsonFile)
    if [ "$currentVersion" = "$newVersion" ]; then
      echo "The version is the same: $currentVersion"
      isEqualVersion=true
    fi
  fi

  newVersion=$(jq -r '.version' $tmpPluginJsonFile)

  pluginJsonFile="$targetDir/$pluginName.json"

  echo "::::Updating plugin json [$pluginJsonFile]"

  jq . $tmpPluginJsonFile >$pluginJsonFile

  # 如果版本不一致,则需要提交
  if [ "$isEqualVersion" = false ]; then
    git add $pluginJsonFile

    git commit -m "$pluginName: Update to version $newVersion" $pluginJsonFile
  fi

  desc=$(jq -r '.description' $tmpPluginJsonFile)
  homepage=$(jq -r '.homepage' $tmpPluginJsonFile)
  echo "::::Adding name:[$pluginName] homepage:[$homepage] to index"
  echo "{ \"name\": \"$pluginName\", \"desc\": \"$desc\", \"homepage\": \"$homepage\" }," >>$indexJsonFile

  echo "::::End processing [$sourceName]"

done

rm $tmpPluginJsonFile

echo "IndexJsonFile: $indexJsonFile"

# Remove the last comma and add closing bracket
sed -i '' -e '$ s/,$//' $indexJsonFile
echo "]" >>$indexJsonFile

# Check if indexJsonFile has changes
if git status --porcelain | grep -q "^ M plugins/index.json"; then
  git add $indexJsonFile
  git commit -m "Update plugin index" $indexJsonFile
else
  echo "No changes in $indexJsonFile, skipping commit"
fi