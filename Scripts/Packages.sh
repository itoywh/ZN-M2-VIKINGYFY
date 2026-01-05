#!/bin/bash

UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	# 1. 清理旧的插件目录，防止重复
	for NAME in "${PKG_LIST[@]}"; do
		[ -z "$NAME" ] && continue
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
		if [ -n "$FOUND_DIRS" ]; then
			echo "$FOUND_DIRS" | while read -r DIR; do rm -rf "$DIR"; done
		fi
	done

	# 2. 克隆新仓库
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"
	if [ $? -ne 0 ]; then return 1; fi

	# 3. 处理特殊的包结构
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		# 修复点：添加 -not -path "./$REPO_NAME/" 避免 cp 自己到自己导致 exit 1
		find "./$REPO_NAME/" -maxdepth 3 -type d -iname "*$PKG_NAME*" -not -path "./$REPO_NAME/" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME/"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# [修改点] 统一插件名称与 Handles.sh 对应，并修复 OpenClash 的调用
UPDATE_PACKAGE "argon" "jerrykuku/luci-theme-argon" "master"
# 注意：OpenClash 仓库里本身就包含同名文件夹，直接克隆即可，若需提取则使用修正后的 pkg 逻辑
UPDATE_PACKAGE "OpenClash" "vernesong/OpenClash" "master" 
UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"

# 自动版本更新逻辑
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")
	[ -z "$PKG_FILES" ] && return
	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE")
		local RELEASE_DATA=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases")
		local PKG_TAG=$(echo "$RELEASE_DATA" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")
		[ "$PKG_TAG" == "null" ] && continue
		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			local NEW_HASH=$(curl -sL "https://github.com/$PKG_REPO/releases/download/$PKG_TAG/$PKG_NAME-$NEW_VER.tar.gz" | sha256sum | cut -d ' ' -f 1)
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
		fi
	done
}

UPDATE_VERSION "sing-box"
