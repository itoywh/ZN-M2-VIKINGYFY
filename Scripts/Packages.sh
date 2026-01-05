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
		# 【关键修复】：使用 -not -path 排除仓库根目录本身，避免 cp 报错
		find "./$REPO_NAME/" -maxdepth 3 -type d -iname "*$PKG_NAME*" -not -path "./$REPO_NAME/" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME/"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# [修改点] 统一插件名称。
# 如果你只需要仓库里的特定子文件夹，请保留 "pkg"；如果只需要整个仓库，可以去掉 "pkg"。
UPDATE_PACKAGE "argon" "jerrykuku/luci-theme-argon" "master"
UPDATE_PACKAGE "OpenClash" "vernesong/OpenClash" "master" "pkg"
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
