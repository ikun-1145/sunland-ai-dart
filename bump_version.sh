#!/bin/bash

file="pubspec.yaml"

# 读取当前版本
version=$(grep '^version:' $file | awk '{print $2}')

# 分割 versionName 和 build number
name=${version%%+*}
build=${version##*+}

# build +1
new_build=$((build + 1))

new_version="$name+$new_build"

# 替换 pubspec.yaml
sed -i '' "s/^version:.*/version: $new_version/" $file

echo "✅ 版本已更新为: $new_version"