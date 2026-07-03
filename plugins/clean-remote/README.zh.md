# clean-remote

一个用于 **local-overlay / clean-remote（本地叠加 / 干净远端）** 工作流的 Claude Code 插件：
让规划文档和 agent 辅助文件在本地被完整追踪并保留历史，同时让公开远端始终保持干净。

## 为什么需要它
有些文件你希望在本地纳入版本管理 —— 规划笔记、agent 指令、设计草稿 —— 但绝不希望它们出现在公开远端上。
脆弱的做法是每次 push 前都得记得手动清理。这个插件把"干净的远端"变成一种由配置保证的属性，而非一种习惯：

- **每个本地开发分支** 都携带它自己的仅限本地文件（已提交，带历史），并映射到它 **自己的公开压缩（squashed）分支** ——
  `feat/login` → `origin/feat/login`、`spike/cache` → `origin/spike/cache`，依此类推；分支之间互不共享；
- **`REMOTE_EXCLUDE.md`** 声明这些路径，并把它自身也列入其中 —— 它从每个分支自己提交的副本中读取，
  因此不同分支可以各自保留自己的私有路径；
- **`publish`** 为当前分支的公开对应分支构建一个干净的提交 —— 只携带该分支自上次发布以来的新增工作，
  并剥离上述路径 —— 因此每条公开历史都保持线性、每次 push 都是 fast-forward（首次发布会 *创建* 该公开分支）；
- 一个 git **`pre-push` 钩子** 会拦截任何仍包含私有路径、且指向公开远端的 push ——
  这样一次失手的 `git push` 也无法泄露内容。

无需保留历史的临时垃圾文件不属于这个插件的职责 —— 那类文件直接放进 `.gitignore` 即可。请保持这
两个列表 **互不重叠**：被追踪但不上远端 → `REMOTE_EXCLUDE.md`，纯临时草稿 → `.gitignore`，
绝不二者兼有（被 gitignore 的路径永远不会被提交，所以也就没有历史可供 `publish` 剥离）。
`doctor` 会标记任何重叠情况。

## 安装
这是一个 Claude Code 插件。该仓库同时也充当它自己的单插件 **marketplace（插件市场）**
（`.claude-plugin/marketplace.json`），所以你可以直接安装它。

**从托管仓库安装**（在 GitHub 上位于 `JakobMusik/clean-remote-claude-plugin`）：

    /plugin marketplace add JakobMusik/clean-remote-claude-plugin
    /plugin install clean-remote@jakobmusik

**从本地克隆安装** —— 先把该目录添加为一个 marketplace，再安装：

    /plugin marketplace add /path/to/clean-remote
    /plugin install clean-remote@jakobmusik

**用于开发** —— 不安装即可加载工作副本（用 `/reload-plugins` 实时获取改动）：

    claude --plugin-dir /path/to/clean-remote

通过 `/plugin`（Installed 选项卡）或 `/plugin list` 进行验证。`skills/` 下的技能会被
自动发现 —— 无需注册 —— 并以命名空间形式出现，分别为 `clean-remote:setup`、
`clean-remote:target`、`clean-remote:publish`、`clean-remote:scrub-refs`、`clean-remote:sync`、
`clean-remote:doctor` 和 `clean-remote:uninstall`。

### 手动安装（无插件）
如果你更希望把这些技能以固定副本的形式直接放进某一个项目 —— 不用 marketplace、不用插件机制 ——
请使用随仓库附带的安装脚本：

    sh /path/to/clean-remote/install.sh /path/to/your/project

它会把这些技能复制到 `<project>/.claude/skills/`，把脚本复制到 `<project>/.claude/clean-remote-scripts/`，
然后把每个技能里的 `${CLAUDE_PLUGIN_ROOT}` 引用改写为绝对路径。该变量 **只有** 插件加载器才会设置，
因此若不改写，一份非插件的副本会试图运行 `sh "/scripts/setup.sh"` 而失败 —— 这也正是为什么仅靠手动
复制 `skills/` 目录（或用诸如 `npx skills install` 之类的技能安装器去获取它）本身并不够。

