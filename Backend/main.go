package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

type StudentLocation struct {
	StudentID   string  `json:"StudentID"`
	StudentName string  `json:"StudentName"`
	Latitude    float64 `json:"Latitude"`
	Longitude   float64 `json:"Longitude"`
	Distance    float64 `json:"Distance"`
	Timestamp   string  `json:"Timestamp"`
	Status      string  `json:"Status"`
}

var (
	adminLat          float64
	adminLon          float64
	sessionName       string
	thresholdMeters   float64
	attendanceActive  bool
	csvFile           *os.File
	csvWriter         *csv.Writer
	mu                sync.Mutex
	submittedStudents map[string]bool
	studentLocations  map[string]StudentLocation // Store student locations
	config            Config
	windowStartTime   time.Time // Track when window was started
)

// Student list cache for performance optimization
var studentCache struct {
	data      []map[string]interface{}
	totalCount int
	timestamp time.Time
	mu        sync.RWMutex
}

const cacheDuration = 10 * time.Second

func parseFloat(s string) (float64, error) {
	var result float64

	_, err := fmt.Sscanf(s, "%f", &result)
	return result, err
}

// enableCORS sets CORS headers for cross-origin requests
func enableCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	// Note: Content-Type for JSON should be set in each handler after enableCORS
}

// haversine calculates distance between two GPS coordinates in meters
func haversine(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371000 // Earth radius in meters

	// Convert degrees to radians
	φ1 := lat1 * math.Pi / 180
	φ2 := lat2 * math.Pi / 180
	Δφ := (lat2 - lat1) * math.Pi / 180
	Δλ := (lon2 - lon1) * math.Pi / 180

	a := math.Sin(Δφ/2)*math.Sin(Δφ/2) + math.Cos(φ1)*math.Cos(φ2)*math.Sin(Δλ/2)*math.Sin(Δλ/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	distance := R * c
	return distance
}

func setCenterHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := r.ParseForm(); err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}

	// Get group_id (required for multi-group support)
	groupID := getGroupID(r)
	if groupID == "" {
		// Fallback to legacy behavior if no group_id
		groupID = "default"
	}

	group := groupManager.GetOrCreateGroup(groupID)
	group.mu.Lock()
	defer group.mu.Unlock()

	// Parse form data
	latStr := r.FormValue("lat")
	lonStr := r.FormValue("lon")
	sessionName := r.FormValue("session_name")
	thresholdStr := r.FormValue("threshold")

	var err error
	group.AdminLat, err = parseFloat(latStr)
	if err != nil {
		http.Error(w, "Invalid latitude", http.StatusBadRequest)
		return
	}
	group.AdminLon, err = parseFloat(lonStr)
	if err != nil {
		http.Error(w, "Invalid longitude", http.StatusBadRequest)
		return
	}
	group.ThresholdMeters, err = parseFloat(thresholdStr)
	if err != nil {
		http.Error(w, "Invalid threshold", http.StatusBadRequest)
		return
	}
	if sessionName != "" {
		group.Name = sessionName
	}

	// Update group in database
	if groupID != "default" {
		updateURL := fmt.Sprintf("%s/rest/v1/groups?id=eq.%s", config.SupabaseURL, groupID)
		updateData := map[string]interface{}{
			"location_lat":     group.AdminLat,
			"location_lon":     group.AdminLon,
			"threshold_meters": group.ThresholdMeters,
		}
		jsonData, _ := json.Marshal(updateData)
		req, _ := http.NewRequest("PATCH", updateURL, strings.NewReader(string(jsonData)))
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
		req.Header.Set("Content-Type", "application/json")
		http.DefaultClient.Do(req) // Fire and forget
	}

	// Create CSV file
	timestamp := time.Now().Format("20060102_150405")
	filename := fmt.Sprintf("%s_%s.csv", group.Name, timestamp)

	var fileErr error
	group.CSVFile, fileErr = os.Create(filename)
	if fileErr != nil {
		http.Error(w, "Failed to create CSV file", http.StatusInternalServerError)
		return
	}

	group.CSVWriter = csv.NewWriter(group.CSVFile)

	// Write CSV headers
	headers := []string{
		"StudentName",
		"Time",
		"Distance(m)",
	}
	group.CSVWriter.Write(headers)
	group.CSVWriter.Flush()

	// Return success response
	response := map[string]interface{}{
		"success": true,
		"message": "Center set",
	}
	json.NewEncoder(w).Encode(response)
}

