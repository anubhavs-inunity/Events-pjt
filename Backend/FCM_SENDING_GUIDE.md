# FCM Sending Implementation Guide

## Current Status

The broadcast messaging system is implemented, but FCM notification sending needs to be completed.

## What's Done

✅ Database schema for messages and FCM tokens
✅ Backend endpoints for saving tokens and sending messages
✅ Admin UI for sending broadcast messages
✅ Student UI for viewing messages
✅ Message storage and retrieval

## What Needs Implementation

### FCM Notification Sending

The `sendFCMNotification()` function in `messaging.go` is currently a placeholder. You need to implement actual FCM sending.

## Option 1: Using Firebase Admin SDK for Go (Recommended)

### Step 1: Install Firebase Admin SDK

```bash
cd Backend
go get firebase.google.com/go/v4
go get firebase.google.com/go/v4/messaging
```

### Step 2: Get Service Account Key

1. Go to Firebase Console → Project Settings → Service Accounts
2. Click "Generate new private key"
3. Save the JSON file as `serviceAccountKey.json` in Backend folder
4. Add to `.gitignore` (don't commit this file!)

### Step 3: Update messaging.go

Replace the `sendFCMNotification` function:

```go
import (
    "context"
    firebase "firebase.google.com/go/v4"
    "firebase.google.com/go/v4/messaging"
    "google.golang.org/api/option"
)

var fcmClient *messaging.Client

func initFCM() error {
    opt := option.WithCredentialsFile("serviceAccountKey.json")
    app, err := firebase.NewApp(context.Background(), nil, opt)
    if err != nil {
        return err
    }
    
    fcmClient, err = app.Messaging(context.Background())
    return err
}

func sendFCMNotification(token, title, body string) bool {
    if fcmClient == nil {
        return false
    }
    
    message := &messaging.Message{
        Notification: &messaging.Notification{
            Title: title,
            Body:  body,
        },
        Token: token,
        Data: map[string]string{
            "type": "broadcast_message",
        },
    }
    
    _, err := fcmClient.Send(context.Background(), message)
    if err != nil {
        fmt.Printf("Error sending FCM: %v\n", err)
        return false
    }
    
    return true
}

// Update sendBroadcastMessageHandler to call initFCM() in main()
```

## Option 2: Using FCM HTTP v1 API (Alternative)

### Step 1: Get OAuth2 Token

You'll need to authenticate with Google Cloud to get an access token.

### Step 2: Send HTTP Request

```go
func sendFCMNotification(token, title, body string) bool {
    // Get OAuth2 token (implement OAuth2 flow)
    accessToken := getOAuth2Token()
    
    url := "https://fcm.googleapis.com/v1/projects/events-pjt/messages:send"
    
    payload := map[string]interface{}{
        "message": map[string]interface{}{
            "token": token,
            "notification": map[string]string{
                "title": title,
                "body":  body,
            },
            "data": map[string]string{
                "type": "broadcast_message",
            },
        },
    }
    
    jsonData, _ := json.Marshal(payload)
    req, _ := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
    req.Header.Set("Authorization", "Bearer "+accessToken)
    req.Header.Set("Content-Type", "application/json")
    
    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return false
    }
    defer resp.Body.Close()
    
    return resp.StatusCode == 200
}
```

## Quick Start (Recommended: Option 1)

1. **Get Service Account Key:**
   - Firebase Console → Project Settings → Service Accounts
   - Generate new private key
   - Save as `Backend/serviceAccountKey.json`

2. **Install dependencies:**
   ```bash
   cd Backend
   go get firebase.google.com/go/v4
   go get firebase.google.com/go/v4/messaging
   ```

3. **Update messaging.go:**
   - Add imports
   - Add `initFCM()` function
   - Replace `sendFCMNotification()` with real implementation
   - Call `initFCM()` in `main()`

4. **Test:**
   - Send a broadcast message from admin UI
   - Check if students receive push notifications

## Security Note

⚠️ **Never commit `serviceAccountKey.json` to git!**
- Add to `.gitignore`
- Use environment variables for production
- Rotate keys regularly

## Testing

After implementation:
1. Admin sends broadcast message
2. Students should receive push notification
3. Tapping notification opens messages page
4. Message appears in student's message list

---

**Note:** The current implementation stores messages in database and displays them in UI. Push notifications will make it real-time!