以这种方式安装后，这些技能是 **没有命名空间前缀的** 项目级技能 —— `setup`、`target`、`publish`、
`scrub-refs`、`sync`、`doctor`、`uninstall`（没有 `clean-remote:` 前缀）—— 并且只随那一个仓库存在。改写后的路径是绝对的；
如果你迁移了项目位置，重新运行该安装脚本即可。其余一切（`setup` → `publish` → `doctor` 流程）
都与下文完全一致。

## 技能（Skills）
| 技能 | 作用 |
|-------|--------------|
| `setup` | 给仓库打标记：记录配置（远端 + 发布分支模板）、创建 `REMOTE_EXCLUDE.md`、安装 pre-push 防护、设置 `worktree.baseRef=head`。幂等；并会自动迁移旧的单分支配置。 |
| `target` | 显示或更改某个本地开发分支发布到哪个公开分支 —— 列出完整的"分支 → 公开分支"映射、设置逐分支覆盖，或恢复为模板。仅配置；从不 push。 |
| `publish` | 把当前分支的新增工作前向移植到它的公开分支 tip 之上（首次发布时会创建它），剥离 `REMOTE_EXCLUDE` 中的路径，留下一个可供 push 的干净提交。`--branch <name>` 可指定另一个分支。从不 push；也从不改动你的工作树。 |
| `scrub-refs` | 在 *将要发布* 的文件中查找指向 `REMOTE_EXCLUDE` 路径的引用（链接、import、提及）—— 由于 `publish` 已剥离这些目标，它们在公开远端上是失效的 —— 以便你重写或删除它们。只读探测器；`--ref` 可扫描发布产物或某个远端分支。 |
| `sync` | publish 的反向操作：把外部的公开提交（例如一个已合并的贡献者 PR）cherry-pick 回对应的开发分支，使其始终是其公开分支的超集。从不移动你的分支；只把 apply 命令交还给你。 |
| `doctor` | 检查防护钩子、设置，并逐分支检查排除列表（包括是否与 `.gitignore` 重叠）、历史关系、待处理的外部提交，以及是否已有私有内容泄露。`--all` 会扫描每一个受管理的分支。 |
| `uninstall` | 移除钩子、`baseRef` 覆盖设置、仓库配置以及逐分支的键。保留你的文件、分支以及已发布的提交。 |

## 快速开始
`setup`、`publish` 和 `doctor` 是 **技能** —— 在 Claude Code 内部调用它们（例如让它
"运行 clean-remote setup"）。下面的 `git` 命令在你的 shell 中运行。