// Handler: POST /api/start-window
func startWindowHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Get group_id (required for multi-group support)
	groupID := getGroupID(r)
	if groupID == "" {
		// Fallback to legacy behavior if no group_id
		groupID = "default"
	}

	group := groupManager.GetOrCreateGroup(groupID)
	group.mu.Lock()
	defer group.mu.Unlock()

	// Parse scope mode (group_only parameter)
	groupOnlyStr := r.FormValue("group_only")
	group.GroupOnly = groupOnlyStr == "true" // Default to false if not specified
	
	// Load group metadata from database if not already set (for newly created groups)
	if group.Name == "" && groupID != "default" {
		// Fetch group name and admin_id from database
		groupURL := fmt.Sprintf("%s/rest/v1/groups?id=eq.%s&select=id,name,admin_id", config.SupabaseURL, groupID)
		req, _ := http.NewRequest("GET", groupURL, nil)
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
		
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			defer resp.Body.Close()
			var groups []struct {
				ID      string `json:"id"`
				Name    string `json:"name"`
				AdminID string `json:"admin_id"`
			}
			if json.NewDecoder(resp.Body).Decode(&groups) == nil && len(groups) > 0 {
				group.Name = groups[0].Name
				group.AdminID = groups[0].AdminID
				fmt.Printf("DEBUG: startWindowHandler - Loaded group metadata: Name=%s, AdminID=%s\n", group.Name, group.AdminID)
			}
		}
	}

	// Start the window
	group.WindowActive = true
	group.WindowStartTime = time.Now()
	group.WindowEndTime = time.Now().Add(10 * time.Minute)
	group.SubmittedStudents = make(map[string]bool)           // Reset submissions
	group.StudentLocations = make(map[string]StudentLocation) // Reset student locations
	
	// Create CSV file if it doesn't exist
	if group.CSVFile == nil {
		timestamp := time.Now().Format("20060102_150405")
		groupName := group.Name
		if groupName == "" {
			groupName = "Group"
		}
		filename := fmt.Sprintf("%s_%s.csv", groupName, timestamp)
		
		var fileErr error
		group.CSVFile, fileErr = os.Create(filename)
		if fileErr != nil {
			fmt.Printf("WARNING: Failed to create CSV file: %v\n", fileErr)
		} else {
			group.CSVWriter = csv.NewWriter(group.CSVFile)
			// Write CSV headers
			headers := []string{
				"StudentName",
				"Time",
				"Distance(m)",
			}
			group.CSVWriter.Write(headers)
			group.CSVWriter.Flush()
			fmt.Printf("DEBUG: startWindowHandler - Created CSV file: %s\n", filename)
		}
	}
	
	fmt.Printf("DEBUG: startWindowHandler - Started window for group %s (Name=%s, GroupOnly=%v, WindowActive=%v)\n", groupID, group.Name, group.GroupOnly, group.WindowActive)
	
	// Persist window status to database
	if groupID != "default" {
		updateURL := fmt.Sprintf("%s/rest/v1/groups?id=eq.%s", config.SupabaseURL, groupID)
		updateData := map[string]interface{}{
			"status":            "active",
			"window_start_time": group.WindowStartTime.Format("2006-01-02 15:04:05"),
			"window_end_time":   group.WindowEndTime.Format("2006-01-02 15:04:05"),
		}
		jsonData, _ := json.Marshal(updateData)
		req, _ := http.NewRequest("PATCH", updateURL, strings.NewReader(string(jsonData)))
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
		req.Header.Set("Content-Type", "application/json")
		http.DefaultClient.Do(req) // Fire and forget
	}

	// Start goroutine to auto-close after 10 minutes
	go func(gID string) {
		time.Sleep(10 * time.Minute)
		if g, exists := groupManager.GetGroup(gID); exists {
			g.mu.Lock()
			g.WindowActive = false
			if g.CSVWriter != nil {
				g.CSVWriter.Flush()
			}
			g.mu.Unlock()
		}
	}(groupID)

	response := map[string]interface{}{
		"success": true,
		"message": "Window opened",
		"group_id": groupID,
	}
	json.NewEncoder(w).Encode(response)
}

// Handler: POST /api/close-window
func closeWindowHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := r.ParseForm(); err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}

	groupID := getGroupID(r)
	if groupID == "" {
		groupID = "default"
	}

	group, exists := groupManager.GetGroup(groupID)
	if !exists {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Group not found",
		})
		return
	}

	group.mu.Lock()
	defer group.mu.Unlock()

	group.WindowActive = false
	
	fmt.Printf("DEBUG: closeWindowHandler - Closed window for group %s\n", groupID)

	if group.CSVWriter != nil {
		group.CSVWriter.Flush()
	}

	if group.CSVFile != nil {
		group.CSVFile.Close()
	}

	// Update database
	if groupID != "default" {
		updateURL := fmt.Sprintf("%s/rest/v1/groups?id=eq.%s", config.SupabaseURL, groupID)
		updateData := map[string]interface{}{
			"status": "closed",
		}
		jsonData, _ := json.Marshal(updateData)
		req, _ := http.NewRequest("PATCH", updateURL, strings.NewReader(string(jsonData)))
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
		req.Header.Set("Content-Type", "application/json")
		http.DefaultClient.Do(req)
	}

	w.Header().Set("Content-Type", "application/json")
	response := map[string]interface{}{
		"success":  true,
		"message":  "Window closed",
		"group_id": groupID,
	}
	json.NewEncoder(w).Encode(response)
}

