package main

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"math"
	"strings"
	"testing"
	"time"

	"github.com/oklog/ulid/v2"
)

// Test basic ULID generation and validation
func TestBasicULIDGeneration(t *testing.T) {
	// Test Make() function
	ulidID := ulid.Make()
	if len(ulidID.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulidID.String()))
	}

	// Test that ULID contains only valid characters
	ulidStr := ulidID.String()
	for _, char := range ulidStr {
		if !strings.ContainsRune(ulid.Encoding, char) {
			t.Errorf("ULID contains invalid character: %c", char)
		}
	}

	// Test parsing
	parsed, err := ulid.Parse(ulidStr)
	if err != nil {
		t.Errorf("Failed to parse ULID: %v", err)
	}

	if parsed != ulidID {
		t.Errorf("Parsed ULID doesn't match original")
	}

	fmt.Printf("Basic ULID generation working - Generated: %s\n", ulidStr)
}

// Test time-based ULID generation with edge cases
func TestTimeBasedULIDGeneration(t *testing.T) {
	// Test with current timestamp
	now := ulid.Now()
	ulid1 := ulid.MustNew(now, ulid.DefaultEntropy())
	if len(ulid1.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid1.String()))
	}

	// Test with minimum timestamp (0)
	ulid2 := ulid.MustNew(0, ulid.DefaultEntropy())
	if len(ulid2.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid2.String()))
	}

	// Test with maximum timestamp
	maxTime := ulid.MaxTime()
	ulid3 := ulid.MustNew(maxTime, ulid.DefaultEntropy())
	if len(ulid3.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid3.String()))
	}

	// Test with specific historical timestamp (Unix epoch)
	epochTime := uint64(0)
	ulid4 := ulid.MustNew(epochTime, ulid.DefaultEntropy())
	if len(ulid4.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid4.String()))
	}

	// Test with future timestamp (year 2100)
	futureTime := uint64(4102444800000) // 2100-01-01 00:00:00 UTC
	ulid5 := ulid.MustNew(futureTime, ulid.DefaultEntropy())
	if len(ulid5.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid5.String()))
	}

	fmt.Printf("Time-based ULID generation working - Generated: %s\n", ulid1.String())
}

// Test entropy sources and edge cases
func TestEntropySources(t *testing.T) {
	// Test with default entropy
	ulid1 := ulid.Make()
	if len(ulid1.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid1.String()))
	}

	// Test with custom entropy (crypto/rand)
	timestamp := ulid.Now()
	ulid2, err := ulid.New(timestamp, rand.Reader)
	if err != nil {
		t.Errorf("Failed to generate ULID with crypto/rand: %v", err)
	}
	if len(ulid2.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid2.String()))
	}

	// Test with zero entropy (all zeros)
	zeroEntropy := bytes.NewReader(make([]byte, 10))
	ulid3, err := ulid.New(timestamp, zeroEntropy)
	if err != nil {
		t.Errorf("Failed to generate ULID with zero entropy: %v", err)
	}
	if len(ulid3.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid3.String()))
	}

	// Test with deterministic entropy
	deterministicEntropy := bytes.NewReader(bytes.Repeat([]byte{0xFF}, 10))
	ulid4, err := ulid.New(timestamp, deterministicEntropy)
	if err != nil {
		t.Errorf("Failed to generate ULID with deterministic entropy: %v", err)
	}
	if len(ulid4.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid4.String()))
	}

	fmt.Printf("Entropy sources working - Generated: %s\n", ulid1.String())
}

// Test ULID parsing with edge cases
func TestULIDParsingEdgeCases(t *testing.T) {
	// Test valid ULID parsing
	validULID := ulid.Make()
	parsed, err := ulid.Parse(validULID.String())
	if err != nil {
		t.Errorf("Failed to parse valid ULID: %v", err)
	}
	if parsed != validULID {
		t.Errorf("Parsed ULID doesn't match original")
	}

	// Test parsing with different cases
	testCases := []struct {
		name       string
		ulidStr    string
		shouldFail bool
	}{
		{"Valid ULID", validULID.String(), false},
		{"Empty string", "", true},
		{"Too short", "01K4FQ7QN4ZSW0SG5XACGM2HB", true},
		{"Too long", "01K4FQ7QN4ZSW0SG5XACGM2HB4X", true},
		{"Invalid characters", "01K4FQ7QN4ZSW0SG5XACGM2HB4I", true}, // I is not in Crockford's Base32
		{"Invalid characters", "01K4FQ7QN4ZSW0SG5XACGM2HB4O", true}, // O is not in Crockford's Base32
		{"Invalid characters", "01K4FQ7QN4ZSW0SG5XACGM2HB4U", true}, // U is not in Crockford's Base32
		{"Invalid characters", "01K4FQ7QN4ZSW0SG5XACGM2HB4L", true}, // L is not in Crockford's Base32
		{"Mixed case", strings.ToLower(validULID.String()), false},  // ULID library handles case conversion
		{"Special characters", "01K4FQ7QN4ZSW0SG5XACGM2HB4!", true},
		{"Numbers only", "12345678901234567890123456", false}, // This might be valid
		{"Letters only", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", true},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ulid.Parse(tc.ulidStr)
			if tc.shouldFail && err == nil {
				t.Errorf("Expected error for %s, but got none", tc.name)
			}
			if !tc.shouldFail && err != nil {
				t.Errorf("Expected no error for %s, but got: %v", tc.name, err)
			}
		})
	}

	fmt.Printf("ULID parsing edge cases working\n")
}

