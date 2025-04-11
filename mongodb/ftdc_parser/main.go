package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/mongodb/ftdc"
)

// MetricFormat represents the legacy ftdc-utils metric export format
type MetricFormat struct {
	NDeltas int `json:"NDeltas"`
	Metrics []MetricEntry `json:"Metrics"`
}

type MetricEntry struct {
	Key    string  `json:"Key"`
	Value  int64   `json:"Value"`
	Deltas []int64 `json:"Deltas"`
}

func main() {
	inputPath := flag.String("i", "", "Input FTDC file path")
	outputPath := flag.String("o", "", "Output JSON file path")
	flag.Parse()

	if *inputPath == "" || *outputPath == "" {
		log.Fatal("Both input and output file paths must be specified")
	}

	inputFile, err := os.Open(*inputPath)
	if err != nil {
		log.Fatalf("Failed to open input file: %v", err)
	}
	defer inputFile.Close()

	outputFile, err := os.Create(*outputPath)
	if err != nil {
		log.Fatalf("Failed to create output file: %v", err)
	}
	defer outputFile.Close()

	ctx := context.Background()
	chunkIter := ftdc.ReadChunks(ctx, inputFile)
	var allSamples []MetricFormat

	for chunkIter.Next() {
		chunk := chunkIter.Chunk()
		metrics := chunk.Metrics
		nSamples := chunk.Size()
		sample := MetricFormat{
			NDeltas: nSamples - 1,
			Metrics: make([]MetricEntry, 0, len(metrics)),
		}
		for _, m := range metrics {
			sample.Metrics = append(sample.Metrics, MetricEntry{
				Key:    m.Key(),
				Value:  m.Values[0],
				Deltas: m.Values[1:],
			})
		}
		allSamples = append(allSamples, sample)
	}

	if err := chunkIter.Err(); err != nil {
		log.Fatalf("Error reading FTDC chunks: %v", err)
	}

	encoder := json.NewEncoder(outputFile)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(allSamples); err != nil {
		log.Fatalf("Failed to write JSON: %v", err)
	}

	fmt.Printf("Exported %d FTDC samples to %s in legacy format\n", len(allSamples), *outputPath)
}
