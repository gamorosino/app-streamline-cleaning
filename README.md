# Streamline Cleaning (app-streamline-cleaning)

This repository provides a reproducible pipeline to **clean spurious streamlines** in tractography tracks.

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

Amorosino, G., Caron, B., Kwon, J., Carrasco, M., Reid, R. C., Lenglet, C., ... & Pestilli, F. (2026).
*A retinotopic wiring principle of the human brain.*
bioRxiv, 2026-04.

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

All parameters are provided via a `config.json` file (or via the CLI wrapper — see [Local usage](#usage-locally)).

### Mandatory (one of)

| Field   | Description                                              |
| ------- | -------------------------------------------------------- |
| `track` | Single input tract file (`.trk` or `.tck`)              |
| `tcks`  | Directory of `.tck` files (cleaned iteratively, one each) |

`track` and `tcks` are mutually exclusive. When `tcks` is provided, the cleaning pipeline is applied independently to every `.tck` file found in the directory.

### Optional parameters

| Field                  | Type    | Default      | Description                                                    |
| ---------------------- | ------- | ------------ | -------------------------------------------------------------- |
| `min_length`           | number  | `0`          | Minimum streamline length (mm)                                |
| `max_length`           | number  | `10000000`   | Maximum streamline length (mm)                                |
| `angle`                | number  | `360`        | Maximum turning angle for loop rejection (degrees)            |
| `reference`            | string  | `null`       | Reference anatomy image for SCIL steps                        |
| `no_qb_loops`          | boolean | `false`      | Disable QuickBundles-based loop detection                     |
| `loop_qb_thr`          | number  | `8`          | Distance threshold (mm) for QB loop filtering                 |
| `alpha`                | number  | `null`       | SCIL outlier rejection alpha (default 0.6; recommend 0.3–0.4) |
| `no_outlier_rejection` | boolean | `false`      | Skip SCIL outlier rejection                                   |
| `purifibre`            | number  | `null`       | Apply Purifibre at final stage (percentage)                   |
| `purifibre_first`      | number  | `null`       | Apply Purifibre before filtering (percentage)                 |
| `nthreads`             | number  | `1`          | Number of threads for loop detection                          |
| `structural`           | string  | `null`       | Structural image for `.tck` → `.trk` conversion (Purifibre)  |

### Example `config.json` — single tract

```json
{
    "track": "input/track.tck",
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

### Example `config.json` — batch folder

```json
{
    "tcks": "input/tracts/",
    "min_length": 20,
    "max_length": 200,
    "nthreads": 4
}
```

---

## Output

| Path                              | Description                                         |
| --------------------------------- | --------------------------------------------------- |
| `track/track.<ext>`               | Cleaned tractogram (single-tract mode)              |
| `clean_tracts/<original_name>.tck`| Cleaned tractograms, one per input file (tcks mode) |

---

## Usage on Brainlife.io

This app is designed to run on **Brainlife.io**.

### Web UI

1. Locate the **app-streamline-cleaning** app
2. Select the input track (`.trk` or `.tck`) or a tcks directory
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

### 2a. Run via CLI wrapper (recommended for local testing)

`main_cli.sh` generates `config.json` automatically and invokes `main`:

```bash
# single tract
bash main_cli.sh --track path/to/bundle.tck --min_length 20 --max_length 200

# folder of tracts
bash main_cli.sh --tcks path/to/tracts/ --nthreads 4

# with Purifibre
bash main_cli.sh --tcks path/to/tracts/ --purifibre_first 0.3 --purifibre 0.1
```

All `config.json` keys are available as `--key value` flags. Boolean switches (`--no_qb_loops`, `--no_outlier_rejection`) take no value.

### 2b. Run via `config.json`

Create a `config.json` file manually:

```json
{
    "track": "path/to/track.tck",
    "min_length": 20,
    "max_length": 200
}
```

Then run:

```bash
bash main
```

This will:

- read the configuration file
- apply length filtering, loop filtering, and outlier rejection
- save the cleaned tractogram(s) to `track/track.<ext>` (single) or `clean_tracts/` (batch)

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

The app relies on the following software:
- **Singularity / Apptainer**

that executes the following scripts/functions:

- **scilpy** (`scil_filter_streamlines_by_length.py`, `scil_detect_streamlines_loops.py`, `scil_outlier_rejection.py`, `scil_count_streamlines.py`)
- **MRtrix3** (`tckconvert`, used only when Purifibre is enabled with `.tck` input)
- **jq**