**1. 每个仓库一次性操作。** 在你的工作分支上、远端已配置好的前提下，运行
**`setup`** 技能。它会给仓库打标记（git config、pre-push 钩子、`worktree.baseRef=head` —— 见
[配置](#配置)）并创建 `REMOTE_EXCLUDE.md`。幂等，因此重复运行是安全的。

**2. 声明你仅限本地的路径。** 编辑 `REMOTE_EXCLUDE.md`，列出你希望保留在本地的路径
（每行一个 git pathspec，例如 `.planning/`），然后在你的分支上提交它：

    git add REMOTE_EXCLUDE.md && git commit -m "Track local-only paths"

**3. 照常工作。** 把所有内容 —— 公开改动 *以及* 仅限本地的文件 —— 都提交到你的
私有分支。它们就存放在那里，带完整历史，而且永远不会被 push：

    git add -A && git commit -m "your work"

**4. 准备好后发布。** 用一行摘要运行 **`publish`** 技能。它会把你分支上的新增工作前向移植到
远端 tip 之上，剥离 `REMOTE_EXCLUDE` 中的路径，并打印三条命令 ——
**review（审阅）**、**push（推送）**、**tidy（清理）**。先审阅 diff，然后自己运行打印出的 `push`；
`publish` 从不替你 push。`publish` 移除的是私有 *文件*，但已发布的文件里可能仍 *链接到* 或 *提及*
它们 —— 运行 **`scrub-refs`** 技能找出这些已失效的引用，并在 push 前重写或删除它们。

**5. 把贡献回拉（当一个 PR 落到远端时）。** 如果有人把一个 PR 合并到了公开分支上，运行
**`sync`** 技能。它会把这些外部提交 cherry-pick 到一个 `clean-remote/sync-*` 分支上，并打印
**review**、**apply**、**tidy** —— 用打印出的 `git merge --ff-only` 把这份工作应用进你的私有分支。
无论如何发布都会保留该 PR，但把它同步回来能让你的私有分支保持为唯一可信来源（也避免日后你编辑同一处
行时产生冲突）。见 [与贡献者协作](#与贡献者协作)。

随时运行 **`doctor`** 技能，以确认配置健康且没有任何私有内容泄露。

## 配置
clean-remote 把它的设置存放在 **git config** 中 —— 与 `user.name` 或 `remote.origin.url`
使用同一机制。`setup` 用 `git config clean-remote.<key> <value>` 写入它们，这些设置会落在
仓库的本地配置文件（`.git/config`）里。git 从不追踪自己的配置，所以这些设置在构造上就是
**逐仓库、本地、且永不被 push** 的 —— 这也是为什么一份全新克隆一开始并不带它们
（需要在那里重新运行 `setup`）。

这里 **没有单一的 `source` 分支** —— 命令作用于当前分支（或 `--branch <name>`），而每个分支都映射到
它自己的公开分支。设置分为仓库级的键和逐分支的键（后者位于 git 自己的 `branch.<name>.*` 命名空间下，
与 `branch.<name>.remote` 并列）：

| 键 | 作用域 | 含义 | 默认值 |
|-----|-------|---------|---------|
| `clean-remote.remote` | 仓库 | 你发布到的远端 —— 也是 pre-push 防护所保护的那个 | `origin` |
| `clean-remote.publishBranchTemplate` | 仓库 | 把本地分支名映射到它的公开分支名；`%s` 即分支名 | `%s`（同名） |
| `branch.<B>.cleanRemotePublish` | 分支 | 为本地分支 `B` 显式指定公开分支名（覆盖模板） | 未设置 → 用模板 |
| `branch.<B>.cleanRemoteSyncpoint` | 分支 | `sync` 为 `B` 集成的最后一个提交 —— 让下一次发布从已集成的 PR 工作 *之后* 开始 diff（自动管理；仅当它仍是 `B` 的祖先时才生效） | 首次 `sync` 前未设置 |

因此在默认模板下，本地 `feat/x` 会发布到 `origin/feat/x`。要更改某个分支发布到哪里，最省事的
办法是用 **`target`** 技能（它会做校验并对下面的注意事项给出提示）；底层其实就是普通的 git config，
你也可以自己运行：

    # 查看完整映射（哪个分支 → 哪个公开分支，覆盖还是模板）
    git config --get-regexp 'cleanRemotePublish'          # 仅看逐分支覆盖
    # 把 feat/x 指向另一个公开分支
    git config branch.feat/x.cleanRemotePublish public/feat-x
    # 把 feat/x 恢复为同名模板
    git config --unset branch.feat/x.cleanRemotePublish

更改会在 **下一次 publish** 时生效；不会推送任何东西。一个注意事项：把一个 *已经发布过* 的分支
重新指向新目标会在新目标上重新建立基线 —— 旧的公开分支会原样保留（既不更新也不删除），而如果新目标
尚不存在，首次 publish 会 *创建* 它。`doctor` 会逐分支显示最终的映射关系。

在 setup 时用环境变量设置仓库级的键 —— `CR_REMOTE`、`CR_TEMPLATE` —— 或用 `CR_PUBLISH=<name>`
设置 *当前* 分支的覆盖值。之后可用 `git config` 修改任意键 —— 而且重新运行 `setup` 会 **保留**
已经设置好的值（环境变量用于覆盖已有值；一次不带参数的重跑绝不会把 `remote`/`template` 或任何
逐分支覆盖重置为默认值）。用 `git config --get-regexp '^clean-remote\.'` 和
`git config --get-regexp 'cleanRemote'` 查看全部。这些技能会读取这些设置（并回退到上面的默认值），
所以你很少需要手动传入任何东西。

**从旧的单分支配置升级？** `setup` 会自动把
`clean-remote.{source,publishBranch,syncpoint}` 迁移到上面的逐分支键
（`branch.<source>.cleanRemotePublish` / `cleanRemoteSyncpoint`）并移除旧的全局键。

`REMOTE_EXCLUDE.md`（仓库根目录）是路径列表 —— 每行一个 git pathspec，允许 `#` 注释。
与上面的 git-config 设置不同，它 **是** 被追踪的：提交在每个开发分支上（带历史）并列出它
自身，所以这份策略会随分支同行，但永远不会抵达远端。它从 **每个分支自己提交的副本** 中读取，
因此不同开发分支可以声明不同的私有路径 —— 防护钩子和 `publish` 会为每个分支套用正确的列表。

## 说明与限制
- **增量、无冲突的重复发布。** 每次发布只前向移植自上次以来的新增工作 —— 由该分支公开提交上的一个
  `clean-remote-source` trailer 追踪 —— 到当前公开 tip 之上。重新编辑一个已发布的文件即可正常工作，
  而直接在公开分支上做出的提交（例如一个已合并的 PR）也会保留下来。真正的重叠（公开分支改动了
  与你的新增工作相同的行）会被呈现出来交由你手动协调，而不会被强行处理。首次发布会把该公开分支
  *创建* 为开发分支（剥离排除项后）的一个干净 orphan 快照；私有历史被改写后的恢复也以同样方式重新同步。
  `doctor` 会逐分支报告其状态。
- **每次发布一个干净提交。** 每次发布都会在远端 tip 之上放置一个被清理过的单一提交；你逐个提交
  的私有历史仍留在本地。这对干净的公开日志很有好处 —— 但它不是你本地提交的镜像。
- **pre-push 防护阻止的是意外，它不是安全边界。** 它可以用 `git push --no-verify` 绕过，而且
  它只保护 `clean-remote.remote` 中所命名的 **那一个** 远端 —— 推送到任何 *其它* 远端
  （比如第二个 fork）都不会被检查。请把那个配置指向你实际 push 的远端。
- **配置是本地且不纳入版本管理的 —— 全新克隆后请重新运行 `setup`。** 钩子位于
  `.git/hooks/` 中，`worktree.baseRef=head` 位于 `.claude/settings.local.json` 中
  （Claude Code 默认会将其 gitignore）；二者都不会被提交。在你重新运行 `setup` 之前，
  防护是缺失的，新的 worktree 会从远端而非你的本地线分支。
- **每条私有线都是单写者模型。** 你的开发分支是你自己的；每个公开分支都是一个发布目标，
  其他人可以通过 PR 向它贡献（见下文）。在 *私有* 分支自身上进行重度的多写者协作不在本插件范围内。

## 与贡献者协作
公开分支是一个普通分支 —— 人们可以 fork 它、提 PR，你也可以在托管平台（GitHub 等）上合并它们。
clean-remote 对两个方向都有处理：

- **出站（`publish`）。** 每次发布都会把你新增的私有工作前向移植 *到* 当前远端 tip 之上，
  因此落在公开分支上的一个已合并 PR 会被 **保留**，绝不会被覆盖。
- **入站（`sync`）。** 一个已合并的 PR 在你把它拉回来之前只存在于公开远端上。运行
  **`sync`** 把这些外部提交 cherry-pick 进你的私有分支（它会按 patch-id 跳过你自己的发布以及
  任何已集成的内容）。应用打印出的 `git merge --ff-only`。

**为什么要把它同步回来，而不是仅靠 publish 去保留它？** 你的私有分支是唯一可信来源。
如果你 *不* 集成某个 PR，你的分支就会悄悄地缺少它 —— 而下次你编辑该 PR 也改动过的某一行时，
publish 就会撞上一个真正的"公开改动了相同的行"冲突。同步能保持私有 ⊇ 公开，于是这种情况永不发生。
`sync` 会记录一个逐分支的 `branch.<name>.cleanRemoteSyncpoint`，让下一次发布从已集成的工作 *之后*
开始 diff；没有它的话，publish 的"上次发布"标记会停在该 PR 之前，并与一个陈旧的基底产生冲突。