// Handler: POST /api/submit-attendance
func submitAttendanceHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := r.ParseForm(); err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}

	groupID := getGroupID(r)
	if groupID == "" {
		groupID = "default"
	}

	group, exists := groupManager.GetGroup(groupID)
	if !exists {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Group not found",
		})
		return
	}

	group.mu.RLock()
	windowActive := group.WindowActive
	groupOnly := group.GroupOnly
	group.mu.RUnlock()

	if !windowActive {
		w.WriteHeader(http.StatusForbidden)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Attendance window is closed",
		})
		return
	}

	// Check if student is in group (if group_only mode)
	if groupOnly && groupID != "default" {
		studentID := r.FormValue("student_id")
		studentUUID := getStudentUUIDByID(studentID)
		
		if studentUUID == "" {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "Invalid student ID",
			})
			return
		}
		
		// Check if student is in this group
		checkURL := fmt.Sprintf("%s/rest/v1/group_students?group_id=eq.%s&student_id=eq.%s&select=id&limit=1", 
			config.SupabaseURL, groupID, studentUUID)
		req, _ := http.NewRequest("GET", checkURL, nil)
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
		
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			defer resp.Body.Close()
			var results []map[string]interface{}
			json.NewDecoder(resp.Body).Decode(&results)
			
			if len(results) == 0 {
				w.WriteHeader(http.StatusForbidden)
				json.NewEncoder(w).Encode(map[string]string{
					"error": "You are not a member of this group. Attendance is restricted to group members only.",
				})
				return
			}
		}
	}

	group.mu.Lock()
	defer group.mu.Unlock()

	// Parse form data
	studentName := r.FormValue("student_name")
	studentID := r.FormValue("student_id")
	latStr := r.FormValue("lat")
	lonStr := r.FormValue("lon")

	// Parse coordinates
	studentLat, err := parseFloat(latStr)
	if err != nil {
		http.Error(w, "Invalid latitude", http.StatusBadRequest)
		return
	}

	studentLon, err := parseFloat(lonStr)
	if err != nil {
		http.Error(w, "Invalid longitude", http.StatusBadRequest)
		return
	}

	// Check if already submitted
	if group.SubmittedStudents[studentID] {
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Already submitted",
		})
		return
	}

	// Calculate distance
	distance := haversine(group.AdminLat, group.AdminLon, studentLat, studentLon)

	// Determine status
	status := "Absent"
	if distance <= group.ThresholdMeters {
		status = "Present"
	}

	// Get current timestamp
	timestamp := time.Now().Format("2006-01-02 15:04:05")

	// Write to CSV (only student name, time, and distance)
	if group.CSVWriter != nil {
		row := []string{
			studentName,
			timestamp,
			fmt.Sprintf("%.0f", distance),
		}
		group.CSVWriter.Write(row)
		group.CSVWriter.Flush()
	}

	// Store student location
	group.StudentLocations[studentID] = StudentLocation{
		StudentID:   studentID,
		StudentName: studentName,
		Latitude:    studentLat,
		Longitude:   studentLon,
		Distance:    distance,
		Timestamp:   timestamp,
		Status:      status,
	}

	// Debug: Print stored location
	fmt.Printf("DEBUG: Stored student location - %s (%s): %.6f, %.6f, %.0fm, %s\n",
		studentName, studentID, studentLat, studentLon, distance, status)
	fmt.Printf("DEBUG: Total student locations: %d\n", len(group.StudentLocations))

	// Mark as submitted
	group.SubmittedStudents[studentID] = true

	// Store in database for persistence
	if groupID != "default" {
		studentUUID := getStudentUUIDByID(studentID)
		if studentUUID != "" {
			attendanceURL := fmt.Sprintf("%s/rest/v1/group_attendance", config.SupabaseURL)
			attendanceData := map[string]interface{}{
				"group_id":   groupID,
				"student_id": studentUUID,
				"status":     status,
				"distance":   distance,
				"latitude":   studentLat,
				"longitude":  studentLon,
			}
			jsonData, _ := json.Marshal(attendanceData)
			req, _ := http.NewRequest("POST", attendanceURL, strings.NewReader(string(jsonData)))
			req.Header.Set("apikey", config.SupabaseAnonKey)
			req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Prefer", "resolution=merge-duplicates")
			http.DefaultClient.Do(req) // Fire and forget
		}
	}

	// Return success response
	w.Header().Set("Content-Type", "application/json")
	response := map[string]string{
		"status":    status,
		"distance":  fmt.Sprintf("%.0f", distance),
		"timestamp": timestamp,
	}
	json.NewEncoder(w).Encode(response)
}

// Handler: GET /api/download-csv
func downloadCSVHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Get group_id (for multi-group support)
	groupID := getGroupID(r)
	if groupID == "" {
		groupID = "default"
	}

	group, exists := groupManager.GetGroup(groupID)
	if !exists {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Group not found",
		})
		return
	}

	group.mu.RLock()
	csvFile := group.CSVFile
	csvWriter := group.CSVWriter
	group.mu.RUnlock()

	// Check if CSV file exists
	if csvFile == nil {
		// Try to generate CSV from database if file doesn't exist
		if groupID != "default" {
			// Generate CSV from database attendance records
			attendanceURL := fmt.Sprintf("%s/rest/v1/group_attendance?group_id=eq.%s&select=*,students(student_id,student_name)&order=submitted_at.asc", config.SupabaseURL, groupID)
			req, _ := http.NewRequest("GET", attendanceURL, nil)
			req.Header.Set("apikey", config.SupabaseAnonKey)
			req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
			
			resp, err := http.DefaultClient.Do(req)
			if err == nil {
				defer resp.Body.Close()
				var records []map[string]interface{}
				if json.NewDecoder(resp.Body).Decode(&records) == nil && len(records) > 0 {
					// Generate CSV content
					var csvBuilder strings.Builder
					csvBuilder.WriteString("StudentName,Time,Distance(m)\n")
					for _, record := range records {
						student := record["students"].(map[string]interface{})
						studentName := student["student_name"].(string)
						timestamp := record["submitted_at"].(string)
						distance := record["distance"]
						csvBuilder.WriteString(fmt.Sprintf("%s,%s,%.0f\n", studentName, timestamp, distance))
					}
					
					w.Header().Set("Content-Type", "text/csv")
					w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=attendance_%s_%s.csv", groupID, time.Now().Format("20060102_150405")))
					w.Write([]byte(csvBuilder.String()))
					return
				}
			}
		}
		
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "No attendance data",
		})
		return
	}

	// Flush writer
	if csvWriter != nil {
		csvWriter.Flush()
	}

	// Get filename
	filename := csvFile.Name()

	// Read file contents
	fileBytes, err := os.ReadFile(filename)
	if err != nil {
		http.Error(w, "Failed to read file", http.StatusInternalServerError)
		return
	}

	// Set response headers
	w.Header().Set("Content-Type", "text/csv")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))

	// Write file to response
	w.Write(fileBytes)
}

