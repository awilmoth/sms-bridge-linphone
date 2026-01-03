#!/bin/bash
# Monitor mmsgate Docker build progress

VPS_HOST="${1:-sip-us.aaronwilmoth.org}"
VPS_USER="${2:-root}"

echo "Monitoring mmsgate build on $VPS_USER@$VPS_HOST..."
echo ""

while true; do
  echo "[$(date '+%H:%M:%S')] Checking Docker images..."
  
  ssh -i ~/.ssh/id_ed25519 "$VPS_USER@$VPS_HOST" 'docker image ls --format "table {{.Repository}}\t{{.Size}}"' 2>/dev/null | grep -E "flexisip|pjsip|mmsgate|registry" || echo "  (no images yet)"
  
  echo ""
  
  # Check if all three layers exist
  if ssh -i ~/.ssh/id_ed25519 "$VPS_USER@$VPS_HOST" 'docker image ls | grep -q flexisip' 2>/dev/null; then
    echo "✓ Flexisip layer exists"
  else
    echo "⏳ Flexisip layer building..."
  fi
  
  if ssh -i ~/.ssh/id_ed25519 "$VPS_USER@$VPS_HOST" 'docker image ls | grep -q "^pjsip "' 2>/dev/null; then
    echo "✓ PJSIP layer exists"
  else
    echo "⏳ PJSIP layer building..."
  fi
  
  if ssh -i ~/.ssh/id_ed25519 "$VPS_USER@$VPS_HOST" 'docker image ls | grep -q "^mmsgate "' 2>/dev/null; then
    echo "✓ mmsgate layer exists"
    echo ""
    echo "All layers built! Ready to start containers."
    break
  else
    echo "⏳ mmsgate layer building..."
  fi
  
  echo ""
  sleep 30
done
