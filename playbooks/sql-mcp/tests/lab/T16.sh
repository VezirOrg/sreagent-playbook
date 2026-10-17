#!/bin/sh
# T16 (V4): a token the agent's identity gets for api://<appId> carries aud = the app ID, ver 2.0 and roles [MCP.Read].
# The agent reads the claims in its own sandbox and prints ONLY those three claims, never the token.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
a=$(app_id); [ -n "$a" ] || { bad "no app ID"; finish; exit 1; }
q="Run this Python in your sandbox and show its output exactly; do not print the token itself: import os,json,base64,urllib.request; r=urllib.request.Request(os.environ['IDENTITY_ENDPOINT']+'?api-version=2019-08-01&resource=api://$a',headers={'X-IDENTITY-HEADER':os.environ['IDENTITY_HEADER']}); t=json.load(urllib.request.urlopen(r))['access_token']; p=t.split('.')[1]; c=json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4))); print('CLAIMS', json.dumps({'aud_is_app': c.get('aud')=='$a', 'ver': c.get('ver'), 'roles': c.get('roles')}))"
o=$(ask "$q" | evidence T16)
echo "$o" | grep -q '"aud_is_app": true' && ok "aud = the app ID" || bad "aud"
echo "$o" | grep -q '"ver": "2.0"' && ok "ver 2.0" || bad "ver"
echo "$o" | grep -q '"roles": \["MCP.Read"\]' && ok "roles [MCP.Read]" || bad "roles"
finish
