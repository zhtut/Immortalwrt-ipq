#!/usr/bin/env bash
#
# update_branch.sh
# 从 immortalwrt 上游 openwrt-25.12 分支同步代码到当前仓库，并提交。
#
# 同步策略:
#   - 使用 depth=1 浅克隆，加快下载速度
#   - 使用 rsync --delete 镜像上游内容到当前目录
#   - 保留本地 .git 目录与本脚本自身（否则无法提交）
#   - 提交信息: feat: update (YYYY-MM-DD)

set -euo pipefail

UPSTREAM_URL="https://github.com/immortalwrt/immortalwrt.git"
UPSTREAM_BRANCH="openwrt-25.12"

# 当前脚本所在目录即仓库根目录
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$REPO_DIR"

# 必须是 git 仓库，否则后续 commit 无意义
if [ ! -d ".git" ]; then
    echo "[ERROR] 当前目录不是 git 仓库: $REPO_DIR" >&2
    exit 1
fi

# 依赖检查
for cmd in git rsync; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] 缺少依赖: $cmd" >&2
        exit 1
    fi
done

DATE_STR="$(date +%F)"
TMP_DIR="$(mktemp -d -t immortalwrt-upstream-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[INFO] 浅克隆 $UPSTREAM_URL ($UPSTREAM_BRANCH) 到临时目录 ..."
# 加速选项:
#   --depth=1                只取最新一次提交
#   --single-branch          只取目标分支
#   --no-tags                不下载 tag
#   --filter=blob:none 已被 depth=1 覆盖, 此处不再叠加
#   并行: 通过 GIT_HTTP_LOW_SPEED_* 与 protocol.version=2 提升体验
GIT_TERMINAL_PROMPT=0 git \
    -c protocol.version=2 \
    -c http.postBuffer=524288000 \
    clone \
    --depth=1 \
    --single-branch \
    --branch "$UPSTREAM_BRANCH" \
    --no-tags \
    --quiet \
    "$UPSTREAM_URL" "$TMP_DIR/src"

UPSTREAM_SHA="$(git -C "$TMP_DIR/src" rev-parse --short HEAD)"
echo "[INFO] 上游最新提交: $UPSTREAM_SHA"

echo "[INFO] 使用 rsync 强制覆盖到本地仓库 ..."
# rsync 说明:
#   -a            保留权限/时间等
#   --delete      上游已删除的本地也删除（实现强制对齐）
#   --exclude     保留 .git 与本脚本，避免破坏仓库与无法提交
#   源路径结尾的 / 表示同步“目录内容”
rsync -a --delete \
    --exclude='.git' \
    --exclude='.git/**' \
    --exclude="/$SCRIPT_NAME" \
    "$TMP_DIR/src/" "$REPO_DIR/"

# 暂存全部变更
echo "[INFO] git add ..."
git add -A

if git diff --cached --quiet; then
    echo "[INFO] 没有需要提交的变更，与上游一致。"
    exit 0
fi

COMMIT_MSG="feat: update ($DATE_STR)"
echo "[INFO] 提交: $COMMIT_MSG"
git commit -m "$COMMIT_MSG"

echo "[INFO] 推送到远端 ..."
CURRENT_BRANCH="$(git symbolic-ref --short HEAD)"
git push origin "$CURRENT_BRANCH"

echo "[DONE] 已同步至上游 ${UPSTREAM_BRANCH}@${UPSTREAM_SHA} 并推送到 origin/${CURRENT_BRANCH}"
