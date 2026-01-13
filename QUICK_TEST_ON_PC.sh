#!/bin/bash

echo "🚀 Quick FCM Test on PC"
echo "======================"
echo ""

# Launch Android emulator
echo "📱 Launching Android emulator..."
flutter emulators --launch Medium_Phone_API_36

echo ""
echo "⏳ Waiting for emulator to boot (30 seconds)..."
sleep 30

echo ""
echo "📦 Running app on emulator..."
cd Frontend
flutter run -d Medium_Phone_API_36

echo ""
echo "✅ App should be running on emulator!"
echo "📱 Look for FCM token in console: '📱 FCM Token: ...'"
echo ""

