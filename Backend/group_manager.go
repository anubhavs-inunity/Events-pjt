package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// Groups cache for performance optimization
var groupsCache struct {
	data       map[string][]map[string]interface{} // admin_id -> groups list
	timestamps map[string]time.Time                 // admin_id -> timestamp
	mu         sync.RWMutex
}

const groupsCacheDuration = 5 * time.Minute // Extended cache for better performance

// GroupData holds all state for a specific group
type GroupData struct {
	ID                string
	Name              string
	AdminID           string
	AdminLat          float64
	AdminLon          float64
	ThresholdMeters   float64
	WindowActive      bool
	WindowStartTime   time.Time
	WindowEndTime     time.Time
	GroupOnly         bool // true = only group students, false = all students
	SubmittedStudents map[string]bool
	StudentLocations  map[string]StudentLocation
	CSVFile           *os.File
	CSVWriter         *csv.Writer
	mu                sync.RWMutex // Per-group mutex for fine-grained locking
}

// GroupManager manages all groups efficiently
type GroupManager struct {
	groups map[string]*GroupData // group_id -> GroupData
	mu     sync.RWMutex          // Protects groups map
}

var groupManager = &GroupManager{
	groups: make(map[string]*GroupData),
}

// GetOrCreateGroup gets existing group or creates new one (thread-safe)
func (gm *GroupManager) GetOrCreateGroup(groupID string) *GroupData {
	gm.mu.RLock()
	group, exists := gm.groups[groupID]
	gm.mu.RUnlock()

	if exists {
		return group
	}

	// Create new group
	gm.mu.Lock()
	defer gm.mu.Unlock()

	// Double-check after acquiring write lock
	if group, exists := gm.groups[groupID]; exists {
		return group
	}

	group = &GroupData{
		ID:                groupID,
		SubmittedStudents: make(map[string]bool),
		StudentLocations:  make(map[string]StudentLocation),
		WindowActive:      false,
	}
	gm.groups[groupID] = group
	return group
}

// GetGroup safely retrieves a group
func (gm *GroupManager) GetGroup(groupID string) (*GroupData, bool) {
	gm.mu.RLock()
	defer gm.mu.RUnlock()
	group, exists := gm.groups[groupID]
	return group, exists
}

// DeleteGroup removes a group (cleanup)
func (gm *GroupManager) DeleteGroup(groupID string) {
	gm.mu.Lock()
	defer gm.mu.Unlock()
	if group, exists := gm.groups[groupID]; exists {
		if group.CSVWriter != nil {
			group.CSVWriter.Flush()
		}
		if group.CSVFile != nil {
			group.CSVFile.Close()
		}
		delete(gm.groups, groupID)
	}
}

// Helper function to get group_id from request (query param or form value)
func getGroupID(r *http.Request) string {
	groupID := r.URL.Query().Get("group_id")
	if groupID == "" {
		groupID = r.FormValue("group_id")
	}
	return groupID
}

