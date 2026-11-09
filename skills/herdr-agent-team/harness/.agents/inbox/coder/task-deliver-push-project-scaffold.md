[TASK] from: pm -> to: coder
Task ID: deliver-push-project-scaffold
Controller pane: w92:p1
Target pane: w92:p3

Task class: delivery
Operation: implementation
Base branch: feature/task-board-mvp
Work branch: feature/task-board-mvp
Allowed files: N/A
Required behavior: Run exactly one agent_authorized_push for commit 254bcf2eece92eb6ae030df5c6aad5194f81b4ce on branch feature/task-board-mvp to origin.
Forbidden scope: Do not modify files, create local commits, create PRs, push other branches, force push, delete refs, use another remote, or perform any other remote mutation.
Simplicity: Directly execute the one authorized push and report the result.

Acceptance Gate:
BLOCKER:
- Exact authorized push of feature/task-board-mvp at commit 254bcf2eece92eb6ae030df5c6aad5194f81b4ce succeeds.
ADVISORY: none
Revision budget: 2
Model budget: economical
Verification: none

Model Selection:
Role: coder
Runtime: pi
Model: tencent/kimi-k3
Reason: Low-risk delivery fast path requiring one exact guarded push and no code changes.

Execution constraints:
- Verify the current branch and HEAD only as required by agent_authorized_push.
- Use the exact authorization token below unchanged.
- Run no raw git push and no other remote operation.
- Report [DONE] or [STUCK] to controller pane w92:p1.

Authorization:
[AUTHORIZE_PR_PUSH] branch=feature/task-board-mvp commit=254bcf2eece92eb6ae030df5c6aad5194f81b4ce

Reply required: [ACK], then [DONE] or [STUCK], to pane w92:p1.

Context Handoff:
Next session focus: Execute the single authorized branch push.
Current state: Human authorization is present and scope is frozen.
Completed:
- PM confirmed direct delivery staffing and exact Coder model.
Pending next action:
- Run agent_authorized_push once and report guarded evidence.
Open decisions / blockers:
- none
Artifacts:
- none
Suggested skills:
- agent-shared — required push-message helpers.
Sensitive data: none / redacted

Dispatch Record:
Task ID: deliver-push-project-scaffold
Target pane: w92:p3
from: pm
to: coder
Intended role: coder
Delivery status: sent
