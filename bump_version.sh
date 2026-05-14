#!/bin/bash

set -e  # 出错直接停

file="pubspec.yaml"

echo "🔍 正在读取版本号..."

version=$(grep '^version:' $file | awk '{print $2}')

if [ -z "$version" ]; then
  echo "❌ 未找到 version 字段"
  exit 1
fi

name=${version%%+*}
build=${version##*+}

if ! [[ "$build" =~ ^[0-9]+$ ]]; then
  echo "❌ build number 不是数字"
  exit 1
fi

new_build=$((build + 1))
new_version="$name+$new_build"


echo "🚀 升级版本: $version → $new_version"

# 更新网站 update.json（请根据你的实际路径修改）
update_file="/Users/liuxize/Documents/xixi/update.json"

if [ -f "$update_file" ]; then
  echo "🌐 正在更新 update.json..."

  # macOS sed 写法
  sed -i '' "s/\"version\": *\"[^\"]*\"/\"version\": \"$name\"/" $update_file
  sed -i '' "s/\"build\": *[0-9]*/\"build\": $new_build/" $update_file

  echo "✅ update.json 已更新"

  # 切换到网站目录提交
  cd /Users/liuxize/Documents/xixi
  git add update.json
  git commit -m "chore: bump version to $new_version" || true
  git push || echo "⚠️ push 失败，请检查远程仓库配置"
  cd - > /dev/null
else
  echo "⚠️ 未找到 update.json，已跳过"
fi

# macOS sed
sed -i '' "s/^version:.*/version: $new_version/" $file

# Git 提交
git add $file
git commit -m "chore: bump version to $new_version" || true

# 打包 APK
echo "📦 正在构建 APK..."
flutter build apk --release

echo "✅ 完成！当前版本: $new_version"