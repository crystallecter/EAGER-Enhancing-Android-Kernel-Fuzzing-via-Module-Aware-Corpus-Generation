#!/bin/bash

path="$0"
native_dirpath="$(dirname "$0")"

skip_next=false
filtered_args=()

source_file_dir="."
source_file_name=""


for arg in "$@"
do
  if [ "$skip_next" = true ]; then
    skip_next=false
    continue
  fi
  
  if [ "$arg" = "-o" ]; then
    skip_next=true
    continue
  fi

  if [[ "$arg" =~ \.c$ || "$arg" =~ \.cpp$ ]]; then
    source_file_dir="$(dirname "$arg")"
    source_file_name="$(basename "$arg")"
  fi

  filtered_args+=( "$arg" )
done


(exec -a "$native_dirpath"/clang++ "$native_dirpath"/clang++-native "$@" -emit-llvm)
out_file="$("$native_dirpath"/run.sh "$@")"
cp "$out_file" "${out_file%.o}".bc


bc_file_name="${source_file_name%.*}.bc"
bc_output_path="$source_file_dir/$bc_file_name"

echo "[INFO] Will generate IR (.bc) to: $bc_output_path" 1>&2


(exec -a "$native_dirpath"/clang++ "$native_dirpath"/clang++-native \
    -c "${filtered_args[@]}" \
    -emit-llvm \
    -o "$bc_output_path")

exec -a "$native_dirpath"/clang++ "$native_dirpath"/clang++-native "$@"