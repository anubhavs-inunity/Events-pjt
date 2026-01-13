package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
)

// FCM token storage (in-memory cache + database)
var fcmTokensCache struct {
	tokens map[string]string // user_id_user_type -> fcm_token
	mu     sync.RWMutex
}

func init() {
	fcmTokensCache.tokens = make(map[string]string)
}

// Handler: POST /api/save-fcm-token
func saveFCMTokenHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var data struct {
		FCMToken   string `json:"fcm_token"`
		UserID     string `json:"user_id"`
		UserType   string `json:"user_type"` // "admin" or "student"
		DeviceType string `json:"device_type"`
	}

	if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Validate user_type
	if data.UserType != "admin" && data.UserType != "student" {
		http.Error(w, "Invalid user_type. Must be 'admin' or 'student'", http.StatusBadRequest)
		return
	}

	// Store in cache
	key := fmt.Sprintf("%s_%s", data.UserType, data.UserID)
	fcmTokensCache.mu.Lock()
	fcmTokensCache.tokens[key] = data.FCMToken
	fcmTokensCache.mu.Unlock()

	// Save to database
	if config.SupabaseURL != "" {
		// Check if token exists
		checkURL := fmt.Sprintf("%s/rest/v1/fcm_tokens?user_id=eq.%s&user_type=eq.%s&fcm_token=eq.%s&select=id",
			config.SupabaseURL, data.UserID, data.UserType, data.FCMToken)
		
		req, _ := http.NewRequest("GET", checkURL, nil)
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
		
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			defer resp.Body.Close()
			body, _ := io.ReadAll(resp.Body)
			
			// If token doesn't exist, insert it
			if resp.StatusCode == http.StatusOK && len(body) <= 2 { // Empty array
				tokenData := map[string]interface{}{
					"user_id":     data.UserID,
					"user_type":   data.UserType,
					"fcm_token":   data.FCMToken,
					"device_type": data.DeviceType,
				}
				
				jsonData, _ := json.Marshal(tokenData)
				insertURL := fmt.Sprintf("%s/rest/v1/fcm_tokens", config.SupabaseURL)
				insertReq, _ := http.NewRequest("POST", insertURL, bytes.NewBuffer(jsonData))
				insertReq.Header.Set("apikey", config.SupabaseAnonKey)
				insertReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
				insertReq.Header.Set("Content-Type", "application/json")
				insertReq.Header.Set("Prefer", "resolution=merge-duplicates")
				
				http.DefaultClient.Do(insertReq) // Fire and forget
			} else {
				// Update existing token
				updateURL := fmt.Sprintf("%s/rest/v1/fcm_tokens?user_id=eq.%s&user_type=eq.%s",
					config.SupabaseURL, data.UserID, data.UserType)
				updateData := map[string]interface{}{
					"fcm_token":  data.FCMToken,
					"updated_at": "now()",
				}
				updateJson, _ := json.Marshal(updateData)
				updateReq, _ := http.NewRequest("PATCH", updateURL, bytes.NewBuffer(updateJson))
				updateReq.Header.Set("apikey", config.SupabaseAnonKey)
				updateReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
				updateReq.Header.Set("Content-Type", "application/json")
				
				http.DefaultClient.Do(updateReq) // Fire and forget
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

// Handler: POST /api/send-broadcast-message
func sendBroadcastMessageHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("🔔 sendBroadcastMessageHandler called - Method: %s\n", r.Method)
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var data struct {
		AdminID   string `json:"admin_id"`
		GroupID   string `json:"group_id"` // Optional: if empty, send to all students
		Title     string `json:"title"`
		Message   string `json:"message"`
		SendToAll bool   `json:"send_to_all"` // true = all students, false = group only
	}

	if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
		fmt.Printf("ERROR: Failed to decode request body: %v\n", err)
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	fmt.Printf("DEBUG: Received broadcast message request - AdminID: %s, Title: %s, SendToAll: %v, GroupID: %s\n", 
		data.AdminID, data.Title, data.SendToAll, data.GroupID)

	// Validate required fields
	if data.AdminID == "" || data.Title == "" || data.Message == "" {
		fmt.Printf("❌ ERROR: Missing required fields - AdminID: %s, Title: %s, Message length: %d\n", 
			data.AdminID, data.Title, len(data.Message))
		http.Error(w, "Missing required fields: admin_id, title, message", http.StatusBadRequest)
		return
	}
	
	// Validate admin_id exists in database
	adminURL := fmt.Sprintf("%s/rest/v1/admins?id=eq.%s&select=id", config.SupabaseURL, data.AdminID)
	adminReq, _ := http.NewRequest("GET", adminURL, nil)
	adminReq.Header.Set("apikey", config.SupabaseAnonKey)
	adminReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	adminResp, err := http.DefaultClient.Do(adminReq)
	if err == nil {
		defer adminResp.Body.Close()
		var admins []struct {
			ID string `json:"id"`
		}
		if json.NewDecoder(adminResp.Body).Decode(&admins) == nil {
			if len(admins) == 0 {
				fmt.Printf("❌ ERROR: Admin ID %s does not exist in database\n", data.AdminID)
				http.Error(w, "Invalid admin_id", http.StatusBadRequest)
				return
			}
			fmt.Printf("✅ DEBUG: Admin ID %s validated\n", data.AdminID)
		}
	}

	// Get student IDs to send to
	var studentIDs []string
	var studentUUIDs []string

	if data.SendToAll || data.GroupID == "" {
		// Get all students
		url := fmt.Sprintf("%s/rest/v1/students?select=id,student_id", config.SupabaseURL)
		req, _ := http.NewRequest("GET", url, nil)
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			defer resp.Body.Close()
			var students []struct {
				ID        string `json:"id"`
				StudentID string `json:"student_id"`
			}
			if json.NewDecoder(resp.Body).Decode(&students) == nil {
				for _, s := range students {
					studentIDs = append(studentIDs, s.StudentID)
					studentUUIDs = append(studentUUIDs, s.ID)
				}
			}
		}
	} else {
		// Get students in group
		url := fmt.Sprintf("%s/rest/v1/group_students?group_id=eq.%s&select=student_id,students(id,student_id)",
			config.SupabaseURL, data.GroupID)
		req, _ := http.NewRequest("GET", url, nil)
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			defer resp.Body.Close()
			var groupStudents []struct {
				StudentID string `json:"student_id"`
				Students  struct {
					ID        string `json:"id"`
					StudentID string `json:"student_id"`
				} `json:"students"`
			}
			if json.NewDecoder(resp.Body).Decode(&groupStudents) == nil {
				for _, gs := range groupStudents {
					studentIDs = append(studentIDs, gs.Students.StudentID)
					studentUUIDs = append(studentUUIDs, gs.Students.ID)
				}
			}
		}
	}

	if len(studentUUIDs) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "No students found"})
		return
	}

	// Save message to database
	messageData := map[string]interface{}{
		"admin_id":    data.AdminID,
		"title":       data.Title,
		"message":     data.Message,
		"sent_to_all": data.SendToAll,
	}
	if data.GroupID != "" {
		messageData["group_id"] = data.GroupID
	}

	jsonData, _ := json.Marshal(messageData)
	fmt.Printf("DEBUG: Message data to insert: %s\n", string(jsonData))
	msgURL := fmt.Sprintf("%s/rest/v1/broadcast_messages", config.SupabaseURL)
	fmt.Printf("DEBUG: POST URL: %s\n", msgURL)
	msgReq, _ := http.NewRequest("POST", msgURL, bytes.NewBuffer(jsonData))
	msgReq.Header.Set("apikey", config.SupabaseAnonKey)
	msgReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	msgReq.Header.Set("Content-Type", "application/json")
	msgReq.Header.Set("Prefer", "return=representation")

	fmt.Printf("DEBUG: Sending message creation request...\n")
	msgResp, err := http.DefaultClient.Do(msgReq)
	var messageID string
	if err != nil {
		fmt.Printf("ERROR: Failed to create broadcast message: %v\n", err)
	} else {
		defer msgResp.Body.Close()
		bodyBytes, _ := io.ReadAll(msgResp.Body)
		if msgResp.StatusCode != http.StatusCreated && msgResp.StatusCode != http.StatusOK {
			fmt.Printf("ERROR: Failed to create message, status: %d, body: %s\n", msgResp.StatusCode, string(bodyBytes))
		} else {
			// Supabase returns array with return=representation
			var createdMsgs []struct {
				ID string `json:"id"`
			}
			if err := json.Unmarshal(bodyBytes, &createdMsgs); err != nil {
				// Try single object format as fallback
				var createdMsg struct {
					ID string `json:"id"`
				}
				if err2 := json.Unmarshal(bodyBytes, &createdMsg); err2 == nil {
					messageID = createdMsg.ID
				} else {
					fmt.Printf("❌ ERROR: Failed to decode message response (both array and object): %v, body: %s\n", err, string(bodyBytes))
				}
			} else {
				if len(createdMsgs) > 0 {
					messageID = createdMsgs[0].ID
				}
			}
			
			if messageID != "" {
				fmt.Printf("✅ DEBUG: Created broadcast message with ID: %s\n", messageID)
			} else {
				fmt.Printf("❌ ERROR: Message ID is empty after parsing, response body: %s\n", string(bodyBytes))
			}
		}
	}

	// Create message recipients
	recipientsCreated := 0
	if messageID == "" {
		fmt.Printf("❌ ERROR: Message ID is empty, cannot create recipients. Check message creation above.\n")
	} else {
		fmt.Printf("✅ DEBUG: Creating recipients for message %s, %d students\n", messageID, len(studentUUIDs))
		
		// Batch insert recipients (more efficient)
		if len(studentUUIDs) > 0 {
			recipientsData := make([]map[string]interface{}, 0, len(studentUUIDs))
			for _, studentUUID := range studentUUIDs {
				recipientsData = append(recipientsData, map[string]interface{}{
					"message_id": messageID,
					"student_id": studentUUID,
				})
			}
			
			recipientJson, _ := json.Marshal(recipientsData)
			recipientURL := fmt.Sprintf("%s/rest/v1/message_recipients", config.SupabaseURL)
			recipientReq, _ := http.NewRequest("POST", recipientURL, bytes.NewBuffer(recipientJson))
			recipientReq.Header.Set("apikey", config.SupabaseAnonKey)
			recipientReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
			recipientReq.Header.Set("Content-Type", "application/json")
			recipientReq.Header.Set("Prefer", "resolution=merge-duplicates")
			
			fmt.Printf("DEBUG: Sending batch recipient creation request for %d recipients\n", len(recipientsData))
			resp, err := http.DefaultClient.Do(recipientReq)
			if err != nil {
				fmt.Printf("❌ ERROR: Failed to create recipients (network error): %v\n", err)
			} else {
				defer resp.Body.Close()
				bodyBytes, _ := io.ReadAll(resp.Body)
				if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
					fmt.Printf("❌ ERROR: Failed to create recipients, status: %d, body: %s\n", resp.StatusCode, string(bodyBytes))
				} else {
					recipientsCreated = len(studentUUIDs)
					fmt.Printf("✅ DEBUG: Successfully created %d recipients for message %s\n", recipientsCreated, messageID)
					fmt.Printf("DEBUG: Response body: %s\n", string(bodyBytes))
				}
			}
		}
	}

	// FCM notifications removed - messages will be retrieved via polling

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":            true,
		"message":            "Broadcast message sent",
		"total_students":     len(studentUUIDs),
		"recipients_created": recipientsCreated,
		"message_id":         messageID,
	})
}

