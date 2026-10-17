#!/bin/sh
# T20: the agent reaches DAB through the VNet: with the Windows Filtering Platform connection audit on for a moment,
# the inbound connections to port 5000 come from the agent subnet. The audit is switched off again in every case.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
cidr=$(agent_subnet)
v vm1 'auditpol /set /subcategory:"Filtering Platform Connection" /success:enable' >/dev/null
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ask "How many entities does the sqlmcp describe_entities tool list? Answer with the number." >/dev/null
o=$(v vm1 "Get-WinEvent -FilterHashtable @{LogName='Security'; Id=5156; StartTime=[datetime]'$since'} -ErrorAction SilentlyContinue | ForEach-Object { \$x = [xml]\$_.ToXml(); \$d = @{}; \$x.Event.EventData.Data | ForEach-Object { \$d[\$_.Name] = \$_.'#text' }; if (\$d.DestPort -eq '5000' -and \$d.Direction -eq '%%14592') { 'SRC ' + \$d.SourceAddress } } | Sort-Object -Unique")
v vm1 'auditpol /set /subcategory:"Filtering Platform Connection" /success:disable' >/dev/null
check "audit off again" "$(v vm1 'auditpol /get /subcategory:"Filtering Platform Connection" /r | ConvertFrom-Csv | ForEach-Object "Inclusion Setting"' | tr -d '\r' | tail -1)" "No Auditing"
srcs=$(echo "$o" | sed -n 's/^SRC //p' | tr -d '\r')
[ -n "$srcs" ] || { bad "no inbound connection to 5000 seen"; finish; exit 1; }
for s in $srcs; do
  if python3 -c 'import ipaddress, sys; sys.exit(ipaddress.ip_address(sys.argv[1]) not in ipaddress.ip_network(sys.argv[2]))' "$s" "$cidr"
  then ok "source in the agent subnet"; else bad "source outside the agent subnet"; fi
done
finish
