#!/bin/bash
# Sequentially re-ingest comments then archive data sources
# (Bedrock KB limits concurrent ingestion jobs per KB to 1).
set -e
KB=BPB9QGVZBQ
DS_COMMENTS=D2AITIKISA
DS_ARCHIVE=QUN2YTOAJE
REGION=us-east-1

poll_until_terminal () {
  local ds=$1 job=$2
  for i in $(seq 1 60); do
    local st
    st=$(aws bedrock-agent get-ingestion-job \
          --knowledge-base-id "$KB" \
          --data-source-id "$ds" \
          --ingestion-job-id "$job" \
          --region "$REGION" \
          --output json | python3 -c "import sys,json;print(json.load(sys.stdin)['ingestionJob']['status'])")
    echo "  [$i] ds=$ds job=$job status=$st"
    case "$st" in
      COMPLETE) return 0 ;;
      FAILED)   return 1 ;;
    esac
    sleep 5
  done
  return 1
}

wait_no_active_job () {
  local ds=$1
  for i in $(seq 1 60); do
    local st
    st=$(aws bedrock-agent list-ingestion-jobs \
          --knowledge-base-id "$KB" \
          --data-source-id "$ds" \
          --region "$REGION" \
          --max-results 1 \
          --sort-by attribute=STARTED_AT,order=DESCENDING \
          --output json | python3 -c "import sys,json;j=json.load(sys.stdin)['ingestionJobSummaries'];print(j[0]['status'] if j else 'NONE')")
    echo "  [$i] ds=$ds latest=$st"
    case "$st" in
      STARTING|IN_PROGRESS) sleep 5 ;;
      *) return 0 ;;
    esac
  done
  return 1
}

echo "=== wait for any in-flight ingestion on comments DS ==="
wait_no_active_job "$DS_COMMENTS"
echo "=== wait for any in-flight ingestion on archive DS ==="
wait_no_active_job "$DS_ARCHIVE"

echo "=== start comments ingestion ==="
CJ=$(aws bedrock-agent start-ingestion-job \
      --knowledge-base-id "$KB" \
      --data-source-id "$DS_COMMENTS" \
      --region "$REGION" \
      --output json | python3 -c "import sys,json;print(json.load(sys.stdin)['ingestionJob']['ingestionJobId'])")
echo "comments job=$CJ"
poll_until_terminal "$DS_COMMENTS" "$CJ"

echo "=== start archive ingestion ==="
AJ=$(aws bedrock-agent start-ingestion-job \
      --knowledge-base-id "$KB" \
      --data-source-id "$DS_ARCHIVE" \
      --region "$REGION" \
      --output json | python3 -c "import sys,json;print(json.load(sys.stdin)['ingestionJob']['ingestionJobId'])")
echo "archive job=$AJ"
poll_until_terminal "$DS_ARCHIVE" "$AJ"

echo "=== warming wait 60s ==="
sleep 60
echo "DONE"
