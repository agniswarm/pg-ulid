package main

import (
	"database/sql"
	"fmt"
	"os"
	"testing"
	"time"

	_ "github.com/lib/pq"
	"github.com/oklog/ulid/v2"
)

// Test configuration
const (
	DB_HOST     = "localhost"
	DB_PORT     = "5432"
	DB_USER     = "postgres"
	DB_PASSWORD = "test"
	DB_NAME     = "postgres"
)

var db *sql.DB

func TestMain(m *testing.M) {
	// Setup database connection
	setupDatabase()

	// Run tests
	code := m.Run()

	// Cleanup
	cleanupDatabase()

	os.Exit(code)
}

func setupDatabase() {
	// Try to connect to database
	var dsn string
	if DB_PASSWORD == "" {
		dsn = fmt.Sprintf("host=%s port=%s user=%s dbname=%s sslmode=disable",
			DB_HOST, DB_PORT, DB_USER, DB_NAME)
	} else {
		dsn = fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
			DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME)
	}

	var err error
	db, err = sql.Open("postgres", dsn)
	if err != nil {
		fmt.Printf("Warning: Could not connect to database: %v\n", err)
		fmt.Println("Skipping database tests")
		return
	}

	// Test connection
	if err = db.Ping(); err != nil {
		fmt.Printf("Warning: Could not ping database: %v\n", err)
		fmt.Println("Skipping database tests")
		db = nil
		return
	}

	fmt.Println("Database connection established")
}

func cleanupDatabase() {
	if db != nil {
		db.Close()
	}
}

// SQL Functions Tests (requires Docker)
func TestSQLFunctions(t *testing.T) {
	if db == nil {
		t.Skip("Database not available - make sure Docker is running")
	}

	// Test basic ULID generation
	var ulidStr string
	err := db.QueryRow("SELECT ulid()").Scan(&ulidStr)
	if err != nil {
		t.Fatalf("Failed to generate ULID: %v", err)
	}

	if len(ulidStr) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulidStr))
	}

	// Validate ULID format
	_, err = ulid.Parse(ulidStr)
	if err != nil {
		t.Errorf("Generated invalid ULID: %v", err)
	}

	fmt.Printf("Basic ULID generation working - Generated: %s\n", ulidStr)
}

func TestRandomULID(t *testing.T) {
	if db == nil {
		t.Skip("Database not available - make sure Docker is running")
	}

	var ulidStr string
	err := db.QueryRow("SELECT ulid_random()").Scan(&ulidStr)
	if err != nil {
		t.Fatalf("Failed to generate random ULID: %v", err)
	}

	if len(ulidStr) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulidStr))
	}

	fmt.Printf("Random ULID generation working - Generated: %s\n", ulidStr)
}

func TestCryptoULID(t *testing.T) {
	if db == nil {
		t.Skip("Database not available - make sure Docker is running")
	}

	var ulidStr string
	err := db.QueryRow("SELECT ulid_crypto()").Scan(&ulidStr)
	if err != nil {
		t.Fatalf("Failed to generate crypto ULID: %v", err)
	}

	if len(ulidStr) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulidStr))
	}

	fmt.Printf("Crypto ULID generation working - Generated: %s\n", ulidStr)
}

func TestTimeBasedULID(t *testing.T) {
	if db == nil {
		t.Skip("Database not available - make sure Docker is running")
	}

	// Test with a specific timestamp (Jan 1, 2022)
	timestamp := int64(1640995200000)
	var ulidStr string
	err := db.QueryRow("SELECT ulid_time($1)", timestamp).Scan(&ulidStr)
	if err != nil {
		t.Fatalf("Failed to generate time-based ULID: %v", err)
	}

	// Parse and validate ULID
	id, err := ulid.Parse(ulidStr)
	if err != nil {
		t.Errorf("Generated invalid ULID: %v", err)
	}

	// Check that the timestamp matches (within 1 second tolerance)
	expectedTime := time.UnixMilli(timestamp)
	actualTime := time.UnixMilli(int64(id.Time()))

	if actualTime.Before(expectedTime.Add(-time.Second)) || actualTime.After(expectedTime.Add(time.Second)) {
		t.Errorf("Expected timestamp around %v, got %v", expectedTime, actualTime)
	}

	fmt.Printf("Time-based ULID generation working - Generated: %s\n", ulidStr)
}

