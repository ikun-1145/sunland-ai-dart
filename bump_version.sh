#!/bin/bash


set -e

# ===== 错误捕获 & 日志输出 =====
LOG_FILE="deploy.log"
exec > >(tee -a $LOG_FILE) 2>&1

trap 'echo "\n❌ 脚本执行失败，日志如下："; tail -n 50 $LOG_FILE' ERR

#
# ===== 手动路径配置（方案一） =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
UPDATE_DIR="/Users/liuxize/Library/Mobile Documents/com~apple~CloudDocs/Documents/xixi"   # ← iCloud 文稿真实路径
UPDATE_FILE="$UPDATE_DIR/update.json"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

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

# ===== 解析语义版本号 =====
IFS='.' read -r major minor patch <<< "$name"

if [ -z "$major" ] || [ -z "$minor" ] || [ -z "$patch" ]; then
  echo "❌ 版本号格式错误，应为 x.y.z"
  exit 1
fi

echo "\n📌 当前版本: $major.$minor.$patch"
echo "请选择升级方式："
echo "1) Patch（修复）: $major.$minor.$((patch+1))"
echo "2) Minor（功能）: $major.$((minor+1)).0"
echo "3) Major（大版本）: $((major+1)).0.0"

read -p "👉 输入选项 (1/2/3): " choice

case $choice in
  1)
    patch=$((patch + 1))
    ;;
  2)
    minor=$((minor + 1))
    patch=0
    ;;
  3)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  *)
    echo "❌ 无效选择"
    exit 1
    ;;
esac

new_name="$major.$minor.$patch"
new_build=$((build + 1))
new_version="$new_name+$new_build"

echo "🚀 升级版本: $version → $new_version"

# ===== 输入发行说明 & 更新描述 =====
read -p "📝 输入本次更新说明（用于 update.json desc）: " desc
read -p "📦 输入 GitHub Release 发行说明: " notes

# ===== 更新 update.json =====
echo "🔍 检查 update.json 路径..."
echo "📁 UPDATE_DIR=$UPDATE_DIR"
echo "📄 UPDATE_FILE=$UPDATE_FILE"

if [ -f "$UPDATE_FILE" ]; then
  echo "✅ 找到 update.json"
else
  echo "❌ 未找到 update.json"
  echo "📂 当前目录内容："
  ls -la "$UPDATE_DIR"
  exit 1
fi

# 继续执行更新
if true; then
  echo "🌐 正在更新 update.json..."

  python3 -c '
import json, sys
path, version, build, desc = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
with open(path) as f:
    data = json.load(f)
data["version"] = version
data["build"] = build
data["url"] = "https://download-worker.liuxizekali.workers.dev/"
data["force"] = False
data["desc"] = desc
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
' "$UPDATE_FILE" "$new_name" "$new_build" "$desc"

  echo "✅ update.json 已更新"

  cd "$UPDATE_DIR"
  git add update.json
  git commit -m "chore: bump version to $new_version" || true
  git push || echo "⚠️ push 失败"
  cd - > /dev/null
fi

# ===== 更新 pubspec.yaml =====
sed -i '' "s/^version:.*/version: $new_version/" $file

git add $file
git commit -m "chore: bump version to $new_version" || true

# ===== 构建前清理 =====
echo "🧹 清理构建缓存..."
flutter clean
flutter pub get

# ===== 构建 APK =====
echo "📦 正在构建 APK..."
flutter build apk --release

# ===== 重命名 APK（带版本号） =====
VERSIONED_APK="build/app/outputs/flutter-apk/app-$new_version.apk"
cp $APK_PATH $VERSIONED_APK

echo "📦 已生成: $VERSIONED_APK"


# ===== 可选：GitHub Release（需 gh CLI） =====
echo "🚀 发布 GitHub Release..."

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ 未安装 gh CLI，请先安装: brew install gh"
else
  if gh release create "v$new_version" "$VERSIONED_APK" \
    --title "v$new_version" \
    --notes "$notes"; then

    echo "🌐 打开 GitHub Release 页面..."
    gh release view v$new_version --web

  else
    echo "⚠️ GitHub Release 失败"
  fi
fi


echo "✅ 完成！当前版本: $new_version"