// Handler: GET /api/get-admin-location
func getAdminLocationHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Get group_id (for multi-group support)
	groupID := getGroupID(r)
	if groupID == "" {
		groupID = "default"
	}

	// Try to get location from group manager first
	group, exists := groupManager.GetGroup(groupID)
	if exists {
		group.mu.RLock()
		if group.AdminLat != 0 && group.AdminLon != 0 {
			group.mu.RUnlock()
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"lat":           group.AdminLat,
				"lon":           group.AdminLon,
				"session_name":  group.Name,
				"threshold":     group.ThresholdMeters,
				"window_active": group.WindowActive,
			})
			return
		}
		group.mu.RUnlock()
	}

	// If group doesn't exist or location not set, try to load from database
	if groupID != "default" {
		groupURL := fmt.Sprintf("%s/rest/v1/groups?id=eq.%s&select=location_lat,location_lon,threshold_meters,name", config.SupabaseURL, groupID)
		req, _ := http.NewRequest("GET", groupURL, nil)
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
		
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			defer resp.Body.Close()
			var groups []struct {
				LocationLat     *float64 `json:"location_lat"`
				LocationLon     *float64 `json:"location_lon"`
				ThresholdMeters *float64 `json:"threshold_meters"`
				Name            string   `json:"name"`
			}
			if json.NewDecoder(resp.Body).Decode(&groups) == nil && len(groups) > 0 {
				if groups[0].LocationLat != nil && groups[0].LocationLon != nil &&
					*groups[0].LocationLat != 0 && *groups[0].LocationLon != 0 {
					// Update group manager with location from database
					group := groupManager.GetOrCreateGroup(groupID)
					group.mu.Lock()
					group.AdminLat = *groups[0].LocationLat
					group.AdminLon = *groups[0].LocationLon
					if groups[0].ThresholdMeters != nil {
						group.ThresholdMeters = *groups[0].ThresholdMeters
					}
					if groups[0].Name != "" {
						group.Name = groups[0].Name
					}
					group.mu.Unlock()
					
					w.Header().Set("Content-Type", "application/json")
					json.NewEncoder(w).Encode(map[string]interface{}{
						"lat":           *groups[0].LocationLat,
						"lon":           *groups[0].LocationLon,
						"session_name":  groups[0].Name,
						"threshold":     groups[0].ThresholdMeters,
						"window_active": false,
					})
					return
				}
			}
		}
	}

	// Fallback to legacy global variables
	mu.Lock()
	defer mu.Unlock()

	// Check if location is set
	if adminLat == 0 && adminLon == 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		response := map[string]string{
			"error": "Admin location not set",
		}
		if err := json.NewEncoder(w).Encode(response); err != nil {
			http.Error(w, "Failed to encode response", http.StatusInternalServerError)
			return
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")

	response := map[string]interface{}{
		"lat":           adminLat,
		"lon":           adminLon,
		"session_name":  sessionName,
		"threshold":     thresholdMeters,
		"window_active": attendanceActive,
	}

	if err := json.NewEncoder(w).Encode(response); err != nil {
		http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}
}

// Handler: GET /api/get-window-status
func getWindowStatusHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Check if student_id is provided (for student dashboard)
	studentID := r.URL.Query().Get("student_id")
	
	// If student_id provided, find active windows they can access
	if studentID != "" {
		studentUUID := getStudentUUIDByID(studentID)
		fmt.Printf("DEBUG: getWindowStatusHandler - studentID: %s, studentUUID: %s\n", studentID, studentUUID)
		if studentUUID != "" {
			// Find all groups this student belongs to
			groupsURL := fmt.Sprintf("%s/rest/v1/group_students?student_id=eq.%s&select=group_id", config.SupabaseURL, studentUUID)
			req, _ := http.NewRequest("GET", groupsURL, nil)
			req.Header.Set("apikey", config.SupabaseAnonKey)
			req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
			
			resp, err := http.DefaultClient.Do(req)
			if err == nil {
				defer resp.Body.Close()
				var groupMemberships []map[string]interface{}
				if err := json.NewDecoder(resp.Body).Decode(&groupMemberships); err != nil {
					fmt.Printf("DEBUG: getWindowStatusHandler - Failed to decode group memberships: %v\n", err)
				}
				fmt.Printf("DEBUG: getWindowStatusHandler - Found %d group memberships for student\n", len(groupMemberships))
				
				// Check all groups for active windows
				var activeWindows []map[string]interface{}
				
				groupManager.mu.RLock()
				fmt.Printf("DEBUG: getWindowStatusHandler - Total groups in manager: %d\n", len(groupManager.groups))
				for _, membership := range groupMemberships {
					gID, ok := membership["group_id"].(string)
					if !ok {
						fmt.Printf("DEBUG: getWindowStatusHandler - Invalid group_id in membership: %v\n", membership)
						continue
					}
					fmt.Printf("DEBUG: getWindowStatusHandler - Checking group %s for active window\n", gID)
					if group, exists := groupManager.groups[gID]; exists {
						group.mu.RLock()
						fmt.Printf("DEBUG: getWindowStatusHandler - Group %s exists, WindowActive: %v, GroupOnly: %v\n", gID, group.WindowActive, group.GroupOnly)
						if group.WindowActive {
							elapsed := time.Since(group.WindowStartTime)
							remaining := 600 - int(elapsed.Seconds())
							if remaining < 0 {
								remaining = 0
							}
							fmt.Printf("DEBUG: getWindowStatusHandler - Found active window in group %s with %d seconds remaining\n", gID, remaining)
							activeWindows = append(activeWindows, map[string]interface{}{
								"group_id":          gID,
								"group_name":        group.Name,
								"group_only":        group.GroupOnly,
								"remaining_seconds": remaining,
							})
						}
						group.mu.RUnlock()
					} else {
						fmt.Printf("DEBUG: getWindowStatusHandler - Group %s not found in groupManager\n", gID)
					}
				}
				
				// Also check for "all students" windows (group_only = false)
				for gID, group := range groupManager.groups {
					group.mu.RLock()
					if group.WindowActive && !group.GroupOnly {
						elapsed := time.Since(group.WindowStartTime)
						remaining := 600 - int(elapsed.Seconds())
						if remaining < 0 {
							remaining = 0
						}
						// Check if not already added
						found := false
						for _, w := range activeWindows {
							if w["group_id"] == gID {
								found = true
								break
							}
						}
						if !found {
							activeWindows = append(activeWindows, map[string]interface{}{
								"group_id":          gID,
								"group_name":        group.Name,
								"group_only":        false,
								"remaining_seconds": remaining,
							})
						}
					}
					group.mu.RUnlock()
				}
				groupManager.mu.RUnlock()
				
				// Return the first active window (or most relevant one)
				w.Header().Set("Content-Type", "application/json")
				if len(activeWindows) > 0 {
					// Return the window with most time remaining
					bestWindow := activeWindows[0]
					for _, w := range activeWindows {
						if w["remaining_seconds"].(int) > bestWindow["remaining_seconds"].(int) {
							bestWindow = w
						}
					}
					json.NewEncoder(w).Encode(map[string]interface{}{
						"active":            true,
						"remaining_seconds": bestWindow["remaining_seconds"],
						"group_id":          bestWindow["group_id"],
						"group_name":        bestWindow["group_name"],
						"session_name":      bestWindow["group_name"], // session_name is same as group_name
					})
					return
				}
			}
		}
	}

	// Fallback: Check specific group_id (for admin dashboard)
	groupID := getGroupID(r)
	if groupID == "" {
		groupID = "default"
	}

	group, exists := groupManager.GetGroup(groupID)
	if !exists {
		// Try to restore window status from database
		if groupID != "default" {
			groupURL := fmt.Sprintf("%s/rest/v1/groups?id=eq.%s&select=id,name,status,window_start_time,window_end_time", config.SupabaseURL, groupID)
			req, _ := http.NewRequest("GET", groupURL, nil)
			req.Header.Set("apikey", config.SupabaseAnonKey)
			req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
			
			resp, err := http.DefaultClient.Do(req)
			if err == nil {
				defer resp.Body.Close()
				var groups []struct {
					ID              string     `json:"id"`
					Name            string     `json:"name"`
					Status          string     `json:"status"`
					WindowStartTime *string    `json:"window_start_time"`
					WindowEndTime   *string    `json:"window_end_time"`
				}
				if json.NewDecoder(resp.Body).Decode(&groups) == nil && len(groups) > 0 {
					g := groups[0]
					if g.Status == "active" && g.WindowStartTime != nil && g.WindowEndTime != nil {
						// Restore window from database
						group = groupManager.GetOrCreateGroup(groupID)
						group.mu.Lock()
						group.Name = g.Name
						// Parse time with timezone support (handle both formats)
						startTime, err1 := time.Parse(time.RFC3339, *g.WindowStartTime)
						if err1 != nil {
							startTime, _ = time.Parse("2006-01-02T15:04:05", strings.Split(*g.WindowStartTime, "+")[0])
						}
						endTime, err2 := time.Parse(time.RFC3339, *g.WindowEndTime)
						if err2 != nil {
							endTime, _ = time.Parse("2006-01-02T15:04:05", strings.Split(*g.WindowEndTime, "+")[0])
						}
						group.WindowStartTime = startTime
						group.WindowEndTime = endTime
						group.WindowActive = time.Now().Before(endTime) // Only active if not expired
						group.mu.Unlock()
						exists = true
						fmt.Printf("DEBUG: getWindowStatusHandler - Restored window from database for group %s (Active=%v, EndTime=%v, Now=%v)\n", groupID, group.WindowActive, endTime, time.Now())
					}
				}
			}
		}
		
		if !exists {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"active":            false,
				"remaining_seconds": 0,
				"session_name":      "",
			})
			return
		}
	}

	group.mu.RLock()
	defer group.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")

	// Check if window is still active (not expired)
	if !group.WindowActive || time.Now().After(group.WindowEndTime) {
		// Window expired or closed
		if group.WindowActive {
			// Auto-close expired window
			group.mu.RUnlock()
			group.mu.Lock()
			group.WindowActive = false
			group.mu.Unlock()
			group.mu.RLock()
		}
	response := map[string]interface{}{
		"active":            false,
		"remaining_seconds": 0,
		"group_id":          groupID,
		"session_name":      group.Name,
	}
	json.NewEncoder(w).Encode(response)
	return
}

	// Calculate remaining seconds
	elapsed := time.Since(group.WindowStartTime)
	remaining := 600 - int(elapsed.Seconds()) // 10 minutes = 600 seconds

	if remaining < 0 {
		remaining = 0
	}

	response := map[string]interface{}{
		"active":            group.WindowActive,
		"remaining_seconds": remaining,
		"start_time":        group.WindowStartTime.Format("2006-01-02 15:04:05"),
		"group_id":          groupID,
		"session_name":     group.Name,
	}

	json.NewEncoder(w).Encode(response)
}

