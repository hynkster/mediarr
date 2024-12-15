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

# Add timeout function
timeout_handler() {
    local pid=$1
    local timeout=$2
    (
        sleep $timeout
        kill -s SIGTERM $pid 2>/dev/null
        sleep 2
        kill -s SIGKILL $pid 2>/dev/null
    ) &
    timeout_pid=$!
}

# Enhanced input validation
validate_input() {
    local input_file="$1"
    local lock_file="/tmp/$(basename "$input_file").lock"
    
    # Check if file is being processed
    if [ -f "$lock_file" ]; then
        log_message "File is already being processed: $input_file" "WARNING"
        return 1
    fi
    
    # Create lock file
    touch "$lock_file"
    
    # Validate file integrity
    if ! ffmpeg -v error -i "$input_file" -f null - 2>/dev/null; then
        log_message "Input file corrupted: $input_file" "ERROR"
        rm -f "$lock_file"
        return 1
    fi
    
    return 0
}

validate_audio() {
    local input_file="$1"
    local error_output="/tmp/ffmpeg_audio_$$.txt"
    
    if ! ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$input_file" 2>"$error_output"; then
        log_message "Audio validation failed: $(cat $error_output)" "ERROR"
        rm -f "$error_output"
        return 1
    fi
    return 0
}

# Update signal handling
trap cleanup_and_exit SIGINT SIGTERM SIGQUIT
trap 'log_message "Received interrupt signal, cleaning up..." "WARNING"; cleanup_and_exit' INT TERM QUIT

# Improved cleanup
cleanup_and_exit() {
    local exit_code=${1:-1}
    log_message "Cleaning up..." "INFO"
    # Kill any running ffmpeg processes
    pkill -P $$ ffmpeg
    # Remove lock files
    find /tmp -name "*.lock" -user $USER -delete
    # Remove temporary files
    find /tmp -name "temp_convert_$$.*" -delete
    find /tmp -name "ffmpeg_*_$$.*" -delete
    # Kill timeout handler if running
    [ -n "$timeout_pid" ] && kill $timeout_pid 2>/dev/null
    exit $exit_code
}

# Enhanced conversion function
convert_file() {
    local input_file="$1"
    local output_file="${input_file%.*}.mkv"
    local temp_output_file="/tmp/temp_convert_$$.mkv"
    local error_output="/tmp/ffmpeg_error_$$.txt"
    local timeout=3600  # 1 hour timeout
    
    ((CURRENT_FILE++))
    
    # Validate input and audio
    if ! validate_input "$input_file" || ! validate_audio "$input_file"; then
        ((ERROR_FILES++))
        return 1
    fi

    # Conversion methods array
    local -a conversion_methods=(
        "-c:v libx264 -preset medium -crf 22 -c:a aac -b:a 192k"
        "-c:v libx264 -preset slower -crf 23 -c:a copy"
        "-c:v libx264 -preset veryslow -crf 24 -c:a aac -b:a 256k"
    )
    
    # Try each conversion method
    for method in "${conversion_methods[@]}"; do
        log_message "Attempting conversion with: $method"
        
        ffmpeg -i "$input_file" $method "$temp_output_file" &
        ffmpeg_pid=$!
        
        # Set timeout
        timeout_handler $ffmpeg_pid $timeout
        
        # Wait for ffmpeg
        wait $ffmpeg_pid
        local result=$?
        
        # Cleanup timeout handler
        kill $timeout_pid 2>/dev/null
        
        if [ $result -eq 0 ] && [ -f "$temp_output_file" ] && [ -s "$temp_output_file" ]; then
            mv "$temp_output_file" "$output_file"
            echo "$input_file" >> "$PROCESSED_LIST"
            ((SUCCESS_FILES++))
            log_message "Successfully converted: $(basename "$input_file")"
            rm -f "$error_output"
            return 0
        fi
        
        log_message "Conversion attempt failed: $(tail -n 2 $error_output)" "ERROR"
    done
    
    ((ERROR_FILES++))
    rm -f "$temp_output_file" "$error_output"
    return 1
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