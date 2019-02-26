# Time Machine Fixer


The dreaded "Time Machine completed a verification of your backups. To improve
reliability, Time Machine must create a new backup for you."

Time Machine periodically gives me an error that it needs to create a new
backup. This takes forever, and I lose history.

It turns out this happens when the underlying filesystem is corrupted, usually
because of an abrupt disconnect while a backup was running.

The tools to repair this corruption are already in place on the system. This
scripts makes use of them to repair the TM volume and get it working again. Then
it runs a backup, which completes WITHOUT starting over.

The output will look nicer if you have 'pv' installed. `brew install pv`
