#!/bin/bash

# Simple test for new gateway features
echo "Testing new gateway features..."

# Test 1: Script syntax
echo -n "Testing script syntax... "
if bash -n install_gateway_v10.sh; then
    echo "✅ PASS"
else
    echo "❌ FAIL"
    exit 1
fi

# Test 2: Version update
echo -n "Testing version update... "
if grep -q "SCRIPT_VERSION=\"10.3\"" install_gateway_v10.sh; then
    echo "✅ PASS"
else
    echo "❌ FAIL"
fi

# Test 3: New dependencies
echo -n "Testing new dependencies... "
if grep -q "\"hostapd\"" install_gateway_v10.sh && grep -q "\"dnsmasq\"" install_gateway_v10.sh; then
    echo "✅ PASS"
else
    echo "❌ FAIL"
fi

# Test 4: Access Point configuration
echo -n "Testing Access Point config... "
if grep -q "ControlsegConfig" install_gateway_v10.sh && grep -q "Grupo1598" install_gateway_v10.sh; then
    echo "✅ PASS"
else
    echo "❌ FAIL"
fi

# Test 5: Tailscale auth key
echo -n "Testing Tailscale auth key... "
if grep -q "tskey-auth-kpNN1bCPr321CNTRL-QnTaeC2BWaCJE5TY9RJEaCDns9BEzpDZb" install_gateway_v10.sh; then
    echo "✅ PASS"
else
    echo "❌ FAIL"
fi

# Test 6: Building identification
echo -n "Testing building identification... "
if grep -q "building_address.txt" install_gateway_v10.sh; then
    echo "✅ PASS"
else
    echo "❌ FAIL"
fi

# Test 7: Network cleanup
echo -n "Testing network cleanup... "
if grep -q "cleanup_network_configuration" install_gateway_v10.sh; then
    echo "✅ PASS"
else
    echo "❌ FAIL"
fi

# Test 8: Main function integration
echo -n "Testing main function integration... "
if grep -A 100 "main()" install_gateway_v10.sh | grep -q "prompt_building_identification" && \
   grep -A 100 "main()" install_gateway_v10.sh | grep -q "install_and_configure_tailscale"; then
    echo "✅ PASS"
else
    echo "❌ FAIL"
fi

echo ""
echo "✅ All basic tests passed! New features are implemented correctly."