# Action Execution

This context describes actions identified by a key and their execution rules.

## Language

**Execution Scope**:
The period or condition that determines when an action identified by a key can be considered complete. Session, permanent, hourly, daily, monthly, and yearly scopes are independent, even when they use the same key. Calendar scopes use the local period at the time of the call.

**Completed Action**:
An action whose execution finished successfully and whose completion was recorded in its scope.
