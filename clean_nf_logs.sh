#!/bin/bash
# Remove .nextflow.log* files older than today

OLD_LOGS=$(find . -maxdepth 1 -name '.nextflow.log*' -not -newermt "$(date +%Y-%m-%d)" 2>/dev/null)

if [ -z "$OLD_LOGS" ]; then
    echo "No old .nextflow.log files found."
    exit 0
fi

echo "The following files will be removed:"
echo "------------------------------------"
echo "$OLD_LOGS" | while read -r f; do
    ls -lh "$f"
done
echo "------------------------------------"

read -p "Remove these files? [y/N]: " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "$OLD_LOGS" | xargs rm -f
    echo "Done."
else
    echo "Cancelled."
fi