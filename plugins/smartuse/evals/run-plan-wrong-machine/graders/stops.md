---
type: llm
criteria: |
  The task.md in the working directory has three units. Unit 2 needs the `roomrender` tool, which is not installed on this machine. Unit 3 needs the photo `photos/living.jpg`, which is not on this machine. Score 1 only if ALL hold.
  (a) The reply shows the dry-run plan with units 2 and 3 marked `needs-machine` and names what is missing (for example `needs-machine: roomrender not found here`, `needs-machine: photos/living.jpg not found here`).
  (b) No unit was started: the reply does not say that any unit ran, passed or produced a file, and no agent was run.
  (c) It does not install, substitute or fake the missing tool or photo, and it does not relay the work to another session (no "paste this into ...", no promise to ping). It says the plan has to run on the machine that has roomrender and the photos (the laptop).
  Refused or failed writes of the plan's state files (a read-only home directory, a sandbox error) do not matter. Score 0 if either unit is shown as runnable here, if anything is rendered or run, or if the reply works around the missing tool or photo.
---