// Handler: GET /api/get-all-student-locations
func getAllStudentLocationsHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	groupID := getGroupID(r)
	if groupID == "" {
		groupID = "default"
	}

	group, exists := groupManager.GetGroup(groupID)
	if !exists {
		// Try to load from database
		if groupID != "default" {
			group = groupManager.GetOrCreateGroup(groupID)
			exists = true
		} else {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"students": []interface{}{},
				"count":    0,
			})
			return
		}
	}

	group.mu.RLock()
	locationsCount := len(group.StudentLocations)
	group.mu.RUnlock()

	// If no locations in memory, try to load from database
	if locationsCount == 0 && groupID != "default" {
		// Load attendance records from database
		attendanceURL := fmt.Sprintf("%s/rest/v1/group_attendance?group_id=eq.%s&select=*,students(student_id,student_name)&order=submitted_at.asc", config.SupabaseURL, groupID)
		req, _ := http.NewRequest("GET", attendanceURL, nil)
		req.Header.Set("apikey", config.SupabaseAnonKey)
		req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
		
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			defer resp.Body.Close()
			var records []map[string]interface{}
			if json.NewDecoder(resp.Body).Decode(&records) == nil {
				group.mu.Lock()
				for _, record := range records {
					student := record["students"].(map[string]interface{})
					studentID := student["student_id"].(string)
					studentName := student["student_name"].(string)
					
					loc := StudentLocation{
						StudentID:   studentID,
						StudentName: studentName,
						Latitude:    record["latitude"].(float64),
						Longitude:   record["longitude"].(float64),
						Distance:    record["distance"].(float64),
						Timestamp:   record["submitted_at"].(string),
						Status:      record["status"].(string),
					}
					group.StudentLocations[studentID] = loc
					group.SubmittedStudents[studentID] = true
				}
				locationsCount = len(group.StudentLocations)
				group.mu.Unlock()
				fmt.Printf("DEBUG: getAllStudentLocationsHandler - Loaded %d locations from database for group %s\n", locationsCount, groupID)
			}
		}
	}

	group.mu.RLock()
	// Convert map to slice (copy data while holding lock)
	locations := make([]StudentLocation, 0, len(group.StudentLocations))
	for _, loc := range group.StudentLocations {
		locations = append(locations, loc)
	}
	group.mu.RUnlock()

	// Debug: Print student locations count
	fmt.Printf("DEBUG: Returning %d student locations\n", len(locations))
	for _, loc := range locations {
		fmt.Printf("  - %s (%s): %.6f, %.6f, %.0fm\n", loc.StudentName, loc.StudentID, loc.Latitude, loc.Longitude, loc.Distance)
	}

	// Set headers
	w.Header().Set("Content-Type", "application/json")

	response := map[string]interface{}{
		"students": locations,
		"count":    len(locations),
	}

	// Debug: Print response before encoding
	fmt.Printf("DEBUG: Response map: %+v\n", response)

	// Encode JSON manually to ensure it works
	jsonBytes, err := json.Marshal(response)
	if err != nil {
		fmt.Printf("ERROR: Failed to marshal JSON: %v\n", err)
		http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}

	fmt.Printf("DEBUG: JSON bytes length: %d\n", len(jsonBytes))
	fmt.Printf("DEBUG: JSON string: %s\n", string(jsonBytes))

	// Write JSON bytes directly
	if _, err := w.Write(jsonBytes); err != nil {
		fmt.Printf("ERROR: Failed to write response: %v\n", err)
		return
	}

	fmt.Printf("DEBUG: Successfully sent response with %d students\n", len(locations))
}