// Handler: POST /api/create-group
func createGroupHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Method not allowed",
		})
		return
	}

	if err := r.ParseForm(); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Failed to parse form",
		})
		return
	}

	groupName := r.FormValue("name")
	adminID := r.FormValue("admin_id")

	fmt.Printf("DEBUG: Creating group - name: %s, admin_id: %s\n", groupName, adminID)

	if groupName == "" || adminID == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Group name and admin_id are required",
		})
		return
	}

	// Create group in database
	url := fmt.Sprintf("%s/rest/v1/groups", config.SupabaseURL)
	groupData := map[string]interface{}{
		"name":     groupName,
		"admin_id": adminID,
		"status":   "inactive",
	}

	jsonData, _ := json.Marshal(groupData)
	req, err := http.NewRequest("POST", url, strings.NewReader(string(jsonData)))
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Failed to create request",
		})
		return
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Printf("DEBUG: Database request error: %v\n", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Database connection error",
		})
		return
	}
	defer resp.Body.Close()

	fmt.Printf("DEBUG: Supabase response status: %d\n", resp.StatusCode)

	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		fmt.Printf("DEBUG: Supabase error response: %s\n", string(bodyBytes))
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   "Failed to create group",
			"details": string(bodyBytes),
		})
		return
	}

	bodyBytes, _ := io.ReadAll(resp.Body)
	fmt.Printf("DEBUG: Supabase response body: %s\n", string(bodyBytes))
	
	var createdGroup []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(bodyBytes, &createdGroup); err != nil {
		fmt.Printf("DEBUG: JSON decode error: %v\n", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   "Failed to parse created group",
			"details": err.Error(),
		})
		return
	}
	
	if len(createdGroup) == 0 {
		fmt.Printf("DEBUG: No group returned from Supabase\n")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "No group data returned from database",
		})
		return
	}
	
	fmt.Printf("DEBUG: Created group - ID: %s, Name: %s\n", createdGroup[0].ID, createdGroup[0].Name)

	// Initialize in-memory group data with proper metadata
	group := groupManager.GetOrCreateGroup(createdGroup[0].ID)
	group.mu.Lock()
	group.Name = createdGroup[0].Name
	group.AdminID = adminID
	group.mu.Unlock()
	fmt.Printf("DEBUG: createGroupHandler - Initialized group in manager: ID=%s, Name=%s, AdminID=%s\n", createdGroup[0].ID, createdGroup[0].Name, adminID)

	// Invalidate groups cache for this admin to ensure fresh data on next fetch
	groupsCache.mu.Lock()
	if groupsCache.data != nil {
		delete(groupsCache.data, adminID)
	}
	if groupsCache.timestamps != nil {
		delete(groupsCache.timestamps, adminID)
	}
	groupsCache.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"group": map[string]string{
			"id":   createdGroup[0].ID,
			"name": createdGroup[0].Name,
		},
	}); err != nil {
		// If encoding fails, log it but response might already be sent
		fmt.Printf("Error encoding response: %v\n", err)
	}
}

// Handler: GET /api/get-my-groups?admin_id=xxx
func getMyGroupsHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	adminID := r.URL.Query().Get("admin_id")
	if adminID == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "admin_id is required",
		})
		return
	}

	// Check for cache bust parameter
	forceRefresh := r.URL.Query().Get("_t") != ""
	if forceRefresh {
		// Clear cache for this admin
		groupsCache.mu.Lock()
		if groupsCache.data != nil {
			delete(groupsCache.data, adminID)
		}
		if groupsCache.timestamps != nil {
			delete(groupsCache.timestamps, adminID)
		}
		groupsCache.mu.Unlock()
	}

	// Check cache first (only if not forcing refresh)
	if !forceRefresh {
		groupsCache.mu.RLock()
		if cachedGroups, exists := groupsCache.data[adminID]; exists {
			if timestamp, hasTimestamp := groupsCache.timestamps[adminID]; hasTimestamp {
				if time.Since(timestamp) < groupsCacheDuration {
					groupsCache.mu.RUnlock()
					// Return cached data
					w.Header().Set("Content-Type", "application/json")
					w.Header().Set("X-Cache", "HIT")
					json.NewEncoder(w).Encode(map[string]interface{}{
						"groups": cachedGroups,
						"count":  len(cachedGroups),
					})
					return
				}
			}
		}
		groupsCache.mu.RUnlock()
	}

	// Query groups from database
	url := fmt.Sprintf("%s/rest/v1/groups?admin_id=eq.%s&order=created_at.desc&select=id,name,status,created_at", config.SupabaseURL, adminID)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		http.Error(w, "Failed to create request", http.StatusInternalServerError)
		return
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, "Database connection error", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Failed to fetch groups",
		})
		return
	}

	var groups []map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&groups); err != nil {
		http.Error(w, "Failed to parse response", http.StatusInternalServerError)
		return
	}

	// Update cache
	groupsCache.mu.Lock()
	if groupsCache.data == nil {
		groupsCache.data = make(map[string][]map[string]interface{})
		groupsCache.timestamps = make(map[string]time.Time)
	}
	groupsCache.data[adminID] = groups
	groupsCache.timestamps[adminID] = time.Now()
	groupsCache.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Cache", "MISS")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"groups": groups,
		"count":  len(groups),
	})
}