// FCM functions removed - using polling instead

// Handler: GET /api/get-messages (for students)
func getMessagesHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("📬 getMessagesHandler called - Method: %s, URL: %s\n", r.Method, r.URL.String())
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	studentID := r.URL.Query().Get("student_id")
	fmt.Printf("DEBUG: getMessagesHandler - student_id from query: %s\n", studentID)
	if studentID == "" {
		fmt.Printf("ERROR: getMessagesHandler - student_id is empty\n")
		http.Error(w, "student_id is required", http.StatusBadRequest)
		return
	}

	// Get student UUID
	studentUUID := getStudentUUIDByID(studentID)
	fmt.Printf("DEBUG: getMessagesHandler - studentID: %s, studentUUID: %s\n", studentID, studentUUID)
	if studentUUID == "" {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "Student not found"})
		return
	}

	// Get messages for this student
	// First get message recipients
	url := fmt.Sprintf("%s/rest/v1/message_recipients?student_id=eq.%s&select=message_id,is_read",
		config.SupabaseURL, studentUUID)
	
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Database error"})
		return
	}
	defer resp.Body.Close()

	var recipients []map[string]interface{}
	if resp.StatusCode != http.StatusOK {
		// No messages or error
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"messages": []interface{}{},
			"count":    0,
		})
		return
	}

	if err := json.NewDecoder(resp.Body).Decode(&recipients); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Failed to parse response"})
		return
	}

	fmt.Printf("DEBUG: Found %d recipients for student %s\n", len(recipients), studentUUID)
	if len(recipients) == 0 {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"messages": []interface{}{},
			"count":    0,
		})
		return
	}

	// Get message IDs
	messageIDs := make([]string, 0)
	readStatus := make(map[string]bool)
	for _, recipient := range recipients {
		if msgID, ok := recipient["message_id"].(string); ok {
			messageIDs = append(messageIDs, msgID)
			if isRead, ok := recipient["is_read"].(bool); ok {
				readStatus[msgID] = isRead
			}
		}
	}

	fmt.Printf("DEBUG: Found %d message IDs: %v\n", len(messageIDs), messageIDs)

	if len(messageIDs) == 0 {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"messages": []interface{}{},
			"count":    0,
		})
		return
	}

	// Get actual messages
	// Format: id=in.(uuid1,uuid2,uuid3)
	msgIDsParam := strings.Join(messageIDs, ",")
	msgURL := fmt.Sprintf("%s/rest/v1/broadcast_messages?id=in.(%s)&select=id,title,message,created_at,admin_id,admins(username)&order=created_at.desc",
		config.SupabaseURL, msgIDsParam)
	
	fmt.Printf("DEBUG: Querying messages with URL: %s\n", msgURL)
	
	msgReq, _ := http.NewRequest("GET", msgURL, nil)
	msgReq.Header.Set("apikey", config.SupabaseAnonKey)
	msgReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	msgResp, err := http.DefaultClient.Do(msgReq)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Database error"})
		return
	}
	defer msgResp.Body.Close()

	var broadcastMessages []map[string]interface{}
	if msgResp.StatusCode == http.StatusOK {
		if err := json.NewDecoder(msgResp.Body).Decode(&broadcastMessages); err != nil {
			fmt.Printf("ERROR: Failed to decode broadcast messages: %v\n", err)
			broadcastMessages = []map[string]interface{}{}
		}
		fmt.Printf("DEBUG: Retrieved %d broadcast messages\n", len(broadcastMessages))
	} else {
		bodyBytes, _ := io.ReadAll(msgResp.Body)
		fmt.Printf("ERROR: Failed to get broadcast messages, status: %d, body: %s\n", msgResp.StatusCode, string(bodyBytes))
		broadcastMessages = []map[string]interface{}{}
	}

	// Format response
	messages := make([]map[string]interface{}, 0)
	for _, msg := range broadcastMessages {
		msgID, _ := msg["id"].(string)
		messages = append(messages, map[string]interface{}{
			"id":         msgID,
			"title":      msg["title"],
			"message":    msg["message"],
			"is_read":    readStatus[msgID] || false,
			"created_at": msg["created_at"],
			"admin_name": func() string {
				if admin, ok := msg["admins"].(map[string]interface{}); ok {
					if username, ok := admin["username"].(string); ok {
						return username
					}
				}
				return "Admin"
			}(),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"messages": messages,
		"count":    len(messages),
	})
}

