# Streamline Cleaning (app-streamline-cleaning)

This repository provides a reproducible pipeline to **clean spurious streamlines** in a tractography track using:

```bash
filter_spurious_streamlines.sh
```

The pipeline sequentially applies:

1. Optional **Purifibre** (first pass)
2. **Length filtering**
3. **Loop filtering** (angle-based + optional QuickBundles)
4. **Outlier rejection** (scilpy)
5. Optional **Purifibre** (final pass)

The app is designed for **Brainlife.io** and runs inside a **containerized environment** to ensure reproducibility and portability.

---

## Features

- Supports `.trk` and `.tck` tractogram formats
- Fully configurable via `config.json`
- Outputs a cleaned tractogram and a QC JSON report
- Optional integration with **Purifibre** for learning-based cleaning
- Robust fallback logic: if any step fails, the pipeline continues from the last valid track

---

## Author

Gabriele Amorosino
[gabriele.amorosino@utexas.edu](mailto:gabriele.amorosino@utexas.edu)

---

## Citation

If you use this app in your research, please cite:

### Primary work



---

### Software dependencies

#### scilpy

Renauld, E., Boré, A., Poirier, C., Valcourt-Caron, A., Karan, P., Théberge, A., et al. (2026).
*Tractography analysis with the scilpy toolbox.*
Aperture Neuro.

#### purifibre

Aydogan D. B. "Fiber coupling (FICO) measure using anisotropic smoothing of track orientation density images for tractogram filtering", ISMRM 2022



#### Brainlife.io

Hayashi, S., et al. (2024).
*Brainlife.io: a decentralized platform for reproducible neuroscience.*
Nature Methods.

[https://doi.org/10.1038/s41592-024-02237-2](https://doi.org/10.1038/s41592-024-02237-2)

---

## Inputs

All parameters are provided via a `config.json` file.

### Mandatory

| Field    | Description                          |
| -------- | ------------------------------------ |
| `track` | Input tract file (`.trk` or `.tck`) |

### Optional parameters

| Field                  | Type    | Default      | Description                                                   |
| ---------------------- | ------- | ------------ | ------------------------------------------------------------- |
| `min_length`           | number  | `0`          | Minimum streamline length (mm)                               |
| `max_length`           | number  | `10000000`   | Maximum streamline length (mm)                               |
| `angle`                | number  | `360`        | Maximum turning angle for loop rejection (degrees)           |
| `reference`            | string  | `null`       | Reference anatomy image for SCIL steps                       |
| `no_qb_loops`          | boolean | `false`      | Disable QuickBundles-based loop detection                    |
| `loop_qb_thr`          | number  | `8`          | Distance threshold (mm) for QB loop filtering                |
| `alpha`                | number  | `null`       | SCIL outlier rejection alpha (default 0.6; recommend 0.3–0.4)|
| `no_outlier_rejection` | boolean | `false`      | Skip SCIL outlier rejection                                  |
| `purifibre`            | number  | `null`       | Apply Purifibre at final stage (percentage)                  |
| `purifibre_first`      | number  | `null`       | Apply Purifibre before filtering (percentage)                |
| `nthreads`             | number  | `1`          | Number of threads for loop detection                         |
| `structural`           | string  | `null`       | Structural image for `.tck` → `.trk` conversion (Purifibre) |

### Example `config.json`

```json
{
    "track": "input/track.trk",
    "min_length": 20,
    "max_length": 200,
    "angle": 360,
    "reference": null,
    "no_qb_loops": false,
    "loop_qb_thr": 8,
    "alpha": null,
    "no_outlier_rejection": false,
    "purifibre": null,
    "purifibre_first": null,
    "nthreads": 1,
    "structural": null
}
```

---

## Output

| Path                         | Description                            |
| ---------------------------- | -------------------------------------- |
| `track/track.<ext>`          | Cleaned tractogram                     |
| `track/track_qc.json`        | QC report with per-step streamline counts |

The QC JSON includes per-step counts (before/after/removed), status, and timestamps for full provenance tracking.

---

## Usage on Brainlife.io

This app is designed to run on **Brainlife.io**.

### Web UI

1. Locate the **app-streamline-cleaning** app
2. Select the input track (`.trk` or `.tck`)
3. Configure optional parameters (length thresholds, angle, outlier rejection, etc.)
4. Execute the pipeline

### CLI

```bash
bl login

bl app run --id <app_id> \
           --project <project_id> \
           --input track:<tractogram_object>
```

---

## Usage locally

### 1. Clone the repository

```bash
git clone https://github.com/gamorosino/app-streamline-cleaning.git
cd app-streamline-cleaning
```

### 2. Prepare configuration

Create a `config.json` file:

```json
{
    "track": "path/to/track.trk",
    "min_length": 20,
    "max_length": 200
}
```

### 3. Run the pipeline

```bash
./main
```

This will:

- read the configuration file
- apply length filtering, loop filtering, and outlier rejection
- save the cleaned tractogram to `track/track.<ext>`
- save the QC report to `track/track_qc.json`

---

## Pipeline steps

```
Input track
    │
    ├── [optional] Purifibre first pass  (--purifibre-first)
    │
    ├── Length filter                    (--minL / --maxL)
    │
    ├── Loop filter                      (-a angle, optional QB)
    │
    ├── Outlier rejection                (scilpy, --alpha)
    │
    └── [optional] Purifibre final pass  (--purifibre)
            │
            └── Output track
```

---

## Requirements

The app relies on the following software (executed via Singularity container):

- **scilpy** (`scil_filter_streamlines_by_length.py`, `scil_detect_streamlines_loops.py`, `scil_outlier_rejection.py`, `scil_count_streamlines.py`)
- **MRtrix3** (`tckconvert`, used only when Purifibre is enabled with `.tck` input)
- **Singularity / Apptainer**
- **jq**
