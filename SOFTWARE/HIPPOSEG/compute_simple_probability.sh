#!/bin/bash
#
# compute_simple_probability.sh
# Simple probability computation by averaging segmentation labels
# No weighting - just takes mean of all template votes
#
# Usage: compute_simple_probability.sh <4D_segmentations> <output_prob>
#

if [ $# -ne 2 ]; then
    echo "Usage: $0 <4D_segmentations> <output_prob>"
    echo "  4D_segmentations: 4D volume with warped segmentations (0/1 labels)"
    echo "  output_prob: output probability map (0-1 values)"
    exit 1
fi

segmentations_4d=$1
output_prob=$2

echo "Computing simple averaged probability map..."

# Get number of templates
num_templates=`fslinfo ${segmentations_4d} | grep "^dim4" | awk '{print $2}'`
echo "Number of templates: ${num_templates}"

# compute the mean across the 4th dimension
# This gives us: P(voxel) = sum(votes) / num_templates
fslmaths ${segmentations_4d} -Tmean ${output_prob}

echo "Simple probability map saved to: ${output_prob}"
echo "Probability range: [$(fslstats ${output_prob} -R)]"
echo "Values represent: proportion of templates voting 'hippocampus' at each voxel" 