// Handler: POST /api/add-students-to-group
func addStudentsToGroupHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Method not allowed",
		})
		return
	}

	if err := r.ParseForm(); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Failed to parse form",
		})
		return
	}

	groupID := r.FormValue("group_id")
	studentIDs := r.FormValue("student_ids") // Comma-separated list

	if groupID == "" || studentIDs == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "group_id and student_ids are required",
		})
		return
	}

	// Parse student IDs and convert to UUIDs
	ids := strings.Split(studentIDs, ",")
	var insertData []map[string]string
	var failedIDs []string
	
	fmt.Printf("DEBUG: addStudentsToGroup - Group ID: %s\n", groupID)
	fmt.Printf("DEBUG: Received student IDs string: %s\n", studentIDs)
	fmt.Printf("DEBUG: Parsed %d student IDs\n", len(ids))
	
	// Batch lookup: Get all student UUIDs in one query for better performance
	// Build OR query: student_id=in.(ST001,ST002,ST003,...)
	studentIDList := make([]string, 0, len(ids))
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id != "" {
			studentIDList = append(studentIDList, id)
		}
	}
	
	if len(studentIDList) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "No valid student IDs provided",
		})
		return
	}
	
	// Batch lookup all students at once
	studentUUIDMap := getStudentUUIDsByIDs(studentIDList)
	fmt.Printf("DEBUG: Found UUIDs for %d out of %d students\n", len(studentUUIDMap), len(studentIDList))
	
	for _, id := range studentIDList {
		studentUUID, found := studentUUIDMap[id]
		if !found || studentUUID == "" {
			fmt.Printf("ERROR: Failed to find UUID for student_id: %s\n", id)
			failedIDs = append(failedIDs, id)
			continue
		}
		
		insertData = append(insertData, map[string]string{
			"group_id":   groupID,
			"student_id": studentUUID,
		})
	}

	fmt.Printf("DEBUG: Successfully converted %d students, failed: %d\n", len(insertData), len(failedIDs))

	if len(failedIDs) > 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   "Some student IDs not found",
			"details": fmt.Sprintf("Failed to find UUIDs for: %s", strings.Join(failedIDs, ", ")),
		})
		return
	}

	if len(insertData) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "No valid student IDs provided",
		})
		return
	}

	// Insert into group_students table
	url := fmt.Sprintf("%s/rest/v1/group_students", config.SupabaseURL)
	jsonData, _ := json.Marshal(insertData)
	req, err := http.NewRequest("POST", url, strings.NewReader(string(jsonData)))
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Failed to create request",
		})
		return
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "resolution=merge-duplicates")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Database connection error",
		})
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", "application/json")
	if resp.StatusCode == http.StatusCreated || resp.StatusCode == http.StatusOK {
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": fmt.Sprintf("Added %d students to group", len(insertData)),
		})
	} else {
		bodyBytes, _ := io.ReadAll(resp.Body)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   "Failed to add students",
			"details": string(bodyBytes),
		})
	}
}

