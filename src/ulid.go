package main

import (
	"crypto/rand"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"
)

// Global monotonic entropy source for thread-safe ULID generation
var (
	monotonicEntropy = ulid.Monotonic(rand.Reader, 0)
	monotonicMutex   = &sync.Mutex{}
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <command> [args...]\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "Commands:\n")
		fmt.Fprintf(os.Stderr, "  generate                    - Generate a random ULID\n")
		fmt.Fprintf(os.Stderr, "  monotonic                   - Generate a monotonic ULID\n")
		fmt.Fprintf(os.Stderr, "  time <timestamp_ms>         - Generate ULID with specific timestamp\n")
		fmt.Fprintf(os.Stderr, "  parse <ulid>                - Parse and validate ULID\n")
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "generate":
		generateRandomULID()
	case "monotonic":
		generateMonotonicULID()
	case "time":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Error: timestamp required for 'time' command\n")
			os.Exit(1)
		}
		generateTimeBasedULID(os.Args[2])
	case "parse":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Error: ULID required for 'parse' command\n")
			os.Exit(1)
		}
		parseULID(os.Args[2])
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown command '%s'\n", command)
		os.Exit(1)
	}
}

// Generate a random ULID using crypto/rand
func generateRandomULID() {
	entropy := rand.Reader
	id := ulid.MustNew(ulid.Timestamp(time.Now()), entropy)
	fmt.Println(id.String())
}

// Generate a monotonic ULID (ensures ordering within same millisecond)
func generateMonotonicULID() {
	monotonicMutex.Lock()
	defer monotonicMutex.Unlock()

	id := ulid.MustNew(ulid.Timestamp(time.Now()), monotonicEntropy)
	fmt.Println(id.String())
}

// Generate ULID with specific timestamp
func generateTimeBasedULID(timestampStr string) {
	timestamp, err := strconv.ParseUint(timestampStr, 10, 64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: invalid timestamp '%s': %v\n", timestampStr, err)
		os.Exit(1)
	}

	entropy := rand.Reader
	id := ulid.MustNew(ulid.Timestamp(time.UnixMilli(int64(timestamp))), entropy)
	fmt.Println(id.String())
}

// Parse and validate a ULID
func parseULID(ulidStr string) {
	id, err := ulid.ParseStrict(ulidStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: invalid ULID '%s': %v\n", ulidStr, err)
		os.Exit(1)
	}

	// Extract timestamp and entropy
	timestamp := id.Time()
	entropy := id.Entropy()

	fmt.Printf("Valid ULID: %s\n", id.String())
	fmt.Printf("Timestamp: %d ms (%s)\n", timestamp, time.UnixMilli(int64(timestamp)).Format(time.RFC3339))
	fmt.Printf("Entropy: %x\n", entropy)
}
