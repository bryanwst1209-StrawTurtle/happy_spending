#!/bin/sh
# 把 scripts/git-hooks 里的钩子链接进 .git/hooks。重新克隆仓库后运行一次即可。
cd "$(git rev-parse --show-toplevel)" || exit 1
for hook in post-checkout post-merge; do
  ln -sf "../../scripts/git-hooks/$hook" ".git/hooks/$hook"
done
echo "已安装:切换分支、合并后会自动运行 xcodegen generate"
