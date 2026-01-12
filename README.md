## Preprocesisng pipeline for diffusion-weighted images.

This script will: 

1) Convert DWI bruker files to nifti
2) Create brain mask and skull stripping
3) Denoising and eddy correction via MRtrix/FSL
4) Extract b0 images
5) Calculation of diffusion tensor metrics (MD, FA, AD, RD) via MRtrix
6) Generate a population-speficif brain template via ANTs
7) Registration of b0 images to template and apply transformation to DTI maps


_NOTE: you need to have installed MRtrix, FSL and ANTs._

-------------------------------------------------------------------------
Before you start:

The DTI scan number variable is hard-coded and need to be modify depending of your dataset

-------------------------------------------------------------------------

### The script is call with 3 arguments:

1) The base directory 
2) The folder containing your bruker files (should only have those files)
3) The folder you want to put everything else (it will create a new folder depending of what you put in the command line; for example "dti")

USAGE:

`./dti_preproc_pipe <my_path/> <my_path/raw> <my_path/dti> `