func TestBatchULID(t *testing.T) {
	if db == nil {
		t.Skip("Database not available - make sure Docker is running")
	}

	var batchStr string
	err := db.QueryRow("SELECT ulid_batch(5)").Scan(&batchStr)
	if err != nil {
		t.Fatalf("Failed to generate batch ULIDs: %v", err)
	}

	// Parse the array string (PostgreSQL array format)
	batchStr = batchStr[1 : len(batchStr)-1] // Remove { and }
	ulids := make([]string, 0)
	start := 0
	for i, char := range batchStr {
		if char == ',' {
			ulidStr := batchStr[start:i]
			// Remove quotes if present
			if len(ulidStr) >= 2 && ulidStr[0] == '"' && ulidStr[len(ulidStr)-1] == '"' {
				ulidStr = ulidStr[1 : len(ulidStr)-1]
			}
			ulids = append(ulids, ulidStr)
			start = i + 1
		}
	}
	// Add the last one
	lastULID := batchStr[start:]
	if len(lastULID) >= 2 && lastULID[0] == '"' && lastULID[len(lastULID)-1] == '"' {
		lastULID = lastULID[1 : len(lastULID)-1]
	}
	ulids = append(ulids, lastULID)

	if len(ulids) != 5 {
		t.Errorf("Expected 5 ULIDs, got %d", len(ulids))
	}

	// Validate each ULID
	for i, ulidStr := range ulids {
		if len(ulidStr) != 26 {
			t.Errorf("ULID %d: Expected length 26, got %d", i, len(ulidStr))
		}

		_, err := ulid.Parse(ulidStr)
		if err != nil {
			t.Errorf("ULID %d: Invalid format: %v", i, err)
		}
	}

	fmt.Printf("Batch ULID generation working - Generated %d ULIDs\n", len(ulids))
}

func TestRandomBatchULID(t *testing.T) {
	if db == nil {
		t.Skip("Database not available - make sure Docker is running")
	}

	var batchStr string
	err := db.QueryRow("SELECT ulid_random_batch(3)").Scan(&batchStr)
	if err != nil {
		t.Fatalf("Failed to generate random batch ULIDs: %v", err)
	}

	// Parse the array string
	batchStr = batchStr[1 : len(batchStr)-1] // Remove { and }
	ulids := make([]string, 0)
	start := 0
	for i, char := range batchStr {
		if char == ',' {
			ulids = append(ulids, batchStr[start:i])
			start = i + 1
		}
	}
	ulids = append(ulids, batchStr[start:]) // Add the last one

	if len(ulids) != 3 {
		t.Errorf("Expected 3 ULIDs, got %d", len(ulids))
	}

	fmt.Printf("Random batch ULID generation working - Generated %d ULIDs\n", len(ulids))
}

func TestULIDParsing(t *testing.T) {
	if db == nil {
		t.Skip("Database not available - make sure Docker is running")
	}

	// Test with a valid ULID
	validULID := "01K4FRQ1CZDHKG25YHF6Q5W0Z1"

	var isValid bool
	var timestampMs sql.NullInt64
	var timestampIso sql.NullString
	var entropyHex sql.NullString

	err := db.QueryRow("SELECT * FROM ulid_parse($1)", validULID).Scan(
		&isValid, &timestampMs, &timestampIso, &entropyHex)
	if err != nil {
		t.Fatalf("Failed to parse ULID: %v", err)
	}

	if !isValid {
		t.Errorf("Expected valid ULID, got invalid")
	}

	fmt.Printf("ULID parsing working - Valid ULID parsed successfully\n")

	// Test with an invalid ULID
	invalidULID := "invalid-ulid"

	err = db.QueryRow("SELECT * FROM ulid_parse($1)", invalidULID).Scan(
		&isValid, &timestampMs, &timestampIso, &entropyHex)
	if err != nil {
		t.Fatalf("Failed to parse invalid ULID: %v", err)
	}

	if isValid {
		t.Errorf("Expected invalid ULID, got valid")
	}

	fmt.Printf("ULID parsing working - Invalid ULID correctly rejected\n")
}
