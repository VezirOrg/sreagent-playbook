#!/bin/sh
# T17 (V5): only the agent: vm1's own managed identity is refused a token for api://<appId> (AADSTS501051, assignment
# required), and an ARM token of the same identity gets 401 from DAB even with the role header.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
a=$(app_id); [ -n "$a" ] || { bad "no app ID"; finish; exit 1; }
o=$(v vm1 "try { Invoke-RestMethod -Headers @{Metadata='true'} -UseBasicParsing -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=api://$a' | Out-Null; 'GOT_TOKEN' } catch { 'REFUSED ' + \$_.ErrorDetails.Message }")
echo "$o" | grep -q 'AADSTS501051' && ok "vm1 MI refused (AADSTS501051)" || bad "vm1 MI not refused: $(echo "$o" | head -c 300)"
o=$(v vm1 "\$t = (Invoke-RestMethod -Headers @{Metadata='true'} -UseBasicParsing -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F').access_token; try { C:\\sqlmcp\\mcp-call.ps1 -Url 'http://$real1.$domain:5000/mcp' -List -Token \$t -Role MCP.Read | Out-Null; 'ACCEPTED' } catch { 'STATUS ' + [int]\$_.Exception.Response.StatusCode }")
check "ARM token to DAB" "$(echo "$o" | kv STATUS)" "401"
finish