// Handler: GET /api/get-all-students
// Fetches all students from the database with pagination support
// Query parameters: page (default: 1), limit (default: 10)
func getAllStudentsHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse pagination parameters
	page := 1
	limit := 100 // Increased default to show all students
	if pageStr := r.URL.Query().Get("page"); pageStr != "" {
		if p, err := strconv.Atoi(pageStr); err == nil && p > 0 {
			page = p
		}
	}
	if limitStr := r.URL.Query().Get("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 200 {
			limit = l // Allow up to 200 students per page
		}
	}
	
	// Check for cache bust parameter - clear cache if present
	if r.URL.Query().Get("_t") != "" {
		studentCache.mu.Lock()
		studentCache.data = nil
		studentCache.totalCount = 0
		studentCache.timestamp = time.Time{} // Reset timestamp to force cache miss
		studentCache.mu.Unlock()
	}

	offset := (page - 1) * limit

	// Check if this is a list view (skip in-memory status checks for performance)
	isListView := r.URL.Query().Get("view") == "list"

	// Check cache first (only for list view, page 1, and if cache is valid)
	if isListView && page == 1 && !studentCache.timestamp.IsZero() {
		studentCache.mu.RLock()
		if time.Since(studentCache.timestamp) < cacheDuration && len(studentCache.data) > 0 {
			// Return cached data
			cachedData := studentCache.data
			cachedTotal := studentCache.totalCount
			studentCache.mu.RUnlock()

			hasMore := len(cachedData) == limit
			totalPages := 1
			if cachedTotal > 0 {
				totalPages = (cachedTotal + limit - 1) / limit
			}

			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("X-Cache", "HIT") // Indicate cache hit
			json.NewEncoder(w).Encode(map[string]interface{}{
				"students":   cachedData,
				"count":      len(cachedData),
				"page":       page,
				"limit":      limit,
				"hasMore":    hasMore,
				"totalPages": totalPages,
			})
			return
		}
		studentCache.mu.RUnlock()
	}

	// Query Supabase to get paginated students with count in single request
	url := fmt.Sprintf("%s/rest/v1/students?select=id,student_id,student_name&order=student_id.asc&limit=%d&offset=%d",
		config.SupabaseURL, limit, offset)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		http.Error(w, "Failed to create request", http.StatusInternalServerError)
		return
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "count=exact") // Get count in same request

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Database connection error",
		})
		return
	}
	defer resp.Body.Close()

	// Get total count from Content-Range header
	totalCount := 0
	if countHeader := resp.Header.Get("Content-Range"); countHeader != "" {
		parts := strings.Split(countHeader, "/")
		if len(parts) == 2 {
			if total, err := strconv.Atoi(parts[1]); err == nil {
				totalCount = total
			}
		}
	}

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   "Failed to fetch students from database",
			"status":  resp.StatusCode,
			"details": string(bodyBytes),
		})
		return
	}

	var students []struct {
		ID          string `json:"id"`
		StudentID   string `json:"student_id"`
		StudentName string `json:"student_name"`
	}

	// Decode directly from response body
	if err := json.NewDecoder(resp.Body).Decode(&students); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   "Failed to parse response",
			"details": err.Error(),
		})
		return
	}

	// Fast path for list view - skip in-memory checks and redundant fields
	if isListView {
		// Convert to simple format without redundant field names
		studentList := make([]map[string]interface{}, 0, len(students))
		for _, student := range students {
			studentList = append(studentList, map[string]interface{}{
				"id":           student.ID,
				"student_id":   student.StudentID,
				"student_name": student.StudentName,
				"status":       "Not Submitted", // Default status
			})
		}

		// Cache the result (only for page 1)
		if page == 1 {
			studentCache.mu.Lock()
			studentCache.data = studentList
			studentCache.totalCount = totalCount
			studentCache.timestamp = time.Now()
			studentCache.mu.Unlock()
		}

		// Determine pagination
		hasMore := len(students) == limit
		totalPages := 1
		if totalCount > 0 {
			totalPages = (totalCount + limit - 1) / limit
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("X-Cache", "MISS") // Indicate cache miss
		json.NewEncoder(w).Encode(map[string]interface{}{
			"students":   studentList,
			"count":      len(studentList),
			"page":       page,
			"limit":      limit,
			"hasMore":    hasMore,
			"totalPages": totalPages,
		})
		return
	}

	// Full path with attendance status (for other views that need it)
	mu.Lock()
	studentList := make([]map[string]interface{}, 0, len(students))
	for _, student := range students {
		status := "Not Submitted"
		var distance float64
		var timestamp string

		// Check if student has submitted attendance
		if submitted, exists := submittedStudents[student.StudentID]; exists && submitted {
			if loc, exists := studentLocations[student.StudentID]; exists {
				status = loc.Status
				distance = loc.Distance
				timestamp = loc.Timestamp
			}
		}

		// Single format - no redundant field names
		studentData := map[string]interface{}{
			"id":           student.ID,
			"student_id":   student.StudentID,
			"student_name": student.StudentName,
			"status":       status,
			"distance":     distance,
			"timestamp":    timestamp,
		}

		studentList = append(studentList, studentData)
	}
	mu.Unlock()

	// Determine if there are more pages
	hasMore := len(students) == limit
	totalPages := 1
	if totalCount > 0 {
		totalPages = (totalCount + limit - 1) / limit
	}

	// Set headers
	w.Header().Set("Content-Type", "application/json")

	response := map[string]interface{}{
		"students":   studentList,
		"count":      len(studentList),
		"page":       page,
		"limit":      limit,
		"hasMore":    hasMore,
		"totalPages": totalPages,
	}

	jsonBytes, err := json.Marshal(response)
	if err != nil {
		fmt.Printf("ERROR: Failed to marshal JSON: %v\n", err)
		http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}

	if _, err := w.Write(jsonBytes); err != nil {
		// Silent error - response already sent
		return
	}
}

