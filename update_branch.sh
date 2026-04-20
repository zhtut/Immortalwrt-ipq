#!/usr/bin/env bash
#
# update_branch.sh
# 从 https://github.com/immortalwrt/immortalwrt.git 的 openwrt-25.12 分支
# 强制更新当前仓库代码，并提交。
#
# 特性:
#   - 先用 ls-remote 检查上游 SHA，如未更新则直接退出，不做任何操作。
#   - 浅拉取 (depth=1)，速度快。
#   - reset --hard 时保留本脚本自身。
#

set -euo pipefail

UPSTREAM_URL="https://github.com/immortalwrt/immortalwrt.git"
UPSTREAM_BRANCH="openwrt-25.12"
REMOTE_NAME="immortalwrt-upstream"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

cd "$SCRIPT_DIR"

if [ ! -d ".git" ]; then
    echo "错误: 当前目录不是一个 git 仓库: $SCRIPT_DIR" >&2
    exit 1
fi

# 添加或更新上游 remote
if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
    git remote set-url "$REMOTE_NAME" "$UPSTREAM_URL"
else
    git remote add "$REMOTE_NAME" "$UPSTREAM_URL"
fi

# 1) 用 ls-remote 拿到上游最新 SHA（轻量，不下载对象）
echo ">>> 查询上游 $UPSTREAM_BRANCH 最新 commit ..."
REMOTE_SHA="$(git ls-remote "$REMOTE_NAME" "refs/heads/$UPSTREAM_BRANCH" | awk '{print $1}')"
if [ -z "$REMOTE_SHA" ]; then
    echo "错误: 无法获取上游分支 $UPSTREAM_BRANCH 的 SHA" >&2
    exit 1
fi
echo "    上游 SHA: $REMOTE_SHA"

# 2) 与本地记录的上游 SHA 比较，未变化则直接退出
LAST_SHA_FILE="$SCRIPT_DIR/.git/.update_branch_last_sha"
LOCAL_SHA=""
if [ -f "$LAST_SHA_FILE" ]; then
    LOCAL_SHA="$(cat "$LAST_SHA_FILE" 2>/dev/null || true)"
fi

# 兜底: 如果 remote-tracking 引用已存在，也用它比较
if [ -z "$LOCAL_SHA" ] && git rev-parse --verify --quiet "refs/remotes/$REMOTE_NAME/$UPSTREAM_BRANCH" >/dev/null; then
    LOCAL_SHA="$(git rev-parse "refs/remotes/$REMOTE_NAME/$UPSTREAM_BRANCH")"
fi

if [ -n "$LOCAL_SHA" ] && [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
    echo ">>> 上游无更新 ($REMOTE_SHA)，跳过。"
    exit 0
fi

# 3) 浅拉取上游分支
echo ">>> 浅拉取上游分支 $UPSTREAM_BRANCH (depth=1) ..."
git fetch --depth=1 --no-tags "$REMOTE_NAME" "$UPSTREAM_BRANCH"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo ">>> 当前分支: $CURRENT_BRANCH"

# 4) reset --hard 前备份本脚本
echo ">>> 强制重置到 $REMOTE_NAME/$UPSTREAM_BRANCH ..."
BACKUP_PATH="$(mktemp -t "${SCRIPT_NAME}.XXXXXX")"
cp -p "$SCRIPT_PATH" "$BACKUP_PATH"

git reset --hard "$REMOTE_NAME/$UPSTREAM_BRANCH"

# 5) 恢复脚本
cp -p "$BACKUP_PATH" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
rm -f "$BACKUP_PATH"

DATE_STR="$(date +%Y-%m-%d)"
COMMIT_MSG="feat: update (${DATE_STR})"

git add -- "$SCRIPT_PATH"

# 如果工作区相对当前 HEAD 没有任何变化，则不创建空提交
if git diff --cached --quiet && git diff --quiet; then
    echo ">>> 工作区无差异，无需提交。"
else
    git commit -m "$COMMIT_MSG"
    echo ">>> 完成: $COMMIT_MSG"
fi

# 6) 记录本次同步到的上游 SHA
echo "$REMOTE_SHA" > "$LAST_SHA_FILE"
