# Modified Software for Probabilistic Output

This repository contains modified versions of three medical image segmentation software packages (HippoSeg, FastSurfer, and InnerEye) to enable probabilistic output for uncertainty quantification in hippocampal segmentation.

## 📁 Directory Structure
Individual implementations and results for each segmentation tool:
- **`INNEREYE/`** - Microsoft InnerEye deep learning segmentation tool (modified for probabilistic output)
- **`HIPPOSEG/`** - CMIC HippoSeg segmentation tool (modified for probabilistic output)
- **`FASTSURFER/`** - FastSurfer deep learning neuroimaging pipeline (modified for probabilistic output)

- **`ASHS/`** - Automatic Segmentation of Hippocampal Subfields implementation
- **`FREESURFER/`** - FreeSurfer cortical reconstruction and segmentation

## Software Modifications

### HippoSeg
Modified to output segmentation probability maps alongside standard binary segmentations. Following shell script was added to the original HippoSeg implementation:

- `compute_simple_probability.sh` - Extracts probability maps from model outputs

In the niftHippo.sh file, this script is called to extract and save the probability maps. Relevant code for computation of the average across the templates:

```bash
segmentations_4d=$1
output_prob=$2

echo "Computing simple averaged probability map..."

# Get number of templates
num_templates=`fslinfo ${segmentations_4d} | grep "^dim4" | awk '{print $2}'`
echo "Number of templates: ${num_templates}"

# compute the mean across the 4th dimension
# This gives us: P(voxel) = sum(votes) / num_templates
fslmaths ${segmentations_4d} -Tmean ${output_prob}
```

### FastSurfer
Modified the `run_prediction.py` script to save hippocampus probability maps during segmentation. The key changes include:

- Extracts probability maps for left (label 17) and right (label 53) hippocampus from softmax output
- Saves probability maps as `aparc.DKTatlas+aseg.deep.hippo_probs.mgz` 
- Controlled by `--save_hippo_probs` flag (defaults to True)
- Preserves probability distributions before argmax operation

Relevant code for extracting hippocampus probabilities from `run_prediction.py`:

```python
# Get hard predictions
pred_classes = torch.argmax(pred_prob, 3)

# Store hippocampus probabilities if requested (before deleting pred_prob)
# Hippocampus labels: 17 (left), 53 (right) in FreeSurfer space
# But in pred_prob tensor they are at sequential indices: 13 (left), 28 (right)
hippo_probs = None
if self.save_hippo_probs:
    LOGGER.info("Extracting hippocampus probability maps...")
    
    # Extract and save raw logit values for hippocampus classes
    # These are the raw network outputs before softmax
    # Using sequential indices from FastSurfer LUT: 13=left hippo, 28=right hippo
    self._left_hippo_raw = pred_prob[:, :, :, 13].cpu().numpy().astype(np.float32)
    self._right_hippo_raw = pred_prob[:, :, :, 28].cpu().numpy().astype(np.float32)
```

The modified file is located at `SOFTWARE/FASTSURFER/modified/run_prediction.py` and replaces the original in the Docker container.

### InnerEye
Adapted the scoring script to output probability maps in addition to binary segmentations. The modifications include:

- Modified `score.py` to save raw probability outputs from the ensemble model
- Preserves prediction confidence scores for uncertainty quantification
- Maintains compatibility with original InnerEye workflow

Relevant code for saving posteriors from `score.py`:

```python
# Save posteriors (probability maps) for each class
class_names_and_indices = config.class_and_index_with_background().items()
posterior_files = []
for class_name, index in class_names_and_indices:
    posterior = inference_result.posteriors[index, ...]
    posterior_file_name = model_folder / f"posterior_{class_name}.nii.gz"
    posterior_path = store_posteriors_as_nifti(
        image=posterior,
        header=images[0].header,
        file_name=posterior_file_name
    )
    posterior_files.append(posterior_path)
    logging.info(f"Saved posterior for class {class_name}: {posterior_path}")
```

The modified scoring script outputs both traditional binary segmentations and corresponding probability maps for each prediction.


