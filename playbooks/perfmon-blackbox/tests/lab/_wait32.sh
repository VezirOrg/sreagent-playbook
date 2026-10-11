. "$(dirname "$0")/common.sh"
for i in $(seq 1 90); do
  got=$(v arc1 '$c = Get-Content C:\ProgramData\PerfmonBlackbox\config.json -Raw | ConvertFrom-Json; "$($c.MaxSizeMB)/$($c.SampleIntervalSeconds)"' | tr -d '\r' | tail -1)
  [ "$got" = "32/10" ] && { echo "$(date -u +%H:%M:%S) reached 32/10"; exit 0; }
  sleep 30
done; exit 1
