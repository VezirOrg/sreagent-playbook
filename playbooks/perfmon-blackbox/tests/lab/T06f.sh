#!/bin/sh
# T06f part 2 [arc1] (a machine without IIS): G3 is not configured; install IIS + ASP.NET 4.x (lab step), then within
# 30 min the collector holds the G3 lines whose objects now exist, re-created through the pending path (no sample lost
# beyond the restart). Part 1 (no event storm) was proven on dc (decisions P27).
. "$(dirname "$0")/common.sh"
m="${1:-arc1}"
before=$(guest "$m" collector.ps1 | grep 'G3 configured'); echo "before: $before"
v "$m" 'Install-WindowsFeature Web-Server, Web-Asp-Net45 | Select-Object Success, RestartNeeded | Format-List | Out-String'
for i in $(seq 1 60); do
  after=$(guest "$m" collector.ps1 | grep 'G3 configured')
  case "$after" in *"G3 configured: 0"*|"$before") sleep 30 ;; *) break ;; esac
done
echo "after:  $after"
[ "$after" != "$before" ] && ok 'G3 lines added after IIS appeared' || bad 'G3 unchanged after 30 min'
guest "$m" collector.ps1 | grep -q 'RESULT: PASS' && ok 'collector equals the expected list, running' || bad 'collector check'
finish