// Handler: GET /api/get-student-attendance-history
func getStudentAttendanceHistoryHandler(w http.ResponseWriter, r *http.Request) {
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
	if studentID == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "student_id is required"})
		return
	}

	studentUUID := getStudentUUIDByID(studentID)
	if studentUUID == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "Student not found"})
		return
	}

	// Get attendance history from database
	attendanceURL := fmt.Sprintf("%s/rest/v1/group_attendance?student_id=eq.%s&select=*,groups(name,session_name),submitted_at&order=submitted_at.desc",
		config.SupabaseURL, studentUUID)
	
	fmt.Printf("DEBUG: getStudentAttendanceHistoryHandler - Querying URL: %s\n", attendanceURL)
	fmt.Printf("DEBUG: getStudentAttendanceHistoryHandler - studentID: %s, studentUUID: %s\n", studentID, studentUUID)
	
	req, _ := http.NewRequest("GET", attendanceURL, nil)
	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Database error"})
		return
	}
	defer resp.Body.Close()

	var records []map[string]interface{}
	if resp.StatusCode == http.StatusOK {
		bodyBytes, readErr := io.ReadAll(resp.Body)
		if readErr != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(map[string]string{"error": "Failed to read response"})
			return
		}
		
		if len(bodyBytes) > 0 {
			if decodeErr := json.Unmarshal(bodyBytes, &records); decodeErr != nil {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusInternalServerError)
				json.NewEncoder(w).Encode(map[string]string{"error": "Failed to parse database response"})
				return
			}
		}
	} else {
		// If not OK status, return error
		bodyBytes, _ := io.ReadAll(resp.Body)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		errorMsg := "Database query failed"
		if len(bodyBytes) > 0 {
			errorMsg = string(bodyBytes)
		}
		json.NewEncoder(w).Encode(map[string]string{"error": errorMsg})
		return
	}

	// Format response
	attendanceHistory := make([]map[string]interface{}, 0)
	for _, record := range records {
		groupData, ok := record["groups"].(map[string]interface{})
		if !ok {
			groupData = map[string]interface{}{"name": "N/A", "session_name": ""}
		}
		
		attendanceHistory = append(attendanceHistory, map[string]interface{}{
			"id":           record["id"],
			"status":       record["status"],
			"distance":     record["distance"],
			"latitude":     record["latitude"],
			"longitude":    record["longitude"],
			"submitted_at": record["submitted_at"],
			"group_name":   groupData["name"],
			"session_name": groupData["session_name"],
		})
	}

	// Always return valid JSON, even if empty
	response := map[string]interface{}{
		"attendance_history": attendanceHistory,
		"count":              len(attendanceHistory),
	}
	
	fmt.Printf("DEBUG: getStudentAttendanceHistoryHandler - Returning %d records for student %s\n", len(attendanceHistory), studentID)
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if encodeErr := json.NewEncoder(w).Encode(response); encodeErr != nil {
		// If encoding fails, try to write a simple error response
		fmt.Printf("ERROR: Failed to encode attendance history response: %v\n", encodeErr)
		// Reset and write error
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error": "Failed to encode response"}`)
	}
}

// Handler: POST /api/update-session-name
func updateSessionNameHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := r.ParseForm(); err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}

	sessionName := r.FormValue("session_name")
	groupID := r.FormValue("group_id")

	if sessionName == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "session_name is required",
		})
		return
	}

	// If group_id is provided, update the group in database
	if groupID != "" && groupID != "default" {
		// Update group in database
		updateURL := fmt.Sprintf("%s/rest/v1/groups?id=eq.%s", config.SupabaseURL, groupID)
		updateData := map[string]interface{}{
			"name": sessionName,
		}
		jsonData, _ := json.Marshal(updateData)
		req, err := http.NewRequest("PATCH", updateURL, strings.NewReader(string(jsonData)))
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

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "Database connection error",
			})
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
			bodyBytes, _ := io.ReadAll(resp.Body)
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"error":   "Failed to update session name",
				"details": string(bodyBytes),
			})
			return
		}

		// Update in-memory group data
		group := groupManager.GetOrCreateGroup(groupID)
		group.mu.Lock()
		group.Name = sessionName
		group.mu.Unlock()
	} else {
		// For default/legacy mode, just update the in-memory group
		group := groupManager.GetOrCreateGroup("default")
		group.mu.Lock()
		group.Name = sessionName
		group.mu.Unlock()
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Session name updated successfully",
		"session_name": sessionName,
	})
}

