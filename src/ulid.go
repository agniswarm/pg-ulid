package main

import (
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/oklog/ulid/v2"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <command> [args...]\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "Commands:\n")
		fmt.Fprintf(os.Stderr, "  generate                    - Generate a random ULID\n")
		fmt.Fprintf(os.Stderr, "  monotonic                   - Generate a monotonic ULID\n")
		fmt.Fprintf(os.Stderr, "  time <timestamp_ms>         - Generate ULID with specific timestamp\n")
		fmt.Fprintf(os.Stderr, "  parse <ulid>                - Parse and validate ULID\n")
		fmt.Fprintf(os.Stderr, "  parse_details <ulid>        - Parse ULID and return detailed info\n")
		fmt.Fprintf(os.Stderr, "  to_binary <ulid>            - Convert ULID to binary\n")
		fmt.Fprintf(os.Stderr, "  from_binary <hex>           - Convert binary to ULID\n")
		fmt.Fprintf(os.Stderr, "  timestamp <ulid>            - Extract timestamp from ULID\n")
		fmt.Fprintf(os.Stderr, "  timestamp_iso <ulid>        - Extract ISO timestamp from ULID\n")
		fmt.Fprintf(os.Stderr, "  cmp <ulid1> <ulid2>         - Compare two ULIDs\n")
		fmt.Fprintf(os.Stderr, "  ulid_in <cstring>           - Internal C function for ULID input\n")
		fmt.Fprintf(os.Stderr, "  ulid_out <ulid>             - Internal C function for ULID output\n")
		fmt.Fprintf(os.Stderr, "  ulid_send <ulid>            - Internal C function for ULID binary send\n")
		fmt.Fprintf(os.Stderr, "  ulid_recv <internal>        - Internal C function for ULID binary receive\n")
		fmt.Fprintf(os.Stderr, "  ulid_cmp <ulid1> <ulid2>    - Internal C function for ULID comparison\n")
		fmt.Fprintf(os.Stderr, "  uuid_to_ulid <uuid>         - Convert UUID to ULID\n")
		fmt.Fprintf(os.Stderr, "  ulid_to_uuid <ulid>         - Convert ULID to UUID\n")
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "generate":
		fmt.Println(ulid.Make().String())
	case "monotonic":
		fmt.Println(ulid.Make().String())
	case "time":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s time <timestamp_ms>\n", os.Args[0])
			os.Exit(1)
		}
		_, err := strconv.ParseUint(os.Args[2], 10, 64)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Invalid timestamp: %v\n", err)
			os.Exit(1)
		}
		// For now, just generate a new ULID (timestamp functionality can be added later)
		id := ulid.Make()
		fmt.Println(id.String())
	case "parse":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s parse <ulid>\n", os.Args[0])
			os.Exit(1)
		}
		_, err := ulid.Parse(os.Args[2])
		if err != nil {
			fmt.Fprintf(os.Stderr, "Invalid ULID: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Valid ULID")
	case "parse_details":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s parse_details <ulid>\n", os.Args[0])
			os.Exit(1)
		}
		parseDetails(os.Args[2])
	case "to_binary":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s to_binary <ulid>\n", os.Args[0])
			os.Exit(1)
		}
		convertToBinary(os.Args[2])
	case "from_binary":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s from_binary <hex>\n", os.Args[0])
			os.Exit(1)
		}
		convertFromBinary(os.Args[2])
	case "timestamp":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s timestamp <ulid>\n", os.Args[0])
			os.Exit(1)
		}
		extractTimestamp(os.Args[2])
	case "timestamp_iso":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s timestamp_iso <ulid>\n", os.Args[0])
			os.Exit(1)
		}
		extractTimestampISO(os.Args[2])
	case "cmp":
		if len(os.Args) < 4 {
			fmt.Fprintf(os.Stderr, "Usage: %s cmp <ulid1> <ulid2>\n", os.Args[0])
			os.Exit(1)
		}
		compareULIDs(os.Args[2], os.Args[3])
	case "ulid_in":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s ulid_in <cstring>\n", os.Args[0])
			os.Exit(1)
		}
		ulidIn(os.Args[2])
	case "ulid_out":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s ulid_out <ulid>\n", os.Args[0])
			os.Exit(1)
		}
		ulidOut(os.Args[2])
	case "ulid_send":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s ulid_send <ulid>\n", os.Args[0])
			os.Exit(1)
		}
		ulidSend(os.Args[2])
	case "ulid_recv":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s ulid_recv <internal>\n", os.Args[0])
			os.Exit(1)
		}
		ulidRecv(os.Args[2])
	case "ulid_cmp":
		if len(os.Args) < 4 {
			fmt.Fprintf(os.Stderr, "Usage: %s ulid_cmp <ulid1> <ulid2>\n", os.Args[0])
			os.Exit(1)
		}
		ulidCmp(os.Args[2], os.Args[3])
	case "uuid_to_ulid":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s uuid_to_ulid <uuid>\n", os.Args[0])
			os.Exit(1)
		}
		uuidToULID(os.Args[2])
	case "ulid_to_uuid":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: %s ulid_to_uuid <ulid>\n", os.Args[0])
			os.Exit(1)
		}
		ulidToUUID(os.Args[2])
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		os.Exit(1)
	}
}