// Test ULID ordering and comparison
func TestULIDOrdering(t *testing.T) {
	// Test time-based ordering
	timestamp1 := ulid.Now()
	timestamp2 := timestamp1 + 1
	timestamp3 := timestamp1 + 1000

	ulid1 := ulid.MustNew(timestamp1, ulid.DefaultEntropy())
	ulid2 := ulid.MustNew(timestamp2, ulid.DefaultEntropy())
	ulid3 := ulid.MustNew(timestamp3, ulid.DefaultEntropy())

	// Test string ordering (lexicographic)
	if ulid1.String() >= ulid2.String() {
		t.Errorf("ULID ordering failed: %s should be < %s", ulid1.String(), ulid2.String())
	}
	if ulid2.String() >= ulid3.String() {
		t.Errorf("ULID ordering failed: %s should be < %s", ulid2.String(), ulid3.String())
	}

	// Test with same timestamp but different entropy
	ulid4 := ulid.MustNew(timestamp1, rand.Reader)
	ulid5 := ulid.MustNew(timestamp1, rand.Reader)

	// They should be different due to different entropy
	if ulid4 == ulid5 {
		t.Errorf("ULIDs with same timestamp but different entropy should be different")
	}

	// Test monotonic ordering
	monotonic := ulid.Monotonic(ulid.DefaultEntropy(), 0)
	ulid6 := ulid.MustNew(timestamp1, monotonic)
	ulid7 := ulid.MustNew(timestamp1, monotonic)

	// Monotonic ULIDs should be ordered even with same timestamp
	if ulid6.String() >= ulid7.String() {
		t.Errorf("Monotonic ULID ordering failed: %s should be < %s", ulid6.String(), ulid7.String())
	}

	fmt.Printf("ULID ordering working\n")
}

// Test monotonic ULID generation
func TestMonotonicULIDGeneration(t *testing.T) {
	// Test basic monotonic generation
	monotonic := ulid.Monotonic(ulid.DefaultEntropy(), 0)
	timestamp := ulid.Now()

	ulid1 := ulid.MustNew(timestamp, monotonic)
	ulid2 := ulid.MustNew(timestamp, monotonic)
	ulid3 := ulid.MustNew(timestamp, monotonic)

	// All should be different and ordered
	if ulid1.String() >= ulid2.String() {
		t.Errorf("Monotonic ordering failed: %s should be < %s", ulid1.String(), ulid2.String())
	}
	if ulid2.String() >= ulid3.String() {
		t.Errorf("Monotonic ordering failed: %s should be < %s", ulid2.String(), ulid3.String())
	}

	// Test with different increment values
	monotonic2 := ulid.Monotonic(ulid.DefaultEntropy(), 100)
	ulid4 := ulid.MustNew(timestamp, monotonic2)
	ulid5 := ulid.MustNew(timestamp, monotonic2)

	if ulid4.String() >= ulid5.String() {
		t.Errorf("Monotonic ordering with increment failed: %s should be < %s", ulid4.String(), ulid5.String())
	}

	fmt.Printf("Monotonic ULID generation working\n")
}

// Test ULID time extraction
func TestULIDTimeExtraction(t *testing.T) {
	// Test with current time
	now := time.Now()
	timestamp := ulid.Timestamp(now)
	ulidID := ulid.MustNew(timestamp, ulid.DefaultEntropy())

	// Extract time from ULID
	extractedTime := ulid.Time(ulidID.Time())
	timeDiff := now.Sub(extractedTime)

	// Should be within 1 second (ULID has millisecond precision)
	if timeDiff > time.Second {
		t.Errorf("Time extraction failed: expected within 1 second, got %v", timeDiff)
	}

	// Test with specific timestamp
	specificTime := time.Date(2022, 1, 1, 0, 0, 0, 0, time.UTC)
	specificTimestamp := ulid.Timestamp(specificTime)
	ulidID2 := ulid.MustNew(specificTimestamp, ulid.DefaultEntropy())

	extractedTime2 := ulid.Time(ulidID2.Time())
	if !extractedTime2.Equal(specificTime) {
		t.Errorf("Time extraction failed: expected %v, got %v", specificTime, extractedTime2)
	}

	fmt.Printf("ULID time extraction working\n")
}