// Handler: POST /api/mark-message-read
func markMessageReadHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var data struct {
		StudentID string `json:"student_id"`
		MessageID string `json:"message_id"`
	}

	if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	studentUUID := getStudentUUIDByID(data.StudentID)
	if studentUUID == "" {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "Student not found"})
		return
	}

	// Update message as read
	updateURL := fmt.Sprintf("%s/rest/v1/message_recipients?message_id=eq.%s&student_id=eq.%s",
		config.SupabaseURL, data.MessageID, studentUUID)
	updateData := map[string]interface{}{
		"is_read": true,
		"read_at": "now()",
	}
	updateJson, _ := json.Marshal(updateData)
	updateReq, _ := http.NewRequest("PATCH", updateURL, bytes.NewBuffer(updateJson))
	updateReq.Header.Set("apikey", config.SupabaseAnonKey)
	updateReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	updateReq.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(updateReq)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Failed to update"})
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

// Handler: POST /api/delete-message (for students to delete their message)
func deleteMessageHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost && r.Method != http.MethodDelete {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var data struct {
		StudentID string `json:"student_id"`
		MessageID string `json:"message_id"`
	}

	if r.Method == http.MethodPost {
		if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}
	} else {
		// DELETE method - get from query params
		data.StudentID = r.URL.Query().Get("student_id")
		data.MessageID = r.URL.Query().Get("message_id")
	}

	if data.StudentID == "" || data.MessageID == "" {
		http.Error(w, "student_id and message_id are required", http.StatusBadRequest)
		return
	}

	studentUUID := getStudentUUIDByID(data.StudentID)
	if studentUUID == "" {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "Student not found"})
		return
	}

	// Delete message recipient record (this removes the message for this student)
	deleteURL := fmt.Sprintf("%s/rest/v1/message_recipients?message_id=eq.%s&student_id=eq.%s",
		config.SupabaseURL, data.MessageID, studentUUID)

	deleteReq, _ := http.NewRequest("DELETE", deleteURL, nil)
	deleteReq.Header.Set("apikey", config.SupabaseAnonKey)
	deleteReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	resp, err := http.DefaultClient.Do(deleteReq)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Failed to delete message"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNoContent || resp.StatusCode == http.StatusOK {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "success", "message": "Message deleted successfully"})
	} else {
		bodyBytes, _ := io.ReadAll(resp.Body)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error":   "Failed to delete message",
			"details": string(bodyBytes),
		})
	}
}
