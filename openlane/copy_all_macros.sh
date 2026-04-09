#!/bin/bash

# Check if project root is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 PROJECT_ROOT"
    exit 1
fi

PROJECT_ROOT=$1
# Path to your single-macro copy script
COPY_SCRIPT="./openframe_multiproject/openlane/copy_views.sh"

# List of macros to process
# Note: Macro name and Run Tag are the same
MACROS=(
    "scan_controller_macro"
    "purple_macro_p4"
    "purple_macro_p3"
    "green_macro"
    "project_macro"
    "orange_macro_v"
    "orange_macro_h"
)

# Ensure the single copy script is executable
chmod +x "$COPY_SCRIPT"

echo "Starting bulk copy of macro views..."
echo "------------------------------------"

for MACRO in "${MACROS[@]}"; do
    echo "Processing Macro: $MACRO (Tag: $MACRO)..."
    
    # Execute the single copy script
    # Arguments: PROJECT_ROOT, MACRO_NAME, RUN_TAG
    $COPY_SCRIPT "$PROJECT_ROOT" "$MACRO" "$MACRO"
    
    if [ $? -eq 0 ]; then
        echo "SUCCESS: $MACRO views copied."
    else
        echo "ERROR: Failed to copy views for $MACRO."
    fi
    echo "------------------------------------"
done

echo "Bulk copy complete."
