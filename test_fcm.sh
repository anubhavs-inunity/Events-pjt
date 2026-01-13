#!/bin/bash

# FCM Quick Test Script
# This script helps you quickly test FCM setup

echo "🧪 FCM Testing Helper"
echo "===================="
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed or not in PATH"
    exit 1
fi

echo "✅ Flutter found"
echo ""

# Navigate to Frontend directory
cd Frontend || exit 1

echo "📦 Checking dependencies..."
flutter pub get > /dev/null 2>&1
echo "✅ Dependencies checked"
echo ""

echo "🚀 Starting app in debug mode..."
echo ""
echo "📱 Watch for these logs:"
echo "   ✅ Firebase initialized"
echo "   ✅ FCM initialized"
echo "   📱 FCM Token: <your-token>"
echo ""
echo "💡 Tips:"
echo "   1. Copy the FCM token from logs"
echo "   2. Go to Firebase Console → Cloud Messaging"
echo "   3. Send test message with your token"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Run the app
flutter run