// Test ULID encoding and decoding
func TestULIDEncoding(t *testing.T) {
	// Test that ULID string is valid Crockford's Base32
	ulidID := ulid.Make()
	ulidStr := ulidID.String()

	// Check length
	if len(ulidStr) != ulid.EncodedSize {
		t.Errorf("Expected encoded size %d, got %d", ulid.EncodedSize, len(ulidStr))
	}

	// Check all characters are valid
	for i, char := range ulidStr {
		if !strings.ContainsRune(ulid.Encoding, char) {
			t.Errorf("Invalid character at position %d: %c", i, char)
		}
	}

	// Test round-trip encoding/decoding
	parsed, err := ulid.Parse(ulidStr)
	if err != nil {
		t.Errorf("Failed to parse encoded ULID: %v", err)
	}
	if parsed != ulidID {
		t.Errorf("Round-trip encoding failed")
	}

	fmt.Printf("ULID encoding working\n")
}

// Test edge cases with extreme values
func TestExtremeValues(t *testing.T) {
	// Test with maximum timestamp
	maxTime := ulid.MaxTime()
	ulid1 := ulid.MustNew(maxTime, ulid.DefaultEntropy())
	if len(ulid1.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid1.String()))
	}

	// Test with zero timestamp
	ulid2 := ulid.MustNew(0, ulid.DefaultEntropy())
	if len(ulid2.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid2.String()))
	}

	// Test with very large increment
	monotonic := ulid.Monotonic(ulid.DefaultEntropy(), math.MaxUint64)
	ulid3 := ulid.MustNew(ulid.Now(), monotonic)
	if len(ulid3.String()) != 26 {
		t.Errorf("Expected ULID length 26, got %d", len(ulid3.String()))
	}

	fmt.Printf("Extreme values handling working\n")
}

// Test concurrent ULID generation
func TestConcurrentGeneration(t *testing.T) {
	const numGoroutines = 100
	const numULIDs = 10

	results := make(chan ulid.ULID, numGoroutines*numULIDs)
	errors := make(chan error, numGoroutines)

	// Generate ULIDs concurrently
	for i := 0; i < numGoroutines; i++ {
		go func() {
			for j := 0; j < numULIDs; j++ {
				ulidID := ulid.Make()
				results <- ulidID
			}
		}()
	}

	// Collect results
	ulids := make([]ulid.ULID, 0, numGoroutines*numULIDs)
	for i := 0; i < numGoroutines*numULIDs; i++ {
		select {
		case ulidID := <-results:
			ulids = append(ulids, ulidID)
		case err := <-errors:
			t.Errorf("Concurrent generation error: %v", err)
		}
	}

	// Check that all ULIDs are unique
	seen := make(map[ulid.ULID]bool)
	for _, ulidID := range ulids {
		if seen[ulidID] {
			t.Errorf("Duplicate ULID generated: %s", ulidID.String())
		}
		seen[ulidID] = true

		// Validate each ULID
		if len(ulidID.String()) != 26 {
			t.Errorf("Invalid ULID length: %d", len(ulidID.String()))
		}
	}

	fmt.Printf("Concurrent ULID generation working - Generated %d unique ULIDs\n", len(ulids))
}

// Test error handling
func TestErrorHandling(t *testing.T) {
	// Test Parse with invalid string
	_, err := ulid.Parse("invalid")
	if err == nil {
		t.Errorf("Expected error for invalid ULID string, but got none")
	}

	// Test Parse with empty string
	_, err = ulid.Parse("")
	if err == nil {
		t.Errorf("Expected error for empty ULID string, but got none")
	}

	// Test Parse with too short string
	_, err = ulid.Parse("short")
	if err == nil {
		t.Errorf("Expected error for too short ULID string, but got none")
	}

	// Test Parse with too long string
	_, err = ulid.Parse("thisiswaytoolongtobeavalidulidstring")
	if err == nil {
		t.Errorf("Expected error for too long ULID string, but got none")
	}

	fmt.Printf("Error handling working\n")
}

// Test ULID string representation
func TestULIDStringRepresentation(t *testing.T) {
	ulidID := ulid.Make()
	ulidStr := ulidID.String()

	// Test that string representation is consistent
	if ulidStr != ulidID.String() {
		t.Errorf("String representation not consistent")
	}

	// Test that string is printable
	for _, char := range ulidStr {
		if char < 32 || char > 126 {
			t.Errorf("Non-printable character in ULID: %c", char)
		}
	}

	fmt.Printf("ULID string representation working - %s\n", ulidStr)
}
