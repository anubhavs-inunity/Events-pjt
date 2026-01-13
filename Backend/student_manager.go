package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// Handler: POST /api/add-student
func addStudentHandler(w http.ResponseWriter, r *http.Request) {
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
		StudentID   string `json:"student_id"`
		StudentName string `json:"student_name"`
	}

	if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Validate required fields
	if data.StudentID == "" || data.StudentName == "" {
		http.Error(w, "student_id and student_name are required", http.StatusBadRequest)
		return
	}

	// Check if student_id already exists
	checkURL := fmt.Sprintf("%s/rest/v1/students?student_id=eq.%s&select=id", config.SupabaseURL, data.StudentID)
	checkReq, _ := http.NewRequest("GET", checkURL, nil)
	checkReq.Header.Set("apikey", config.SupabaseAnonKey)
	checkReq.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)

	checkResp, err := http.DefaultClient.Do(checkReq)
	if err == nil {
		defer checkResp.Body.Close()
		bodyBytes, _ := io.ReadAll(checkResp.Body)
		var existing []map[string]interface{}
		if json.NewDecoder(bytes.NewReader(bodyBytes)).Decode(&existing) == nil && len(existing) > 0 {
			w.WriteHeader(http.StatusConflict)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "Student ID already exists",
			})
			return
		}
	} else {
		fmt.Printf("DEBUG: Error checking existing student: %v\n", err)
	}

	// Create student
	studentData := map[string]interface{}{
		"student_id":   data.StudentID,
		"student_name": data.StudentName,
	}

	jsonData, _ := json.Marshal(studentData)
	fmt.Printf("DEBUG: Adding student - ID: %s, Name: %s\n", data.StudentID, data.StudentName)
	fmt.Printf("DEBUG: Request body: %s\n", string(jsonData))
	url := fmt.Sprintf("%s/rest/v1/students", config.SupabaseURL)
	fmt.Printf("DEBUG: POST URL: %s\n", url)
	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	req.Header.Set("apikey", config.SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+config.SupabaseAnonKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Database connection error",
		})
		return
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)
	fmt.Printf("DEBUG: Response status: %d\n", resp.StatusCode)
	fmt.Printf("DEBUG: Response body: %s\n", string(bodyBytes))
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		w.WriteHeader(resp.StatusCode)
		json.NewEncoder(w).Encode(map[string]string{
			"error": fmt.Sprintf("Failed to create student: %s", string(bodyBytes)),
		})
		return
	}

	// Parse response
	var createdStudents []struct {
		ID        string `json:"id"`
		StudentID string `json:"student_id"`
		StudentName string `json:"student_name"`
	}
	if err := json.Unmarshal(bodyBytes, &createdStudents); err != nil {
		// Try single object format
		var createdStudent struct {
			ID        string `json:"id"`
			StudentID string `json:"student_id"`
			StudentName string `json:"student_name"`
		}
		if err2 := json.Unmarshal(bodyBytes, &createdStudent); err2 == nil {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": true,
				"message": "Student added successfully",
				"student": map[string]string{
					"id":           createdStudent.ID,
					"student_id":   createdStudent.StudentID,
					"student_name": createdStudent.StudentName,
				},
			})
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Failed to parse response",
		})
		return
	}

	if len(createdStudents) > 0 {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Student added successfully",
			"student": map[string]string{
				"id":           createdStudents[0].ID,
				"student_id":   createdStudents[0].StudentID,
				"student_name": createdStudents[0].StudentName,
			},
		})
	} else {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Student created but no data returned",
		})
	}
}

