#!/bin/bash

# Configuration
LOG_FILE="/opt/mediarr/logs/avi_convert.log"
ERROR_LOG="/opt/mediarr/logs/avi_convert_errors.log"
PROCESSED_LIST="/opt/mediarr/logs/converted_files.txt"
TOTAL_FILES=0
CURRENT_FILE=0
START_TIME=$(date +%s)

# Check for required commands
check_dependencies() {
    local missing_deps=()
    
    for cmd in ffmpeg bc numfmt; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Missing required commands: ${missing_deps[*]}" | tee -a "$ERROR_LOG"
        echo "Please install them using:"
        echo "sudo pacman -S ffmpeg bc coreutils"
        exit 1
    fi
}

# Create necessary directories and files
mkdir -p "$(dirname "$LOG_FILE")"
touch "$PROCESSED_LIST"
touch "$ERROR_LOG"

# Function to format time without bc
format_time() {
    local seconds=$1
    printf "%02d:%02d:%02d" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
}

# Function to format size
format_size() {
    local size=$1
    numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "Unknown size"
}

# Function to calculate ETA without bc
calculate_eta() {
    local elapsed=$1
    local current=$2
    local total=$3
    
    if [ $current -eq 0 ]; then
        echo 0
        return
    fi
    
    local rate=$((elapsed / current))
    echo $((rate * (total - current)))
}

# Function to update progress display
update_progress() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local percent=$((CURRENT_FILE * 100 / TOTAL_FILES))
    local eta=$(calculate_eta $elapsed $CURRENT_FILE $TOTAL_FILES)
    
    printf "\rProgress: [%d/%d] %d%% - Elapsed: %s - ETA: %s" \
        $CURRENT_FILE $TOTAL_FILES $percent \
        "$(format_time $elapsed)" "$(format_time $eta)"
}

# Function to log messages
log_message() {
    local message="$1"
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') [$CURRENT_FILE/$TOTAL_FILES] - $message" | tee -a "$LOG_FILE"
    update_progress
}

# Function to monitor conversion progress
monitor_ffmpeg_progress() {
    local input_size=$1
    local pid=$2
    local temp_file=$3
    
    while kill -0 $pid 2>/dev/null; do
        if [ -f "$temp_file" ]; then
            local current_size=$(stat -c %s "$temp_file" 2>/dev/null || echo 0)
            local percent=0
            if [ $input_size -gt 0 ]; then
                percent=$((current_size * 100 / input_size))
            fi
            printf "\rConverting: %d%% (%s / %s)" \
                $percent \
                "$(format_size $current_size)" \
                "$(format_size $input_size)"
        fi
        sleep 1
    done
    printf "\n"
}

# Function to monitor copy progress
monitor_copy_progress() {
    local source=$1
    local dest=$2
    local size=$(stat -c %s "$source")
    
    while [ -f "$source" ]; do
        local current_size=$(stat -c %s "$dest" 2>/dev/null || echo 0)
        local percent=0
        if [ $size -gt 0 ]; then
            percent=$((current_size * 100 / size))
        fi
        printf "\rCopying: %d%% (%s / %s)" \
            $percent \
            "$(format_size $current_size)" \
            "$(format_size $size)"
        if [ $current_size -eq $size ]; then
            break
        fi
        sleep 1
    done
    printf "\n"
}

# Function to convert a single file
convert_file() {
    local input_file="$1"
    local output_file="${input_file%.*}.mkv"
    local temp_output_file="/tmp/temp_convert_$$.mkv"
    local error_output="/tmp/ffmpeg_error_$$.txt"
    
    ((CURRENT_FILE++))
    
    # Skip check with reason
    if grep -Fxq "$input_file" "$PROCESSED_LIST"; then
        # Check if MKV exists
        local mkv_file="${input_file%.*}.mkv"
        if [ -f "$mkv_file" ]; then
            local mkv_size=$(stat -c %s "$mkv_file")
            log_message "Skipping: $(basename "$input_file") (MKV exists: $(format_size $mkv_size))"
        else
            log_message "Warning: $(basename "$input_file") is marked as processed but MKV not found"
            # Optionally remove from processed list
            sed -i "\#^$input_file\$#d" "$PROCESSED_LIST"
            return 0
        fi
        return 0
    fi
    
    local input_size=$(stat -c %s "$input_file")
    log_message "Starting: $(basename "$input_file") ($(format_size $input_size))"
    
    rm -f "$temp_output_file" "$error_output"
    
    # First attempt with genpts flag
    ffmpeg -nostdin -v warning -fflags +genpts \
        -i "$input_file" \
        -map 0 -c copy \
        "$temp_output_file" 2> "$error_output"
    
    local ffmpeg_status=$?
    
    # Retry with alternative flags if first attempt failed
    if [ $ffmpeg_status -ne 0 ]; then
        log_message "Retrying conversion with alternative method..."
        rm -f "$temp_output_file"
        
        ffmpeg -nostdin -v warning -fflags +genpts+igndts \
            -i "$input_file" \
            -map 0 -c copy \
            "$temp_output_file" 2> "$error_output"
        
        ffmpeg_status=$?
    fi
    
    if [ $ffmpeg_status -ne 0 ]; then
        local error_msg=$(cat "$error_output")
        log_message "Conversion failed: $error_msg"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - File: $input_file - Error: $error_msg" >> "$ERROR_LOG"
        rm -f "$temp_output_file" "$error_output"
        return 1
    fi
    
    if mv "$temp_output_file" "$output_file"; then
        echo "$input_file" >> "$PROCESSED_LIST"
        local final_size=$(stat -c %s "$output_file")
        log_message "Completed: $(basename "$input_file") ($(format_size $final_size))"
        rm -f "$error_output"
        return 0
    else
        log_message "Error: Failed to move converted file"
        rm -f "$temp_output_file" "$error_output"
        return 1
    fi
}

# Function to process directory
process_directory() {
    local dir="$1"
    
    if [ ! -d "$dir" ]; then
        echo "Error: Directory not found: $dir"
        return 1
    fi
    
    # Count total files
    TOTAL_FILES=$(find "$dir" -type f -iname "*.avi" | wc -l)
    echo "Starting conversion of $TOTAL_FILES files in: $dir"
    echo "----------------------------------------"
    
    # Process files
    find "$dir" -type f -iname "*.avi" -print0 | while IFS= read -r -d '' file; do
        convert_file "$file"
    done
    
    # Show final statistics
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    echo -e "\n----------------------------------------"
    echo "Conversion completed in $(format_time $total_time)"
    echo "Processed: $CURRENT_FILE/$TOTAL_FILES files"
}

# Main script execution
if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

# Check dependencies before starting
check_dependencies

process_directory "$1"
exit $?