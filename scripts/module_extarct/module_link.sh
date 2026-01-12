#!/bin/bash

optimize_bc() {
    local input_bc="$1"
    
    echo "Optimizing $input_bc using LLVM 18 Pass Manager..."
    if opt --passes='internalize,globaldce' -o "$input_bc" "$input_bc"; then
        echo "Optimization successful for $input_bc"
    elif opt --passes='default<O2>' -o "$input_bc" "$input_bc"; then
        echo "Fallback optimization successful for $input_bc"
    else
        echo "Warning: opt failed on $input_bc, skipping optimization."
    fi
}

link_bc_recursive() {
    local dir="$1"
    echo "Processing directory: $dir"

    declare -A processed_bc
    local all_bc_files=($(find "$dir" -maxdepth 1 -type f -name "*.bc"))
    
    for mod_file in "$dir"/*.mod; do
        if [[ -f "$mod_file" ]]; then
            mod_name=$(basename "$mod_file" .mod)
            output_file="$dir/${mod_name}-single.bc"
            linked_bc_files=()

            while read -r o_file; do
                bc_filename="$(basename "$o_file").bc"
                bc_path="$dir/$bc_filename"

                if [[ -f "$bc_path" && -s "$bc_path" ]]; then
                    linked_bc_files+=("$bc_path")
                    processed_bc["$bc_filename"]=1
                else
                    echo "Skipping invalid or empty bitcode file: $bc_path"
                fi
            done < "$mod_file"

            if [[ ${#linked_bc_files[@]} -gt 0 ]]; then
                echo "Linking ${mod_name}.mod -> $output_file"
                /home/eager/prebuilts/clang/host/linux-x86/clang-r510928/bin/llvm-link -o "$output_file" "${linked_bc_files[@]}"
            fi
        fi
    done

    local dir_name=$(basename "$dir")
    single_bc_output="$dir/${dir_name}-single.bc"
    remaining_bc=()

    for bc_file in "${all_bc_files[@]}"; do
        bc_basename=$(basename "$bc_file")
        if [[ -z "${processed_bc[$bc_basename]}" && -s "$bc_file" ]]; then
            remaining_bc+=("$bc_file")
        fi
    done

    if [[ ${#remaining_bc[@]} -gt 0 ]]; then
        echo "Linking remaining files in $dir -> $single_bc_output"
        /home/eager/prebuilts/clang/host/linux-x86/clang-r510928/bin/llvm-link -o "$single_bc_output" "${remaining_bc[@]}"
    fi

    local sub_bc_files=()
    for subdir in "$dir"/*/; do
        if [[ -d "$subdir" ]]; then
            link_bc_recursive "$subdir"
            local sub_bc="$subdir/$(basename "$subdir")-single.bc"
            if [[ -f "$sub_bc" && -s "$sub_bc" ]]; then
                sub_bc_files+=("$sub_bc")
            fi
        fi
    done

    if [[ ${#sub_bc_files[@]} -gt 0 ]]; then
        output_file="$dir/${dir_name}-linked.bc"
        echo "Linking subdirectories -> $output_file"
        /home/eager/prebuilts/clang/host/linux-x86/clang-r510928/bin/llvm-link -o "$output_file" "${sub_bc_files[@]}"
    fi
}

start_dir="./"

start_dir=$(realpath -m "$start_dir")

link_bc_recursive "$start_dir"

echo "Bitcode linking completed."