// Handler: DELETE /api/delete-group
func deleteGroupHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodDelete && r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Method not allowed",
		})
		return
	}

	// Support both DELETE and POST (for form data)
	var groupID string
	if r.Method == http.MethodDelete {
		groupID = r.URL.Query().Get("group_id")
	} else {
		if err := r.ParseForm(); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "Failed to parse form",
			})
			return
		}
		groupID = r.FormValue("group_id")
	}

	if groupID == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "group_id is required",
		})
		return
	}

	// Delete from database (CASCADE will handle related records)
	url := fmt.Sprintf("%s/rest/v1/groups?id=eq.%s", config.SupabaseURL, groupID)
	req, err := http.NewRequest("DELETE", url, nil)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Failed to create request",
		})
		return
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Database connection error",
		})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNoContent || resp.StatusCode == http.StatusOK {
		// Remove from in-memory cache
		groupManager.mu.Lock()
		delete(groupManager.groups, groupID)
		groupManager.mu.Unlock()

		// Invalidate groups cache (will be refreshed on next fetch)
		groupsCache.mu.Lock()
		// Clear all admin caches since we don't know which admin
		if groupsCache.data != nil {
			groupsCache.data = make(map[string][]map[string]interface{})
		}
		if groupsCache.timestamps != nil {
			groupsCache.timestamps = make(map[string]time.Time)
		}
		groupsCache.mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Group deleted successfully",
		})
	} else {
		bodyBytes, _ := io.ReadAll(resp.Body)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   "Failed to delete group",
			"details": string(bodyBytes),
		})
	}
}

// Handler: GET /api/get-group-students?group_id=xxx
func getGroupStudentsHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	groupID := r.URL.Query().Get("group_id")
	if groupID == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "group_id is required",
		})
		return
	}

	// Query students in this group
	url := fmt.Sprintf("%s/rest/v1/group_students?group_id=eq.%s&select=student_id,students(id,student_id,student_name)", config.SupabaseURL, groupID)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		http.Error(w, "Failed to create request", http.StatusInternalServerError)
		return
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, "Database connection error", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Failed to fetch group students",
		})
		return
	}

	var groupStudents []map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&groupStudents); err != nil {
		http.Error(w, "Failed to parse response", http.StatusInternalServerError)
		return
	}

	// Extract student data
	var students []map[string]interface{}
	for _, gs := range groupStudents {
		if student, ok := gs["students"].(map[string]interface{}); ok {
			students = append(students, student)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"students": students,
		"count":    len(students),
	})
}

// Helper function to get student UUID by student_id
// Batch lookup: Get UUIDs for multiple student IDs at once (much faster)
func getStudentUUIDsByIDs(studentIDs []string) map[string]string {
	result := make(map[string]string)
	if len(studentIDs) == 0 {
		return result
	}
	
	// Build OR query using Supabase's `in` operator
	// Format: student_id=in.(ST001,ST002,ST003)
	idsParam := strings.Join(studentIDs, ",")
	url := fmt.Sprintf("%s/rest/v1/students?student_id=in.(%s)&select=id,student_id", config.SupabaseURL, idsParam)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		fmt.Printf("ERROR: getStudentUUIDsByIDs - Failed to create request: %v\n", err)
		return result
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Printf("ERROR: getStudentUUIDsByIDs - Database connection error: %v\n", err)
		return result
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		fmt.Printf("ERROR: getStudentUUIDsByIDs - Supabase returned status %d, body: %s\n", resp.StatusCode, string(bodyBytes))
		return result
	}

	var students []struct {
		ID        string `json:"id"`
		StudentID string `json:"student_id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&students); err != nil {
		bodyBytes, _ := io.ReadAll(resp.Body)
		fmt.Printf("ERROR: getStudentUUIDsByIDs - Failed to parse response: %v, body: %s\n", err, string(bodyBytes))
		return result
	}

	for _, student := range students {
		result[student.StudentID] = student.ID
		fmt.Printf("DEBUG: Mapped student_id %s -> UUID %s\n", student.StudentID, student.ID)
	}
	
	fmt.Printf("DEBUG: getStudentUUIDsByIDs - Found %d out of %d students\n", len(result), len(studentIDs))
	return result
}

// Single lookup (kept for backward compatibility, but use batch version when possible)
func getStudentUUIDByID(studentID string) string {
	result := getStudentUUIDsByIDs([]string{studentID})
	return result[studentID]
}
