# shape-feedback.jq: turn raw GraphQL pages into the item list address-review triages.
#
# Input:  {threads: [pages], comments: [pages], reviews: [pages]}
#         where each page is one response from `gh api graphql --paginate --slurp`.
# Output: {pr: {...}, items: [...], skipped: [...]}  (see tests/shape_test.sh for the contract)
#
# Rules:
#   - resolved threads are skipped (reason "resolved")
#   - a thread whose LAST comment is our own reply (carries the marker) is skipped ("answered");
#     if a reviewer wrote after our reply the thread is kept and flagged reopened
#   - comments and reviews carrying our marker are our own replies ("own-reply")
#   - comments and reviews whose id an earlier reply of ours names are "answered"
#   - CI bots (codecov, github-actions) are skipped ("ci-bot")
#   - boilerplate bodies are skipped: CodeRabbit auto-generated wrappers, rate-limit notices,
#     bare approvals ("Approved.", "LGTM")
#   - empty review bodies are skipped ("empty")
#   - threads with no comments are skipped ("empty")
#   - the PR author's own items are KEPT: /deep-review verdicts live there

def marker: "<!-- address-review:";
def has_marker: (. // "") | contains(marker);
def is_bot: (. // "") | (endswith("[bot]") or . == "coderabbitai");
def ci_bot: (. // "") as $l | (["codecov", "codecov[bot]", "github-actions[bot]"] | index($l)) != null;
def boilerplate:
  test("^\\s*<!-- This is an auto-generated comment")
  or test("Review limit reached")
  or test("^\\s*(Approved\\.?|LGTM!?|\\+1)\\s*$"; "i");
def deep_review: test("^\\s*<!-- \\*\\*Head SHA:\\*\\*");

(.threads[0].data.repository.pullRequest) as $p
| {
    number: $p.number, author: $p.author.login, state: $p.state,
    head_sha: $p.headRefOid, head_ref: $p.headRefName, head_owner: $p.headRepositoryOwner.login,
    title: $p.title, url: $p.url
  } as $pr
| [.threads[].data.repository.pullRequest.reviewThreads.nodes[]] as $threads
| [.comments[].data.repository.pullRequest.comments.nodes[]] as $comments
| [.reviews[].data.repository.pullRequest.reviews.nodes[]] as $reviews
| ([ $comments[].body, $threads[].comments.nodes[].body ]
    | map(select(has_marker) | capture("answers (?<id>[A-Za-z0-9_=:-]+)") | .id)) as $answered
| def answered: . as $i | ($answered | index($i)) != null;

  ($threads | map(
    . as $t
    | ($t.comments.nodes | map(.body | has_marker) | rindex(true)) as $mi
    | ($t.comments.nodes | length) as $n
    | if $t.isResolved then {kind: "thread", id: $t.id, reason: "resolved", skip: true}
      elif ($n == 0) then {kind: "thread", id: $t.id, reason: "empty", skip: true}
      elif ($mi != null and $mi == $n - 1) then {kind: "thread", id: $t.id, reason: "answered", skip: true}
      else {
        kind: "thread", id: $t.id, skip: false,
        author: ($t.comments.nodes[0].author.login // "ghost"),
        is_bot: ($t.comments.nodes[0].author.login | is_bot),
        path: $t.path, line: $t.line, original_line: $t.originalLine,
        start_line: $t.startLine, original_start_line: $t.originalStartLine,
        is_outdated: $t.isOutdated,
        reopened: ($mi != null),
        comments: [$t.comments.nodes[] | {id, author: .author.login, body, url, created_at: .createdAt}]
      } end)) as $thread_items
| ($reviews | map(
    if ((.body // "") | test("^\\s*$")) then {kind: "review", id, reason: "empty", skip: true}
    elif (.body | has_marker) then {kind: "review", id, reason: "own-reply", skip: true}
    elif (.author.login | ci_bot) then {kind: "review", id, reason: "ci-bot", skip: true}
    elif (.body | boilerplate) then {kind: "review", id, reason: "boilerplate", skip: true}
    elif (.id | answered) then {kind: "review", id, reason: "answered", skip: true}
    else {
      kind: "review", id, skip: false,
      author: (.author.login // "ghost"), is_bot: ((.author.login // "ghost") | is_bot),
      state, body, url, created_at: .submittedAt,
      is_deep_review: (.body | deep_review)
    } end)) as $review_items
| ($comments | map(
    if (.body | has_marker) then {kind: "comment", id, reason: "own-reply", skip: true}
    elif (.author.login | ci_bot) then {kind: "comment", id, reason: "ci-bot", skip: true}
    elif (.body | boilerplate) then {kind: "comment", id, reason: "boilerplate", skip: true}
    elif (.id | answered) then {kind: "comment", id, reason: "answered", skip: true}
    else {
      kind: "comment", id, skip: false,
      author: (.author.login // "ghost"), is_bot: ((.author.login // "ghost") | is_bot),
      body, url, created_at: .createdAt
    } end)) as $comment_items
| ($thread_items + $review_items + $comment_items) as $all
| {
    pr: $pr,
    items: ($all | map(select(.skip | not) | del(.skip)) | to_entries | map({n: (.key + 1)} + .value)),
    skipped: ($all | map(select(.skip) | {kind, id, reason}))
  }