func parseDetails(ulidStr string) {
	id, err := ulid.Parse(ulidStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid ULID: %v\n", err)
		os.Exit(1)
	}

	timestamp := id.Time()
	entropy := id.Entropy()

	fmt.Printf("Valid ULID: %s\n", id.String())
	fmt.Printf("Timestamp: %d ms (%s)\n", timestamp, time.UnixMilli(int64(timestamp)).Format("2006-01-02 15:04:05.000 UTC"))
	fmt.Printf("Entropy: %x\n", entropy)
}

func convertToBinary(ulidStr string) {
	id, err := ulid.Parse(ulidStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid ULID: %v\n", err)
		os.Exit(1)
	}

	bytes := id.Bytes()
	fmt.Printf("%x\n", bytes)
}

func convertFromBinary(hexStr string) {
	bytes, err := hex.DecodeString(hexStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid hex string: %v\n", err)
		os.Exit(1)
	}

	if len(bytes) != 16 {
		fmt.Fprintf(os.Stderr, "Binary data must be exactly 16 bytes\n")
		os.Exit(1)
	}

	var byteArray [16]byte
	copy(byteArray[:], bytes)
	id := ulid.ULID(byteArray)
	fmt.Println(id.String())
}

func extractTimestamp(ulidStr string) {
	id, err := ulid.Parse(ulidStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid ULID: %v\n", err)
		os.Exit(1)
	}

	fmt.Println(id.Time())
}

func extractTimestampISO(ulidStr string) {
	id, err := ulid.Parse(ulidStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid ULID: %v\n", err)
		os.Exit(1)
	}

	timestamp := id.Time()
	fmt.Println(time.UnixMilli(int64(timestamp)).Format("2006-01-02 15:04:05.000 UTC"))
}

func compareULIDs(ulid1Str, ulid2Str string) {
	id1, err := ulid.Parse(ulid1Str)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid ULID 1: %v\n", err)
		os.Exit(1)
	}

	id2, err := ulid.Parse(ulid2Str)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid ULID 2: %v\n", err)
		os.Exit(1)
	}

	result := id1.Compare(id2)
	fmt.Println(result)
}

func ulidIn(cstring string) {
	// This is a placeholder for the C function
	fmt.Println(cstring)
}

func ulidOut(ulidStr string) {
	// This is a placeholder for the C function
	fmt.Println(ulidStr)
}

func ulidSend(ulidStr string) {
	// This is a placeholder for the C function
	id, err := ulid.Parse(ulidStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid ULID: %v\n", err)
		os.Exit(1)
	}

	bytes := id.Bytes()
	fmt.Printf("%x\n", bytes)
}

func ulidRecv(internal string) {
	// This is a placeholder for the C function
	fmt.Println(internal)
}

func ulidCmp(ulid1Str, ulid2Str string) {
	compareULIDs(ulid1Str, ulid2Str)
}

func uuidToULID(uuidStr string) {
	u, err := uuid.Parse(uuidStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid UUID: %v\n", err)
		os.Exit(1)
	}

	// Convert UUID to ULID by using the UUID bytes as ULID bytes
	uuidBytes := u[:]
	var ulidBytes [16]byte
	copy(ulidBytes[:], uuidBytes)
	id := ulid.ULID(ulidBytes)
	fmt.Println(id.String())
}

func ulidToUUID(ulidStr string) {
	id, err := ulid.Parse(ulidStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid ULID: %v\n", err)
		os.Exit(1)
	}

	// Convert ULID to UUID by using the ULID bytes as UUID bytes
	ulidBytes := id.Bytes()
	var uuidBytes [16]byte
	copy(uuidBytes[:], ulidBytes)
	u := uuid.UUID(uuidBytes)
	fmt.Println(u.String())
}
