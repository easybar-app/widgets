local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/inbox_host.lua"))()

local state = host.load(root, easybar_root, "inbox-demo")

assert(#state.items == 0, "Inbox Demo must start without publishing demo items")
assert(state.configuration.order == 10000, "Inbox Demo must stay after normal Inbox sources")
assert(assert(state:source_action("refresh")).title == "Add demo", "Inbox Demo must expose its add action")
assert(assert(state:source_action("clear")).title == "Clear demo", "Inbox Demo must expose its clear action")

state.context_action_handler({ action_id = "refresh" })
assert(state:has_busy_source_action(), "adding demo items must show source activity")
assert(#state.items == 0, "Inbox Demo must retain an empty snapshot while the demo is being prepared")

state:run_next_timer()
assert(not state:has_busy_source_action(), "adding demo items must clear source activity when complete")
assert(#state.items == 10, "Inbox Demo must publish the complete representative snapshot")

local github_review = assert(state:item("github-review"), "Inbox Demo must publish the GitHub review item")
assert(github_review.source.name == "GitHub", "GitHub demo items must retain their source presentation")
assert(github_review.source.order == 10000, "GitHub demo items must stay after normal Inbox sources")
assert(
	github_review.source.icon == root .. "/packages/inbox-demo/assets/github.svg",
	"GitHub demo items must resolve their packaged icon"
)

local github_security = assert(state:item("github-security"), "Inbox Demo must publish the Markdown security item")
assert(github_security.format == "markdown", "the security demo item must exercise Markdown rendering")
assert(github_security.severity == "error", "the security demo item must exercise error severity")
assert(github_security.unread == true, "the security demo item must exercise unread state")

local github_mention = assert(state:item("github-mention"), "Inbox Demo must publish a read item")
assert(github_mention.unread == false, "the mention demo item must exercise read state")

local gitlab_pipeline = assert(state:item("gitlab-pipeline"), "Inbox Demo must publish the GitLab warning item")
assert(gitlab_pipeline.source.name == "GitLab", "GitLab demo items must retain their source presentation")
assert(gitlab_pipeline.severity == "warning", "the GitLab pipeline item must exercise warning severity")

local brew_error = assert(state:item("brew-error"), "Inbox Demo must publish the Homebrew error item")
assert(brew_error.source.name == "Homebrew", "Homebrew demo items must retain their source presentation")
assert(brew_error.category == "Updates", "the Homebrew error item must retain its category")

state.context_action_handler({ action_id = "clear" })
assert(#state.items == 0, "Clear demo must remove every published demo item")

print("Inbox Demo widget regression checks passed")
