#!/bin/bash

INPUT_DIR="./data/pdfs"
OUTPUT_DIR="./data/datastet_results"

mkdir -p "$OUTPUT_DIR"

for pdf in "$INPUT_DIR"/*.xml; do
    filename=$(basename "$pdf" .xml)
    output_file="$OUTPUT_DIR/${filename}.xml"

    echo "Processing $pdf -> $output_file"

    http_code=$(curl -s -w "%{http_code}" -o "$output_file" \
        --form "input=@${pdf}" \
        --form "disambiguate=1" \
        localhost:8060/service/annotateDatasetPDF)

    curl_exit=$?


    echo "Successfully processed $pdf"
done