// Handler: POST /api/admin-login
func adminLoginHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse form data
	if err := r.ParseForm(); err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}

	username := r.FormValue("username")
	password := r.FormValue("password")

	if username == "" || password == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Username and password are required",
		})
		return
	}

	// Query Supabase using REST API
	url := fmt.Sprintf("%s/rest/v1/admins?username=eq.%s&password=eq.%s&select=*",
		config.SupabaseURL, username, password)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		http.Error(w, "Failed to create request", http.StatusInternalServerError)
		return
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, "Database connection error", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	var admins []struct {
		ID       string `json:"id"`
		Username string `json:"username"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&admins); err != nil {
		http.Error(w, "Failed to parse response", http.StatusInternalServerError)
		return
	}

	if len(admins) == 0 {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Invalid credentials",
		})
		return
	}

	// Success
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Login successful",
		"admin": map[string]string{
			"id":       admins[0].ID,
			"username": admins[0].Username,
		},
	})
}

// Handler: POST /api/student-login
func studentLoginHandler(w http.ResponseWriter, r *http.Request) {
	enableCORS(w)

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse form data
	if err := r.ParseForm(); err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}

	studentID := r.FormValue("student_id")
	studentName := r.FormValue("student_name")

	if studentID == "" || studentName == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Student ID and name are required",
		})
		return
	}

	// Query Supabase using REST API
	// First check if student_id exists
	url := fmt.Sprintf("%s/rest/v1/students?student_id=eq.%s&select=*",
		config.SupabaseURL, studentID)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		http.Error(w, "Failed to create request", http.StatusInternalServerError)
		return
	}

	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, "Database connection error", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	var students []struct {
		ID          string `json:"id"`
		StudentID   string `json:"student_id"`
		StudentName string `json:"student_name"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&students); err != nil {
		http.Error(w, "Failed to parse response", http.StatusInternalServerError)
		return
	}

	if len(students) == 0 {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Student ID not found",
		})
		return
	}

	// Check if name matches (case-insensitive)
	if !strings.EqualFold(students[0].StudentName, studentName) {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Student name does not match the registered ID",
		})
		return
	}

	// Success
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Login successful",
		"student": map[string]string{
			"id":           students[0].ID,
			"student_id":   students[0].StudentID,
			"student_name": students[0].StudentName,
		},
	})
}

// Main function
func main() {
	// Load configuration
	config = LoadConfig()

	// Validate config
	if config.SupabaseURL == "" || config.SupabaseAnonKey == "" {
		fmt.Println("Warning: SUPABASE_URL or SUPABASE_ANON_KEY not set")
		fmt.Println("Please create a .env file with:")
		fmt.Println("  SUPABASE_URL=your_supabase_url")
		fmt.Println("  SUPABASE_ANON_KEY=your_anon_key")
	}

	// Initialize submitted students map and student locations
	submittedStudents = make(map[string]bool)
	studentLocations = make(map[string]StudentLocation)

	// Register handlers
	http.HandleFunc("/api/admin-login", adminLoginHandler)
	http.HandleFunc("/api/student-login", studentLoginHandler)
	http.HandleFunc("/api/set-center", setCenterHandler)
	http.HandleFunc("/api/start-window", startWindowHandler)
	http.HandleFunc("/api/close-window", closeWindowHandler)
	http.HandleFunc("/api/submit-attendance", submitAttendanceHandler)
	http.HandleFunc("/api/download-csv", downloadCSVHandler)
	http.HandleFunc("/api/get-admin-location", getAdminLocationHandler)
	http.HandleFunc("/api/get-window-status", getWindowStatusHandler)
	http.HandleFunc("/api/get-all-student-locations", getAllStudentLocationsHandler)
	http.HandleFunc("/api/get-all-students", getAllStudentsHandler)

	// Register group management handlers
	http.HandleFunc("/api/create-group", createGroupHandler)
	http.HandleFunc("/api/get-my-groups", getMyGroupsHandler)
	http.HandleFunc("/api/add-students-to-group", addStudentsToGroupHandler)
	http.HandleFunc("/api/get-group-students", getGroupStudentsHandler)
	http.HandleFunc("/api/delete-group", deleteGroupHandler)

	// Register student management handlers
	http.HandleFunc("/api/add-student", addStudentHandler)
	
	// Register session management handlers
	http.HandleFunc("/api/update-session-name", updateSessionNameHandler)
	
	// Register messaging handlers
	http.HandleFunc("/api/save-fcm-token", saveFCMTokenHandler)
	http.HandleFunc("/api/send-broadcast-message", sendBroadcastMessageHandler)
	http.HandleFunc("/api/get-messages", getMessagesHandler)
	http.HandleFunc("/api/mark-message-read", markMessageReadHandler)
	http.HandleFunc("/api/delete-message", deleteMessageHandler)
	http.HandleFunc("/api/get-student-attendance-history", getStudentAttendanceHistoryHandler)

	// Enable CORS (for Flutter app)
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
	})

	// Start server
	fmt.Println("Server running on :8080")
	fmt.Println("Endpoints:")
	fmt.Println("  POST /api/admin-login")
	fmt.Println("  POST /api/student-login")
	fmt.Println("  POST /api/set-center")
	fmt.Println("  POST /api/start-window")
	fmt.Println("  POST /api/close-window")
	fmt.Println("  POST /api/submit-attendance")
	fmt.Println("  GET  /api/download-csv")
	fmt.Println("  GET  /api/get-admin-location")
	fmt.Println("  GET  /api/get-window-status")
	fmt.Println("  GET  /api/get-all-student-locations")
	fmt.Println("  GET  /api/get-all-students")
	fmt.Println("  POST /api/create-group")
	fmt.Println("  GET  /api/get-my-groups")
	fmt.Println("  POST /api/add-students-to-group")
	fmt.Println("  GET  /api/get-group-students")
	fmt.Println("  DELETE /api/delete-group")
	fmt.Println("  POST /api/add-student")
	fmt.Println("  POST /api/save-fcm-token")
	fmt.Println("  POST /api/send-broadcast-message")
	fmt.Println("  GET  /api/get-messages")
	fmt.Println("  POST /api/mark-message-read")
	fmt.Println("  POST /api/delete-message")
	fmt.Println("  GET  /api/get-student-attendance-history")

	if err := http.ListenAndServe(":8080", nil); err != nil {
		fmt.Printf("Server failed to start: %v\n", err)
	}
}
