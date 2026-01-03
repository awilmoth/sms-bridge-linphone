#!/bin/bash

# Build and push images to local Docker registry
# Handles mmsgate's multi-layer build process (flexisip → pjsip → mmsgate)

set -e

REGISTRY="localhost:5001"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BRIDGE_SERVER="$PROJECT_ROOT/bridge-server"

echo "=== Building and Pushing Images to Local Registry ==="
echo "Registry: $REGISTRY"
echo ""

# Ensure registry is running
echo "✓ Starting Docker registry..."
cd "$BRIDGE_SERVER"
docker-compose up -d registry

# Wait for registry to be ready
sleep 2

# Build and push sms-bridge
echo ""
echo "✓ Building sms-bridge..."
cd "$BRIDGE_SERVER"
docker build -t $REGISTRY/sms-bridge:latest -f Dockerfile .

echo "✓ Pushing sms-bridge to registry..."
docker push $REGISTRY/sms-bridge:latest

# Build and push mmsgate (with dependencies)
echo ""
echo "✓ Checking mmsgate repository..."
if [ ! -d "$BRIDGE_SERVER/mmsgate" ]; then
    echo "  Cloning mmsgate from GitHub..."
    cd "$BRIDGE_SERVER"
    git clone --recursive https://github.com/RVgo4it/mmsgate
fi

echo ""
echo "✓ Building mmsgate layers..."
cd "$BRIDGE_SERVER"

# mmsgate uses a multi-layer build process:
# Dockerfile_flexisip_install (base layer with flexisip)
# Dockerfile_pjsip_install (adds pjsip library)
# Dockerfile_mmsgate_install (final mmsgate service)
# All layers are built into a single final image

# Build flexisip layer (base for pjsip)
echo "  - Building flexisip layer (5-10 minutes)..."
docker build -t $REGISTRY/flexisip:latest \
  -f mmsgate/Dockerfile_flexisip_install \
  --build-arg="BRANCH=release/2.3" \
  mmsgate

# Build pjsip layer (base for mmsgate)
echo "  - Building pjsip layer (5-10 minutes)..."
docker build -t $REGISTRY/pjsip:latest \
  -f mmsgate/Dockerfile_pjsip_install \
  --build-arg="BRANCH=support-2.14.1" \
  mmsgate

# Build final mmsgate image (includes everything)
echo "  - Building mmsgate (10-15 minutes)..."
docker build -t $REGISTRY/mmsgate:latest \
  -f mmsgate/Dockerfile_mmsgate_install \
  mmsgate

echo "  - Pushing mmsgate to registry..."
docker push $REGISTRY/mmsgate:latest

echo ""
echo "=== ✅ Images built and pushed successfully ==="
echo ""
echo "Next steps:"
echo "  1. Copy config files: cp ../configs/*.example ./"
echo "  2. Edit configs with your domain and VoIP.ms credentials"
echo "  3. Deploy: docker-compose up -d"
echo "  4. Check logs: docker-compose logs -f"
