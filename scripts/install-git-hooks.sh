#!/bin/sh
# 把 scripts/git-hooks 里的钩子复制进 .git/hooks。重新克隆仓库后运行一次即可;钩子内容改了再运行一次。
# 用复制而不是链接:切到没有 scripts/ 目录的旧分支时,链接会失效。
cd "$(git rev-parse --show-toplevel)" || exit 1
for hook in post-checkout post-merge; do
  rm -f ".git/hooks/$hook"
  cp "scripts/git-hooks/$hook" ".git/hooks/$hook"
  chmod +x ".git/hooks/$hook"
done
echo "已安装:切换分支、合并后会自动运行 xcodegen generate"
